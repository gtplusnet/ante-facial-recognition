import 'dart:typed_data';
import 'dart:isolate';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:injectable/injectable.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../../core/ml/face_processing_utils.dart';
import '../../../../core/ml/tflite_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/constants/face_recognition_constants.dart';
import '../../../face_detection/data/services/face_detection_service.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';
import 'face_match_scorer.dart';

@singleton
class FaceEncodingService {
  final TFLiteService _tfliteService;
  final FaceDetectionService _faceDetectionService;

  // Cache for processed faces
  final Map<String, FaceEncodingResult> _encodingCache = {};
  static const int maxCacheSize = 100;

  // Processing state
  bool _isProcessing = false;
  Isolate? _processingIsolate;
  ReceivePort? _receivePort;

  FaceEncodingService({
    required TFLiteService tfliteService,
    required FaceDetectionService faceDetectionService,
  })  : _tfliteService = tfliteService,
        _faceDetectionService = faceDetectionService;

  /// Cache management
  final Map<String, Float32List> _faceEncodingCache = {};

  /// Initialize service
  Future<void> initialize() async {
    try {
      Logger.info('Initializing face encoding service');

      // Initialize TFLite service if not already initialized
      if (!_tfliteService.isInitialized) {
        await _tfliteService.initialize();
      }

      // Setup processing isolate for heavy computations
      await _setupProcessingIsolate();

      Logger.success('Face encoding service initialized');
    } catch (e) {
      Logger.error('Failed to initialize face encoding service', error: e);
      throw Exception('Face encoding initialization failed: $e');
    }
  }

