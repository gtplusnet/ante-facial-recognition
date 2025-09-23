import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthenticateDevice extends AuthEvent {
  final String apiKey;

  const AuthenticateDevice(this.apiKey);

  @override
  List<Object?> get props => [apiKey];
}

class CheckAuthStatus extends AuthEvent {
  const CheckAuthStatus();
}

class ValidateDeviceHealth extends AuthEvent {
  const ValidateDeviceHealth();
}

class SignOut extends AuthEvent {
  const SignOut();
}

class Logout extends AuthEvent {
  const Logout();
}