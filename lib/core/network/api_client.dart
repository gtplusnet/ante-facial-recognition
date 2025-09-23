import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../utils/logger.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  // Health Check
  Future<Response> checkHealth() async {
    try {
      final response = await _dio.get(ApiEndpoints.health);
      Logger.success('Health check successful');
      return response;
    } catch (e) {
      Logger.error('Health check failed', error: e);
      rethrow;
    }
  }

  // Get Employees
  Future<Response> getEmployees({bool withPhotos = true}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.employees,
        queryParameters: {
          ApiEndpoints.withPhotosParam: withPhotos,
        },
      );
      Logger.success('Fetched ${response.data['data']?.length ?? 0} employees');
      return response;
    } catch (e) {
      Logger.error('Failed to fetch employees', error: e);
      rethrow;
    }
  }

  // Clock In
  Future<Response> clockIn(String employeeId) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.timeIn,
        data: {
          'employeeId': employeeId,
        },
      );
      Logger.success('Clock in successful for employee: $employeeId');
      return response;
    } catch (e) {
      Logger.error('Clock in failed for employee: $employeeId', error: e);
      rethrow;
    }
  }

  // Clock Out
  Future<Response> clockOut(String timeRecordId) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.timeOut,
        data: {
          'timeRecordId': timeRecordId,
        },
      );
      Logger.success('Clock out successful for record: $timeRecordId');
      return response;
    } catch (e) {
      Logger.error('Clock out failed for record: $timeRecordId', error: e);
      rethrow;
    }
  }

  // Get Employee Status
  Future<Response> getEmployeeStatus(String employeeId) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.employeeStatus,
        queryParameters: {
          ApiEndpoints.employeeIdParam: employeeId,
        },
      );
      Logger.success('Fetched status for employee: $employeeId');
      return response;
    } catch (e) {
      Logger.error('Failed to fetch status for employee: $employeeId', error: e);
      rethrow;
    }
  }

  // Get Daily Logs
  Future<Response> getDailyLogs({
    String? date,
    String? employeeId,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (date != null) queryParams[ApiEndpoints.dateParam] = date;
      if (employeeId != null) queryParams[ApiEndpoints.employeeIdParam] = employeeId;

      final response = await _dio.get(
        ApiEndpoints.dailyLogs,
        queryParameters: queryParams,
      );
      Logger.success('Fetched daily logs');
      return response;
    } catch (e) {
      Logger.error('Failed to fetch daily logs', error: e);
      rethrow;
    }
  }

  // Generic GET request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      Logger.error('GET request failed: $path', error: e);
      rethrow;
    }
  }

  // Generic POST request
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      Logger.error('POST request failed: $path', error: e);
      rethrow;
    }
  }

  // Generic PUT request
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      Logger.error('PUT request failed: $path', error: e);
      rethrow;
    }
  }

  // Generic DELETE request
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      Logger.error('DELETE request failed: $path', error: e);
      rethrow;
    }
  }
}