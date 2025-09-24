import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../utils/logger.dart';
import 'embedding_strategy.dart';

/// Real TFLite implementation of embedding extraction strategy
///
/// This strategy uses the actual MobileFaceNet TensorFlow Lite model
/// to generate face embeddings for production use.
@injectable
class TFLiteEmbeddingStrategy implements EmbeddingStrategy {
  static const String modelPath = 'assets/models/mobilefacenet.tflite';
  static const int inputSize = 112;
  static const int outputSize = 192;  // MobileFaceNet outputs 192-dimensional embeddings

  Interpreter? _interpreter;
  Interpreter? _cpuInterpreter;  // CPU-only interpreter for fallback
  List<int>? _inputShape;
  List<int>? _outputShape;
  TensorType? _inputType;
  TensorType? _outputType;
  bool _isInitialized = false;
  bool _hasGpuSupport = false;

  // Isolate processing
  Isolate? _isolate;
  SendPort? _sendPort;

  @override
  bool get isInitialized => _isInitialized;

  @override
  String get strategyName => 'TFLite Production';

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.info('Initializing TFLite embedding strategy...');

      // Load model from assets
      final modelBytes = await rootBundle.load(modelPath);
      final buffer = modelBytes.buffer.asUint8List();

      // Create interpreter options with GPU delegation
      final gpuOptions = InterpreterOptions();
      final cpuOptions = InterpreterOptions();

      // Try to enable GPU delegation for better performance
      try {
        final gpuDelegate = GpuDelegateV2();
        gpuOptions.addDelegate(gpuDelegate);
        _interpreter = Interpreter.fromBuffer(buffer, options: gpuOptions);
        _hasGpuSupport = true;
        Logger.success('GPU delegation enabled for main thread');
      } catch (e) {
        Logger.warning('GPU delegation not available, using CPU: $e');
        _interpreter = Interpreter.fromBuffer(buffer, options: cpuOptions);
        _hasGpuSupport = false;
      }

      // Always create a CPU-only interpreter for fallback
      _cpuInterpreter = Interpreter.fromBuffer(buffer, options: cpuOptions);
      Logger.info('CPU interpreter created for fallback');

      // Get input and output shapes
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      _inputType = _interpreter!.getInputTensor(0).type;
      _outputType = _interpreter!.getOutputTensor(0).type;

      Logger.info('Model loaded successfully');
      Logger.debug('Input shape: $_inputShape, type: $_inputType');
      Logger.debug('Output shape: $_outputShape, type: $_outputType');

      // Initialize isolate for background processing
      await _initializeIsolate();

      _isInitialized = true;
      Logger.success('TFLite embedding strategy initialized');
    } catch (e) {
      Logger.error('Failed to initialize TFLite strategy', error: e);
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  Future<Float32List> extractEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized || (_interpreter == null && _cpuInterpreter == null)) {
      throw StateError('TFLite strategy not initialized');
    }

    try {
      // Decode and preprocess image
      final input = _preprocessImage(imageBytes);

      // Create output tensor with correct dimensions
      final output = List.generate(1, (index) => List.filled(outputSize, 0.0));

      // Try GPU inference first (only works on main thread)
      bool success = false;
      if (_hasGpuSupport && _interpreter != null) {
        try {
          _interpreter!.run(input, output);
          success = true;
          Logger.debug('Used GPU for inference');
        } catch (gpuError) {
          Logger.warning('GPU inference failed, falling back to CPU: $gpuError');
        }
      }

      // Fallback to CPU if GPU failed or not available
      if (!success && _cpuInterpreter != null) {
        _cpuInterpreter!.run(input, output);
        Logger.debug('Used CPU for inference');
      }

      // Extract and normalize embedding
      final embedding = Float32List.fromList(output[0].cast<double>());
      return normalizeEmbedding(embedding);
    } catch (e) {
      Logger.error('Failed to extract embedding with TFLite', error: e);
      rethrow;
    }
  }

  @override
  Float32List normalizeEmbedding(Float32List embedding) {
    // Calculate L2 norm
    double norm = 0.0;
    for (int i = 0; i < embedding.length; i++) {
      norm += embedding[i] * embedding[i];
    }
    norm = math.sqrt(norm);

    // Avoid division by zero
    if (norm == 0.0) {
      return embedding;
    }

    // Normalize to unit length
    final normalized = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }

    return normalized;
  }

  @override
  void dispose() {
    try {
      _interpreter?.close();
      _cpuInterpreter?.close();
      _isolate?.kill();
      _isInitialized = false;
      Logger.info('TFLite embedding strategy disposed');
    } catch (e) {
      Logger.error('Error disposing TFLite strategy', error: e);
    }
  }

  /// Preprocess image for model input
  List<List<List<List<double>>>> _preprocessImage(Uint8List imageBytes) {
    // Decode image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Resize to model input size
    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    // Convert to model input format [1, height, width, channels]
    final input = List.generate(
      1,
      (batch) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) => List.generate(3, (c) {
            final pixel = resized.getPixel(x, y);
            switch (c) {
              case 0:
                return (pixel.r / 255.0 - 0.5) * 2.0; // Red
              case 1:
                return (pixel.g / 255.0 - 0.5) * 2.0; // Green
              case 2:
                return (pixel.b / 255.0 - 0.5) * 2.0; // Blue
              default:
                return 0.0;
            }
          }).cast<double>(),
        ).cast<List<double>>(),
      ).cast<List<List<double>>>(),
    ).cast<List<List<List<double>>>>();

    return input;
  }

  /// Initialize isolate for background processing
  Future<void> _initializeIsolate() async {
    try {
      final receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
      _sendPort = await receivePort.first as SendPort;
      Logger.success('Processing isolate created');
    } catch (e) {
      Logger.warning('Failed to create processing isolate: $e');
      // Continue without isolate - processing will be on main thread
    }
  }

  /// Isolate entry point for background processing
  static void _isolateEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      // Handle isolate processing requests
      // Implementation would depend on specific requirements
    });
  }
}