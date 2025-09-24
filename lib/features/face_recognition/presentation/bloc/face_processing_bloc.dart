import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as camera;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/constants/face_recognition_constants.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../../employee/data/datasources/employee_local_datasource.dart';
import '../../../face_detection/data/services/face_detection_service.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../data/services/face_encoding_service.dart';

// Events
abstract class FaceProcessingEvent {}

class InitializeFaceProcessing extends FaceProcessingEvent {}

class ProcessCameraFrame extends FaceProcessingEvent {
  final camera.CameraImage image;
  ProcessCameraFrame(this.image);
}

class ResetProcessing extends FaceProcessingEvent {}

// States
abstract class FaceProcessingState {}

class FaceProcessingInitial extends FaceProcessingState {}

class FaceProcessingInitializing extends FaceProcessingState {}

class FaceProcessingReady extends FaceProcessingState {}

class FaceProcessingActive extends FaceProcessingState {
  final double faceQuality; // Always have a value (0.0 when no face)
  final bool faceDetected;
  final int processingTimeMs;
  final int frameCount; // For FPS calculation

  FaceProcessingActive({
    required this.faceQuality, // Now required
    required this.faceDetected,
    this.processingTimeMs = 0,
    this.frameCount = 0,
  });
}

class FaceRecognized extends FaceProcessingState {
  final Employee employee;
  final double confidence;

  FaceRecognized({
    required this.employee,
    required this.confidence,
  });
}

class FaceNotRecognized extends FaceProcessingState {
  final double faceQuality;

  FaceNotRecognized({
    required this.faceQuality,
  });
}

// Simplified BLoC
@injectable
class FaceProcessingBloc extends Bloc<FaceProcessingEvent, FaceProcessingState> {
  final FaceEncodingService _faceEncodingService;
  final FaceDetectionService _faceDetectionService;
  final CameraDataSource _cameraDataSource;
  final EmployeeLocalDataSource _employeeDataSource;

  final Map<String, Employee> _employeeDatabase = {};
  final Map<String, Float32List> _employeeEncodings = {};

  bool _isProcessing = false;
  DateTime _lastProcessedTime = DateTime.now();
  static const _processingInterval = Duration(milliseconds: 500);

  // Frame tracking for live feedback
  int _frameCount = 0;
  DateTime _startTime = DateTime.now();

  FaceProcessingBloc({
    required FaceEncodingService faceEncodingService,
    required FaceDetectionService faceDetectionService,
    required CameraDataSource cameraDataSource,
    required EmployeeLocalDataSource employeeDataSource,
  })  : _faceEncodingService = faceEncodingService,
        _faceDetectionService = faceDetectionService,
        _cameraDataSource = cameraDataSource,
        _employeeDataSource = employeeDataSource,
        super(FaceProcessingInitial()) {
    on<InitializeFaceProcessing>(_onInitialize);
    on<ProcessCameraFrame>(_onProcessCameraFrame);
    on<ResetProcessing>(_onReset);
  }

  Future<void> _onInitialize(
    InitializeFaceProcessing event,
    Emitter<FaceProcessingState> emit,
  ) async {
    try {
      emit(FaceProcessingInitializing());

      // Initialize services
      await _faceEncodingService.initialize();

      // Initialize camera
      if (!_cameraDataSource.isInitialized) {
        await _cameraDataSource.initializeCamera();
      }

      // Load employees
      await _loadEmployees();

      emit(FaceProcessingReady());
      Logger.success('Face processing initialized with ${_employeeDatabase.length} employees');
    } catch (e) {
      Logger.error('Failed to initialize face processing', error: e);
      emit(FaceProcessingInitial());
    }
  }

