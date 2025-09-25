import 'dart:typed_data';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../config/face_quality_config.dart';
import '../error/error_handler.dart';
import '../utils/logger.dart';
import 'embedding_strategy.dart';
import 'tflite_embedding_strategy.dart';

@singleton
class TFLiteService {
  static const String modelPath = 'assets/models/mobilefacenet.tflite';
  static const int inputSize = 112;
  static const int outputSize = 192; // Updated to match verified MobileFaceNet model
  static const int numThreads = 4;

  // Strategy pattern implementation
  late EmbeddingStrategy _embeddingStrategy;
  bool _isInitialized = false;

  // Legacy fields (kept for backward compatibility during migration)
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  // Model input/output shapes
  late List<int> _inputShape;
  late List<int> _outputShape;
  late TensorType _inputType;
  late TensorType _outputType;

  bool get isInitialized => _isInitialized;

  /// Initialize the TensorFlow Lite interpreter
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.warning('TFLite service already initialized');
      return;
    }

    Logger.info('=== TFLITE SERVICE INITIALIZATION START ===');
    Logger.info('Initializing TFLite service...');

    try {
      // Initialize TFLite strategy - NO FALLBACK TO MOCK
      _embeddingStrategy = TFLiteEmbeddingStrategy();
      Logger.info('Created TFLite embedding strategy instance');

      try {
        await _embeddingStrategy.initialize();
        Logger.success('✓ TFLite model loaded successfully');
        Logger.info('Strategy name: ${_embeddingStrategy.strategyName}');
        Logger.info('Model is ready for face recognition');
      } catch (e) {
        // Log detailed error information
        Logger.error('❌ CRITICAL: TFLite model failed to load', error: e);
        Logger.error('Expected model paths:');
        Logger.error('  1. assets/models/mobilefacenet_verified.tflite (preferred)');
        Logger.error('  2. assets/models/mobilefacenet.tflite (fallback)');
        Logger.error('');
        Logger.error('This is a CRITICAL ERROR - face recognition WILL NOT WORK!');
        Logger.error('Please ensure the TFLite model file exists in the assets folder.');

        // Throw exception with detailed message - DO NOT FALLBACK
        throw Exception(
          'CRITICAL: Failed to load TFLite model for face recognition.\n'
          'The app cannot function without the ML model.\n'
          'Please check that the model file exists at: assets/models/mobilefacenet_verified.tflite\n'
          'Error details: $e'
        );
      }

      // Initialize legacy components for backward compatibility
      await _initializeLegacyComponents();

      _isInitialized = true;
      Logger.success('=== TFLITE SERVICE INITIALIZATION SUCCESS ===');
      Logger.success('TFLite service fully initialized with ${_embeddingStrategy.strategyName}');
    } catch (e) {
      Logger.error('=== TFLITE SERVICE INITIALIZATION FAILED ===', error: e);
      _isInitialized = false;
      // Re-throw to propagate to initialization service
      throw e;
    }
  }

  /// Initialize legacy components for backward compatibility
  Future<void> _initializeLegacyComponents() async {
    try {
      // Load model from assets
      final modelBytes = await _loadModelFromAssets();

      // Create interpreter options
      final options = InterpreterOptions()
        ..threads = numThreads;

      // Try to use GPU delegate if available with enhanced error handling
      if (Platform.isAndroid) {
        await _tryEnableGpuDelegate(options);
      }

      try {
        // Create interpreter
        _interpreter = Interpreter.fromBuffer(modelBytes, options: options);

        // Get input and output shapes
        _inputShape = _interpreter!.getInputTensor(0).shape;
        _outputShape = _interpreter!.getOutputTensor(0).shape;
        _inputType = _interpreter!.getInputTensor(0).type;
        _outputType = _interpreter!.getOutputTensor(0).type;

        Logger.debug('Legacy interpreter initialized');
        Logger.debug('Input shape: $_inputShape, type: $_inputType');
        Logger.debug('Output shape: $_outputShape, type: $_outputType');

        // Create isolate interpreter for background processing
        await _initializeIsolateInterpreter();
      } catch (modelError) {
        Logger.warning('Legacy interpreter failed: $modelError');
        // Set up mock values for testing
        _inputShape = [1, inputSize, inputSize, 3];
        _outputShape = [1, outputSize];
        _inputType = TensorType.float32;
        _outputType = TensorType.float32;
      }
    } catch (e) {
      Logger.warning('Legacy components initialization failed: $e');
    }
  }

  /// Initialize isolate interpreter for background processing
  Future<void> _initializeIsolateInterpreter() async {
    try {
      final interpreterAddress = _interpreter!.address;
      _isolateInterpreter = await IsolateInterpreter.create(
        address: interpreterAddress,
      );
      Logger.success('Isolate interpreter created');
    } catch (e) {
      Logger.warning('Failed to create isolate interpreter: $e');
    }
  }

  /// Load model from assets
  Future<Uint8List> _loadModelFromAssets() async {
    try {
      final modelData = await rootBundle.load(modelPath);
      return modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
    } catch (e) {
      Logger.error('Failed to load model from assets', error: e);
      throw Exception('Model file not found: $modelPath');
    }
  }

  /// Extract face embedding from image bytes
  Future<Float32List> extractEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized) {
      throw Exception('TFLite service not initialized - cannot extract embeddings');
    }

    try {
      // Use strategy pattern for embedding extraction - NO MOCK FALLBACK
      return await _embeddingStrategy.extractEmbedding(imageBytes);
    } catch (e) {
      Logger.error('Failed to extract embedding', error: e);
      // No fallback - throw the error
      throw Exception('Failed to extract face embedding: $e');
    }
  }

  /// Legacy embedding extraction method for backward compatibility
  Future<Float32List> _extractEmbeddingLegacy(Uint8List imageBytes) async {
    // Check if we have a real interpreter or are in mock mode
    if (_interpreter == null) {
      // Mock mode - generate random but consistent embedding for testing
      Logger.debug('Generating mock embedding for testing');
      return _generateMockEmbedding(imageBytes);
    }

    // Decode and preprocess image
    final input = _preprocessImage(imageBytes);

    // Prepare output buffer
    final output = List.filled(outputSize, 0.0)
        .reshape([1, outputSize]);

    // Run inference
    if (_isolateInterpreter != null) {
      // Use isolate for background processing
      await _isolateInterpreter!.run(input, output);
    } else {
      // Fallback to main thread
      _interpreter!.run(input, output);
    }

    // Convert to Float32List and normalize
    final embedding = Float32List.fromList(
      (output as List<List<double>>)[0].cast<double>(),
    );

    return _normalizeEmbedding(embedding);
  }

  /// Generate a mock embedding for testing
  Float32List _generateMockEmbedding(Uint8List imageBytes) {
    // Generate a consistent embedding based on image bytes
    // This is just for testing - real embeddings come from the model
    final embedding = Float32List(outputSize);

    // Use image bytes to generate pseudo-random but consistent values
    int seed = 0;
    final sampleSize = imageBytes.length.clamp(0, FaceQualityConfig.embeddingSeedSampleSize);
    for (int i = 0; i < sampleSize; i++) {
      seed = (seed + imageBytes[i]) % FaceQualityConfig.embeddingSeedModulo;
    }

    // Generate normalized values using configuration constants
    for (int i = 0; i < outputSize; i++) {
      final rawValue = (seed + i * FaceQualityConfig.embeddingValueMultiplier) % FaceQualityConfig.embeddingSeedModulo;
      embedding[i] = (rawValue / (FaceQualityConfig.embeddingSeedModulo - 1)) - 0.5;
    }

    return _normalizeEmbedding(embedding);
  }

  /// Extract face embedding in isolate (for background processing)
  static Future<Float32List> extractEmbeddingInIsolate(
    SendPort sendPort,
    Uint8List imageBytes,
    int interpreterAddress,
  ) async {
    try {
      // Create interpreter from address
      final interpreter = Interpreter.fromAddress(interpreterAddress);

      // Preprocess image
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Failed to decode image');

      // Resize and normalize
      final resized = img.copyResize(image, width: inputSize, height: inputSize);
      final input = _imageToTensor(resized);

      // Prepare output
      final output = List.filled(outputSize, 0.0).reshape([1, outputSize]);

      // Run inference
      interpreter.run(input, output);

      // Return embedding
      final embedding = Float32List.fromList(
        (output as List<List<double>>)[0].cast<double>(),
      );

      return _normalizeEmbeddingStatic(embedding);
    } catch (e) {
      throw Exception('Isolate embedding extraction failed: $e');
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
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.cubic,
    );

    // Convert to tensor
    return _imageToTensor(resized);
  }

  /// Convert image to tensor format
  static List<List<List<List<double>>>> _imageToTensor(img.Image image) {
    final tensor = List.generate(
      1,
      (b) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) => List.generate(3, (c) {
            final pixel = image.getPixel(x, y);
            // Normalize to [-1, 1] for MobileFaceNet
            switch (c) {
              case 0: return (pixel.r / 127.5) - 1.0; // Red
              case 1: return (pixel.g / 127.5) - 1.0; // Green
              case 2: return (pixel.b / 127.5) - 1.0; // Blue
              default: return 0.0;
            }
          }),
        ),
      ),
    );
    return tensor;
  }

  /// Normalize embedding to unit vector
  Float32List _normalizeEmbedding(Float32List embedding) {
    return _normalizeEmbeddingStatic(embedding);
  }

  /// Static method for normalizing embedding (for isolate use)
  static Float32List _normalizeEmbeddingStatic(Float32List embedding) {
    // Calculate L2 norm
    double norm = 0.0;
    for (final value in embedding) {
      norm += value * value;
    }
    norm = Math.sqrt(norm);

    // Normalize to unit vector
    if (norm > 0) {
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] /= norm;
      }
    }

    return embedding;
  }

  /// Calculate Euclidean distance between two embeddings
  double calculateDistance(Float32List embedding1, Float32List embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embedding dimensions do not match: ${embedding1.length} vs ${embedding2.length}');
    }

    double sum = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      sum += diff * diff;
    }

    return Math.sqrt(sum);
  }

  /// Calculate cosine similarity between two embeddings
  double calculateCosineSimilarity(Float32List embedding1, Float32List embedding2) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embedding dimensions do not match: ${embedding1.length} vs ${embedding2.length}');
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    norm1 = Math.sqrt(norm1);
    norm2 = Math.sqrt(norm2);

    if (norm1 == 0.0 || norm2 == 0.0) {
      return 0.0;
    }

    return dotProduct / (norm1 * norm2);
  }

  /// Check if two faces match based on distance threshold
  bool isFaceMatch(Float32List embedding1, Float32List embedding2, {double threshold = 0.6}) {
    final distance = calculateDistance(embedding1, embedding2);
    return distance < threshold;
  }

  /// Get confidence score for face match (0-1, higher is better)
  double getMatchConfidence(Float32List embedding1, Float32List embedding2) {
    final distance = calculateDistance(embedding1, embedding2);
    // Convert distance to confidence score
    // Distance of 0 = 100% confidence, distance of 2 = 0% confidence
    return Math.max(0, Math.min(1, 1 - (distance / 2)));
  }

  /// Try to enable GPU delegate with comprehensive error handling
  Future<void> _tryEnableGpuDelegate(InterpreterOptions options) async {
    try {
      // Check if GPU delegate is supported
      final gpuDelegateV2 = GpuDelegateV2(
        options: GpuDelegateOptionsV2(
          isPrecisionLossAllowed: false,
        ),
      );

      options.addDelegate(gpuDelegateV2);
      Logger.success('GPU delegate enabled with optimized settings');

    } catch (e) {
      // Log specific GPU delegate errors for debugging SELinux issues
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('dmabuf') || errorString.contains('getattr')) {
        Logger.warning('GPU delegate blocked by SELinux policy (dmabuf access denied)');
        Logger.info('This is common on devices with strict security policies');
        Logger.info('App will use CPU processing - functionality preserved but slower');
      } else if (errorString.contains('gpu') || errorString.contains('opencl')) {
        Logger.warning('GPU hardware not available or incompatible');
        Logger.info('Falling back to CPU processing');
      } else if (errorString.contains('permission') || errorString.contains('access')) {
        Logger.warning('GPU access permission denied - check app permissions');
      } else {
        Logger.warning('Unknown GPU delegate error: $e');
      }

      // Always continue with CPU-only processing
      Logger.info('Continuing with CPU-only inference');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await ErrorHandler.handleOptionalOperationWithWarning(
      'dispose TFLite service',
      () async {
        // Dispose strategy
        if (_isInitialized) {
          _embeddingStrategy.dispose();
        }

        // Dispose legacy components
        _isolateInterpreter?.close();
        _interpreter?.close();

        _isInitialized = false;
        Logger.info('TFLite service disposed');
      },
    );
  }
}

// Math utilities for Dart
class Math {
  static double sqrt(double x) => x < 0 ? 0 : _sqrt(x);
  static double _sqrt(double x) {
    if (x == 0) return 0;
    double guess = x;
    double epsilon = 0.00001;
    while ((guess - x / guess).abs() > epsilon * guess) {
      guess = (guess + x / guess) / 2.0;
    }
    return guess;
  }

  static double max(double a, double b) => a > b ? a : b;
  static double min(double a, double b) => a < b ? a : b;
}