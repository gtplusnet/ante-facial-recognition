import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/employee_local_datasource.dart';
import '../../data/models/employee_model.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/usecases/sync_employees_usecase.dart';
import '../../domain/usecases/generate_face_encoding_usecase.dart';
import '../../../face_recognition/data/services/simplified_face_recognition_service.dart';
import 'employee_event.dart';
import 'employee_state.dart';

@injectable
class EmployeeBloc extends Bloc<EmployeeEvent, EmployeeState> {
  final SyncEmployeesUseCase _syncEmployeesUseCase;
  final GenerateFaceEncodingUseCase _generateFaceEncodingUseCase;
  final EmployeeRepository _employeeRepository;
  final EmployeeLocalDataSource _localDataSource;
  final SimplifiedFaceRecognitionService _faceRecognitionService;

  EmployeeBloc(
    this._syncEmployeesUseCase,
    this._generateFaceEncodingUseCase,
    this._employeeRepository,
    this._localDataSource,
    this._faceRecognitionService,
  ) : super(const EmployeeInitial()) {
    on<LoadEmployees>(_onLoadEmployees);
    on<SyncEmployees>(_onSyncEmployees);
    on<RefreshEmployees>(_onRefreshEmployees);
    on<SearchEmployees>(_onSearchEmployees);
    on<GenerateFaceEmbeddings>(_onGenerateFaceEmbeddings);
    on<GenerateAllFaceEmbeddings>(_onGenerateAllFaceEmbeddings);
    on<ClearEmployeeCache>(_onClearEmployeeCache);
    on<LoadEmployeeDetail>(_onLoadEmployeeDetail);
    on<AddFaceImage>(_onAddFaceImage);
    on<DeleteFaceImage>(_onDeleteFaceImage);
  }

  Future<void> _onLoadEmployees(
    LoadEmployees event,
    Emitter<EmployeeState> emit,
  ) async {
    emit(const EmployeeLoading());

    try {
      // Load employees from local database
      final employees = await _localDataSource.getAllEmployees();
      final lastSyncTime = await _syncEmployeesUseCase.getLastSyncTime();

      emit(EmployeeLoaded(
        employees: employees,
        lastSyncTime: lastSyncTime,
      ));

      // Check if sync is needed
      final syncNeeded = await _syncEmployeesUseCase.isSyncNeeded();
      if (syncNeeded) {
        Logger.info('Auto-sync triggered as sync is needed');
        add(const SyncEmployees());
      }
    } catch (e) {
      Logger.error('Failed to load employees', error: e);
      emit(EmployeeError(message: 'Failed to load employees: ${e.toString()}'));
    }
  }

  Future<void> _onSyncEmployees(
    SyncEmployees event,
    Emitter<EmployeeState> emit,
  ) async {
    Logger.info('[EmployeeBloc] === Starting Sync Employees Event ===');

    // Keep current employees if available
    List<Employee> currentEmployees = [];
    if (state is EmployeeLoaded) {
      currentEmployees = (state as EmployeeLoaded).employees;
      Logger.debug('[EmployeeBloc] Current employees count: ${currentEmployees.length}');
    }

    emit(const EmployeeSyncing(
      progress: 0,
      message: 'Starting synchronization...',
    ));
    Logger.info('[EmployeeBloc] Emitted EmployeeSyncing state');

    try {
      // Use StreamController to emit progress updates
      final progressController = StreamController<EmployeeSyncing>();

      progressController.stream.listen((syncState) {
        if (!emit.isDone) {
          emit(syncState);
          Logger.debug('[EmployeeBloc] Progress update: ${syncState.message}');
        }
      });

      // Start sync process
      Logger.info('[EmployeeBloc] Calling SyncEmployeesUseCase...');
      final result = await _syncEmployeesUseCase.call(NoParams());
      Logger.info('[EmployeeBloc] SyncEmployeesUseCase completed');

      await progressController.close();

      // Handle failure case
      if (result.isLeft()) {
        final failure = result.fold((l) => l, (r) => null)!;
        Logger.error('[EmployeeBloc] Sync failed with failure: ${failure.message}');
        emit(EmployeeError(
          message: failure.message,
          cachedEmployees: currentEmployees,
        ));
        return;
      }

      // Handle success case with proper async/await
      final syncResult = result.fold((l) => null, (r) => r)!;
      Logger.success('[EmployeeBloc] Sync successful: ${syncResult.syncedEmployees} synced, ${syncResult.failedEmployees} failed');

      // Reload employees from local database
      Logger.info('[EmployeeBloc] Reloading employees from local database...');
      final employees = await _localDataSource.getAllEmployees();
      Logger.info('[EmployeeBloc] Loaded ${employees.length} employees from local database');

      // Emit success state
      emit(EmployeeSyncSuccess(
        syncResult: syncResult,
        employees: employees,
      ));

      // After showing success, transition to loaded state
      await Future.delayed(const Duration(seconds: 2));

      // Check if we can still emit before emitting loaded state
      if (!emit.isDone) {
        // Emit loaded state
        emit(EmployeeLoaded(
          employees: employees,
          lastSyncTime: syncResult.syncTime,
        ));
        Logger.info('[EmployeeBloc] === Sync Employees Event Completed Successfully ===');
      } else {
        Logger.warning('[EmployeeBloc] Cannot emit final state - emitter is done');
      }
    } catch (e) {
      Logger.error('[EmployeeBloc] Sync failed with exception', error: e);
      emit(EmployeeError(
        message: 'Sync failed: ${e.toString()}',
        cachedEmployees: currentEmployees,
      ));
    }
  }

