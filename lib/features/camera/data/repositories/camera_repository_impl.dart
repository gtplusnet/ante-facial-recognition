import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as camera;
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/services/camerax_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/camera_image.dart';
import '../../domain/repositories/camera_repository.dart';
import '../datasources/camera_data_source.dart';

@Injectable(as: CameraRepository)
class CameraRepositoryImpl implements CameraRepository {
  final CameraDataSource _cameraDataSource;
  final CameraXService _cameraXService;

  // Configuration flag to determine which camera implementation to use
  static const bool _useCameraX = true; // Can be configured via environment

  CameraRepositoryImpl(
    this._cameraDataSource,
    this._cameraXService,
  );

  @override
  Future<bool> checkCameraPermission() async {
    try {
      if (_useCameraX) {
        return await _cameraXService.checkCameraPermission();
      }
      // For standard camera package, permission is checked during initialization
      return true;
    } catch (e) {
      Logger.error('Failed to check camera permission', error: e);
      return false;
    }
  }

  @override
  Future<void> initializeCamera() async {
    try {
      if (_useCameraX) {
        await _initializeCameraX();
      } else {
        await _initializeStandardCamera();
      }
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
      rethrow;
    }
  }

  Future<void> _initializeCameraX() async {
    final hasPermission = await _cameraXService.checkCameraPermission();
    if (!hasPermission) {
      throw CameraException(message: 'Camera permission not granted');
    }

    await _cameraXService.initializeCamera();
  }

  Future<void> _initializeStandardCamera() async {
    await _cameraDataSource.getAvailableCameras();
    await _cameraDataSource.initializeCamera();
  }

  @override
  Future<void> startImageStream(Function(CameraImage) onImage) async {
    try {
      if (_useCameraX) {
        await _startCameraXStream(onImage);
      } else {
        await _startStandardCameraStream(onImage);
      }
    } catch (e) {
      Logger.error('Failed to start image stream', error: e);
      rethrow;
    }
  }

  Future<void> _startCameraXStream(Function(CameraImage) onImage) async {
    await _cameraXService.startImageStream();

    // Convert CameraX frames to CameraImage format for compatibility
    _cameraXService.frameStream.listen((frame) {
      final cameraImage = CameraImage(
        data: frame.nv21Data,
        width: frame.width,
        height: frame.height,
        format: CameraImageFormat.nv21,
        timestamp: frame.timestamp,
      );
      onImage(cameraImage);
    });
  }

  Future<void> _startStandardCameraStream(Function(CameraImage) onImage) async {
    await _cameraDataSource.startImageStream((camera.CameraImage image) {
      final cameraImage = CameraImage(
        data: _convertCameraImageData(image),
        width: image.width,
        height: image.height,
        format: _mapImageFormat(image.format),
        timestamp: DateTime.now(),
      );
      onImage(cameraImage);
    });
  }

  @override
  Future<void> stopImageStream() async {
    try {
      if (_useCameraX) {
        await _cameraXService.stopImageStream();
      } else {
        await _cameraDataSource.stopImageStream();
      }
    } catch (e) {
      Logger.error('Failed to stop image stream', error: e);
      rethrow;
    }
  }

  @override
  Future<void> switchCamera() async {
    try {
      if (_useCameraX) {
        await _cameraXService.switchCamera();
      } else {
        await _cameraDataSource.switchCamera();
      }
    } catch (e) {
      Logger.error('Failed to switch camera', error: e);
      rethrow;
    }
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    try {
      if (_useCameraX) {
        final cameraXMode = _mapFlashModeToCameraX(mode);
        await _cameraXService.setFlashMode(cameraXMode);
      } else {
        final standardMode = _mapFlashModeToStandard(mode);
        await _cameraDataSource.setFlashMode(standardMode);
      }
    } catch (e) {
      Logger.error('Failed to set flash mode', error: e);
      rethrow;
    }
  }

  @override
  Future<void> setZoomLevel(double zoom) async {
    try {
      if (_useCameraX) {
        // CameraX zoom implementation would go here
        Logger.warning('Zoom not yet implemented for CameraX');
      } else {
        await _cameraDataSource.setZoomLevel(zoom);
      }
    } catch (e) {
      Logger.error('Failed to set zoom level', error: e);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_useCameraX) {
        await _cameraXService.dispose();
      } else {
        await _cameraDataSource.dispose();
      }
    } catch (e) {
      Logger.error('Failed to dispose camera', error: e);
    }
  }

  @override
  bool get isInitialized {
    if (_useCameraX) {
      return _cameraXService.isInitialized;
    } else {
      return _cameraDataSource.isInitialized;
    }
  }

  @override
  Stream<CameraState> get stateStream {
    if (_useCameraX) {
      // Map CameraX states to CameraState enum
      return Stream.value(
        _cameraXService.isInitialized ? CameraState.ready : CameraState.uninitialized,
      );
    } else {
      return _cameraDataSource.stateStream;
    }
  }

  @override
  Object? get cameraController {
    if (_useCameraX) {
      return _cameraXService.textureId;
    } else {
      return _cameraDataSource.controller;
    }
  }

  // Helper methods for data conversion

  Uint8List _convertCameraImageData(camera.CameraImage image) {
    // Convert camera package image data to Uint8List
    // This implementation depends on the format
    if (image.format.group == camera.ImageFormatGroup.yuv420) {
      // Assuming NV21 format for Android
      final int ySize = image.planes[0].bytes.length;
      final int uvSize = image.planes[1].bytes.length;

      final Uint8List nv21 = Uint8List(ySize + uvSize);
      nv21.setRange(0, ySize, image.planes[0].bytes);

      if (image.planes.length > 1) {
        nv21.setRange(ySize, ySize + uvSize, image.planes[1].bytes);
      }

      return nv21;
    }

    // Return raw bytes for other formats
    return image.planes[0].bytes;
  }

  CameraImageFormat _mapImageFormat(camera.ImageFormat format) {
    if (format.group == camera.ImageFormatGroup.yuv420) {
      return CameraImageFormat.nv21;
    } else if (format.group == camera.ImageFormatGroup.bgra8888) {
      return CameraImageFormat.bgra8888;
    } else {
      return CameraImageFormat.unknown;
    }
  }

  CameraXFlashMode _mapFlashModeToCameraX(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return CameraXFlashMode.off;
      case FlashMode.on:
        return CameraXFlashMode.on;
      case FlashMode.auto:
        return CameraXFlashMode.auto;
    }
  }

  camera.FlashMode _mapFlashModeToStandard(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return camera.FlashMode.off;
      case FlashMode.on:
        return camera.FlashMode.always;
      case FlashMode.auto:
        return camera.FlashMode.auto;
    }
  }
}