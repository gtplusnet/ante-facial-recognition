import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:get_it/get_it.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/app_constants.dart';
import '../storage/secure_storage_helper.dart';
import '../utils/logger.dart';

class DioFactory {
  DioFactory._();

  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${AppConstants.baseUrl}${AppConstants.apiPath}',
        connectTimeout: AppConstants.apiTimeout,
        receiveTimeout: AppConstants.apiTimeout,
        sendTimeout: AppConstants.apiTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors
    dio.interceptors.addAll([
      _AuthInterceptor(),
      _ErrorInterceptor(),
      RetryInterceptor(
        dio: dio,
        logPrint: (message) => Logger.network(message),
        retries: AppConstants.maxRetryAttempts,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
      ),
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        logPrint: (object) => Logger.network(object.toString()),
      ),
    ]);

    return dio;
  }
}

class _AuthInterceptor extends Interceptor {
  static String? _cachedApiKey;
  static DateTime? _cacheTime;
  static const _cacheExpiry = Duration(minutes: 10);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      // Check if we have a valid cached API key
      final now = DateTime.now();
      if (_cachedApiKey != null &&
          _cacheTime != null &&
          now.difference(_cacheTime!) < _cacheExpiry) {
        // Use cached API key
        options.headers[AppConstants.apiKeyHeader] = _cachedApiKey!;
        Logger.debug('[AUTH] Using cached API key for request: ${options.uri}');
        handler.next(options);
        return;
      }

      // Cache is empty or expired, fetch from secure storage
      final secureStorage = GetIt.instance<SecureStorageHelper>();
      final apiKey = await secureStorage.getApiKey();

      if (apiKey != null && apiKey.isNotEmpty) {
        // Cache the API key
        _cachedApiKey = apiKey;
        _cacheTime = now;

        options.headers[AppConstants.apiKeyHeader] = apiKey;
        Logger.debug('[AUTH] API Key fetched and cached for request: ${options.uri}');
      } else {
        Logger.warning('[AUTH] No API key found for request: ${options.uri}');
        // Clear any existing cache if API key is not available
        _cachedApiKey = null;
        _cacheTime = null;

        // Fail fast for unauthenticated requests
        handler.reject(
          DioException(
            requestOptions: options,
            error: 'Authentication required: No API key available',
            type: DioExceptionType.cancel,
          ),
        );
        return;
      }
    } catch (e) {
      Logger.error('[AUTH] Failed to get API key: $e');
      // Clear cache on error
      _cachedApiKey = null;
      _cacheTime = null;

      // Fail fast on authentication errors
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'Authentication failed: ${e.toString()}',
          type: DioExceptionType.cancel,
        ),
      );
      return;
    }

    handler.next(options);
  }

  /// Clear the cached API key (useful for logout or key refresh)
  static void clearCache() {
    _cachedApiKey = null;
    _cacheTime = null;
    Logger.info('[AUTH] API key cache cleared');
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    Logger.error(
      'API Error: ${err.message}',
      error: err.error,
      stackTrace: err.stackTrace,
    );

    DioException transformedError;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: 'Connection timeout. Please check your internet connection.',
          type: err.type,
          response: err.response,
        );
        break;
      case DioExceptionType.connectionError:
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: 'No internet connection. Please check your network.',
          type: err.type,
          response: err.response,
        );
        break;
      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode ?? 0;
        String errorMessage;
        switch (statusCode) {
          case 400:
            errorMessage = 'Bad request. Please check your input.';
            break;
          case 401:
            errorMessage = 'Unauthorized. Please authenticate.';
            break;
          case 403:
            errorMessage = 'Forbidden. You don\'t have permission.';
            break;
          case 404:
            errorMessage = 'Resource not found.';
            break;
          case 500:
          case 502:
          case 503:
          case 504:
            errorMessage = 'Server error. Please try again later.';
            break;
          default:
            errorMessage = 'An error occurred. Please try again.';
        }
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: errorMessage,
          type: err.type,
          response: err.response,
        );
        break;
      case DioExceptionType.cancel:
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: 'Request cancelled.',
          type: err.type,
          response: err.response,
        );
        break;
      case DioExceptionType.badCertificate:
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: 'Security certificate error.',
          type: err.type,
          response: err.response,
        );
        break;
      case DioExceptionType.unknown:
        transformedError = DioException(
          requestOptions: err.requestOptions,
          error: 'An unexpected error occurred.',
          type: err.type,
          response: err.response,
        );
        break;
    }

    handler.next(transformedError);
  }
}