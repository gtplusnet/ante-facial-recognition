/// Base exception class for consistent formatting across the app
abstract class AppException implements Exception {
  final String message;
  final String? code;

  const AppException({
    required this.message,
    this.code,
  });

  /// Get the exception name (class name without 'Exception' suffix)
  String get exceptionName {
    final className = runtimeType.toString();
    return className.endsWith('Exception')
        ? className.substring(0, className.length - 'Exception'.length)
        : className;
  }

  @override
  String toString() {
    if (code != null) {
      return '[$exceptionName]: $message (code: $code)';
    }
    return '[$exceptionName]: $message';
  }
}

class ServerException extends AppException {
  const ServerException({
    required super.message,
    super.code,
  });
}

class CacheException extends AppException {
  const CacheException({
    required super.message,
    super.code,
  });
}

class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code,
  });
}

class CameraException extends AppException {
  const CameraException({
    required super.message,
    super.code,
  });
}

class FaceRecognitionException extends AppException {
  const FaceRecognitionException({
    required super.message,
    super.code,
  });
}

class AuthenticationException extends AppException {
  const AuthenticationException({
    required super.message,
    super.code,
  });
}

class ValidationException extends AppException {
  final Map<String, String>? errors;

  const ValidationException({
    required super.message,
    super.code,
    this.errors,
  });

  @override
  String toString() {
    if (errors != null && errors!.isNotEmpty) {
      final errorMessages = errors!.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      return '[$exceptionName]: $message - $errorMessages';
    }
    return super.toString();
  }
}

class NotFoundException extends AppException {
  const NotFoundException({
    required super.message,
    super.code,
  });
}