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
      enableClassification: true,    // Enable for better quality scoring
      enableLandmarks: true,         // Enable for face orientation detection
      enableContours: true,          // Required for ACCURATE mode to work properly
      enableTracking: true,          // Enable for continuity between frames
      minFaceSize: 0.10,            // 10% of image - better detection at distance
      performanceMode: mlkit.FaceDetectorMode.accurate,  // Accurate mode for better face detection
    );

    _faceDetector = mlkit.FaceDetector(options: options);
    _isDetectorInitialized = true;
    Logger.info('Face detector initialized - ACCURATE mode with tracking, minFaceSize: 0.10');
  }

  static int _detectionAttempts = 0;
  static int _consecutiveFails = 0;

  Future<List<domain.FaceDetectionResult>> detectFacesFromImage(
    mlkit.InputImage inputImage,
  ) async {
    _detectionAttempts++;

    try {
      final stopwatch = Stopwatch()..start();

      // Enhanced logging: Log input image dimensions and metadata
      Logger.debug('📸 DETECTION ATTEMPT #$_detectionAttempts:');
      Logger.debug('  Image size: ${inputImage.metadata?.size.width.toInt()}x${inputImage.metadata?.size.height.toInt()}');
      Logger.debug('  Format: ${inputImage.metadata?.format}');
      Logger.debug('  Rotation: ${inputImage.metadata?.rotation}');
      Logger.debug('  Bytes per row: ${inputImage.metadata?.bytesPerRow}');

      final faces = await detector.processImage(inputImage);
      stopwatch.stop();

      // Enhanced logging for detection patterns
      if (faces.isNotEmpty) {
        Logger.info('🎯 SUCCESS: Detected ${faces.length} face(s) in ${stopwatch.elapsedMilliseconds}ms (attempt #$_detectionAttempts)');
        for (int i = 0; i < faces.length; i++) {
          final face = faces[i];
          Logger.debug('  Face $i: bounds=${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()} at (${face.boundingBox.left.toInt()},${face.boundingBox.top.toInt()})');
          Logger.debug('  Tracking ID: ${face.trackingId}, Head angles: X=${face.headEulerAngleX?.toStringAsFixed(1)}° Y=${face.headEulerAngleY?.toStringAsFixed(1)}°');
        }
        // Reset consecutive counter when we detect faces
        _consecutiveFails = 0;
      } else {
        // Count consecutive failed attempts
        _consecutiveFails++;
        Logger.debug('❌ No faces detected (${stopwatch.elapsedMilliseconds}ms) - attempt #$_detectionAttempts [${_consecutiveFails} consecutive fails]');

        // Log warning every 30 failed attempts
        if (_consecutiveFails % 30 == 0) {
          Logger.warning('⚠️ DETECTION ISSUE: ${_consecutiveFails} consecutive detection failures - check lighting, positioning, or camera setup');
        }
      }

      return faces.map((face) => _convertToFaceDetectionResult(face)).toList();
    } catch (e) {
      Logger.error('Face detection failed on attempt #$_detectionAttempts', error: e);
      return [];
    }
  }

  Future<List<domain.FaceDetectionResult>> detectFacesFromCameraImage(
    camera.CameraImage image,
    camera.CameraDescription cameraDescription,
  ) async {
    try {
      final inputImage = _convertCameraImage(image, cameraDescription);
      if (inputImage == null) {
        Logger.warning('Failed to convert camera image');
        return [];
      }

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Face detection from camera failed', error: e);
      return [];
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

  /// Detect faces from file path (for JPEG/PNG files)
  Future<List<domain.FaceDetectionResult>> detectFacesFromFilePath(
    String filePath,
  ) async {
    try {
      Logger.debug('Detecting faces from file: $filePath');

      // Use InputImage.fromFilePath which properly handles JPEG files
      final inputImage = mlkit.InputImage.fromFilePath(filePath);

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Face detection from file path failed', error: e);
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

      // Debug logging for rotation
      Logger.debug('Camera: ${cameraDescription.lensDirection == camera.CameraLensDirection.front ? "Front" : "Back"}, '
          'Sensor orientation: ${cameraDescription.sensorOrientation}, '
          'Rotation: $rotation');

      // Get image format
      final format = _getImageFormat(image);
      if (format == null) {
        Logger.warning('Unsupported image format');
        return null;
      }

      // Convert YUV420 to NV21 for ML Kit
      final bytes = _convertYuv420ToNv21(image);

      // CRITICAL FIX: Keep dimensions aligned with byte array layout
      // Do NOT swap dimensions - let ML Kit handle rotation internally
      double width = image.width.toDouble();
      double height = image.height.toDouble();

      // Enhanced debugging for rotation and dimension alignment
      final expectedPixels = width * height;
      final expectedBytes = (expectedPixels * 1.5).round(); // YUV420 = 1.5 bytes per pixel
      final actualBytes = bytes.length;
      final bytesMatch = expectedBytes == actualBytes;

      Logger.debug('Rotation mapping: sensor ${cameraDescription.sensorOrientation}° → ML Kit ${rotation.toString().split('.').last}');
      Logger.debug('Dimensions: ${width}x$height (${expectedPixels.round()} pixels)');
      Logger.debug('Bytes: expected $expectedBytes, actual $actualBytes, match: $bytesMatch');
      Logger.debug('Format: $format, BytesPerRow: ${image.planes[0].bytesPerRow}');

      return mlkit.InputImage.fromBytes(
        bytes: bytes,
        metadata: mlkit.InputImageMetadata(
          size: ui.Size(width, height),
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
    final sensorOrientation = cameraDescription.sensorOrientation;
    final isFrontCamera = cameraDescription.lensDirection == camera.CameraLensDirection.front;

    Logger.debug('Camera rotation - Sensor orientation: $sensorOrientation, Front camera: $isFrontCamera');

    // OPTIMIZED ROTATION MAPPING: Handle front camera rotation more accurately
    // Account for both sensor orientation and front camera mirroring
    int rotation = sensorOrientation;

    if (isFrontCamera) {
      // Front cameras typically need adjusted rotation to account for mirroring
      // and proper ML Kit coordinate system alignment
      switch (sensorOrientation) {
        case 270:
          rotation = 90; // 270° sensor → 90° ML Kit (most common case)
          break;
        case 90:
          rotation = 270; // 90° sensor → 270° ML Kit
          break;
        case 0:
          rotation = 0; // Keep 0° for portrait front cameras
          break;
        case 180:
          rotation = 180; // Keep 180° for upside-down orientation
          break;
        default:
          Logger.warning('Unexpected sensor orientation: $sensorOrientation, using as-is');
          rotation = sensorOrientation;
      }
    }

    Logger.debug('Using rotation: $rotation degrees (sensor: $sensorOrientation)');

    switch (rotation) {
      case 0:
        return mlkit.InputImageRotation.rotation0deg;
      case 90:
        return mlkit.InputImageRotation.rotation90deg;
      case 180:
        return mlkit.InputImageRotation.rotation180deg;
      case 270:
        return mlkit.InputImageRotation.rotation270deg;
      default:
        Logger.warning('Unknown rotation $rotation, defaulting to 0 degrees');
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

    // DIAGNOSTIC LOGGING - Log raw rotation values from ML Kit
    Logger.debug('🔄 ROTATION DEBUG - Raw ML Kit values:');
    Logger.debug('  X (pitch): ${face.headEulerAngleX?.toStringAsFixed(1)}°');
    Logger.debug('  Y (yaw): ${face.headEulerAngleY?.toStringAsFixed(1)}°');
    Logger.debug('  Z (roll): ${face.headEulerAngleZ?.toStringAsFixed(1)}°');

    // Determine face orientation
    final yaw = face.headEulerAngleY?.abs() ?? 0.0;
    final pitch = face.headEulerAngleX?.abs() ?? 0.0;
    String orientation = 'FRONTAL';
    if (yaw > 30) orientation = 'PROFILE';
    if (pitch > 30) orientation = 'TILTED';
    Logger.debug('  Orientation: $orientation (yaw: ${yaw.toStringAsFixed(1)}°, pitch: ${pitch.toStringAsFixed(1)}°)');

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

  Future<void> dispose() async {
    try {
      await _faceDetector?.close();
      _faceDetector = null;
      _isDetectorInitialized = false;
      Logger.info('Face detector disposed and reset');
    } catch (e) {
      Logger.error('Failed to dispose face detector', error: e);
    }
  }
}