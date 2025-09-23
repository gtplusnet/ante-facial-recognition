import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import '../error/exceptions.dart';
import '../utils/logger.dart';

/// Service for interacting with native CameraX implementation via platform channels
@singleton
class CameraXService {
  static const String _channelName = 'com.ante.facial_recognition/camerax';
  static const MethodChannel _channel = MethodChannel(_channelName);

  final StreamController<CameraXFrame> _frameController =
      StreamController<CameraXFrame>.broadcast();

  Stream<CameraXFrame> get frameStream => _frameController.stream;

  int? _textureId;
  bool _isInitialized = false;
  bool _isStreaming = false;
  int _currentLensFacing = 0; // 0 = back camera, 1 = front camera

  int? get textureId => _textureId;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  int get currentLensFacing => _currentLensFacing;

  CameraXService() {
    _setupMethodCallHandler();
  }

  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFrameAvailable':
          _handleFrameAvailable(call.arguments);
          break;
        default:
          Logger.warning('Unknown method call from native: ${call.method}');
      }
    });
  }

  void _handleFrameAvailable(dynamic arguments) {
    if (!_isStreaming) return;

    try {
      final Map<dynamic, dynamic> args = arguments as Map<dynamic, dynamic>;
      final Uint8List frameData = args['data'] as Uint8List;
      final int width = args['width'] as int;
      final int height = args['height'] as int;
      final String format = args['format'] as String;

      _frameController.add(CameraXFrame(
        data: frameData,
        width: width,
        height: height,
        format: format,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      Logger.error('Error handling frame from CameraX', error: e);
    }
  }

  /// Check if camera permission is granted
  Future<bool> checkCameraPermission() async {
    try {
      final bool hasPermission = await _channel.invokeMethod('checkCameraPermission');
      return hasPermission;
    } catch (e) {
      Logger.error('Failed to check camera permission', error: e);
      return false;
    }
  }

  /// Initialize CameraX and get texture ID for preview
  Future<CameraXInitResult> initializeCamera() async {
    try {
      Logger.info('Initializing CameraX');

      final Map<dynamic, dynamic>? result =
          await _channel.invokeMethod('initializeCamera');

      if (result == null) {
        throw CameraException(message: 'Failed to initialize CameraX: null result');
      }

      _textureId = result['textureId'] as int?;
      final int previewWidth = result['previewWidth'] as int;
      final int previewHeight = result['previewHeight'] as int;

      // Set the initial lens facing (default to front camera for facial recognition)
      _currentLensFacing = result['lensFacing'] as int? ?? 1;

      if (_textureId == null) {
        throw CameraException(message: 'Failed to get texture ID from CameraX');
      }

      _isInitialized = true;

      Logger.success('CameraX initialized with texture ID: $_textureId');

      return CameraXInitResult(
        textureId: _textureId!,
        previewWidth: previewWidth,
        previewHeight: previewHeight,
      );
    } catch (e) {
      Logger.error('Failed to initialize CameraX', error: e);
      throw CameraException(message: 'Failed to initialize CameraX: $e');
    }
  }

  /// Start receiving camera frames for processing
  Future<void> startImageStream() async {
    try {
      if (!_isInitialized) {
        throw CameraException(message: 'CameraX not initialized');
      }

      Logger.info('Starting CameraX image stream');

      await _channel.invokeMethod('startImageStream');
      _isStreaming = true;

      Logger.success('CameraX image stream started');
    } catch (e) {
      Logger.error('Failed to start image stream', error: e);
      throw CameraException(message: 'Failed to start image stream: $e');
    }
  }

  /// Stop receiving camera frames
  Future<void> stopImageStream() async {
    try {
      if (!_isStreaming) {
        Logger.warning('Image stream not active');
        return;
      }

      Logger.info('Stopping CameraX image stream');

      await _channel.invokeMethod('stopImageStream');
      _isStreaming = false;

      Logger.success('CameraX image stream stopped');
    } catch (e) {
      Logger.error('Failed to stop image stream', error: e);
      throw CameraException(message: 'Failed to stop image stream: $e');
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    try {
      if (!_isInitialized) {
        throw CameraException(message: 'CameraX not initialized');
      }

      Logger.info('Switching camera');

      await _channel.invokeMethod('switchCamera');

      // Toggle the current lens facing
      _currentLensFacing = _currentLensFacing == 0 ? 1 : 0;

      Logger.success('Camera switched to ${_currentLensFacing == 0 ? "back" : "front"}');
    } catch (e) {
      Logger.error('Failed to switch camera', error: e);
      throw CameraException(message: 'Failed to switch camera: $e');
    }
  }

  /// Set flash mode
  Future<void> setFlashMode(CameraXFlashMode mode) async {
    try {
      if (!_isInitialized) {
        throw CameraException(message: 'CameraX not initialized');
      }

      await _channel.invokeMethod('setFlashMode', {
        'mode': mode.toString().split('.').last,
      });

      Logger.debug('Flash mode set to: $mode');
    } catch (e) {
      Logger.error('Failed to set flash mode', error: e);
      throw CameraException(message: 'Failed to set flash mode: $e');
    }
  }

  /// Dispose CameraX resources
  Future<void> dispose() async {
    try {
      Logger.info('Disposing CameraX resources');

      if (_isStreaming) {
        await stopImageStream();
      }

      await _channel.invokeMethod('dispose');

      _isInitialized = false;
      _textureId = null;

      await _frameController.close();

      Logger.success('CameraX resources disposed');
    } catch (e) {
      Logger.error('Failed to dispose CameraX', error: e);
    }
  }
}

/// Result of CameraX initialization
class CameraXInitResult {
  final int textureId;
  final int previewWidth;
  final int previewHeight;

  CameraXInitResult({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
  });
}

/// Camera frame data from CameraX
class CameraXFrame {
  final Uint8List data;
  final int width;
  final int height;
  final String format;
  final DateTime timestamp;

  CameraXFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.format,
    required this.timestamp,
  });

  /// Get frame data as NV21 format (YUV420sp)
  Uint8List get nv21Data {
    if (format == 'nv21') {
      return data;
    }
    // Convert if needed (implement conversion logic if other formats are used)
    throw UnsupportedError('Format $format not supported yet');
  }
}

/// Flash mode options for CameraX
enum CameraXFlashMode {
  off,
  on,
  auto,
}