import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/error_handler.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/storage/secure_storage_helper.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/employee_local_datasource.dart';
import '../../data/datasources/manpower_api_service.dart';
import '../../data/models/employee_model.dart';
import '../entities/employee.dart';
import '../repositories/employee_repository.dart';
import 'generate_face_encoding_usecase.dart';

class SyncResult {
  final int totalEmployees;
  final int syncedEmployees;
  final int failedEmployees;
  final DateTime syncTime;
  final List<String> errors;

  const SyncResult({
    required this.totalEmployees,
    required this.syncedEmployees,
    required this.failedEmployees,
    required this.syncTime,
    this.errors = const [],
  });
}

class EmployeeProcessingResult {
  final int syncedCount;
  final int failedCount;
  final List<String> errors;

  const EmployeeProcessingResult({
    required this.syncedCount,
    required this.failedCount,
    this.errors = const [],
  });
}

@injectable
class SyncEmployeesUseCase implements UseCase<SyncResult, NoParams> {
  final EmployeeRepository _repository;
  final ManpowerApiService _apiService;
  final EmployeeLocalDataSource _localDataSource;
  final SecureStorageHelper _secureStorage;
  final GenerateFaceEncodingUseCase _generateFaceEncodingUseCase;

  const SyncEmployeesUseCase(
    this._repository,
    this._apiService,
    this._localDataSource,
    this._secureStorage,
    this._generateFaceEncodingUseCase,
  );

  @override
  Future<Either<Failure, SyncResult>> call(NoParams params) async {
    return await ErrorHandler.handleAsyncOperation(
      'employee synchronization',
      () async {
        Logger.info('Starting employee synchronization');

        // Check if we have API key
        final apiKey = await _secureStorage.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          Logger.error('No API key found for sync');
          return Left(const AuthenticationFailure(message: 'Device not authenticated. Please authenticate your device first.'));
        }

        // Add timeout to prevent indefinite loading
        return await _performSync().timeout(
          const Duration(minutes: 5),
          onTimeout: () {
            Logger.error('Sync operation timed out');
            return Left(const ServerFailure(message: 'Sync operation timed out. Please try again.'));
          },
        );
      },
      fallbackValue: Left(const ServerFailure(message: 'Employee synchronization failed')),
    );
  }

  Future<Either<Failure, SyncResult>> _performSync() async {
    try {
      Logger.info('=== Starting Employee Sync Process ===');

      // Step 1: Fetch employees from API
      final employees = await _fetchEmployeesFromApi();
      if (employees.isEmpty) {
        return Right(_createEmptySyncResult());
      }

      Logger.success('Step 2: Successfully fetched ${employees.length} employees from API');

      // Step 2: Process and store employees locally
      final processingResult = await _processEmployees(employees);

      // Step 3: Update sync metadata
      await _updateSyncMetadata();

      Logger.success(
        'Sync completed: ${processingResult.syncedCount} synced, ${processingResult.failedCount} failed',
      );

      return Right(SyncResult(
        totalEmployees: employees.length,
        syncedEmployees: processingResult.syncedCount,
        failedEmployees: processingResult.failedCount,
        syncTime: DateTime.now(),
        errors: processingResult.errors,
      ));
    } catch (e) {
      Logger.error('Employee sync failed', error: e);
      return Left(ServerFailure(message: 'Sync failed: ${e.toString()}'));
    }
  }

  /// Fetch employees from API with photos
  Future<List<Employee>> _fetchEmployeesFromApi() async {
    Logger.info('Step 1: Fetching employees from API with photos...');
    final employees = await _apiService.getEmployees(withPhotos: true);
    Logger.debug('API call completed, received response');

    if (employees.isEmpty) {
      Logger.warning('No employees found from API - database might be empty');
    }

    return employees;
  }

  /// Create empty sync result when no employees found
  SyncResult _createEmptySyncResult() {
    return SyncResult(
      totalEmployees: 0,
      syncedEmployees: 0,
      failedEmployees: 0,
      syncTime: DateTime.now(),
    );
  }

  /// Process and store employees locally
  Future<EmployeeProcessingResult> _processEmployees(List<Employee> employees) async {
    Logger.info('Step 3: Starting to process and store employees locally...');

    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    for (int index = 0; index < employees.length; index++) {
      final employee = employees[index];
      final processedCount = index + 1;

      Logger.debug('Processing employee $processedCount/${employees.length}: ${employee.name}');

      try {
        await _processIndividualEmployee(employee);
        syncedCount++;
      } catch (e) {
        failedCount++;
        errors.add('Failed to sync ${employee.name}: ${e.toString()}');
        Logger.error('Failed to sync employee ${employee.name}', error: e);
      }
    }

    return EmployeeProcessingResult(
      syncedCount: syncedCount,
      failedCount: failedCount,
      errors: errors,
    );
  }

  /// Process a single employee and store locally
  Future<void> _processIndividualEmployee(Employee employee) async {
    if (employee.photoUrl != null && employee.photoUrl!.isNotEmpty) {
      await _processEmployeeWithPhoto(employee);
    } else {
      await _processEmployeeWithoutPhoto(employee);
    }
  }

  /// Process employee with photo download and face encoding
  Future<void> _processEmployeeWithPhoto(Employee employee) async {
    Logger.debug('  - Downloading photo for ${employee.name} from ${employee.photoUrl}');

    final photoBytes = await _apiService.downloadEmployeePhoto(employee.photoUrl!);

    if (photoBytes != null) {
      // Generate face encoding using dedicated use case
      final employeeWithEncoding = await _generateFaceEncodingUseCase.generateAndApplyEncoding(
        employee,
        photoBytes,
      );

      // Update employee with photo bytes (encoding already applied if successful)
      final updatedEmployee = employeeWithEncoding.copyWith(photoBytes: photoBytes);

      // Save to local database (convert to model)
      await _localDataSource.saveEmployee(
        EmployeeModel.fromEntity(updatedEmployee),
      );
    } else {
      // Save without photo if download failed
      await _processEmployeeWithoutPhoto(employee);
      Logger.warning('Failed to download photo for ${employee.name}');
    }
  }

  /// Process employee without photo
  Future<void> _processEmployeeWithoutPhoto(Employee employee) async {
    await _localDataSource.saveEmployee(
      EmployeeModel.fromEntity(employee),
    );
  }

  /// Update sync metadata after successful sync
  Future<void> _updateSyncMetadata() async {
    await _secureStorage.saveLastSyncTime(DateTime.now());
  }

  /// Get last sync time
  Future<DateTime?> getLastSyncTime() async {
    return await ErrorHandler.handleOptionalOperation(
      'get last sync time',
      () => _secureStorage.getLastSyncTime(),
    );
  }

  /// Check if sync is needed (e.g., last sync > 1 hour ago)
  Future<bool> isSyncNeeded() async {
    return await ErrorHandler.handleOperationWithDefault(
      'check if sync needed',
      () async {
        final lastSync = await getLastSyncTime();
        if (lastSync == null) {
          return true; // Never synced
        }

        final timeSinceSync = DateTime.now().difference(lastSync);
        return timeSinceSync.inMinutes > 15; // Sync every 15 minutes
      },
      true, // Default to sync on error
    );
  }
}