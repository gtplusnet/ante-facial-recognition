import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart' as app_exceptions;
import '../../../../core/utils/logger.dart';
import '../../domain/entities/camera_image.dart';
import '../../domain/repositories/camera_repository.dart';

@singleton
class CameraDataSource {
  camera.CameraController? _controller;
  List<camera.CameraDescription>? _cameras;
  int _currentCameraIndex = 0;
  final StreamController<CameraState> _stateController =
      StreamController<CameraState>.broadcast();
  bool _isImageStreamActive = false;

  camera.CameraController? get controller => _controller;
  Stream<CameraState> get stateStream => _stateController.stream;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  camera.CameraDescription? get currentCamera =>
      _cameras != null && _cameras!.isNotEmpty
          ? _cameras![_currentCameraIndex]
          : null;

  Future<List<camera.CameraDescription>> getAvailableCameras() async {
    try {
      Logger.info('Getting available cameras');
      _cameras = await camera.availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw app_exceptions.CameraException(message: 'No cameras available');
      }

      // Prefer front camera for face recognition
      final frontCameraIndex = _cameras!.indexWhere(
        (cam) => cam.lensDirection == camera.CameraLensDirection.front,
      );

      if (frontCameraIndex != -1) {
        _currentCameraIndex = frontCameraIndex;
      }

      Logger.success('Found ${_cameras!.length} cameras');
      return _cameras!;
    } catch (e) {
      Logger.error('Failed to get cameras', error: e);
      throw app_exceptions.CameraException(message: 'Failed to get available cameras: $e');
    }
  }

  Future<void> initializeCamera([camera.CameraDescription? cameraDesc]) async {
    try {
      _stateController.add(CameraState.initializing);

      camera.CameraDescription? cameraToUse = cameraDesc ?? currentCamera;
      if (cameraToUse == null) {
        await getAvailableCameras();
        cameraToUse = currentCamera;
      }

      if (cameraToUse == null) {
        throw app_exceptions.CameraException(message: 'No camera available to initialize');
      }

      Logger.info('Initializing camera: ${cameraToUse.name}');

      _controller = camera.CameraController(
        cameraToUse,
        camera.ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: camera.ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(camera.FlashMode.off);

      Logger.success('Camera initialized successfully');
      _stateController.add(CameraState.ready);
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
      _stateController.add(CameraState.error);
      throw app_exceptions.CameraException(message: 'Failed to initialize camera: $e');
    }
  }

  Future<void> startImageStream(Function(camera.CameraImage) onImage) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw app_exceptions.CameraException(message: 'Camera not initialized');
      }

      if (_isImageStreamActive) {
        Logger.warning('Image stream already active');
        return;
      }

      Logger.info('Starting camera image stream');
      await _controller!.startImageStream(onImage);
      _isImageStreamActive = true;
      _stateController.add(CameraState.streaming);
      Logger.success('Camera image stream started');
    } catch (e) {
      Logger.error('Failed to start image stream', error: e);
      throw app_exceptions.CameraException(message: 'Failed to start image stream: $e');
    }
  }

  Future<void> stopImageStream() async {
    try {
      if (!_isImageStreamActive) {
        Logger.warning('Image stream not active');
        return;
      }

      Logger.info('Stopping camera image stream');
      await _controller?.stopImageStream();
      _isImageStreamActive = false;
      _stateController.add(CameraState.ready);
      Logger.success('Camera image stream stopped');
    } catch (e) {
      Logger.error('Failed to stop image stream', error: e);
      throw app_exceptions.CameraException(message: 'Failed to stop image stream: $e');
    }
  }

  Future<void> switchCamera() async {
    try {
      if (_cameras == null || _cameras!.isEmpty) {
        throw app_exceptions.CameraException(message: 'No cameras available');
      }

      // Stop current stream if active
      if (_isImageStreamActive) {
        await stopImageStream();
      }

      // Dispose current controller
      await _controller?.dispose();

      // Switch to next camera
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;

      Logger.info('Switching to camera: ${_cameras![_currentCameraIndex].name}');

      // Initialize new camera
      await initializeCamera(_cameras![_currentCameraIndex]);

      Logger.success('Camera switched successfully');
    } catch (e) {
      Logger.error('Failed to switch camera', error: e);
      throw app_exceptions.CameraException(message: 'Failed to switch camera: $e');
    }
  }

  Future<void> setFlashMode(camera.FlashMode mode) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw app_exceptions.CameraException(message: 'Camera not initialized');
      }

      await _controller!.setFlashMode(mode);
      Logger.debug('Flash mode set to: $mode');
    } catch (e) {
      Logger.error('Failed to set flash mode', error: e);
      throw app_exceptions.CameraException(message: 'Failed to set flash mode: $e');
    }
  }

  Future<void> setZoomLevel(double zoom) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        throw app_exceptions.CameraException(message: 'Camera not initialized');
      }

      final maxZoom = await _controller!.getMaxZoomLevel();
      final minZoom = await _controller!.getMinZoomLevel();

      final clampedZoom = zoom.clamp(minZoom, maxZoom);
      await _controller!.setZoomLevel(clampedZoom);

      Logger.debug('Zoom level set to: $clampedZoom');
    } catch (e) {
      Logger.error('Failed to set zoom level', error: e);
      throw app_exceptions.CameraException(message: 'Failed to set zoom level: $e');
    }
  }

  Future<void> dispose() async {
    try {
      Logger.info('Disposing camera resources');

      if (_isImageStreamActive) {
        await stopImageStream();
      }

      await _controller?.dispose();
      _controller = null;
      _stateController.add(CameraState.disposed);

      Logger.success('Camera resources disposed');
    } catch (e) {
      Logger.error('Failed to dispose camera', error: e);
    }
  }

  void close() {
    _stateController.close();
  }
}