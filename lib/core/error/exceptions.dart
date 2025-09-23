class ServerException implements Exception {
  final String message;
  final String? code;

  ServerException({
    required this.message,
    this.code,
  });
}

class CacheException implements Exception {
  final String message;

  CacheException({required this.message});
}

class NetworkException implements Exception {
  final String message;

  NetworkException({required this.message});
}

class CameraException implements Exception {
  final String message;

  CameraException({required this.message});
}

class FaceRecognitionException implements Exception {
  final String message;

  FaceRecognitionException({required this.message});
}

class AuthenticationException implements Exception {
  final String message;
  final String? code;

  AuthenticationException({
    required this.message,
    this.code,
  });
}

class ValidationException implements Exception {
  final String message;
  final Map<String, String>? errors;

  ValidationException({
    required this.message,
    this.errors,
  });
}

class NotFoundException implements Exception {
  final String message;

  NotFoundException({required this.message});
}