  /// Setup isolate for processing
  Future<void> _setupProcessingIsolate() async {
    try {
      _receivePort = ReceivePort();
      _processingIsolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
      );

      Logger.success('Processing isolate created');
    } catch (e) {
      Logger.error('Failed to setup processing isolate', error: e);
    }
  }

  /// Isolate entry point for heavy processing
  static void _isolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      // Process message in isolate
      // This is where heavy image processing would happen
    });
  }

  /// Load face encodings into memory cache
  Future<void> loadEncodings(Map<String, Float32List> encodings) async {
    _faceEncodingCache.clear();
    _faceEncodingCache.addAll(encodings);
    Logger.info('Loaded ${encodings.length} face encodings to memory');
  }

  /// Extract face encoding from camera frame
  Future<FaceEncodingResult?> extractFromCameraImage(
    CameraImage cameraImage,
    CameraDescription cameraDescription,
  ) async {
    if (_isProcessing) {
      return null; // Skip frame if still processing
    }

    _isProcessing = true;
    final startTime = DateTime.now();

    try {
      // Detect faces first
      final faces = await _faceDetectionService.detectFacesFromCameraImage(
        cameraImage,
        cameraDescription,
      );

      if (faces.isEmpty) {
        return null;
      }

      // Select best face for processing
      final face = _selectBestFace(faces);
      if (face == null) {
        return null;
      }

      // Convert camera image to processable format
      final image = FaceProcessingUtils.convertCameraImage(cameraImage);
      if (image == null) {
        Logger.error('Failed to convert camera image');
        return null;
      }

      // Crop and process the face
      final processedFace = await _processFaceImage(image, face);
      if (processedFace == null) {
        Logger.error('Failed to process face image');
        return null;
      }

      // Extract embedding
      final embedding = await _extractEmbedding(processedFace);
      if (embedding == null) {
        Logger.error('Failed to extract face embedding');
        return null;
      }

      final processingTime = DateTime.now().difference(startTime);
      Logger.performance(
        'Face encoding extracted',
        duration: processingTime,
      );

      return FaceEncodingResult(
        embedding: embedding,
        face: face,
        quality: FaceProcessingUtils.calculateFaceQuality(face, processedFace),
        processingTime: processingTime,
      );
    } catch (e) {
      Logger.error('Face encoding extraction failed', error: e);
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Extract face encoding from image bytes
  Future<FaceEncodingResult?> extractFromImageBytes(
    Uint8List imageBytes,
  ) async {
    final startTime = DateTime.now();

    try {
      // Save to temporary file for better ML Kit compatibility with JPEG
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_face_${DateTime.now().millisecondsSinceEpoch}.jpg');

      try {
        // Write bytes to temporary file
        await tempFile.writeAsBytes(imageBytes);
        Logger.debug('Saved image to temporary file: ${tempFile.path}');

        // Detect faces using file path method (more reliable for JPEG)
        final faces = await _faceDetectionService.detectFacesFromFilePath(tempFile.path);

        if (faces.isEmpty) {
          Logger.debug('No faces detected using file path method, trying fallback');

          // Fallback: decode and fix orientation
          final image = img.decodeImage(imageBytes);
          if (image == null) {
            Logger.error('Failed to decode image bytes');
            return null;
          }

          // Apply orientation fix for EXIF data
          final orientedImage = img.bakeOrientation(image);

          // Convert to BGRA format for ML Kit
          final bgraBytes = _convertToBGRA(orientedImage);

          // Try face detection with properly formatted bytes
          final fallbackFaces = await _faceDetectionService.detectFacesFromBytes(
            bgraBytes,
            width: orientedImage.width,
            height: orientedImage.height,
            format: ui.ImageByteFormat.rawRgba,
          );

          if (fallbackFaces.isEmpty) {
            Logger.warning('No faces detected even with fallback method');
            return null;
          }

          // Use fallback faces for processing
          final face = _selectBestFace(fallbackFaces);
          if (face == null) return null;

          final processedFace = await _processFaceImage(orientedImage, face);
          if (processedFace == null) return null;

          final embedding = await _extractEmbedding(processedFace);
          if (embedding == null) return null;

          return FaceEncodingResult(
            embedding: embedding,
            face: face,
            quality: FaceProcessingUtils.calculateFaceQuality(face, processedFace),
            processingTime: DateTime.now().difference(startTime),
          );
        }

        Logger.debug('Detected ${faces.length} face(s) using file path method');

        // Process the best face
        final face = _selectBestFace(faces);
        if (face == null) {
          Logger.warning('No suitable face found');
          return null;
        }

        // Decode image for processing
        final image = img.decodeImage(imageBytes);
        if (image == null) {
          Logger.error('Failed to decode image bytes');
          return null;
        }

        // Apply orientation fix
        final orientedImage = img.bakeOrientation(image);

        // Process face image
        final processedFace = await _processFaceImage(orientedImage, face);
        if (processedFace == null) {
          return null;
        }

        // Extract embedding
        final embedding = await _extractEmbedding(processedFace);
        if (embedding == null) {
          return null;
        }

        return FaceEncodingResult(
          embedding: embedding,
          face: face,
          quality: FaceProcessingUtils.calculateFaceQuality(face, processedFace),
          processingTime: DateTime.now().difference(startTime),
        );
      } finally {
        // Clean up temporary file
        if (await tempFile.exists()) {
          await tempFile.delete();
          Logger.debug('Cleaned up temporary file');
        }
      }
    } catch (e) {
      Logger.error('Face encoding extraction from bytes failed', error: e);
      return null;
    }
  }

  /// Convert image to BGRA format for ML Kit
  Uint8List _convertToBGRA(img.Image image) {
    final bytes = Uint8List(image.width * image.height * 4);
    int index = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        bytes[index++] = pixel.b.toInt(); // B
        bytes[index++] = pixel.g.toInt(); // G
        bytes[index++] = pixel.r.toInt(); // R
        bytes[index++] = pixel.a.toInt(); // A
      }
    }

    return bytes;
  }

  /// Select the best face from multiple detections
  FaceDetectionResult? _selectBestFace(List<FaceDetectionResult> faces) {
    if (faces.isEmpty) return null;

    // Sort by quality score and select the best
    faces.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));

    final bestFace = faces.first;
    Logger.debug('Selected face with quality score: ${bestFace.qualityScore}');

    return bestFace;
  }

  /// Process face image to prepare for embedding extraction
  Future<img.Image?> _processFaceImage(
    img.Image fullImage,
    FaceDetectionResult face,
  ) async {
    try {
      // Crop face from full image
      final croppedFace = FaceProcessingUtils.cropFace(
        fullImage,
        face,
        expand: true, // Add some margin around face
      );

      if (croppedFace == null) {
        Logger.error('Failed to crop face from image');
        return null;
      }

      // Resize to model input size (112x112)
      final resizedFace = img.copyResize(
        croppedFace,
        width: 112,
        height: 112,
        interpolation: img.Interpolation.cubic,
      );

      // Return resized face (normalization is done in tensor conversion)
      return resizedFace;
    } catch (e) {
      Logger.error('Face image processing failed', error: e);
      return null;
    }
  }

  /// Extract embedding from processed face
  Future<Float32List?> _extractEmbedding(img.Image processedFace) async {
    try {
      // Convert image to bytes for TFLite service
      final imageBytes = Uint8List.fromList(img.encodePng(processedFace));

      // Use TFLite service to extract embedding
      final embedding = await _tfliteService.extractEmbedding(imageBytes);

      // The TFLite service already normalizes the embedding
      return embedding;
    } catch (e) {
      Logger.error('Embedding extraction failed', error: e);
      return null;
    }
  }


  /// Find best match from cached encodings
  /// Returns null if no match is found
  Map<String, dynamic>? findBestMatch(
    Float32List queryEmbedding,
    Map<String, Float32List> candidateEncodings, {
    double threshold = FaceRecognitionConstants.faceMatchThreshold,
  }) {
    Logger.debug('🔍 Finding best match among ${candidateEncodings.length} candidates');
    Logger.debug('Query embedding size: ${queryEmbedding.length}, threshold: $threshold');

    if (candidateEncodings.isEmpty) {
      Logger.warning('No candidate encodings to match against');
      return null;
    }

    String? bestMatchId;
    double bestDistance = double.infinity;

    // Compare with all candidates
    for (final entry in candidateEncodings.entries) {
      final candidateEmbedding = entry.value;
      Logger.debug('Comparing with ${entry.key} (embedding size: ${candidateEmbedding.length})');

      final distance = _calculateEuclideanDistance(
        queryEmbedding,
        candidateEmbedding,
      );

      Logger.debug('Distance to ${entry.key}: $distance');

      if (distance < bestDistance) {
        bestDistance = distance;
        bestMatchId = entry.key;
      }
    }

    // Check if best match meets threshold
    if (bestMatchId != null && bestDistance < threshold) {
      final confidence = 1.0 - (bestDistance / threshold);

      Logger.success('✅ MATCH FOUND! Employee: $bestMatchId, distance: $bestDistance, confidence: $confidence');

      // Return a simple map with match info
      return {
        'matchedId': bestMatchId,
        'distance': bestDistance,
        'confidence': confidence,
        'isMatch': true,
      };
    }

    Logger.warning('❌ No match found. Best: $bestMatchId, distance: $bestDistance (threshold: $threshold)');
    return null;
  }

  /// Calculate Euclidean distance between two embeddings
  double _calculateEuclideanDistance(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError('Embeddings must have same dimensions');
    }

    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }

    return sum > 0 ? _sqrt(sum) : 0.0;
  }

  /// Square root helper
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x;
    double epsilon = 0.00001;
    while ((guess - x / guess).abs() > epsilon * guess) {
      guess = (guess + x / guess) / 2.0;
    }
    return guess;
  }

  /// Clear cache
  void clearCache() {
    _encodingCache.clear();
    _faceEncodingCache.clear();
    Logger.info('Face encoding cache cleared');
  }

  /// Dispose resources
  void dispose() {
    _processingIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    clearCache();
    Logger.info('Face encoding service disposed');
  }
}

/// Result of face encoding extraction
class FaceEncodingResult {
  final Float32List embedding;
  final FaceDetectionResult face;
  final double quality;
  final Duration processingTime;

  FaceEncodingResult({
    required this.embedding,
    required this.face,
    required this.quality,
    required this.processingTime,
  });
}


