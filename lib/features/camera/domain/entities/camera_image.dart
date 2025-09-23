import 'dart:typed_data';

/// Domain entity for camera image data
/// Independent of any specific camera implementation
class CameraImage {
  final Uint8List data;
  final int width;
  final int height;
  final CameraImageFormat format;
  final DateTime timestamp;

  CameraImage({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
    required this.timestamp,
  });

  /// Calculate the size in bytes of this image
  int get sizeInBytes => data.length;

  /// Get aspect ratio of the image
  double get aspectRatio => width / height;
}

/// Supported camera image formats
enum CameraImageFormat {
  nv21,      // YUV420sp format, common on Android
  bgra8888,  // BGRA format
  yuv420,    // Standard YUV420 format
  unknown,   // Unknown or unsupported format
}

/// Camera flash modes
enum FlashMode {
  off,
  on,
  auto,
}

/// Camera state enum
enum CameraState {
  uninitialized,
  initializing,
  ready,
  streaming,
  error,
  disposed,
}