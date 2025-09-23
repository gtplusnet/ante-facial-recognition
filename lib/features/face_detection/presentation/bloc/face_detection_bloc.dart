import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../data/services/face_detection_service.dart';
import '../../domain/entities/face_detection_result.dart';
import 'face_detection_event.dart';
import 'face_detection_state.dart';

@injectable
class FaceDetectionBloc extends Bloc<FaceDetectionEvent, FaceDetectionState> {
  final FaceDetectionService _faceDetectionService;
  final CameraDataSource _cameraDataSource;

  StreamSubscription? _cameraStreamSubscription;
  bool _isProcessing = false;

  // Store latest camera image temporarily to pass through events (not state)
  camera.CameraImage? _latestCameraImage;

  /// Get the latest camera image for face recognition processing
  /// This avoids storing mutable camera images in immutable state objects
  camera.CameraImage? get latestCameraImage => _latestCameraImage;

  FaceDetectionBloc({
    required FaceDetectionService faceDetectionService,
    required CameraDataSource cameraDataSource,
  })  : _faceDetectionService = faceDetectionService,
        _cameraDataSource = cameraDataSource,
        super(const FaceDetectionInitial()) {
    on<StartFaceDetection>(_onStartFaceDetection);
    on<StopFaceDetection>(_onStopFaceDetection);
    on<ProcessCameraImage>(_onProcessCameraImage);
    on<ResetFaceDetection>(_onResetFaceDetection);
  }

  Future<void> _onStartFaceDetection(
    StartFaceDetection event,
    Emitter<FaceDetectionState> emit,
  ) async {
    try {
      emit(const FaceDetectionLoading());

      // Check if camera is initialized
      if (!_cameraDataSource.isInitialized) {
        emit(const FaceDetectionError(
          'Camera not initialized. Please initialize camera first.',
        ));
        return;
      }

      // Start camera image stream
      await _cameraDataSource.startImageStream(_processCameraImage);

      emit(const FaceDetectionReady());
      Logger.info('Face detection started');
    } catch (e) {
      Logger.error('Failed to start face detection', error: e);
      emit(FaceDetectionError(e.toString()));
    }
  }

  Future<void> _onStopFaceDetection(
    StopFaceDetection event,
    Emitter<FaceDetectionState> emit,
  ) async {
    try {
      await _stopDetection();
      emit(const FaceDetectionStopped());
      Logger.info('Face detection stopped');
    } catch (e) {
      Logger.error('Failed to stop face detection', error: e);
      emit(FaceDetectionError(e.toString()));
    }
  }

  Future<void> _onProcessCameraImage(
    ProcessCameraImage event,
    Emitter<FaceDetectionState> emit,
  ) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final currentCamera = _cameraDataSource.currentCamera;
      if (currentCamera == null) {
        _isProcessing = false;
        return;
      }

      // Store latest camera image for potential use in face recognition
      _latestCameraImage = event.image;

      final faces = await _faceDetectionService.detectFacesFromCameraImage(
        event.image,
        currentCamera,
      );

      if (faces.isEmpty) {
        emit(const FaceDetectionNoFace());
      } else if (faces.length == 1) {
        final face = faces.first;
        if (face.isGoodQuality) {
          emit(FaceDetected(
            face: face,
            imageSize: ImageSize(
              event.image.width.toDouble(),
              event.image.height.toDouble(),
            ),
          ));
        } else {
          emit(FaceDetectionLowQuality(
            face: face,
            qualityScore: face.qualityScore,
          ));
        }
      } else {
        emit(FaceDetectionMultipleFaces(count: faces.length));
      }
    } catch (e) {
      Logger.error('Failed to process camera image', error: e);
      emit(FaceDetectionError(e.toString()));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _onResetFaceDetection(
    ResetFaceDetection event,
    Emitter<FaceDetectionState> emit,
  ) async {
    _isProcessing = false;
    emit(const FaceDetectionInitial());
  }

  void _processCameraImage(camera.CameraImage image) {
    if (!_isProcessing) {
      add(ProcessCameraImage(image));
    }
  }

  Future<void> _stopDetection() async {
    await _cameraStreamSubscription?.cancel();
    await _cameraDataSource.stopImageStream();
    _isProcessing = false;
  }

  @override
  Future<void> close() async {
    await _stopDetection();
    await _faceDetectionService.dispose();
    return super.close();
  }
}

class Size {
  final double width;
  final double height;

  const Size(this.width, this.height);
}