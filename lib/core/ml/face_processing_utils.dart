import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../../features/face_detection/domain/entities/face_detection_result.dart';
import '../utils/logger.dart';

class FaceProcessingUtils {
  static const int targetSize = 112; // MobileFaceNet input size
  static const double expandRatio = 1.2; // Expand face box by 20%

  /// Convert CameraImage to Image package format with rotation
  static img.Image? convertCameraImage(CameraImage cameraImage, {int? sensorOrientation}) {
    try {
      img.Image? image;

      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        image = _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        image = _convertBGRA8888ToImage(cameraImage);
      }

      if (image == null) {
        Logger.warning('Unsupported image format: ${cameraImage.format.group}');
        return null;
      }

      // Apply rotation based on sensor orientation
      if (sensorOrientation != null && sensorOrientation != 0) {
        Logger.debug('Rotating image by $sensorOrientation degrees for face processing');
        image = img.copyRotate(image, angle: sensorOrientation);
      }

      return image;
    } catch (e) {
      Logger.error('Failed to convert camera image', error: e);
      return null;
    }
  }

  /// Convert YUV420 to Image
  static img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    final img.Image image = img.Image(width: width, height: height);

    final Uint8List yPlane = cameraImage.planes[0].bytes;
    final Uint8List uPlane = cameraImage.planes[1].bytes;
    final Uint8List vPlane = cameraImage.planes[2].bytes;

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yValue = yPlane[yIndex];
        final int uValue = uPlane[uvIndex];
        final int vValue = vPlane[uvIndex];

        // Convert YUV to RGB
        final int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        final int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
            .round()
            .clamp(0, 255);
        final int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return image;
  }

  /// Convert BGRA8888 to Image
  static img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: cameraImage.planes[0].bytes.buffer,
      format: img.Format.uint8,
    );
  }

  /// Crop face from image based on detection result
  static img.Image? cropFace(
    img.Image fullImage,
    FaceDetectionResult face, {
    bool expand = true,
  }) {
    try {
      // Get face bounds
      double left = face.bounds.left;
      double top = face.bounds.top;
      double width = face.bounds.width;
      double height = face.bounds.height;

      // Expand bounds if requested (to include more context)
      if (expand) {
        final double expandAmount = (expandRatio - 1.0) / 2.0;
        final double expandX = width * expandAmount;
        final double expandY = height * expandAmount;

        left = (left - expandX).clamp(0, fullImage.width.toDouble());
        top = (top - expandY).clamp(0, fullImage.height.toDouble());
        width = (width + 2 * expandX).clamp(0, fullImage.width - left);
        height = (height + 2 * expandY).clamp(0, fullImage.height - top);
      }

      // Convert to integers
      final int x = left.round();
      final int y = top.round();
      final int w = width.round();
      final int h = height.round();

      // Validate bounds
      if (x < 0 || y < 0 || x + w > fullImage.width || y + h > fullImage.height) {
        Logger.warning('Invalid crop bounds: x=$x, y=$y, w=$w, h=$h');
        return null;
      }

      // Crop the face
      final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);

      // Resize to target size (112x112 for MobileFaceNet)
      final resized = img.copyResize(
        cropped,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.cubic,
      );

      return resized;
    } catch (e) {
      Logger.error('Failed to crop face', error: e);
      return null;
    }
  }

  /// Align face based on eye positions (simple 2D alignment)
  static img.Image? alignFace(
    img.Image faceImage,
    FaceDetectionResult face,
  ) {
    try {
      // Check if we have eye landmarks
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      if (leftEye == null || rightEye == null) {
        Logger.debug('No eye landmarks available for alignment');
        return faceImage;
      }

      // Calculate angle between eyes
      final double dx = rightEye.x - leftEye.x;
      final double dy = rightEye.y - leftEye.y;
      final double angle = math.atan2(dy, dx);

      // Convert to degrees
      final double degrees = angle * 180 / math.pi;

      // Rotate image to align eyes horizontally
      if (degrees.abs() > 5) {
        // Only rotate if angle is significant
        final rotated = img.copyRotate(faceImage, angle: -degrees);

        // Crop to remove black borders from rotation
        final int cropSize = (targetSize * 0.9).round();
        final int offset = ((targetSize - cropSize) / 2).round();

        final cropped = img.copyCrop(
          rotated,
          x: offset,
          y: offset,
          width: cropSize,
          height: cropSize,
        );

        return img.copyResize(
          cropped,
          width: targetSize,
          height: targetSize,
          interpolation: img.Interpolation.cubic,
        );
      }

      return faceImage;
    } catch (e) {
      Logger.error('Failed to align face', error: e);
      return faceImage;
    }
  }

  /// Calculate face quality score
  static double calculateFaceQuality(
    FaceDetectionResult face,
    img.Image? faceImage,
  ) {
    double qualityScore = 1.0;

    // Check face angle (from detection result)
    qualityScore *= face.qualityScore;

    // Check face size (should be large enough)
    final double sizeScore = math.min(1.0, face.bounds.width / 100.0);
    qualityScore *= sizeScore;

    // Check if image is blurry (if image provided)
    if (faceImage != null) {
      final double blurScore = _calculateBlurScore(faceImage);
      qualityScore *= blurScore;
    }

    return qualityScore.clamp(0.0, 1.0);
  }

  /// Calculate blur score using Laplacian variance
  static double _calculateBlurScore(img.Image image) {
    try {
      // Convert to grayscale
      final grayscale = img.grayscale(image);

      // Apply Laplacian kernel
      const kernel = [
        [0, 1, 0],
        [1, -4, 1],
        [0, 1, 0],
      ];

      double variance = 0.0;
      int count = 0;

      for (int y = 1; y < grayscale.height - 1; y++) {
        for (int x = 1; x < grayscale.width - 1; x++) {
          double sum = 0.0;

          for (int ky = 0; ky < 3; ky++) {
            for (int kx = 0; kx < 3; kx++) {
              final pixel = grayscale.getPixel(x + kx - 1, y + ky - 1);
              sum += pixel.r * kernel[ky][kx];
            }
          }

          variance += sum * sum;
          count++;
        }
      }

      variance /= count;

      // Convert variance to score (higher variance = sharper image)
      // Threshold values based on empirical testing
      const double minVariance = 100.0;
      const double maxVariance = 1000.0;

      final double score = (variance - minVariance) / (maxVariance - minVariance);
      return score.clamp(0.0, 1.0);
    } catch (e) {
      Logger.error('Failed to calculate blur score', error: e);
      return 0.5; // Return neutral score on error
    }
  }

  /// Convert image to bytes (for model input)
  static Uint8List imageToBytes(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Create augmented versions of face for better matching
  static List<img.Image> augmentFace(img.Image faceImage) {
    final augmented = <img.Image>[faceImage];

    try {
      // Add slight brightness variations
      augmented.add(img.adjustColor(faceImage, brightness: 1.1));
      augmented.add(img.adjustColor(faceImage, brightness: 0.9));

      // Add slight contrast variations
      augmented.add(img.adjustColor(faceImage, contrast: 1.1));
      augmented.add(img.adjustColor(faceImage, contrast: 0.9));

      // Add horizontal flip (for robustness)
      augmented.add(img.flipHorizontal(faceImage));
    } catch (e) {
      Logger.warning('Failed to augment face image: $e');
    }

    return augmented;
  }

  /// Check if face is frontal (not profile)
  static bool isFaceFrontal(FaceDetectionResult face) {
    // Check head rotation angles
    final double yawThreshold = 30.0; // degrees
    final double pitchThreshold = 30.0; // degrees

    if (face.rotationY != null && face.rotationY!.abs() > yawThreshold) {
      return false; // Face is turned too much left/right
    }

    if (face.rotationX != null && face.rotationX!.abs() > pitchThreshold) {
      return false; // Face is tilted too much up/down
    }

    return true;
  }

  /// Check if lighting conditions are acceptable
  static bool isLightingAcceptable(img.Image faceImage) {
    try {
      // Calculate average brightness
      int totalBrightness = 0;
      int pixelCount = 0;

      for (int y = 0; y < faceImage.height; y += 10) {
        for (int x = 0; x < faceImage.width; x += 10) {
          final pixel = faceImage.getPixel(x, y);
          totalBrightness += ((pixel.r + pixel.g + pixel.b) ~/ 3);
          pixelCount++;
        }
      }

      final double avgBrightness = totalBrightness / pixelCount;

      // Check if brightness is within acceptable range
      const double minBrightness = 50.0;
      const double maxBrightness = 200.0;

      return avgBrightness >= minBrightness && avgBrightness <= maxBrightness;
    } catch (e) {
      Logger.error('Failed to check lighting conditions', error: e);
      return true; // Assume acceptable on error
    }
  }
}