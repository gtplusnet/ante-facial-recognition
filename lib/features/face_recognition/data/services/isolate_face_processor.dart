import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../domain/entities/face_recognition_result.dart';
import 'face_encoding_service.dart';
import 'simplified_face_recognition_service.dart';

/// Data class for sending to isolate
class IsolateProcessingRequest {
  final CameraImage frame;
  final CameraDescription cameraDescription;
  final SendPort responsePort;

  IsolateProcessingRequest({
    required this.frame,
    required this.cameraDescription,
    required this.responsePort,
  });
}

/// Isolate-based face processor for background processing
class IsolateFaceProcessor {
  static const String _isolateName = 'face_processing_isolate';

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isInitialized = false;

  /// Initialize the isolate
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.debug('Isolate face processor already initialized');
      return;
    }

    try {
      Logger.info('Initializing isolate face processor...');

      // Create receive port
      _receivePort = ReceivePort();

      // Spawn isolate
      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
        debugName: _isolateName,
      );

      // Wait for isolate to send its send port
      _sendPort = await _receivePort!.first as SendPort;

      // Create new receive port for responses
      final responsePort = ReceivePort();
      _receivePort = responsePort;

      _isInitialized = true;
      Logger.success('Isolate face processor initialized');
    } catch (e) {
      Logger.error('Failed to initialize isolate face processor', error: e);
      throw Exception('Isolate initialization failed: $e');
    }
  }

  /// Process a camera frame in the isolate
  Future<FaceRecognitionResult?> processFrame(
    CameraImage frame,
    CameraDescription cameraDescription,
  ) async {
    if (!_isInitialized || _sendPort == null) {
      Logger.warning('Isolate not initialized, falling back to main thread processing');
      return null;
    }

    try {
      // Create response port for this request
      final responsePort = ReceivePort();

      // Send request to isolate
      _sendPort!.send(IsolateProcessingRequest(
        frame: frame,
        cameraDescription: cameraDescription,
        responsePort: responsePort.sendPort,
      ));

      // Wait for response
      final response = await responsePort.first;
      responsePort.close();

      if (response is FaceRecognitionResult) {
        return response;
      } else if (response is String && response.startsWith('ERROR:')) {
        Logger.error('Isolate processing error: ${response.substring(6)}');
        return FaceRecognitionResult.error(response.substring(6));
      }

      return null;
    } catch (e) {
      Logger.error('Failed to process frame in isolate', error: e);
      return null;
    }
  }

  /// Isolate entry point
  static void _isolateEntryPoint(SendPort mainSendPort) async {
    // Create receive port in isolate
    final receivePort = ReceivePort();

    // Send our send port to main isolate
    mainSendPort.send(receivePort.sendPort);

    // Initialize services in isolate
    SimplifiedFaceRecognitionService? recognitionService;

    try {
      // Initialize face recognition service
      recognitionService = SimplifiedFaceRecognitionService();
      await recognitionService.initialize();

      debugPrint('[ISOLATE] Face recognition service initialized');
    } catch (e) {
      debugPrint('[ISOLATE] Failed to initialize services: $e');
    }

    // Listen for processing requests
    await for (final message in receivePort) {
      if (message is IsolateProcessingRequest) {
        try {
          if (recognitionService == null) {
            message.responsePort.send('ERROR: Service not initialized');
            continue;
          }

          // Process the frame
          final result = await recognitionService.processFrame(
            message.frame,
            message.cameraDescription,
          );

          // Send result back
          message.responsePort.send(result);
        } catch (e) {
          message.responsePort.send('ERROR: $e');
        }
      }
    }
  }

  /// Dispose the isolate
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
    _isInitialized = false;
    Logger.info('Isolate face processor disposed');
  }
}

/// Compute function for simple face processing (alternative to isolate)
Future<FaceRecognitionResult?> processFaceInBackground(Map<String, dynamic> params) async {
  try {
    final frame = params['frame'] as CameraImage;
    final cameraDescription = params['cameraDescription'] as CameraDescription;
    final service = params['service'] as SimplifiedFaceRecognitionService;

    return await service.processFrame(frame, cameraDescription);
  } catch (e) {
    Logger.error('Background processing failed', error: e);
    return FaceRecognitionResult.error(e.toString());
  }
}