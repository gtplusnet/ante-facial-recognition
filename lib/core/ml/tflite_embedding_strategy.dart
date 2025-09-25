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
  static const int outputSize = 192; // Updated for verified model

  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  TensorType? _inputType;
  TensorType? _outputType;
  bool _isInitialized = false;

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

      // Try verified model first, then fall back to original
      String currentModelPath = 'assets/models/mobilefacenet_verified.tflite';

      // Check if verified model exists
      try {
        await rootBundle.load(currentModelPath);
        Logger.info('Using verified MobileFaceNet model');
      } catch (e) {
        Logger.warning('Verified model not found, falling back to original');
        currentModelPath = modelPath;
      }

      // Load model from assets with detailed validation
      Logger.debug('Loading model from path: $currentModelPath');
      final modelData = await rootBundle.load(currentModelPath);

      // Create a clean copy of the buffer without any offset issues
      final buffer = Uint8List.fromList(
        modelData.buffer.asUint8List(
          modelData.offsetInBytes,
          modelData.lengthInBytes,
        ),
      );

      Logger.debug('Model buffer loaded: ${buffer.length} bytes');

      // Validate model buffer
      if (buffer.isEmpty) {
        throw Exception('Model buffer is empty');
      }

      // Check for TFLite magic number (should start with specific bytes)
      if (buffer.length < 8) {
        throw Exception('Model buffer too small: ${buffer.length} bytes');
      }

      // Log first few bytes for debugging
      final headerBytes = buffer.take(16).toList();
      Logger.debug('Model header bytes: ${headerBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Create interpreter options with enhanced GPU delegation
      final options = InterpreterOptions();

      // Try to enable GPU delegate with enhanced error handling
      await _tryEnableGpuDelegate(options);

      // Create interpreter with detailed error handling
      Logger.debug('Creating interpreter...');
      try {
        // First try loading from asset path directly
        try {
          Logger.debug('Attempting to load from asset path directly...');
          _interpreter = await Interpreter.fromAsset(currentModelPath, options: options);
          Logger.debug('Interpreter created successfully from asset path');
        } catch (assetError) {
          Logger.warning('Asset loading failed: $assetError, trying buffer method...');
          // Fall back to buffer method
          _interpreter = Interpreter.fromBuffer(buffer, options: options);
          Logger.debug('Interpreter created successfully from buffer');
        }
      } catch (interpreterError) {
        Logger.error('Interpreter creation failed: $interpreterError');

        // Try without GPU delegate as fallback
        Logger.info('Retrying without GPU delegate...');
        final cpuOptions = InterpreterOptions()
          ..threads = 2; // Use multiple threads for better performance

        try {
          // Try asset path first
          _interpreter = await Interpreter.fromAsset(currentModelPath, options: cpuOptions);
          Logger.success('Interpreter created successfully with CPU-only mode (asset)');
        } catch (e) {
          // Fall back to buffer
          _interpreter = Interpreter.fromBuffer(buffer, options: cpuOptions);
          Logger.success('Interpreter created successfully with CPU-only mode (buffer)');
        }
      }

      // Get input and output shapes
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      _inputType = _interpreter!.getInputTensor(0).type;
      _outputType = _interpreter!.getOutputTensor(0).type;

      Logger.info('Model loaded successfully');
      Logger.debug('Input shape: $_inputShape, type: $_inputType');
      Logger.debug('Output shape: $_outputShape, type: $_outputType');

      // Validate model architecture
      if (_inputShape!.length != 4 || _outputShape!.length != 2) {
        Logger.warning('Unexpected model architecture: input=${_inputShape}, output=${_outputShape}');
      }

      // Initialize isolate for background processing
      await _initializeIsolate();

      _isInitialized = true;
      Logger.success('TFLite embedding strategy initialized');
    } catch (e) {
      Logger.error('Failed to initialize TFLite strategy', error: e);
      Logger.error('Stack trace: ${StackTrace.current}');
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  Future<Float32List> extractEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized || _interpreter == null) {
      throw StateError('TFLite strategy not initialized');
    }

    try {
      // Decode and preprocess image
      final input = _preprocessImage(imageBytes);

      // Create output tensor - dynamically sized based on model
      final actualOutputSize = _outputShape![1];
      final output = List.generate(1, (index) => List.filled(actualOutputSize, 0.0));

      // Run inference
      _interpreter!.run(input, output);

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

  /// Try to enable GPU delegate with comprehensive error handling
  Future<void> _tryEnableGpuDelegate(InterpreterOptions options) async {
    try {
      // Create GPU delegate with optimized settings
      final gpuDelegate = GpuDelegateV2(
        options: GpuDelegateOptionsV2(
          isPrecisionLossAllowed: false,
        ),
      );

      options.addDelegate(gpuDelegate);
      Logger.success('GPU delegate enabled in embedding strategy');

    } catch (e) {
      // Handle specific GPU errors for better user feedback
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('dmabuf') || errorString.contains('getattr')) {
        Logger.info('GPU delegate blocked by device security policy');
        Logger.info('Face recognition will use CPU processing');
        Logger.debug('SELinux dmabuf access denied - this is expected on secure devices');
      } else if (errorString.contains('gpu') || errorString.contains('opencl')) {
        Logger.info('GPU hardware not compatible with TensorFlow Lite');
        Logger.info('Using optimized CPU processing instead');
      } else if (errorString.contains('permission') || errorString.contains('access')) {
        Logger.warning('GPU access permission issue - check device settings');
      } else {
        Logger.debug('GPU delegate initialization failed: $e');
      }

      // Continue with CPU-only processing - no need to fail
      Logger.info('Embedding strategy initialized with CPU processing');
    }
  }

  @override
  void dispose() {
    try {
      _interpreter?.close();
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