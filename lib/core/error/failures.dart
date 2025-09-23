import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({
    required this.message,
    this.code,
  });

  @override
  List<Object?> get props => [message, code];
}

class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.code,
  });
}

class CacheFailure extends Failure {
  const CacheFailure({
    required super.message,
    super.code,
  });
}

class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.code,
  });
}

class CameraFailure extends Failure {
  const CameraFailure({
    required super.message,
    super.code,
  });
}

class FaceRecognitionFailure extends Failure {
  const FaceRecognitionFailure({
    required super.message,
    super.code,
  });
}

class AuthenticationFailure extends Failure {
  const AuthenticationFailure({
    required super.message,
    super.code,
  });
}

class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.code,
  });
}

class DatabaseFailure extends Failure {
  const DatabaseFailure({
    required super.message,
    super.code,
  });
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    required super.message,
    super.code,
  });
}

class NotFoundException extends Failure {
  const NotFoundException({
    required super.message,
    super.code,
  });
}

class DataFailure extends Failure {
  const DataFailure({
    required super.message,
    super.code,
  });
}