import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/storage/secure_storage_helper.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/employee_local_datasource.dart';
import '../../data/datasources/manpower_api_service.dart';
import '../../data/models/employee_model.dart';
import '../entities/employee.dart';
import '../repositories/employee_repository.dart';

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

@injectable
class SyncEmployeesUseCase implements UseCase<SyncResult, NoParams> {
  final EmployeeRepository _repository;
  final ManpowerApiService _apiService;
  final EmployeeLocalDataSource _localDataSource;
  final SecureStorageHelper _secureStorage;

  const SyncEmployeesUseCase(
    this._repository,
    this._apiService,
    this._localDataSource,
    this._secureStorage,
  );

  @override
  Future<Either<Failure, SyncResult>> call(NoParams params) async {
    try {
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
    } catch (e) {
      Logger.error('Employee sync failed', error: e);
      return Left(ServerFailure(message: 'Sync failed: ${e.toString()}'));
    }
  }

  Future<Either<Failure, SyncResult>> _performSync() async {
    try {
      Logger.info('=== Starting Employee Sync Process ===');

      // Fetch employees with photos from API
      Logger.info('Step 1: Fetching employees from API with photos...');
      final employees = await _apiService.getEmployees(withPhotos: true);
      Logger.debug('API call completed, received response');

      if (employees.isEmpty) {
        Logger.warning('No employees found from API - database might be empty');
        return Right(SyncResult(
          totalEmployees: 0,
          syncedEmployees: 0,
          failedEmployees: 0,
          syncTime: DateTime.now(),
        ));
      }

      Logger.success('Step 2: Successfully fetched ${employees.length} employees from API');

      // Process and store employees
      Logger.info('Step 3: Starting to process and store employees locally...');
      int syncedCount = 0;
      int failedCount = 0;
      final errors = <String>[];
      int processedCount = 0;

      for (final employee in employees) {
        processedCount++;
        Logger.debug('Processing employee ${processedCount}/${employees.length}: ${employee.name}');

        try {
          // Download profile photo if available
          if (employee.photoUrl != null && employee.photoUrl!.isNotEmpty) {
            Logger.debug('  - Downloading photo for ${employee.name} from ${employee.photoUrl}');
            final photoBytes = await _apiService.downloadEmployeePhoto(
              employee.photoUrl!,
            );

            if (photoBytes != null) {
              // Update employee with photo bytes
              final updatedEmployee = employee.copyWith(photoBytes: photoBytes);

              // Save to local database (convert to model)
              await _localDataSource.saveEmployee(
                EmployeeModel.fromEntity(updatedEmployee),
              );
              syncedCount++;
            } else {
              // Save without photo
              await _localDataSource.saveEmployee(
                EmployeeModel.fromEntity(employee),
              );
              syncedCount++;
              Logger.warning('Failed to download photo for ${employee.name}');
            }
          } else {
            // Save employee without photo
            await _localDataSource.saveEmployee(
              EmployeeModel.fromEntity(employee),
            );
            syncedCount++;
          }
        } catch (e) {
          failedCount++;
          errors.add('Failed to sync ${employee.name}: ${e.toString()}');
          Logger.error('Failed to sync employee ${employee.name}', error: e);
        }
      }

      // Update last sync time
      await _secureStorage.saveLastSyncTime(DateTime.now());

      Logger.success(
        'Sync completed: $syncedCount synced, $failedCount failed',
      );

      return Right(SyncResult(
        totalEmployees: employees.length,
        syncedEmployees: syncedCount,
        failedEmployees: failedCount,
        syncTime: DateTime.now(),
        errors: errors,
      ));
    } catch (e) {
      Logger.error('Employee sync failed', error: e);
      return Left(ServerFailure(message: 'Sync failed: ${e.toString()}'));
    }
  }

  /// Get last sync time
  Future<DateTime?> getLastSyncTime() async {
    try {
      return await _secureStorage.getLastSyncTime();
    } catch (e) {
      Logger.error('Failed to get last sync time', error: e);
      return null;
    }
  }

  /// Check if sync is needed (e.g., last sync > 1 hour ago)
  Future<bool> isSyncNeeded() async {
    try {
      final lastSync = await getLastSyncTime();
      if (lastSync == null) {
        return true; // Never synced
      }

      final timeSinceSync = DateTime.now().difference(lastSync);
      return timeSinceSync.inMinutes > 15; // Sync every 15 minutes
    } catch (e) {
      Logger.error('Failed to check if sync needed', error: e);
      return true; // Sync on error
    }
  }
}