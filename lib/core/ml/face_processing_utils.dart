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

  /// Convert CameraImage to Image package format
  static img.Image? convertCameraImage(CameraImage cameraImage) {
    try {
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToImage(cameraImage);
      }

      Logger.warning('Unsupported image format: ${cameraImage.format.group}');
      return null;
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
    // OPTIMIZED QUALITY CALCULATION: More balanced weighting for frontal vs side view faces
    // Weights: face detection quality (60%), orientation bonus (25%), size (10%), blur (5%)

    double weightedSum = 0.0;
    double totalWeight = 0.0;

    // Face detection quality (60% weight - reduced to give more room for other factors)
    final detectionQuality = face.qualityScore;
    weightedSum += detectionQuality * 0.6;
    totalWeight += 0.6;

    // Orientation-based quality bonus (25% weight - NEW)
    // Give frontal faces a quality boost since they're preferred for recognition
    final double orientationScore = _calculateOrientationScore(face);
    weightedSum += orientationScore * 0.25;
    totalWeight += 0.25;

    // Check face size (10% weight - reduced from 20%)
    final double sizeScore = _calculateSizeScore(face);
    weightedSum += sizeScore * 0.1;
    totalWeight += 0.1;

    // Check if image is blurry (5% weight if available - reduced from 10%)
    double blurScore = 0.7; // Default optimistic score for better quality
    if (faceImage != null) {
      blurScore = _calculateBlurScore(faceImage);
      weightedSum += blurScore * 0.05;
      totalWeight += 0.05;
    }

    // Calculate final quality as weighted average
    final double qualityScore = totalWeight > 0 ? weightedSum / totalWeight : 0.0;
    final double finalScore = qualityScore.clamp(0.0, 1.0);

    // DIAGNOSTIC LOGGING - Log quality calculation breakdown
    Logger.debug('💎 QUALITY DEBUG - Face quality breakdown:');
    Logger.debug('  Detection quality: ${(detectionQuality * 100).toStringAsFixed(1)}% (weight: 60%)');
    Logger.debug('  Orientation score: ${(orientationScore * 100).toStringAsFixed(1)}% (weight: 25%)');
    Logger.debug('  Size score: ${(sizeScore * 100).toStringAsFixed(1)}% (width: ${face.bounds.width.toInt()}px, weight: 10%)');
    Logger.debug('  Blur score: ${(blurScore * 100).toStringAsFixed(1)}% (weight: 5%)');
    Logger.debug('  Final quality: ${(finalScore * 100).toStringAsFixed(1)}%');

    // Check if face is frontal
    final isFrontal = isFaceFrontal(face);
    Logger.debug('  Is frontal: $isFrontal');
    if (!isFrontal && face.rotationY != null) {
      Logger.warning('  Face rejected as non-frontal: yaw=${face.rotationY!.abs().toStringAsFixed(1)}° (threshold: 30°)');
    }

    return finalScore;
  }

  /// Calculate orientation-based quality score
  /// Gives frontal faces a higher score since they're preferred for recognition
  static double _calculateOrientationScore(FaceDetectionResult face) {
    final yaw = face.rotationY?.abs() ?? 0.0;
    final pitch = face.rotationX?.abs() ?? 0.0;

    // Perfect frontal face (yaw/pitch both 0°) gets score of 1.0
    // Score decreases as face turns away from frontal
    final yawScore = math.max(0.0, 1.0 - (yaw / 45.0)); // Linear decrease to 0 at 45°
    final pitchScore = math.max(0.0, 1.0 - (pitch / 45.0)); // Linear decrease to 0 at 45°

    // Combine yaw and pitch scores (both matter for frontal detection)
    final orientationScore = (yawScore + pitchScore) / 2.0;

    return orientationScore.clamp(0.0, 1.0);
  }

  /// Calculate size-based quality score with better scaling
  static double _calculateSizeScore(FaceDetectionResult face) {
    final faceWidth = face.bounds.width;

    // Optimal face size for medium resolution (720x480): ~150-300px width
    // Too small faces are harder to recognize, too large may be cropped
    if (faceWidth < 60) {
      // Very small faces: poor quality
      return (faceWidth / 60.0).clamp(0.0, 1.0);
    } else if (faceWidth <= 150) {
      // Small to medium faces: good quality
      return 0.6 + ((faceWidth - 60) / 90.0) * 0.3; // Scale from 0.6 to 0.9
    } else if (faceWidth <= 300) {
      // Medium to large faces: excellent quality
      return 0.9 + ((faceWidth - 150) / 150.0) * 0.1; // Scale from 0.9 to 1.0
    } else {
      // Very large faces: slightly reduced quality (may be cropped)
      return math.max(0.8, 1.0 - ((faceWidth - 300) / 200.0) * 0.2);
    }
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