  Future<void> _onRefreshEmployees(
    RefreshEmployees event,
    Emitter<EmployeeState> emit,
  ) async {
    // Similar to sync but with pull-to-refresh behavior
    add(const SyncEmployees());
  }

  Future<void> _onSearchEmployees(
    SearchEmployees event,
    Emitter<EmployeeState> emit,
  ) async {
    if (state is EmployeeLoaded) {
      final currentState = state as EmployeeLoaded;
      emit(currentState.copyWith(searchQuery: event.query));
    }
  }

  Future<void> _onGenerateFaceEmbeddings(
    GenerateFaceEmbeddings event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      final employee = await _localDataSource.getEmployee(event.employeeId);
      if (employee == null) {
        emit(const EmployeeError(message: 'Employee not found'));
        return;
      }

      if (!employee.hasPhoto) {
        emit(const EmployeeError(message: 'Employee has no photo'));
        return;
      }

      emit(EmployeeGeneratingEmbedding(
        employeeId: event.employeeId,
        employeeName: employee.name,
        progress: 0,
      ));

      // TODO: Implement face embedding generation from photo
      // This will involve:
      // 1. Loading the photo bytes
      // 2. Detecting face in the photo
      // 3. Cropping and preprocessing the face
      // 4. Running through MobileFaceNet to get embedding
      // 5. Saving the embedding to the employee record

      await Future.delayed(const Duration(seconds: 2)); // Placeholder

      emit(EmployeeEmbeddingGenerated(
        employeeId: event.employeeId,
        message: 'Face embedding generated successfully',
      ));

      // Reload employees
      add(const LoadEmployees());
    } catch (e) {
      Logger.error('Failed to generate face embedding', error: e);
      emit(EmployeeError(
        message: 'Failed to generate embedding: ${e.toString()}',
      ));
    }
  }

  Future<void> _onGenerateAllFaceEmbeddings(
    GenerateAllFaceEmbeddings event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      Logger.info('Starting face encoding generation for all employees');

      emit(const EmployeeLoading());

      // Get all employees with photos
      final employees = await _localDataSource.getAllEmployees();
      final employeesWithPhotos = employees.where((e) => e.hasPhoto && e.photoBytes != null).toList();

      if (employeesWithPhotos.isEmpty) {
        emit(const EmployeeError(message: 'No employees with photos found. Please sync employees first.'));
        return;
      }

      Logger.info('Found ${employeesWithPhotos.length} employees with photos to process');

      int processedCount = 0;
      int successCount = 0;
      int errorCount = 0;
      final List<String> errorMessages = [];

      for (final employee in employeesWithPhotos) {
        try {
          Logger.info('Processing face encoding for ${employee.name}...');

          emit(EmployeeGeneratingEmbedding(
            employeeId: employee.id,
            employeeName: employee.name,
            progress: processedCount / employeesWithPhotos.length,
          ));

          // Generate face encoding using the proper use case
          final result = await _generateFaceEncodingUseCase.generateAndApplyEncoding(
            employee.copyWith(),
            employee.photoBytes!,
          );

          // Update the employee with the new encoding
          await _localDataSource.saveEmployee(EmployeeModel.fromEntity(result));

          successCount++;
          Logger.success('Generated face encoding for ${employee.name}');

        } catch (e) {
          errorCount++;
          final errorMsg = 'Failed to generate encoding for ${employee.name}: $e';
          errorMessages.add(errorMsg);
          Logger.error(errorMsg, error: e);
        }

        processedCount++;
      }

      Logger.info('Face encoding generation completed: $successCount successful, $errorCount errors');

      if (errorCount > 0) {
        emit(EmployeeError(message: 'Generated $successCount encodings with $errorCount errors:\n${errorMessages.take(3).join('\n')}${errorMessages.length > 3 ? '\n... and ${errorMessages.length - 3} more errors' : ''}'));
      } else {
        emit(EmployeeEmbeddingGenerated(
          employeeId: '',
          message: 'Successfully generated face encodings for $successCount employees',
        ));
      }

      // Reload face recognition service to pick up new encodings
      try {
        await _faceRecognitionService.reloadEmployees();
        Logger.success('Face recognition service reloaded with updated encodings');
      } catch (e) {
        Logger.warning('Failed to reload face recognition service: $e');
      }

      // Reload employees to show updated data
      add(const LoadEmployees());

    } catch (e) {
      Logger.error('Failed to generate face embeddings', error: e);
      emit(EmployeeError(
        message: 'Failed to generate face embeddings: ${e.toString()}',
      ));
    }
  }

  Future<void> _onClearEmployeeCache(
    ClearEmployeeCache event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      await _localDataSource.clearAllEmployees();
      emit(const EmployeeLoaded(employees: []));
    } catch (e) {
      Logger.error('Failed to clear employee cache', error: e);
      emit(EmployeeError(message: 'Failed to clear cache: ${e.toString()}'));
    }
  }

  Future<void> _onLoadEmployeeDetail(
    LoadEmployeeDetail event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      emit(const EmployeeLoading());

      // Load employee from local database
      final employee = await _localDataSource.getEmployeeById(event.employeeId);

      if (employee != null) {
        emit(EmployeeDetailLoaded(employee: employee));
      } else {
        emit(const EmployeeError(message: 'Employee not found'));
      }
    } catch (e) {
      Logger.error('Failed to load employee detail', error: e);
      emit(EmployeeError(message: 'Failed to load employee: ${e.toString()}'));
    }
  }

  Future<void> _onAddFaceImage(
    AddFaceImage event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      emit(const FaceImageProcessing(
        message: 'Processing face image...',
        progress: 0.2,
      ));

      // Get the employee
      final employee = await _localDataSource.getEmployeeById(event.employeeId);
      if (employee == null) {
        emit(const EmployeeError(message: 'Employee not found'));
        return;
      }

      emit(const FaceImageProcessing(
        message: 'Detecting face...',
        progress: 0.4,
      ));

      // Generate face encoding from the image
      final result = await _generateFaceEncodingUseCase.execute(
        GenerateFaceEncodingParams(
          employeeId: event.employeeId,
          imageBytes: event.imageBytes,
          source: event.source,
        ),
      );

      await result.fold(
        (failure) async {
          emit(EmployeeError(message: 'Failed to process face image: $failure'));
        },
        (encodingId) async {
          emit(FaceImageAdded(
            employeeId: event.employeeId,
            encodingId: encodingId,
          ));

          // Reload the face recognition service with updated encodings
          await _faceRecognitionService.loadEmployees();

          // Reload the employee data to show the new face encoding
          final updatedEmployee = await _localDataSource.getEmployeeById(event.employeeId);
          if (updatedEmployee != null) {
            emit(EmployeeDetailLoaded(employee: updatedEmployee));
          }
        },
      );
    } catch (e) {
      Logger.error('Failed to add face image', error: e);
      emit(EmployeeError(message: 'Failed to add face image: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteFaceImage(
    DeleteFaceImage event,
    Emitter<EmployeeState> emit,
  ) async {
    try {
      emit(const EmployeeLoading());

      // Delete the face encoding from database
      await _localDataSource.deleteFaceEncoding(event.encodingId);

      emit(FaceImageDeleted(
        employeeId: event.employeeId,
        encodingId: event.encodingId,
      ));

      // Reload the face recognition service with updated encodings
      await _faceRecognitionService.loadEmployees();
    } catch (e) {
      Logger.error('Failed to delete face image', error: e);
      emit(EmployeeError(message: 'Failed to delete face image: ${e.toString()}'));
    }
  }
}