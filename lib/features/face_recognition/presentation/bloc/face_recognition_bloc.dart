import 'dart:typed_data';

import 'package:camera/camera.dart' as camera;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../../employee/data/models/face_encoding_model.dart';
import '../../../employee/data/datasources/employee_local_datasource.dart';
import '../../../face_detection/data/services/face_detection_service.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../data/services/face_encoding_service.dart';
import '../../data/services/face_recognition_service.dart';
import '../../data/services/face_match_scorer.dart';
import 'face_recognition_event.dart';
import 'face_recognition_state.dart';

@injectable
class FaceRecognitionBloc extends Bloc<FaceRecognitionEvent, FaceRecognitionState> {
  final FaceEncodingService _faceEncodingService;
  final FaceDetectionService _faceDetectionService;
  final CameraDataSource _cameraDataSource;
  final FaceRecognitionService _recognitionService;
  final EmployeeLocalDataSource _employeeDataSource;

  // Mock employee database (in production, this would come from a repository)
  final Map<String, Employee> _employeeDatabase = {};
  final Map<String, Float32List> _employeeEncodings = {};

  // Recognition history for analytics
  final List<FaceMatchResult> _recognitionHistory = [];

  bool _isProcessing = false;
  // Timer removed - ProcessCameraFrame is triggered by face detection events

  FaceRecognitionBloc({
    required FaceEncodingService faceEncodingService,
    required FaceDetectionService faceDetectionService,
    required CameraDataSource cameraDataSource,
    required FaceRecognitionService recognitionService,
    required EmployeeLocalDataSource employeeDataSource,
  })  : _faceEncodingService = faceEncodingService,
        _faceDetectionService = faceDetectionService,
        _cameraDataSource = cameraDataSource,
        _recognitionService = recognitionService,
        _employeeDataSource = employeeDataSource,
        super(const FaceRecognitionInitial()) {
    on<InitializeFaceRecognition>(_onInitializeFaceRecognition);
    on<StartRecognition>(_onStartRecognition);
    on<StopRecognition>(_onStopRecognition);
    on<ProcessCameraFrame>(_onProcessCameraFrame);
    on<AddEmployee>(_onAddEmployee);
    on<RemoveEmployee>(_onRemoveEmployee);
    on<LoadEmployees>(_onLoadEmployees);
    on<ConfirmRecognition>(_onConfirmRecognition);
    on<ResetRecognition>(_onResetRecognition);
    on<RecognizeFaceWithTopK>(_onRecognizeFaceWithTopK);
    on<SelectMatchFromTopK>(_onSelectMatchFromTopK);
    on<ClearRecognitionHistory>(_onClearRecognitionHistory);
  }

