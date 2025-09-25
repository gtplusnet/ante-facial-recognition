import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:injectable/injectable.dart';
import 'package:image/image.dart' as img;

import '../../../../core/ml/face_processing_utils.dart';
import '../../../../core/ml/tflite_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_detection/data/services/face_detection_service.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';

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

  /// Initialize the service
  Future<void> initialize() async {
    try {
      Logger.info('Initializing face encoding service');

      // Initialize TFLite if not already done
      if (!_tfliteService.isInitialized) {
        await _tfliteService.initialize();
      }

      // Setup isolate for background processing
      await _setupProcessingIsolate();

      Logger.success('Face encoding service initialized');
    } catch (e) {
      Logger.error('Failed to initialize face encoding service', error: e);
      throw Exception('Face encoding initialization failed: $e');
    }
  }

  /// Setup isolate for background processing
  Future<void> _setupProcessingIsolate() async {
    try {
      _receivePort = ReceivePort();
      _processingIsolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
      );
      Logger.success('Processing isolate created');
    } catch (e) {
      Logger.warning('Failed to create processing isolate: $e');
      // Continue without isolate - will process on main thread
    }
  }

  /// Isolate entry point for background processing
  static void _isolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        try {
          final imageBytes = message['imageBytes'] as Uint8List;
          final interpreterAddress = message['interpreterAddress'] as int;

          // Process in isolate
          final embedding = await TFLiteService.extractEmbeddingInIsolate(
            sendPort,
            imageBytes,
            interpreterAddress,
          );

          sendPort.send({'success': true, 'embedding': embedding});
        } catch (e) {
          sendPort.send({'success': false, 'error': e.toString()});
        }
      }
    });
  }

  /// Extract face encoding from camera image
  Future<FaceEncodingResult?> extractFromCameraImage(
    CameraImage cameraImage,
    CameraDescription cameraDescription,
  ) async {
    Logger.info('>>> FaceEncodingService.extractFromCameraImage START <<<');
    Logger.info('Camera image dimensions: ${cameraImage.width}x${cameraImage.height}');
    Logger.info('Camera description: ${cameraDescription.name}');
    Logger.info('Is processing: $_isProcessing');

    // Quick null/validity checks before processing
    try {
      if (cameraImage.planes.isEmpty) {
        Logger.warning('Camera image has no planes - returning null');
        return null;
      }
      Logger.info('Camera image has ${cameraImage.planes.length} planes');
    } catch (e) {
      Logger.error('Invalid camera image provided', error: e);
      return null;
    }

    if (_isProcessing) {
      Logger.warning('Already processing a face - skipping');
      return null;
    }

    _isProcessing = true;
    try {
      final startTime = DateTime.now();

      // Detect faces in the image with enhanced error handling
      Logger.info('Step 1: Detecting faces in camera image...');
      final faceDetectionStopwatch = Stopwatch()..start();

      final faces = await _faceDetectionService.detectFacesFromCameraImage(
        cameraImage,
        cameraDescription,
      ).catchError((e) {
        Logger.error('Face detection failed with CameraImage', error: e);
        throw Exception('Face detection error: $e');
      });

      faceDetectionStopwatch.stop();
      Logger.info('Face detection completed in ${faceDetectionStopwatch.elapsedMilliseconds}ms');
      Logger.info('Detected ${faces.length} faces');

      if (faces.isEmpty) {
        Logger.debug('No faces detected in camera image - returning null');
        return null;
      }

      for (int i = 0; i < faces.length; i++) {
        final face = faces[i];
        Logger.info('Face $i: bounds=${face.bounds.left},${face.bounds.top},${face.bounds.width}x${face.bounds.height}');
        Logger.info('Face $i: quality=${face.qualityScore}');
      }

      // Use the first face (best quality)
      Logger.info('Step 2: Selecting best face...');
      final face = _selectBestFace(faces);
      if (face == null) {
        Logger.warning('No suitable face found for encoding - returning null');
        return null;
      }

      Logger.success('Selected face with quality: ${face.qualityScore}');

      // Convert camera image to processable format with rotation
      Logger.info('Step 3: Converting camera image to processable format...');
      final conversionStopwatch = Stopwatch()..start();
      // Pass sensor orientation for proper rotation (270 for front camera)
      final image = FaceProcessingUtils.convertCameraImage(
        cameraImage,
        sensorOrientation: cameraDescription.sensorOrientation,
      );
      conversionStopwatch.stop();

      Logger.info('Image conversion completed in ${conversionStopwatch.elapsedMilliseconds}ms');

      if (image == null) {
        Logger.error('Failed to convert camera image - returning null');
        return null;
      }

      Logger.success('Converted image dimensions: ${image.width}x${image.height}');

      // Crop and process the face
      Logger.info('Step 4: Processing face image...');
      final processingStopwatch = Stopwatch()..start();
      final processedFace = await _processFaceImage(image, face);
      processingStopwatch.stop();

      Logger.info('Face processing completed in ${processingStopwatch.elapsedMilliseconds}ms');

      if (processedFace == null) {
        Logger.error('Failed to process face image - returning null');
        return null;
      }

      Logger.success('Processed face dimensions: ${processedFace.width}x${processedFace.height}');

      // Extract embedding
      Logger.info('Step 5: Extracting face embedding...');
      final embeddingStopwatch = Stopwatch()..start();
      final embedding = await _extractEmbedding(processedFace);
      embeddingStopwatch.stop();

      Logger.info('Embedding extraction completed in ${embeddingStopwatch.elapsedMilliseconds}ms');

      if (embedding == null) {
        Logger.error('Failed to extract face embedding - returning null');
        return null;
      }

      Logger.success('Extracted embedding length: ${embedding.length}');

      final processingTime = DateTime.now().difference(startTime);
      // Use the original face quality score from detection, not recalculated from processed image
      final quality = face.qualityScore;

      Logger.success('ENCODING SUCCESS - Total time: ${processingTime.inMilliseconds}ms');
      Logger.info('Final quality score: $quality');
      Logger.info('>>> FaceEncodingService.extractFromCameraImage END <<<');

      return FaceEncodingResult(
        embedding: embedding,
        face: face,
        quality: quality,
        processingTime: processingTime,
      );
    } catch (e) {
      Logger.error('Face encoding extraction failed', error: e);
      Logger.info('>>> FaceEncodingService.extractFromCameraImage END (ERROR) <<<');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Extract face encoding from image bytes
  Future<FaceEncodingResult?> extractFromImageBytes(
    Uint8List imageBytes,
  ) async {
    try {
      Logger.info('Extracting face encoding from image bytes...');
      Logger.info('Image bytes size: ${imageBytes.length}');

      // Decode image to get dimensions and process
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        Logger.error('Failed to decode image bytes');
        return null;
      }

      Logger.info('Decoded image dimensions: ${image.width}x${image.height}');

      // Use the new method for detecting faces from image files
      // This handles JPEG/PNG files properly
      final faces = await _faceDetectionService.detectFacesFromImageFile(
        imageBytes, // Pass original file bytes
      );

      Logger.info('Face detection completed: ${faces.length} face(s) found');

      if (faces.isEmpty) {
        Logger.debug('No faces detected in image');
        return null;
      }

      // Process the best face
      final face = _selectBestFace(faces);
      if (face == null) {
        return null;
      }

      // Process face image
      final processedFace = await _processFaceImage(image, face);
      if (processedFace == null) {
        return null;
      }

      // Extract embedding
      final embedding = await _extractEmbedding(processedFace);
      if (embedding == null) {
        return null;
      }

      // Use simplified quality calculation for stored images
      // This matches the camera flow calculation for consistency
      final quality = _calculateSimplifiedQuality(face, image.width, image.height);
      Logger.info('Calculated simplified quality for stored image: ${(quality * 100).toStringAsFixed(1)}%');

      return FaceEncodingResult(
        embedding: embedding,
        face: face,
        quality: quality,
        processingTime: Duration.zero,
      );
    } catch (e) {
      Logger.error('Failed to extract encoding from image bytes', error: e);
      return null;
    }
  }

  /// Select the best face from multiple detections
  FaceDetectionResult? _selectBestFace(List<FaceDetectionResult> faces) {
    if (faces.isEmpty) return null;

    // Sort by quality score and select the best
    final sortedFaces = List<FaceDetectionResult>.from(faces)
      ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore));

    for (final face in sortedFaces) {
      // Check if face is frontal and has good quality
      if (FaceProcessingUtils.isFaceFrontal(face) && face.isGoodQuality) {
        return face;
      }
    }

    // If no ideal face, return the best available
    return sortedFaces.first;
  }

  /// Process face image (crop, align, normalize)
  Future<img.Image?> _processFaceImage(
    img.Image fullImage,
    FaceDetectionResult face,
  ) async {
    try {
      // Crop face from full image
      var faceImage = FaceProcessingUtils.cropFace(fullImage, face);
      if (faceImage == null) {
        return null;
      }

      // Align face if landmarks are available
      faceImage = FaceProcessingUtils.alignFace(faceImage, face) ?? faceImage;

      // Check lighting conditions
      if (!FaceProcessingUtils.isLightingAcceptable(faceImage)) {
        Logger.warning('Poor lighting conditions detected');
      }

      return faceImage;
    } catch (e) {
      Logger.error('Failed to process face image', error: e);
      return null;
    }
  }

  /// Extract embedding from processed face image
  Future<Float32List?> _extractEmbedding(img.Image faceImage) async {
    try {
      // Convert image to bytes
      final imageBytes = FaceProcessingUtils.imageToBytes(faceImage);

      // Extract embedding using TFLite service
      final embedding = await _tfliteService.extractEmbedding(imageBytes);

      return embedding;
    } catch (e) {
      Logger.error('Failed to extract embedding', error: e);
      return null;
    }
  }

  /// Calculate simplified quality score for stored images
  /// This matches the camera flow calculation for consistency
  double _calculateSimplifiedQuality(FaceDetectionResult face, int imageWidth, int imageHeight) {
    final imageArea = imageWidth * imageHeight;
    final faceArea = face.bounds.width * face.bounds.height;
    final faceRatio = faceArea / imageArea;

    // Size score (ideal: 15-50% of image, more lenient)
    double sizeScore = 1.0;
    if (faceRatio < 0.15) {
      // Gentler penalty for smaller faces
      sizeScore = math.pow(faceRatio / 0.15, 0.7).toDouble();
    } else if (faceRatio > 0.5) {
      // Gentler penalty for larger faces
      sizeScore = math.pow(0.5 / faceRatio, 0.7).toDouble();
    }

    // Center score (more forgiving)
    final centerX = imageWidth / 2;
    final centerY = imageHeight / 2;
    final faceCenterX = face.bounds.left + face.bounds.width / 2;
    final faceCenterY = face.bounds.top + face.bounds.height / 2;
    final distanceFromCenter = (faceCenterX - centerX).abs() / centerX +
                               (faceCenterY - centerY).abs() / centerY;
    final centerScore = (1.0 - distanceFromCenter / 3).clamp(0.0, 1.0); // Reduced penalty

    // Give more weight to size score for better UX
    final quality = (sizeScore * 0.7 + centerScore * 0.3).clamp(0.0, 1.0);

    // Log quality details for debugging
    Logger.debug('Stored image face quality - Ratio: ${(faceRatio * 100).toStringAsFixed(1)}%, '
                 'Size score: ${(sizeScore * 100).toStringAsFixed(0)}%, '
                 'Center score: ${(centerScore * 100).toStringAsFixed(0)}%, '
                 'Final: ${(quality * 100).toStringAsFixed(0)}%');

    return quality;
  }

  /// Compare two face encodings
  SimpleFaceMatchResult compareFaces(
    Float32List embedding1,
    Float32List embedding2, {
    double threshold = 0.6,
  }) {
    final distance = _tfliteService.calculateDistance(embedding1, embedding2);
    final similarity = _tfliteService.calculateCosineSimilarity(embedding1, embedding2);
    final confidence = _tfliteService.getMatchConfidence(embedding1, embedding2);
    final isMatch = distance < threshold;

    return SimpleFaceMatchResult(
      isMatch: isMatch,
      distance: distance,
      similarity: similarity,
      confidence: confidence,
      threshold: threshold,
    );
  }

  /// Find best match from a list of known embeddings
  SimpleFaceMatchResult? findBestMatch(
    Float32List queryEmbedding,
    Map<String, Float32List> knownEmbeddings, {
    double threshold = 0.6,
  }) {
    if (knownEmbeddings.isEmpty) return null;

    String? bestMatchId;
    double bestDistance = double.infinity;
    double bestSimilarity = 0;
    double bestConfidence = 0;

    for (final entry in knownEmbeddings.entries) {
      final result = compareFaces(queryEmbedding, entry.value, threshold: threshold);

      if (result.distance < bestDistance) {
        bestDistance = result.distance;
        bestSimilarity = result.similarity;
        bestConfidence = result.confidence;
        bestMatchId = entry.key;
      }
    }

    if (bestMatchId == null || bestDistance >= threshold) {
      return null;
    }

    return SimpleFaceMatchResult(
      isMatch: true,
      distance: bestDistance,
      similarity: bestSimilarity,
      confidence: bestConfidence,
      threshold: threshold,
      matchedId: bestMatchId,
    );
  }

  /// Clear encoding cache
  void clearCache() {
    _encodingCache.clear();
    Logger.debug('Face encoding cache cleared');
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      _processingIsolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      clearCache();
      await _tfliteService.dispose();
      await _faceDetectionService.dispose();
      Logger.info('Face encoding service disposed');
    } catch (e) {
      Logger.error('Error disposing face encoding service', error: e);
    }
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

/// Result of simple face matching
class SimpleFaceMatchResult {
  final bool isMatch;
  final double distance;
  final double similarity;
  final double confidence;
  final double threshold;
  final String? matchedId;

  SimpleFaceMatchResult({
    required this.isMatch,
    required this.distance,
    required this.similarity,
    required this.confidence,
    required this.threshold,
    this.matchedId,
  });

  bool get isHighConfidence => confidence > 0.8;
  bool get isMediumConfidence => confidence > 0.6 && confidence <= 0.8;
  bool get isLowConfidence => confidence <= 0.6;
}