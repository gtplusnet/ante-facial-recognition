import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/employee.dart';

abstract class EmployeeRepository {
  /// Get all employees from local storage
  Future<Either<Failure, List<Employee>>> getLocalEmployees();

  /// Get all employees from API
  Future<Either<Failure, List<Employee>>> getRemoteEmployees({bool withPhotos = true});

  /// Sync employees from API to local storage
  Future<Either<Failure, List<Employee>>> syncEmployees();

  /// Get single employee by ID
  Future<Either<Failure, Employee?>> getEmployee(String id);

  /// Save employees to local storage
  Future<Either<Failure, void>> saveEmployees(List<Employee> employees);

  /// Save single employee
  Future<Either<Failure, void>> saveEmployee(Employee employee);

  /// Delete employee from local storage
  Future<Either<Failure, void>> deleteEmployee(String id);

  /// Clear all employees from local storage
  Future<Either<Failure, void>> clearEmployees();

  /// Download and cache employee photo
  Future<Either<Failure, Uint8List?>> downloadEmployeePhoto(String photoUrl);

  /// Get employee face encodings
  Future<Either<Failure, List<FaceEncoding>>> getEmployeeFaceEncodings(String employeeId);

  /// Save face encoding for employee
  Future<Either<Failure, void>> saveFaceEncoding(String employeeId, FaceEncoding encoding);

  /// Clock in employee
  Future<Either<Failure, EmployeeTimeRecord>> clockIn({
    required String employeeId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  });

  /// Clock out employee
  Future<Either<Failure, EmployeeTimeRecord>> clockOut({
    required String timeRecordId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  });

  /// Get employee status (clocked in/out)
  Future<Either<Failure, EmployeeTimeRecord?>> getEmployeeStatus(String employeeId);

  /// Get daily attendance logs
  Future<Either<Failure, List<EmployeeTimeRecord>>> getDailyLogs({
    DateTime? date,
    String? employeeId,
    int page = 1,
    int limit = 50,
  });

  /// Get time records from local storage
  Future<Either<Failure, List<EmployeeTimeRecord>>> getLocalTimeRecords({
    DateTime? date,
    String? employeeId,
  });

  /// Save time record to local storage
  Future<Either<Failure, void>> saveTimeRecord(EmployeeTimeRecord record);

  /// Get last sync date
  Future<Either<Failure, DateTime?>> getLastSyncDate();

  /// Update last sync date
  Future<Either<Failure, void>> updateLastSyncDate(DateTime date);
}