  Future<void> _onInitializeFaceRecognition(
    InitializeFaceRecognition event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      emit(const FaceRecognitionLoading());

      // Initialize services
      await _faceEncodingService.initialize();
      await _recognitionService.initialize();

      // Initialize camera if not already done
      if (!_cameraDataSource.isInitialized) {
        await _cameraDataSource.initializeCamera();
      }

      // Load employees from local database
      await _loadEmployeesFromDatabase();

      emit(FaceRecognitionReady(
        employeeCount: _employeeDatabase.length,
      ));

      Logger.success('Face recognition initialized');
    } catch (e) {
      Logger.error('Failed to initialize face recognition', error: e);
      emit(FaceRecognitionError(e.toString()));
    }
  }

  Future<void> _onStartRecognition(
    StartRecognition event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      // Allow starting recognition from multiple states for continuous operation
      if (state is FaceRecognitionReady ||
          state is FaceRecognitionPoorQuality ||
          state is FaceRecognitionNoFace ||
          state is FaceRecognitionUnknown ||
          state is FaceRecognitionMatched ||
          state is FaceRecognitionError ||
          state is FaceRecognitionScanning) {
        // Camera stream is already started by CameraPreviewWidget
        // which sends images to FaceDetectionBloc

        emit(const FaceRecognitionScanning());

        // ProcessCameraFrame will be triggered by face detection events
        // instead of a timer to avoid unnecessary processing

        Logger.info('Face recognition started - waiting for face detection');
      } else {
        emit(const FaceRecognitionError('Service not initialized'));
        return;
      }
    } catch (e) {
      Logger.error('Failed to start recognition', error: e);
      emit(FaceRecognitionError(e.toString()));
    }
  }

  Future<void> _onStopRecognition(
    StopRecognition event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      // No timer to cancel since ProcessCameraFrame is triggered by face detection
      // Camera stream is managed by CameraPreviewWidget
      _isProcessing = false;

      emit(FaceRecognitionReady(
        employeeCount: _employeeDatabase.length,
      ));

      Logger.info('Face recognition stopped');
    } catch (e) {
      Logger.error('Failed to stop recognition', error: e);
      emit(FaceRecognitionError(e.toString()));
    }
  }

  Future<void> _onProcessCameraFrame(
    ProcessCameraFrame event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    if (_isProcessing) return;
    if (state is! FaceRecognitionScanning) return;

    _isProcessing = true;
    try {
      // Get camera description
      final cameraDesc = _cameraDataSource.currentCamera;
      if (cameraDesc == null) {
        _isProcessing = false;
        return;
      }

      // Extract face encoding from camera image passed through the event
      final encodingResult = await _faceEncodingService.extractFromCameraImage(
        event.cameraImage,
        cameraDesc,
      );

      if (encodingResult == null) {
        emit(const FaceRecognitionNoFace());
        _isProcessing = false;
        return;
      }

      // Check face quality
      if (encodingResult.quality < 0.9) {
        emit(FaceRecognitionPoorQuality(
          quality: encodingResult.quality,
          message: 'Please face the camera directly in good lighting',
        ));
        _isProcessing = false;
        return;
      }

      // Find best match from known employees
      final matchResult = _faceEncodingService.findBestMatch(
        encodingResult.embedding,
        _employeeEncodings,
        threshold: 0.6,
      );

      if (matchResult != null && matchResult.isMatch) {
        final employee = _employeeDatabase[matchResult.matchedId];
        if (employee != null) {
          emit(FaceRecognitionMatched(
            employee: employee,
            confidence: matchResult.confidence,
            distance: matchResult.distance,
          ));
          Logger.success('Face recognized: ${employee.name} (confidence: ${matchResult.confidence})');
        }
      } else {
        emit(const FaceRecognitionUnknown());
      }
    } catch (e) {
      Logger.error('Error processing camera frame', error: e);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _onAddEmployee(
    AddEmployee event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      // Extract encoding from employee photo
      if (event.employee.photoBytes != null) {
        final encodingResult = await _faceEncodingService.extractFromImageBytes(
          event.employee.photoBytes!,
        );

        if (encodingResult != null) {
          // Store employee and encoding
          _employeeDatabase[event.employee.id] = event.employee;
          _employeeEncodings[event.employee.id] = encodingResult.embedding;

          Logger.success('Employee added: ${event.employee.name}');
        } else {
          Logger.warning('Could not extract face encoding for ${event.employee.name}');
        }
      }
    } catch (e) {
      Logger.error('Failed to add employee', error: e);
    }
  }

  Future<void> _onRemoveEmployee(
    RemoveEmployee event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    _employeeDatabase.remove(event.employeeId);
    _employeeEncodings.remove(event.employeeId);
    Logger.info('Employee removed: ${event.employeeId}');
  }

  Future<void> _onLoadEmployees(
    LoadEmployees event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      emit(const FaceRecognitionLoading());

      // Load from local database
      await _loadEmployeesFromDatabase();

      emit(FaceRecognitionReady(
        employeeCount: _employeeDatabase.length,
      ));
    } catch (e) {
      Logger.error('Failed to load employees', error: e);
      emit(FaceRecognitionError(e.toString()));
    }
  }

  Future<void> _onConfirmRecognition(
    ConfirmRecognition event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    try {
      // In production, this would trigger time tracking API call
      Logger.info('Recognition confirmed for employee: ${event.employeeId}');

      emit(FaceRecognitionConfirmed(
        employee: _employeeDatabase[event.employeeId]!,
        action: event.action,
      ));

      // Reset after confirmation
      await Future.delayed(const Duration(seconds: 3));
      add(const ResetRecognition());
    } catch (e) {
      Logger.error('Failed to confirm recognition', error: e);
      emit(FaceRecognitionError(e.toString()));
    }
  }

  Future<void> _onResetRecognition(
    ResetRecognition event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    emit(const FaceRecognitionScanning());
  }

  Future<void> _loadEmployeesFromDatabase() async {
    try {
      // Load employees from local database
      final employees = await _employeeDataSource.getAllEmployees();

      _employeeDatabase.clear();
      _employeeEncodings.clear();

      int loadedWithEncodings = 0;

      for (final employee in employees) {
        _employeeDatabase[employee.id] = employee;

        // Load face encodings if available
        if (employee.hasFaceEncodings) {
          // Use the first face encoding (from photo)
          final firstEncoding = employee.faceEncodings.first;
          _employeeEncodings[employee.id] = firstEncoding.embedding;
          loadedWithEncodings++;
          Logger.debug('Loaded face encoding for ${employee.name}');
        } else {
          Logger.warning('No face encoding for ${employee.name}');
        }
      }

      Logger.info('Loaded ${employees.length} employees (${loadedWithEncodings} with face encodings)');
    } catch (e) {
      Logger.error('Failed to load employees from database', error: e);
      // Fall back to empty database
      _employeeDatabase.clear();
      _employeeEncodings.clear();
    }
  }

  Future<void> _loadMockEmployees() async {
    // Deprecated - now using actual database
    await _loadEmployeesFromDatabase();
  }

  Future<void> _onRecognizeFaceWithTopK(
    RecognizeFaceWithTopK event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    if (_isProcessing) return;

    _isProcessing = true;
    emit(const FaceRecognitionProcessing());

    try {
      // Get adaptive threshold if needed
      final threshold = event.useAdaptiveThreshold
          ? _recognitionService.getAdaptiveThreshold(
              faceDetection: event.faceDetection,
              lightingQuality: event.lightingQuality ?? 0.7,
              isIndoor: event.isIndoor,
            )
          : event.customThreshold;

      // Perform recognition with top-K matching
      final result = await _recognitionService.recognizeFace(
        imageData: event.imageData,
        faceDetection: event.faceDetection,
        topK: event.topK,
        requireLiveness: event.requireLiveness,
        customThreshold: threshold,
      );

      if (result == null) {
        emit(const FaceRecognitionNoMatches(
          message: 'Unable to process face',
        ));
      } else if (result.hasMatch) {
        // Add to history
        _recognitionHistory.addAll(result.topMatches);

        // Emit state with multiple matches
        emit(FaceRecognitionMultipleMatches(
          topMatches: result.topMatches,
          bestMatch: result.bestMatch!,
          overallConfidence: result.overallConfidence,
          metadata: result.metadata,
        ));

        Logger.success('Found ${result.topMatches.length} matches, best: ${result.bestMatch!.employeeName}');
      } else {
        emit(FaceRecognitionNoMatches(
          message: 'No matching employee found',
          attemptedMatches: result.topMatches,
          metadata: result.metadata,
        ));
      }
    } catch (e) {
      Logger.error('Face recognition failed', error: e);
      emit(FaceRecognitionError(e.toString()));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _onSelectMatchFromTopK(
    SelectMatchFromTopK event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    emit(FaceRecognitionMatchSelected(
      selectedMatch: event.selectedMatch,
      allMatches: event.allMatches,
    ));

    Logger.info('Selected match: ${event.selectedMatch.employeeName} with confidence ${event.selectedMatch.combinedConfidence}');
  }

  Future<void> _onClearRecognitionHistory(
    ClearRecognitionHistory event,
    Emitter<FaceRecognitionState> emit,
  ) async {
    _recognitionHistory.clear();
    Logger.info('Recognition history cleared');
  }

  /// Get match statistics for analytics
  Map<String, dynamic> getRecognitionStatistics() {
    if (_recognitionHistory.isEmpty) {
      return {'total_recognitions': 0};
    }

    return _recognitionService.getMatchStatistics(_recognitionHistory);
  }

  @override
  Future<void> close() {
    _faceEncodingService.dispose();
    _faceDetectionService.dispose();
    return super.close();
  }
}