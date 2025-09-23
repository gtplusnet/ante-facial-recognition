import 'dart:typed_data';

import '../entities/camera_image.dart';

/// Repository interface for camera operations
/// Abstracts away the specific camera implementation (standard camera package vs CameraX)
abstract class CameraRepository {
  /// Check if camera permission is granted
  Future<bool> checkCameraPermission();

  /// Initialize the camera
  Future<void> initializeCamera();

  /// Start streaming camera frames
  Future<void> startImageStream(Function(CameraImage) onImage);

  /// Stop streaming camera frames
  Future<void> stopImageStream();

  /// Switch between front and back camera
  Future<void> switchCamera();

  /// Set flash mode
  Future<void> setFlashMode(FlashMode mode);

  /// Set zoom level (0.0 to 1.0)
  Future<void> setZoomLevel(double zoom);

  /// Dispose camera resources
  Future<void> dispose();

  /// Check if camera is initialized
  bool get isInitialized;

  /// Stream of camera state changes
  Stream<CameraState> get stateStream;

  /// Get the camera controller or texture ID depending on implementation
  Object? get cameraController;
}