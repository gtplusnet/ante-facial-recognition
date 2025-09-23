import 'package:equatable/equatable.dart';

import '../../domain/entities/device_auth.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final DeviceAuth deviceAuth;

  const AuthAuthenticated(this.deviceAuth);

  @override
  List<Object?> get props => [deviceAuth];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthHealthCheckSuccess extends AuthState {
  const AuthHealthCheckSuccess();
}

class AuthHealthCheckFailed extends AuthState {
  final String message;

  const AuthHealthCheckFailed(this.message);

  @override
  List<Object?> get props => [message];
}