  Future<void> _onProcessCameraFrame(
    ProcessCameraFrame event,
    Emitter<FaceProcessingState> emit,
  ) async {
    // Skip if already processing or too soon since last process
    if (_isProcessing) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedTime) < _processingInterval) {
      return;
    }

    _isProcessing = true;
    _lastProcessedTime = now;
    _frameCount++; // Track frame count for FPS

    final startTime = DateTime.now();

    try {
      final cameraDesc = _cameraDataSource.currentCamera;
      if (cameraDesc == null) {
        _isProcessing = false;
        return;
      }

      // Detect faces first
      final faces = await _faceDetectionService.detectFacesFromCameraImage(
        event.image,
        cameraDesc,
      );

      final processingTimeMs = DateTime.now().difference(startTime).inMilliseconds;

      if (faces.isEmpty) {
        // Always emit with 0.0 quality when no face detected
        emit(FaceProcessingActive(
          faceDetected: false,
          faceQuality: 0.0,
          processingTimeMs: processingTimeMs,
          frameCount: _frameCount,
        ));
        _isProcessing = false;
        return;
      }

      // Get the best face (largest)
      final face = faces.reduce((a, b) =>
        a.bounds.width * a.bounds.height > b.bounds.width * b.bounds.height ? a : b
      );

      // Calculate quality
      final quality = _calculateFaceQuality(face);

      // If quality is too low, just show detection
      if (quality < FaceRecognitionConstants.qualityThreshold) {
        emit(FaceProcessingActive(
          faceDetected: true,
          faceQuality: quality,
          processingTimeMs: processingTimeMs,
          frameCount: _frameCount,
        ));
        _isProcessing = false;
        return;
      }

      // Extract face encoding
      final encodingResult = await _faceEncodingService.extractFromCameraImage(
        event.image,
        cameraDesc,
      );

      if (encodingResult == null) {
        emit(FaceProcessingActive(
          faceDetected: true,
          faceQuality: quality,
          processingTimeMs: processingTimeMs,
          frameCount: _frameCount,
        ));
        _isProcessing = false;
        return;
      }

      // Find best match
      final matchResult = _faceEncodingService.findBestMatch(
        encodingResult.embedding,
        _employeeEncodings,
        threshold: FaceRecognitionConstants.faceMatchThreshold,
      );

      if (matchResult != null && matchResult['isMatch'] == true) {
        final employee = _employeeDatabase[matchResult['matchedId']];
        if (employee != null) {
          emit(FaceRecognized(
            employee: employee,
            confidence: matchResult['confidence'] as double,
          ));
          Logger.success('Face recognized: ${employee.name}');
        }
      } else {
        // Unknown face - just show indicator, no dialog
        emit(FaceNotRecognized(faceQuality: quality));
      }
    } catch (e) {
      Logger.error('Error processing camera frame', error: e);
      final processingTimeMs = DateTime.now().difference(startTime).inMilliseconds;
      emit(FaceProcessingActive(
        faceDetected: false,
        faceQuality: 0.0,
        processingTimeMs: processingTimeMs,
        frameCount: _frameCount,
      ));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _onReset(
    ResetProcessing event,
    Emitter<FaceProcessingState> emit,
  ) async {
    _isProcessing = false;
    emit(FaceProcessingReady());
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await _employeeDataSource.getEmployees();

      _employeeDatabase.clear();
      _employeeEncodings.clear();

      for (final employee in employees) {
        _employeeDatabase[employee.id] = employee;

        if (employee.hasFaceEncodings) {
          final firstEncoding = employee.faceEncodings.first;
          _employeeEncodings[employee.id] = firstEncoding.embedding;
        }
      }

      await _faceEncodingService.loadEncodings(_employeeEncodings);
      Logger.info('Loaded ${employees.length} employees');
    } catch (e) {
      Logger.error('Failed to load employees', error: e);
    }
  }

  double _calculateFaceQuality(dynamic face) {
    // Simple quality calculation based on face size and position
    final bounds = face.bounds;
    final sizeScore = (bounds.width * bounds.height) / (720 * 480); // Normalized by camera resolution

    // Clamp between 0 and 1
    return sizeScore.clamp(0.0, 1.0);
  }

  @override
  Future<void> close() {
    _faceEncodingService.dispose();
    _faceDetectionService.dispose();
    return super.close();
  }
}