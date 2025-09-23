import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/app_constants.dart';
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
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    // Will be implemented when we have API key storage
    // final apiKey = getIt<SecureStorageHelper>().getApiKey();
    // if (apiKey != null) {
    //   options.headers[AppConstants.apiKeyHeader] = apiKey;
    // }
    handler.next(options);
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