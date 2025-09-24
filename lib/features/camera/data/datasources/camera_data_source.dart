import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart' as app_exceptions;
import '../../../../core/utils/logger.dart';
import '../../domain/entities/camera_image.dart';
import '../../domain/repositories/camera_repository.dart';

@singleton
class CameraDataSource {
  static CameraDataSource? _instance;
  static bool _isInstanceInitialized = false;

  camera.CameraController? _controller;
  List<camera.CameraDescription>? _cameras;
  int _currentCameraIndex = 0;
  final StreamController<CameraState> _stateController =
      StreamController<CameraState>.broadcast();
  bool _isImageStreamActive = false;
  bool _isInitializing = false;

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
    // ENHANCED: Force complete reinitialization to apply MEDIUM resolution
    Logger.info('🔄 CAMERA INIT: Force reinitializing camera to apply MEDIUM resolution settings');
    _isInstanceInitialized = false;

    // Prevent concurrent initializations
    if (_isInitializing) {
      Logger.warning('Camera initialization already in progress, skipping');
      return;
    }

    _isInitializing = true;
    try {
      _stateController.add(CameraState.initializing);

      // Properly dispose of any existing controller to unbind all use cases
      if (_controller != null) {
        Logger.info('Disposing existing camera controller before reinitializing');
        if (_isImageStreamActive) {
          try {
            await _controller!.stopImageStream();
            _isImageStreamActive = false;
          } catch (e) {
            Logger.warning('Error stopping image stream: $e');
          }
        }
        await _controller!.dispose();
        _controller = null;
        // Add small delay to ensure proper cleanup
        await Future.delayed(const Duration(milliseconds: 100));
      }

      camera.CameraDescription? cameraToUse = cameraDesc ?? currentCamera;
      if (cameraToUse == null) {
        await getAvailableCameras();
        cameraToUse = currentCamera;
      }

      if (cameraToUse == null) {
        throw app_exceptions.CameraException(message: 'No camera available to initialize');
      }

      Logger.info('Initializing camera: ${cameraToUse.name}');
      // Log stack trace to identify caller
      Logger.debug('Camera initialization called from:\n${StackTrace.current.toString().split('\n').take(10).join('\n')}');

      _controller = camera.CameraController(
        cameraToUse,
        camera.ResolutionPreset.medium,  // Medium resolution (720x480) for better frontal face detection
        enableAudio: false,
        imageFormatGroup: camera.ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(camera.FlashMode.off);

      // ENHANCED LOGGING: Verify actual resolution being used
      final actualResolution = _controller!.value.previewSize;
      Logger.success('✅ CAMERA READY: Initialized successfully');
      Logger.info('📐 RESOLUTION: ${actualResolution?.width.toInt()}x${actualResolution?.height.toInt()} (${_controller!.resolutionPreset})');
      Logger.info('📷 CAMERA: ${cameraToUse.name} (${cameraToUse.lensDirection})');

      _isInstanceInitialized = true;
      _stateController.add(CameraState.ready);
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
      _stateController.add(CameraState.error);
      throw app_exceptions.CameraException(message: 'Failed to initialize camera: $e');
    } finally {
      _isInitializing = false;
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
      _isInstanceInitialized = false;  // Reset singleton initialization state
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