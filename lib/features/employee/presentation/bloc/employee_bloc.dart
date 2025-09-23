import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/employee_local_datasource.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/usecases/sync_employees_usecase.dart';
import 'employee_event.dart';
import 'employee_state.dart';

@injectable
class EmployeeBloc extends Bloc<EmployeeEvent, EmployeeState> {
  final SyncEmployeesUseCase _syncEmployeesUseCase;
  final EmployeeRepository _employeeRepository;
  final EmployeeLocalDataSource _localDataSource;

  EmployeeBloc(
    this._syncEmployeesUseCase,
    this._employeeRepository,
    this._localDataSource,
  ) : super(const EmployeeInitial()) {
    on<LoadEmployees>(_onLoadEmployees);
    on<SyncEmployees>(_onSyncEmployees);
    on<RefreshEmployees>(_onRefreshEmployees);
    on<SearchEmployees>(_onSearchEmployees);
    on<GenerateFaceEmbeddings>(_onGenerateFaceEmbeddings);
    on<ClearEmployeeCache>(_onClearEmployeeCache);
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
}