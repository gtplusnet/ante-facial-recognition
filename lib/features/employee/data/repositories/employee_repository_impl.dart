import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/offline_queue_manager.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';
import '../datasources/employee_local_datasource.dart';
import '../datasources/manpower_api_service.dart';
import '../models/employee_model.dart';

@Singleton(as: EmployeeRepository)
class EmployeeRepositoryImpl implements EmployeeRepository {
  final ManpowerApiService _apiService;
  final EmployeeLocalDataSource _localDataSource;
  final OfflineQueueManager _offlineQueueManager;

  EmployeeRepositoryImpl({
    required ManpowerApiService apiService,
    required EmployeeLocalDataSource localDataSource,
    required OfflineQueueManager offlineQueueManager,
  })  : _apiService = apiService,
        _localDataSource = localDataSource,
        _offlineQueueManager = offlineQueueManager;

  @override
  Future<Either<Failure, List<Employee>>> getLocalEmployees() async {
    try {
      final employees = await _localDataSource.getEmployees();
      return Right(employees);
    } catch (e) {
      Logger.error('Failed to get local employees', error: e);
      return Left(DatabaseFailure(message: 'Failed to get local employees: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Employee>>> getRemoteEmployees({bool withPhotos = true}) async {
    try {
      final employees = await _apiService.getEmployees(withPhotos: withPhotos);
      return Right(employees);
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, code: e.code));
    } on AuthenticationException catch (e) {
      return Left(AuthenticationFailure(message: e.message));
    } catch (e) {
      Logger.error('Failed to get remote employees', error: e);
      return Left(ServerFailure(message: 'Failed to get remote employees: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Employee>>> syncEmployees() async {
    try {
      Logger.info('Starting employee synchronization');

      // Get employees from API
      final remoteResult = await getRemoteEmployees(withPhotos: true);

      return await remoteResult.fold(
        (failure) async {
          Logger.warning('Failed to fetch remote employees, using local data');
          // If API fails, return local employees
          return getLocalEmployees();
        },
        (remoteEmployees) async {
          // Download photos for employees
          for (final employee in remoteEmployees) {
            if (employee.photoUrl != null && employee.photoBytes == null) {
              final photoBytes = await _apiService.downloadEmployeePhoto(employee.photoUrl!);
              if (photoBytes != null) {
                final updatedEmployee = (employee as EmployeeModel).copyWith(
                  photoBytes: photoBytes,
                );
                remoteEmployees[remoteEmployees.indexOf(employee)] = updatedEmployee;
              }
            }
          }

          // Save to local storage
          await _localDataSource.saveEmployees(remoteEmployees.cast<EmployeeModel>());

          // Update last sync date
          await _localDataSource.updateLastSyncDate(DateTime.now());

          Logger.success('Employee synchronization completed: ${remoteEmployees.length} employees');
          return Right(remoteEmployees);
        },
      );
    } catch (e) {
      Logger.error('Employee synchronization failed', error: e);
      return Left(ServerFailure(message: 'Synchronization failed: $e'));
    }
  }

  @override
  Future<Either<Failure, Employee?>> getEmployee(String id) async {
    try {
      final employee = await _localDataSource.getEmployee(id);
      return Right(employee);
    } catch (e) {
      Logger.error('Failed to get employee $id', error: e);
      return Left(DatabaseFailure(message: 'Failed to get employee: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveEmployees(List<Employee> employees) async {
    try {
      await _localDataSource.saveEmployees(
        employees.map((e) => EmployeeModel.fromEntity(e)).toList(),
      );
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to save employees', error: e);
      return Left(DatabaseFailure(message: 'Failed to save employees: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveEmployee(Employee employee) async {
    try {
      await _localDataSource.saveEmployee(EmployeeModel.fromEntity(employee));
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to save employee', error: e);
      return Left(DatabaseFailure(message: 'Failed to save employee: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteEmployee(String id) async {
    try {
      await _localDataSource.deleteEmployee(id);
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to delete employee $id', error: e);
      return Left(DatabaseFailure(message: 'Failed to delete employee: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> clearEmployees() async {
    try {
      await _localDataSource.clearEmployees();
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to clear employees', error: e);
      return Left(DatabaseFailure(message: 'Failed to clear employees: $e'));
    }
  }

  @override
  Future<Either<Failure, Uint8List?>> downloadEmployeePhoto(String photoUrl) async {
    try {
      final photoBytes = await _apiService.downloadEmployeePhoto(photoUrl);
      return Right(photoBytes);
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    } catch (e) {
      Logger.error('Failed to download employee photo', error: e);
      return Left(ServerFailure(message: 'Failed to download photo: $e'));
    }
  }

  @override
  Future<Either<Failure, List<FaceEncoding>>> getEmployeeFaceEncodings(String employeeId) async {
    try {
      final encodings = await _localDataSource.getFaceEncodings(employeeId);
      return Right(encodings);
    } catch (e) {
      Logger.error('Failed to get face encodings for $employeeId', error: e);
      return Left(DatabaseFailure(message: 'Failed to get face encodings: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveFaceEncoding(String employeeId, FaceEncoding encoding) async {
    try {
      await _localDataSource.saveFaceEncoding(
        employeeId,
        FaceEncodingModel(
          id: encoding.id,
          embedding: encoding.embedding,
          quality: encoding.quality,
          createdAt: encoding.createdAt,
          source: encoding.source,
          metadata: encoding.metadata,
        ),
      );
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to save face encoding', error: e);
      return Left(DatabaseFailure(message: 'Failed to save face encoding: $e'));
    }
  }

  @override
  Future<Either<Failure, EmployeeTimeRecord>> clockIn({
    required String employeeId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  }) async {
    try {
      final record = await _apiService.clockIn(
        employeeId: employeeId,
        photoBase64: photoBase64,
        location: location,
        confidence: confidence,
      );

      // Save to local storage
      await _localDataSource.saveTimeRecord(record);

      return Right(record);
    } on NetworkException catch (e) {
      // Save to offline queue for later sync
      Logger.warning('Clock in failed due to network, saving to offline queue');

      // Get employee name from local storage
      final employee = await _localDataSource.getEmployee(employeeId);
      final employeeName = employee?.name ?? '';

      // Create a local record
      final localRecord = EmployeeTimeRecordModel(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        employeeId: employeeId,
        employeeName: employeeName,
        clockInTime: DateTime.now(),
        clockInPhoto: photoBase64,
        clockInConfidence: confidence,
        clockInLocation: location,
        status: 'clocked_in',
      );

      // Save to local storage
      await _localDataSource.saveTimeRecord(localRecord);

      // Add to offline queue for sync
      await _offlineQueueManager.addToQueue(
        QueuedRequest(
          endpoint: '/manpower/time-in',
          method: 'POST',
          data: {
            'employeeId': employeeId,
            'photo': photoBase64,
            'location': location,
            'confidence': confidence,
            'recordId': localRecord.id,
          },
          headers: {
            'x-api-key': 'device_api_key_here', // TODO: Get from secure storage
            'Content-Type': 'application/json',
          },
          createdAt: DateTime.now(),
        ),
      );

      return Right(localRecord);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, code: e.code));
    } on AuthenticationException catch (e) {
      return Left(AuthenticationFailure(message: e.message));
    } catch (e) {
      Logger.error('Failed to clock in', error: e);
      return Left(ServerFailure(message: 'Failed to clock in: $e'));
    }
  }

  @override
  Future<Either<Failure, EmployeeTimeRecord>> clockOut({
    required String timeRecordId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  }) async {
    try {
      final record = await _apiService.clockOut(
        timeRecordId: timeRecordId,
        photoBase64: photoBase64,
        location: location,
        confidence: confidence,
      );

      // Save to local storage
      await _localDataSource.saveTimeRecord(record);

      return Right(record);
    } on NetworkException catch (e) {
      // Save to offline queue for later sync
      Logger.warning('Clock out failed due to network, saving to offline queue');

      // Try to get the existing time record from local storage
      final localRecords = await _localDataSource.getTimeRecords();
      final existingRecord = localRecords.firstWhere(
        (r) => r.id == timeRecordId,
        orElse: () => throw Exception('Time record not found'),
      );

      // Update the local record with clock-out data
      final updatedRecord = existingRecord.copyWith(
        clockOutTime: DateTime.now(),
        clockOutPhoto: photoBase64,
        clockOutConfidence: confidence,
        clockOutLocation: location,
        status: 'clocked_out',
        totalHours: DateTime.now().difference(existingRecord.clockInTime ?? DateTime.now()),
      );

      // Save updated record to local storage
      await _localDataSource.saveTimeRecord(updatedRecord as EmployeeTimeRecordModel);

      // Add to offline queue for sync
      await _offlineQueueManager.addToQueue(
        QueuedRequest(
          endpoint: '/manpower/time-out',
          method: 'POST',
          data: {
            'timeRecordId': timeRecordId,
            'photo': photoBase64,
            'location': location,
            'confidence': confidence,
          },
          headers: {
            'x-api-key': 'device_api_key_here', // TODO: Get from secure storage
            'Content-Type': 'application/json',
          },
          createdAt: DateTime.now(),
        ),
      );

      return Right(updatedRecord);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, code: e.code));
    } on AuthenticationException catch (e) {
      return Left(AuthenticationFailure(message: e.message));
    } catch (e) {
      Logger.error('Failed to clock out', error: e);
      return Left(ServerFailure(message: 'Failed to clock out: $e'));
    }
  }

  @override
  Future<Either<Failure, EmployeeTimeRecord?>> getEmployeeStatus(String employeeId) async {
    try {
      final status = await _apiService.getEmployeeStatus(employeeId);
      return Right(status);
    } on NetworkException catch (e) {
      // Try to get from local storage
      final localRecords = await _localDataSource.getTimeRecords(
        employeeId: employeeId,
        date: DateTime.now(),
      );

      if (localRecords.isNotEmpty) {
        final latestRecord = localRecords.first;
        return Right(latestRecord);
      }

      return Left(NetworkFailure(message: e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, code: e.code));
    } catch (e) {
      Logger.error('Failed to get employee status', error: e);
      return Left(ServerFailure(message: 'Failed to get employee status: $e'));
    }
  }

  @override
  Future<Either<Failure, List<EmployeeTimeRecord>>> getDailyLogs({
    DateTime? date,
    String? employeeId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final logs = await _apiService.getDailyLogs(
        date: date,
        employeeId: employeeId,
        page: page,
        limit: limit,
      );

      // Save to local storage for offline access
      for (final log in logs) {
        await _localDataSource.saveTimeRecord(log);
      }

      return Right(logs);
    } on NetworkException catch (e) {
      // Get from local storage
      final localLogs = await _localDataSource.getTimeRecords(
        date: date,
        employeeId: employeeId,
      );
      return Right(localLogs);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, code: e.code));
    } catch (e) {
      Logger.error('Failed to get daily logs', error: e);
      return Left(ServerFailure(message: 'Failed to get daily logs: $e'));
    }
  }

  @override
  Future<Either<Failure, List<EmployeeTimeRecord>>> getLocalTimeRecords({
    DateTime? date,
    String? employeeId,
  }) async {
    try {
      final records = await _localDataSource.getTimeRecords(
        date: date,
        employeeId: employeeId,
      );
      return Right(records);
    } catch (e) {
      Logger.error('Failed to get local time records', error: e);
      return Left(DatabaseFailure(message: 'Failed to get local time records: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveTimeRecord(EmployeeTimeRecord record) async {
    try {
      await _localDataSource.saveTimeRecord(
        EmployeeTimeRecordModel.fromEntity(record),
      );
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to save time record', error: e);
      return Left(DatabaseFailure(message: 'Failed to save time record: $e'));
    }
  }

  @override
  Future<Either<Failure, DateTime?>> getLastSyncDate() async {
    try {
      final date = await _localDataSource.getLastSyncDate();
      return Right(date);
    } catch (e) {
      Logger.error('Failed to get last sync date', error: e);
      return Left(DatabaseFailure(message: 'Failed to get last sync date: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateLastSyncDate(DateTime date) async {
    try {
      await _localDataSource.updateLastSyncDate(date);
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to update last sync date', error: e);
      return Left(DatabaseFailure(message: 'Failed to update last sync date: $e'));
    }
  }
}