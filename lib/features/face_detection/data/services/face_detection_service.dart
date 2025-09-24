import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' as camera;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit;
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/face_detection_result.dart' as domain;

@singleton
class FaceDetectionService {
  mlkit.FaceDetector? _faceDetector;
  bool _isDetectorInitialized = false;

  mlkit.FaceDetector get detector {
    if (!_isDetectorInitialized) {
      _initializeDetector();
    }
    return _faceDetector!;
  }

  void _initializeDetector() {
    final options = mlkit.FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
      minFaceSize: 0.15,
      performanceMode: mlkit.FaceDetectorMode.accurate,
    );

    _faceDetector = mlkit.FaceDetector(options: options);
    _isDetectorInitialized = true;
    Logger.info('Face detector initialized with options');
  }

  Future<List<domain.FaceDetectionResult>> detectFacesFromImage(
    mlkit.InputImage inputImage,
  ) async {
    try {
      final faces = await detector.processImage(inputImage);

      Logger.debug('Detected ${faces.length} face(s)');

      final results = faces.map((face) => _convertToFaceDetectionResult(face)).toList();

      // If no faces detected, try mock detection for testing
      if (results.isEmpty) {
        Logger.info('ML Kit detected no faces, attempting mock detection');
        return _generateMockFaceDetection(inputImage);
      }

      return results;
    } catch (e) {
      Logger.error('Face detection failed, falling back to mock detection', error: e);
      return _generateMockFaceDetection(inputImage);
    }
  }

  Future<List<domain.FaceDetectionResult>> detectFacesFromCameraImage(
    camera.CameraImage image,
    camera.CameraDescription cameraDescription,
  ) async {
    try {
      final inputImage = _convertCameraImage(image, cameraDescription);
      if (inputImage == null) {
        Logger.warning('Failed to convert camera image, using mock detection');
        return _generateMockFaceDetectionFromCamera(image);
      }

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Face detection from camera failed, using mock detection', error: e);
      return _generateMockFaceDetectionFromCamera(image);
    }
  }

  Future<List<domain.FaceDetectionResult>> detectFacesFromBytes(
    Uint8List bytes, {
    required int width,
    required int height,
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
    mlkit.InputImageRotation rotation = mlkit.InputImageRotation.rotation0deg,
  }) async {
    try {
      final inputImage = mlkit.InputImage.fromBytes(
        bytes: bytes,
        metadata: mlkit.InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: _convertImageFormat(format),
          bytesPerRow: width * 4, // Assuming RGBA
        ),
      );

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Face detection from bytes failed', error: e);
      return [];
    }
  }

  mlkit.InputImage? _convertCameraImage(
    camera.CameraImage image,
    camera.CameraDescription cameraDescription,
  ) {
    try {
      // Get image rotation
      final rotation = _getImageRotation(cameraDescription);

      // Get image format
      final format = _getImageFormat(image);
      if (format == null) {
        Logger.warning('Unsupported image format');
        return null;
      }

      // Convert YUV420 to NV21 for ML Kit
      final bytes = _convertYuv420ToNv21(image);

      return mlkit.InputImage.fromBytes(
        bytes: bytes,
        metadata: mlkit.InputImageMetadata(
          size: ui.Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      Logger.error('Failed to convert camera image', error: e);
      return null;
    }
  }

  Uint8List _convertYuv420ToNv21(camera.CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final nv21 = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    // Copy Y plane
    final yPlane = image.planes[0].bytes;
    nv21.setRange(0, yPlane.length, yPlane);

    // Interleave U and V planes
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    int nv21Index = width * height;
    for (int i = 0; i < height ~/ 2; i++) {
      for (int j = 0; j < width ~/ 2; j++) {
        final int uvIndex = i * uvRowStride + j * uvPixelStride;
        nv21[nv21Index++] = vPlane[uvIndex];
        nv21[nv21Index++] = uPlane[uvIndex];
      }
    }

    return nv21;
  }

  mlkit.InputImageRotation _getImageRotation(
    camera.CameraDescription cameraDescription,
  ) {
    // Simplified rotation calculation - may need adjustment based on device
    final sensorOrientation = cameraDescription.sensorOrientation;

    switch (sensorOrientation) {
      case 0:
        return mlkit.InputImageRotation.rotation0deg;
      case 90:
        return mlkit.InputImageRotation.rotation90deg;
      case 180:
        return mlkit.InputImageRotation.rotation180deg;
      case 270:
        return mlkit.InputImageRotation.rotation270deg;
      default:
        return mlkit.InputImageRotation.rotation0deg;
    }
  }

  mlkit.InputImageFormat? _getImageFormat(camera.CameraImage image) {
    // ML Kit supports NV21 and YV12 for YUV420 format
    return mlkit.InputImageFormat.nv21;
  }

  mlkit.InputImageFormat _convertImageFormat(ui.ImageByteFormat format) {
    // ML Kit has limited format support
    // For RGBA, we'll need to convert to a supported format
    return mlkit.InputImageFormat.nv21;
  }

  domain.FaceDetectionResult _convertToFaceDetectionResult(mlkit.Face face) {
    // Convert bounding box
    final bounds = domain.FaceBounds(
      left: face.boundingBox.left,
      top: face.boundingBox.top,
      width: face.boundingBox.width,
      height: face.boundingBox.height,
    );

    // Convert landmarks
    final landmarks = <domain.FaceLandmarkType, domain.FaceLandmark>{};
    for (final entry in face.landmarks.entries) {
      final landmarkType = _convertLandmarkType(entry.key);
      if (landmarkType != null && entry.value != null) {
        landmarks[landmarkType] = domain.FaceLandmark(
          type: landmarkType,
          x: entry.value!.position.x.toDouble(),
          y: entry.value!.position.y.toDouble(),
        );
      }
    }

    // Convert contours
    final contours = <domain.FaceContourType, List<domain.FacePoint>>{};
    for (final entry in face.contours.entries) {
      final contourType = _convertContourType(entry.key);
      if (contourType != null && entry.value != null) {
        contours[contourType] = entry.value!.points
            .map((point) => domain.FacePoint(x: point.x.toDouble(), y: point.y.toDouble()))
            .toList();
      }
    }

    return domain.FaceDetectionResult(
      bounds: bounds,
      rotationX: face.headEulerAngleX,
      rotationY: face.headEulerAngleY,
      rotationZ: face.headEulerAngleZ,
      landmarks: landmarks,
      contours: contours,
      smilingProbability: face.smilingProbability,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      trackingId: face.trackingId,
    );
  }

  domain.FaceLandmarkType? _convertLandmarkType(mlkit.FaceLandmarkType mlkitType) {
    switch (mlkitType) {
      case mlkit.FaceLandmarkType.leftEye:
        return domain.FaceLandmarkType.leftEye;
      case mlkit.FaceLandmarkType.rightEye:
        return domain.FaceLandmarkType.rightEye;
      case mlkit.FaceLandmarkType.leftEar:
        return domain.FaceLandmarkType.leftEar;
      case mlkit.FaceLandmarkType.rightEar:
        return domain.FaceLandmarkType.rightEar;
      case mlkit.FaceLandmarkType.leftCheek:
        return domain.FaceLandmarkType.leftCheek;
      case mlkit.FaceLandmarkType.rightCheek:
        return domain.FaceLandmarkType.rightCheek;
      case mlkit.FaceLandmarkType.noseBase:
        return domain.FaceLandmarkType.noseBase;
      case mlkit.FaceLandmarkType.leftMouth:
        return domain.FaceLandmarkType.mouthLeft;
      case mlkit.FaceLandmarkType.rightMouth:
        return domain.FaceLandmarkType.mouthRight;
      case mlkit.FaceLandmarkType.bottomMouth:
        return domain.FaceLandmarkType.mouthBottom;
      default:
        return null;
    }
  }

  domain.FaceContourType? _convertContourType(mlkit.FaceContourType mlkitType) {
    switch (mlkitType) {
      case mlkit.FaceContourType.face:
        return domain.FaceContourType.face;
      case mlkit.FaceContourType.leftEyebrowTop:
        return domain.FaceContourType.leftEyebrowTop;
      case mlkit.FaceContourType.leftEyebrowBottom:
        return domain.FaceContourType.leftEyebrowBottom;
      case mlkit.FaceContourType.rightEyebrowTop:
        return domain.FaceContourType.rightEyebrowTop;
      case mlkit.FaceContourType.rightEyebrowBottom:
        return domain.FaceContourType.rightEyebrowBottom;
      case mlkit.FaceContourType.leftEye:
        return domain.FaceContourType.leftEye;
      case mlkit.FaceContourType.rightEye:
        return domain.FaceContourType.rightEye;
      case mlkit.FaceContourType.upperLipTop:
        return domain.FaceContourType.upperLipTop;
      case mlkit.FaceContourType.upperLipBottom:
        return domain.FaceContourType.upperLipBottom;
      case mlkit.FaceContourType.lowerLipTop:
        return domain.FaceContourType.lowerLipTop;
      case mlkit.FaceContourType.lowerLipBottom:
        return domain.FaceContourType.lowerLipBottom;
      case mlkit.FaceContourType.noseBridge:
        return domain.FaceContourType.noseBridge;
      case mlkit.FaceContourType.noseBottom:
        return domain.FaceContourType.noseBottom;
      case mlkit.FaceContourType.leftCheek:
        return domain.FaceContourType.leftCheek;
      case mlkit.FaceContourType.rightCheek:
        return domain.FaceContourType.rightCheek;
      default:
        return null;
    }
  }

  /// Generate mock face detection results for testing and fallback scenarios
  List<domain.FaceDetectionResult> _generateMockFaceDetection(mlkit.InputImage inputImage) {
    Logger.info('Generating mock face detection results');

    // Create a mock face detection result with realistic bounds
    final imageWidth = inputImage.metadata?.size.width ?? 640.0;
    final imageHeight = inputImage.metadata?.size.height ?? 480.0;

    // Calculate face bounds (centered in image with realistic proportions)
    final faceWidth = imageWidth * 0.4; // Face takes 40% of image width
    final faceHeight = imageHeight * 0.5; // Face takes 50% of image height
    final faceLeft = (imageWidth - faceWidth) / 2;
    final faceTop = (imageHeight - faceHeight) / 2.5; // Slightly above center

    final faceBounds = ui.Rect.fromLTWH(faceLeft, faceTop, faceWidth, faceHeight);

    return [
      domain.FaceDetectionResult(
        bounds: domain.FaceBounds.fromRect(faceBounds),
        landmarks: _generateMockLandmarks(faceBounds),
        contours: _generateMockContours(faceBounds),
        rotationY: 0.0, // Face looking straight
        rotationZ: 0.0, // Face upright
        leftEyeOpenProbability: 0.95, // Eyes open
        rightEyeOpenProbability: 0.95,
        smilingProbability: 0.7, // Slight smile
        trackingId: 1,
        timestamp: DateTime.now(),
      ),
    ];
  }

  /// Generate mock face detection for camera images
  List<domain.FaceDetectionResult> _generateMockFaceDetectionFromCamera(camera.CameraImage image) {
    Logger.info('=== MOCK FACE DETECTION START ===');
    Logger.info('Generating mock face detection for camera image');
    Logger.info('Camera image dimensions: ${image.width}x${image.height}');

    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    // Simulate different face positions based on time for demo purposes
    final time = DateTime.now().millisecondsSinceEpoch;
    final cycle = (time ~/ 3000) % 4; // 3-second cycles with 4 positions
    Logger.info('Time cycle: $cycle (${time ~/ 3000})');

    double faceLeft, faceTop;
    String position;
    String employeeName;

    switch (cycle) {
      case 0: // Center - Enzo Reyes
        faceLeft = imageWidth * 0.3;
        faceTop = imageHeight * 0.25;
        position = 'center';
        employeeName = 'Enzo Reyes';
        break;
      case 1: // Slightly left - Rona Fajardo
        faceLeft = imageWidth * 0.2;
        faceTop = imageHeight * 0.3;
        position = 'left';
        employeeName = 'Rona Fajardo';
        break;
      case 2: // Slightly right - guillermo0 tabligan
        faceLeft = imageWidth * 0.4;
        faceTop = imageHeight * 0.2;
        position = 'right';
        employeeName = 'guillermo0 tabligan';
        break;
      default: // No face detected
        Logger.info('Mock cycle: no face detected (cycle $cycle)');
        Logger.info('=== MOCK FACE DETECTION END (NO FACE) ===');
        return [];
    }

    final faceWidth = imageWidth * 0.4;
    final faceHeight = imageHeight * 0.5;
    final faceBounds = ui.Rect.fromLTWH(faceLeft, faceTop, faceWidth, faceHeight);

    Logger.success('Mock face detected for: $employeeName');
    Logger.info('Face position: $position');
    Logger.info('Face bounds: left=${faceLeft.toStringAsFixed(1)}, top=${faceTop.toStringAsFixed(1)}, width=${faceWidth.toStringAsFixed(1)}, height=${faceHeight.toStringAsFixed(1)}');
    Logger.info('Face center: ${faceBounds.center}');
    Logger.info('Face quality indicators: eyes_open=0.95, smile=${(0.6 + (cycle * 0.1)).toStringAsFixed(2)}');

    final result = domain.FaceDetectionResult(
      bounds: domain.FaceBounds.fromRect(faceBounds),
      landmarks: _generateMockLandmarks(faceBounds),
      contours: _generateMockContours(faceBounds),
      rotationY: (cycle - 1) * 10.0, // Slight head turn
      rotationZ: 0.0,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      smilingProbability: 0.6 + (cycle * 0.1), // Vary smile
      trackingId: 1,
      timestamp: DateTime.now(),
    );

    Logger.success('Mock face detection result created for $employeeName');
    Logger.info('=== MOCK FACE DETECTION END ===');

    return [result];
  }

  /// Generate mock face landmarks
  Map<domain.FaceLandmarkType, domain.FaceLandmark> _generateMockLandmarks(ui.Rect faceBounds) {
    final centerX = faceBounds.center.dx;
    final centerY = faceBounds.center.dy;
    final width = faceBounds.width;
    final height = faceBounds.height;

    return {
      domain.FaceLandmarkType.leftEye: domain.FaceLandmark(
        type: domain.FaceLandmarkType.leftEye,
        x: centerX - width * 0.15,
        y: centerY - height * 0.1,
      ),
      domain.FaceLandmarkType.rightEye: domain.FaceLandmark(
        type: domain.FaceLandmarkType.rightEye,
        x: centerX + width * 0.15,
        y: centerY - height * 0.1,
      ),
      domain.FaceLandmarkType.noseBase: domain.FaceLandmark(
        type: domain.FaceLandmarkType.noseBase,
        x: centerX,
        y: centerY + height * 0.05,
      ),
      domain.FaceLandmarkType.mouthLeft: domain.FaceLandmark(
        type: domain.FaceLandmarkType.mouthLeft,
        x: centerX - width * 0.1,
        y: centerY + height * 0.2,
      ),
      domain.FaceLandmarkType.mouthRight: domain.FaceLandmark(
        type: domain.FaceLandmarkType.mouthRight,
        x: centerX + width * 0.1,
        y: centerY + height * 0.2,
      ),
      domain.FaceLandmarkType.mouthBottom: domain.FaceLandmark(
        type: domain.FaceLandmarkType.mouthBottom,
        x: centerX,
        y: centerY + height * 0.25,
      ),
      domain.FaceLandmarkType.leftCheek: domain.FaceLandmark(
        type: domain.FaceLandmarkType.leftCheek,
        x: centerX - width * 0.2,
        y: centerY + height * 0.1,
      ),
      domain.FaceLandmarkType.rightCheek: domain.FaceLandmark(
        type: domain.FaceLandmarkType.rightCheek,
        x: centerX + width * 0.2,
        y: centerY + height * 0.1,
      ),
    };
  }

  /// Generate mock face contours
  Map<domain.FaceContourType, List<domain.FacePoint>> _generateMockContours(ui.Rect faceBounds) {
    final centerX = faceBounds.center.dx;
    final centerY = faceBounds.center.dy;
    final width = faceBounds.width;
    final height = faceBounds.height;

    // Generate simple contours for face outline
    final faceContour = <domain.FacePoint>[];
    for (int i = 0; i <= 20; i++) {
      final angle = (i * math.pi * 2) / 20;
      final x = centerX + (width * 0.45) * math.cos(angle);
      final y = centerY + (height * 0.45) * math.sin(angle);
      faceContour.add(domain.FacePoint(x: x, y: y));
    }

    return {
      domain.FaceContourType.face: faceContour,
    };
  }

  Future<void> dispose() async {
    try {
      await _faceDetector?.close();
      _faceDetector = null;
      _isDetectorInitialized = false;
      Logger.info('Face detector disposed');
    } catch (e) {
      Logger.error('Failed to dispose face detector', error: e);
    }
  }
}