import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../../core/utils/logger.dart';

class CameraImageConverter {
  static const int thumbnailSize = 150;
  static const int imageQuality = 70;

  /// Convert CameraImage to JPEG bytes
  static Future<Uint8List?> convertCameraImageToJpeg(
    CameraImage cameraImage,
    CameraDescription cameraDescription,
  ) async {
    try {
      final img.Image? image = await _convertYUV420ToImage(cameraImage);
      if (image == null) return null;

      // Rotate image based on camera orientation
      final rotatedImage = _rotateImage(image, cameraDescription);

      // Encode as JPEG
      return Uint8List.fromList(
        img.encodeJpg(rotatedImage, quality: imageQuality),
      );
    } catch (e) {
      Logger.error('Failed to convert CameraImage to JPEG', error: e);
      return null;
    }
  }

  /// Extract face region from full image
  static Future<Uint8List?> extractFaceRegion(
    Uint8List fullImageBytes,
    Face face,
  ) async {
    try {
      final img.Image? fullImage = img.decodeImage(fullImageBytes);
      if (fullImage == null) return null;

      final boundingBox = face.boundingBox;

      // Add 20% padding around the face
      final padding = boundingBox.width * 0.2;
      final x = (boundingBox.left - padding).clamp(0, fullImage.width.toDouble()).toInt();
      final y = (boundingBox.top - padding).clamp(0, fullImage.height.toDouble()).toInt();
      final width = (boundingBox.width + padding * 2).clamp(0, fullImage.width - x.toDouble()).toInt();
      final height = (boundingBox.height + padding * 2).clamp(0, fullImage.height - y.toDouble()).toInt();

      // Crop face region
      final faceImage = img.copyCrop(fullImage, x: x, y: y, width: width, height: height);

      // Encode as JPEG
      return Uint8List.fromList(
        img.encodeJpg(faceImage, quality: imageQuality),
      );
    } catch (e) {
      Logger.error('Failed to extract face region', error: e);
      return fullImageBytes; // Return original if extraction fails
    }
  }

  /// Create thumbnail from image
  static Future<Uint8List?> createThumbnail(Uint8List imageBytes) async {
    try {
      final img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Resize to thumbnail size while maintaining aspect ratio
      final thumbnail = img.copyResize(
        image,
        width: thumbnailSize,
        height: thumbnailSize,
        interpolation: img.Interpolation.linear,
      );

      // Encode as JPEG
      return Uint8List.fromList(
        img.encodeJpg(thumbnail, quality: imageQuality),
      );
    } catch (e) {
      Logger.error('Failed to create thumbnail', error: e);
      return null;
    }
  }

  /// Convert YUV420 CameraImage to RGB Image
  static Future<img.Image?> _convertYUV420ToImage(CameraImage cameraImage) async {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;

      final int yRowStride = cameraImage.planes[0].bytesPerRow;
      final int uvRowStride = cameraImage.planes[1].bytesPerRow;
      final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

      final img.Image image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          final int yValue = cameraImage.planes[0].bytes[yIndex];
          final int uValue = cameraImage.planes[1].bytes[uvIndex];
          final int vValue = cameraImage.planes[2].bytes[uvIndex];

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
    } catch (e) {
      Logger.error('Failed to convert YUV420 to Image', error: e);
      return null;
    }
  }

  /// Rotate image based on camera orientation
  static img.Image _rotateImage(img.Image image, CameraDescription camera) {
    // For front camera with 270° sensor orientation, we need to rotate the image
    // by the sensor orientation itself to get correct orientation
    int rotationAngle = camera.sensorOrientation;

    Logger.debug('Rotating log image by $rotationAngle degrees for ${camera.lensDirection.name} camera');

    // Apply rotation based on sensor orientation
    switch (rotationAngle) {
      case 90:
        return img.copyRotate(image, angle: 90);
      case 180:
        return img.copyRotate(image, angle: 180);
      case 270:
        return img.copyRotate(image, angle: 270);
      default:
        return image;
    }
  }

  /// Get storage size estimate for images
  static int estimateStorageSize({
    required int fullImageSize,
    required int thumbnailSize,
    required bool hasFaceRegion,
  }) {
    int totalSize = thumbnailSize;
    if (hasFaceRegion) {
      // Face region is typically 20-30% of full image
      totalSize += (fullImageSize * 0.25).toInt();
    } else {
      totalSize += fullImageSize;
    }
    return totalSize;
  }

  /// Compress image to target size
  static Future<Uint8List?> compressImageToSize(
    Uint8List imageBytes,
    int targetSizeKB,
  ) async {
    try {
      final img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return null;

      int quality = imageQuality;
      Uint8List compressedBytes;

      do {
        compressedBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
        quality -= 10;
      } while (compressedBytes.length > targetSizeKB * 1024 && quality > 10);

      return compressedBytes;
    } catch (e) {
      Logger.error('Failed to compress image to target size', error: e);
      return imageBytes;
    }
  }
}