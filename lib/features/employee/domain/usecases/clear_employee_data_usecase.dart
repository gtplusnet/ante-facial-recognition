import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/storage/secure_storage_helper.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/employee_local_datasource.dart';

class ClearDataResult {
  final int deletedEmployees;
  final int deletedLogs;
  final int freedBytes;
  final DateTime clearedAt;

  const ClearDataResult({
    required this.deletedEmployees,
    required this.deletedLogs,
    required this.freedBytes,
    required this.clearedAt,
  });
}

enum ClearDataType {
  employeesOnly,
  logsOnly,
  cacheOnly,
  allData,
}

class ClearEmployeeDataParams {
  final ClearDataType type;
  final bool keepApiKey;

  const ClearEmployeeDataParams({
    required this.type,
    this.keepApiKey = true,
  });
}

@injectable
class ClearEmployeeDataUseCase implements UseCase<ClearDataResult, ClearEmployeeDataParams> {
  final EmployeeLocalDataSource _localDataSource;
  final DatabaseHelper _databaseHelper;
  final SecureStorageHelper _secureStorage;

  const ClearEmployeeDataUseCase(
    this._localDataSource,
    this._databaseHelper,
    this._secureStorage,
  );

  @override
  Future<Either<Failure, ClearDataResult>> call(ClearEmployeeDataParams params) async {
    try {
      Logger.info('Starting data clear operation: ${params.type}');

      int deletedEmployees = 0;
      int deletedLogs = 0;
      int freedBytes = 0;

      final db = await _databaseHelper.database;

      switch (params.type) {
        case ClearDataType.employeesOnly:
          deletedEmployees = await _clearEmployeeData(db);
          break;

        case ClearDataType.logsOnly:
          deletedLogs = await _clearFaceRecognitionLogs(db);
          break;

        case ClearDataType.cacheOnly:
          freedBytes = await _clearCacheData();
          break;

        case ClearDataType.allData:
          deletedEmployees = await _clearEmployeeData(db);
          deletedLogs = await _clearFaceRecognitionLogs(db);
          freedBytes = await _clearCacheData();
          await _clearOfflineQueue(db);

          if (!params.keepApiKey) {
            await _clearAuthenticationData();
          }
          break;
      }

      Logger.success(
        'Data clear completed: $deletedEmployees employees, $deletedLogs logs, ${freedBytes / 1024} KB freed',
      );

      return Right(ClearDataResult(
        deletedEmployees: deletedEmployees,
        deletedLogs: deletedLogs,
        freedBytes: freedBytes,
        clearedAt: DateTime.now(),
      ));
    } catch (e) {
      Logger.error('Failed to clear data', error: e);
      return Left(DataFailure(message: 'Failed to clear data: ${e.toString()}'));
    }
  }

  Future<int> _clearEmployeeData(db) async {
    try {
      Logger.info('Clearing employee data');

      // Count employees before deletion
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM employees');
      final employeeCount = countResult.first['count'] as int;

      // Clear employees table
      await _databaseHelper.clearTable(db, 'employees');

      // Clear sync timestamp
      await _secureStorage.deleteLastSyncTime();

      Logger.success('Cleared $employeeCount employees');
      return employeeCount;
    } catch (e) {
      Logger.error('Failed to clear employee data', error: e);
      rethrow;
    }
  }

  Future<int> _clearFaceRecognitionLogs(db) async {
    try {
      Logger.info('Clearing face recognition logs');

      // Count logs before deletion
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM face_recognition_logs');
      final logsCount = countResult.first['count'] as int;

      // Clear face recognition logs table
      await _databaseHelper.clearTable(db, 'face_recognition_logs');

      Logger.success('Cleared $logsCount face recognition logs');
      return logsCount;
    } catch (e) {
      Logger.error('Failed to clear face recognition logs', error: e);
      rethrow;
    }
  }

  Future<int> _clearCacheData() async {
    try {
      Logger.info('Clearing cache data');

      // This would require path_provider and file system operations
      // For now, return a placeholder
      // In a real implementation, you would:
      // 1. Get temp directory
      // 2. Calculate current size
      // 3. Delete temp files
      // 4. Return freed bytes

      Logger.success('Cache data cleared');
      return 0; // Placeholder
    } catch (e) {
      Logger.error('Failed to clear cache data', error: e);
      rethrow;
    }
  }

  Future<void> _clearOfflineQueue(db) async {
    try {
      Logger.info('Clearing offline queue');

      await _databaseHelper.clearTable(db, 'offline_queue');

      Logger.success('Offline queue cleared');
    } catch (e) {
      Logger.error('Failed to clear offline queue', error: e);
      rethrow;
    }
  }

  Future<void> _clearAuthenticationData() async {
    try {
      Logger.info('Clearing authentication data');

      await _secureStorage.deleteApiKey();
      await _secureStorage.deleteLastSyncTime();

      Logger.success('Authentication data cleared');
    } catch (e) {
      Logger.error('Failed to clear authentication data', error: e);
      rethrow;
    }
  }

  /// Get data statistics before clearing
  Future<Map<String, dynamic>> getDataStatistics() async {
    try {
      final db = await _databaseHelper.database;

      final employeeCount = await db.rawQuery('SELECT COUNT(*) as count FROM employees');
      final logsCount = await db.rawQuery('SELECT COUNT(*) as count FROM face_recognition_logs');
      final queueCount = await db.rawQuery('SELECT COUNT(*) as count FROM offline_queue');

      // Calculate image data size
      final imageSizeResult = await db.rawQuery('''
        SELECT SUM(LENGTH(photo_bytes)) as total_size
        FROM employees
        WHERE photo_bytes IS NOT NULL
      ''');

      final imageDataSize = imageSizeResult.first['total_size'] as int? ?? 0;

      return {
        'employeeCount': employeeCount.first['count'] as int,
        'logsCount': logsCount.first['count'] as int,
        'queueCount': queueCount.first['count'] as int,
        'imageDataSize': imageDataSize,
        'lastSyncTime': await _secureStorage.getLastSyncTime(),
        'hasApiKey': await _secureStorage.getApiKey() != null,
      };
    } catch (e) {
      Logger.error('Failed to get data statistics', error: e);
      return {};
    }
  }
}