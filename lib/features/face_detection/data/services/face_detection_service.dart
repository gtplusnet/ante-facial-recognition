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

      if (results.isEmpty) {
        Logger.warning('No faces detected in image');
      }

      return results;
    } catch (e) {
      Logger.error('Face detection failed - NO FALLBACK', error: e);
      throw Exception('Face detection failed: $e');
    }
  }

  Future<List<domain.FaceDetectionResult>> detectFacesFromCameraImage(
    camera.CameraImage image,
    camera.CameraDescription cameraDescription,
  ) async {
    try {
      final inputImage = _convertCameraImage(image, cameraDescription);
      if (inputImage == null) {
        Logger.error('Failed to convert camera image for ML Kit');
        throw Exception('Camera image conversion failed');
      }

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Face detection from camera failed - NO FALLBACK', error: e);
      throw Exception('Camera face detection failed: $e');
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

  /// Detect faces from a decoded image file (JPEG/PNG)
  Future<List<domain.FaceDetectionResult>> detectFacesFromImageFile(
    Uint8List fileBytes,
  ) async {
    try {
      Logger.info('Detecting faces from image file...');
      Logger.info('File size: ${fileBytes.length} bytes');

      // Directly use the alternative method which properly decodes the image
      return _detectFacesFromDecodedImage(fileBytes);
    } catch (e) {
      Logger.error('Failed to detect faces from image file', error: e);
      return [];
    }
  }

  /// Alternative method: Decode image and convert to NV21 for ML Kit
  Future<List<domain.FaceDetectionResult>> _detectFacesFromDecodedImage(
    Uint8List fileBytes,
  ) async {
    try {
      Logger.info('Using alternative face detection method...');

      // Import image package for decoding
      // Note: This requires adding 'import 'package:image/image.dart' as img;' at the top
      final codec = await ui.instantiateImageCodec(fileBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Get image dimensions
      final width = image.width;
      final height = image.height;

      Logger.info('Decoded image: ${width}x${height}');

      // Convert to byte data
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        Logger.error('Failed to convert image to byte data');
        return [];
      }

      final rgbaBytes = byteData.buffer.asUint8List();

      // Convert RGBA to NV21 for ML Kit
      final nv21Bytes = _convertRgbaToNv21(rgbaBytes, width, height);

      // Create InputImage with NV21 format
      final inputImage = mlkit.InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: mlkit.InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: mlkit.InputImageRotation.rotation0deg,
          format: mlkit.InputImageFormat.nv21,
          bytesPerRow: width, // NV21 has no padding
        ),
      );

      return detectFacesFromImage(inputImage);
    } catch (e) {
      Logger.error('Alternative face detection also failed', error: e);
      return [];
    }
  }

  /// Convert RGBA bytes to NV21 format for ML Kit
  Uint8List _convertRgbaToNv21(Uint8List rgba, int width, int height) {
    // NV21 size = width * height * 1.5
    final ySize = width * height;
    final uvSize = (width * height) ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    // Convert RGBA to YUV and then to NV21
    int nv21Index = 0;
    int uvIndex = ySize;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final rgbaIndex = (y * width + x) * 4;
        final r = rgba[rgbaIndex];
        final g = rgba[rgbaIndex + 1];
        final b = rgba[rgbaIndex + 2];

        // Convert RGB to Y (luminance)
        final yValue = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
        nv21[nv21Index++] = yValue.clamp(0, 255);

        // Sample UV values at every 2x2 block
        if (y % 2 == 0 && x % 2 == 0 && uvIndex < nv21.length - 1) {
          // Convert RGB to UV
          final u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
          final v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

          // NV21 format: V comes first, then U
          nv21[uvIndex++] = v.clamp(0, 255);
          nv21[uvIndex++] = u.clamp(0, 255);
        }
      }
    }

    return nv21;
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

      // Important: For NV21 format, bytesPerRow should match image width for ML Kit
      // The Y plane's bytesPerRow might include padding, but NV21 buffer doesn't
      return mlkit.InputImage.fromBytes(
        bytes: bytes,
        metadata: mlkit.InputImageMetadata(
          size: ui.Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.width, // Use width for NV21, not plane's bytesPerRow
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

    // Calculate the correct NV21 buffer size
    // Y plane: width * height
    // UV plane (interleaved): (width * height) / 2
    final int ySize = width * height;
    final int uvSize = (width * height) ~/ 2;

    final nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane directly
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;

    // Handle Y plane based on stride
    if (yPlane.bytesPerRow == width) {
      // Direct copy if no padding
      nv21.setRange(0, ySize, yBytes);
    } else {
      // Copy row by row if there's padding
      int nv21Offset = 0;
      for (int row = 0; row < height; row++) {
        final start = row * yPlane.bytesPerRow;
        nv21.setRange(nv21Offset, nv21Offset + width, yBytes, start);
        nv21Offset += width;
      }
    }

    // Handle U and V planes
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

    // Start writing UV data after Y data
    int nv21Offset = ySize;

    // Interleave U and V for NV21 format (V first, then U)
    if (uvPixelStride == 2) {
      // UV planes are already interleaved (common on many devices)
      // Just need to ensure V comes before U
      for (int i = 0; i < uvSize ~/ 2; i++) {
        nv21[nv21Offset++] = vBytes[i * 2];
        nv21[nv21Offset++] = uBytes[i * 2];
      }
    } else {
      // UV planes are separate, need to interleave manually
      for (int row = 0; row < height ~/ 2; row++) {
        for (int col = 0; col < width ~/ 2; col++) {
          final int uvIndex = row * uvRowStride + col * uvPixelStride;
          if (uvIndex < vBytes.length && uvIndex < uBytes.length) {
            nv21[nv21Offset++] = vBytes[uvIndex];
            nv21[nv21Offset++] = uBytes[uvIndex];
          }
        }
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

  // Mock detection methods removed - no fallback allowed

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