import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage_helper.dart';
import '../../../../core/utils/logger.dart';
import '../models/employee_model.dart';

@singleton
class ManpowerApiService {
  final ApiClient _apiClient;
  final SecureStorageHelper _secureStorage;

  static const String baseUrl = 'http://100.109.133.12:3000/api/public/manpower';

  ManpowerApiService({
    required ApiClient apiClient,
    required SecureStorageHelper secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  Future<Map<String, String>> _getHeaders() async {
    final apiKey = await _secureStorage.getApiKey();
    return {
      'x-api-key': apiKey ?? '',
      'Content-Type': 'application/json',
    };
  }

  /// Check API health status and get device info
  Future<Map<String, dynamic>?> checkHealth() async {
    try {
      Logger.info('Checking API health');

      final response = await _apiClient.get(
        '$baseUrl/health',
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        Logger.success('API health check successful');
        return response.data as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      Logger.error('API health check failed', error: e);
      return null;
    }
  }

  /// Get list of employees with optional photos
  Future<List<EmployeeModel>> getEmployees({bool withPhotos = true}) async {
    try {
      Logger.info('[ManpowerApiService] Fetching employees list with photos=$withPhotos');

      final headers = await _getHeaders();
      Logger.debug('[ManpowerApiService] Request headers prepared');

      final url = '$baseUrl/employees';
      Logger.debug('[ManpowerApiService] Making GET request to: $url');

      final response = await _apiClient.get(
        url,
        queryParameters: {'withPhotos': withPhotos},
        options: Options(headers: headers),
      );

      Logger.debug('[ManpowerApiService] Response received with status: ${response.statusCode}');
      Logger.debug('[ManpowerApiService] Response data type: ${response.data.runtimeType}');

      if (response.statusCode == 200) {
        // Fixed API response parsing - check 'employees' field first
        final List<dynamic> data = response.data['employees'] ?? response.data['data'] ?? response.data ?? [];
        Logger.debug('[ManpowerApiService] Extracted ${data.length} employees from response');

        final employees = data.map((json) => EmployeeModel.fromJson(json)).toList();

        Logger.success('[ManpowerApiService] Successfully parsed ${employees.length} employees');
        return employees;
      } else {
        throw ServerException(
          message: 'Failed to fetch employees',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      Logger.error('[ManpowerApiService] Failed to fetch employees', error: e);
      if (e is DioException) {
        Logger.error('[ManpowerApiService] DioException details: ${e.message}, Response: ${e.response?.data}');
        throw _handleDioError(e);
      }
      throw ServerException(message: 'Failed to fetch employees: $e');
    }
  }

  /// Download employee photo
  Future<Uint8List?> downloadEmployeePhoto(String photoUrl) async {
    try {
      Logger.info('Downloading employee photo: $photoUrl');

      final response = await _apiClient.get(
        photoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: await _getHeaders(),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        Logger.success('Photo downloaded successfully');
        return Uint8List.fromList(response.data);
      }

      return null;
    } catch (e) {
      Logger.error('Failed to download photo', error: e);
      return null;
    }
  }

  /// Clock in an employee
  Future<EmployeeTimeRecordModel> clockIn({
    required String employeeId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  }) async {
    try {
      Logger.info('Clocking in employee: $employeeId');

      final body = {
        'employeeId': employeeId,
        if (photoBase64 != null) 'photo': photoBase64,
        if (location != null) 'location': location,
        if (confidence != null) 'confidence': confidence,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await _apiClient.post(
        '$baseUrl/time-in',
        data: body,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data['data'] ?? response.data;
        Logger.success('Clock in successful for employee: $employeeId');
        return EmployeeTimeRecordModel.fromJson(data);
      } else {
        throw ServerException(
          message: 'Failed to clock in',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      Logger.error('Failed to clock in', error: e);
      if (e is DioException) {
        throw _handleDioError(e);
      }
      throw ServerException(message: 'Failed to clock in: $e');
    }
  }

  /// Clock out an employee
  Future<EmployeeTimeRecordModel> clockOut({
    required String timeRecordId,
    String? photoBase64,
    Map<String, dynamic>? location,
    double? confidence,
  }) async {
    try {
      Logger.info('Clocking out time record: $timeRecordId');

      final body = {
        'timeRecordId': timeRecordId,
        if (photoBase64 != null) 'photo': photoBase64,
        if (location != null) 'location': location,
        if (confidence != null) 'confidence': confidence,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await _apiClient.post(
        '$baseUrl/time-out',
        data: body,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data['data'] ?? response.data;
        Logger.success('Clock out successful for record: $timeRecordId');
        return EmployeeTimeRecordModel.fromJson(data);
      } else {
        throw ServerException(
          message: 'Failed to clock out',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      Logger.error('Failed to clock out', error: e);
      if (e is DioException) {
        throw _handleDioError(e);
      }
      throw ServerException(message: 'Failed to clock out: $e');
    }
  }

  /// Check employee status (clocked in or out)
  Future<EmployeeTimeRecordModel?> getEmployeeStatus(String employeeId) async {
    try {
      Logger.info('Checking status for employee: $employeeId');

      final response = await _apiClient.get(
        '$baseUrl/employee-status',
        queryParameters: {'employeeId': employeeId},
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] ?? response.data;
        if (data != null && data is Map<String, dynamic>) {
          Logger.success('Employee status retrieved');
          return EmployeeTimeRecordModel.fromJson(data);
        }
        return null;
      } else {
        throw ServerException(
          message: 'Failed to get employee status',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      Logger.error('Failed to get employee status', error: e);
      if (e is DioException) {
        throw _handleDioError(e);
      }
      throw ServerException(message: 'Failed to get employee status: $e');
    }
  }

  /// Get daily attendance logs
  Future<List<EmployeeTimeRecordModel>> getDailyLogs({
    DateTime? date,
    String? employeeId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      Logger.info('Fetching daily logs');

      final queryParams = {
        if (date != null) 'date': date.toIso8601String().split('T')[0],
        if (employeeId != null) 'employeeId': employeeId,
        'page': page,
        'limit': limit,
      };

      final response = await _apiClient.get(
        '$baseUrl/daily-logs',
        queryParameters: queryParams,
        options: Options(headers: await _getHeaders()),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data ?? [];
        final logs = data.map((json) => EmployeeTimeRecordModel.fromJson(json)).toList();

        Logger.success('Fetched ${logs.length} daily logs');
        return logs;
      } else {
        throw ServerException(
          message: 'Failed to fetch daily logs',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      Logger.error('Failed to fetch daily logs', error: e);
      if (e is DioException) {
        throw _handleDioError(e);
      }
      throw ServerException(message: 'Failed to fetch daily logs: $e');
    }
  }

  /// Save device API key
  Future<void> saveApiKey(String apiKey) async {
    await _secureStorage.saveApiKey(apiKey);
    Logger.info('API key saved securely');
  }

  /// Clear device API key
  Future<void> clearApiKey() async {
    await _secureStorage.deleteApiKey();
    Logger.info('API key cleared');
  }

  /// Handle Dio errors
  Exception _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(message: 'Connection timeout');

      case DioExceptionType.connectionError:
        return NetworkException(message: 'No internet connection');

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message = error.response?.data?['message'] ?? 'Server error';

        if (statusCode == 401) {
          return AuthenticationException(message: 'Unauthorized: Invalid API key');
        } else if (statusCode == 404) {
          return NotFoundException(message: message);
        } else if (statusCode == 422) {
          return ValidationException(message: message);
        } else if (statusCode != null && statusCode >= 500) {
          return ServerException(
            message: message,
            code: statusCode.toString(),
          );
        }
        return ServerException(message: message);

      case DioExceptionType.cancel:
        return NetworkException(message: 'Request cancelled');

      default:
        return NetworkException(message: 'Network error: ${error.message}');
    }
  }
}