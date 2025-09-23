import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/authenticate_device_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';

@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthenticateDeviceUseCase _authenticateDevice;
  final AuthRepository _authRepository;

  AuthBloc({
    required AuthenticateDeviceUseCase authenticateDevice,
    required AuthRepository authRepository,
  })  : _authenticateDevice = authenticateDevice,
        _authRepository = authRepository,
        super(const AuthInitial()) {
    on<AuthenticateDevice>(_onAuthenticateDevice);
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<ValidateDeviceHealth>(_onValidateDeviceHealth);
    on<SignOut>(_onSignOut);
    on<Logout>(_onSignOut);

    // Check auth status on initialization
    add(const CheckAuthStatus());
  }

  Future<void> _onAuthenticateDevice(
    AuthenticateDevice event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      Logger.info('Authenticating with API key');

      final result = await _authenticateDevice(event.apiKey);

      result.fold(
        (failure) {
          Logger.error('Authentication failed: ${failure.message}');
          emit(AuthError(failure.message));
        },
        (deviceAuth) {
          Logger.success('Device authenticated successfully');
          emit(AuthAuthenticated(deviceAuth));
        },
      );
    } catch (e) {
      Logger.error('Unexpected error during authentication', error: e);
      emit(AuthError('Authentication failed: ${e.toString()}'));
    }
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    try {
      Logger.debug('Checking authentication status');

      final result = await _authRepository.getStoredAuth();

      result.fold(
        (failure) {
          Logger.warning('Failed to check auth status: ${failure.message}');
          emit(const AuthUnauthenticated());
        },
        (auth) {
          if (auth != null) {
            Logger.info('User is authenticated');
            emit(AuthAuthenticated(auth));
          } else {
            Logger.info('User is not authenticated');
            emit(const AuthUnauthenticated());
          }
        },
      );
    } catch (e) {
      Logger.error('Error checking auth status', error: e);
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onValidateDeviceHealth(
    ValidateDeviceHealth event,
    Emitter<AuthState> emit,
  ) async {
    try {
      Logger.info('Validating device health');

      final result = await _authRepository.validateDeviceHealth();

      result.fold(
        (failure) {
          Logger.error('Health check failed: ${failure.message}');
          emit(AuthHealthCheckFailed(failure.message));
        },
        (isHealthy) {
          if (isHealthy) {
            Logger.success('Device health check passed');
            emit(const AuthHealthCheckSuccess());
          } else {
            Logger.warning('Device health check failed');
            emit(const AuthHealthCheckFailed('Device is not healthy or inactive'));
          }
        },
      );
    } catch (e) {
      Logger.error('Error during health check', error: e);
      emit(AuthHealthCheckFailed('Health check failed: ${e.toString()}'));
    }
  }

  Future<void> _onSignOut(
    AuthEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      Logger.info('Signing out');

      final result = await _authRepository.clearAuth();

      result.fold(
        (failure) {
          Logger.error('Failed to sign out: ${failure.message}');
          emit(AuthError('Failed to sign out: ${failure.message}'));
        },
        (_) {
          Logger.success('Signed out successfully');
          emit(const AuthUnauthenticated());
        },
      );
    } catch (e) {
      Logger.error('Error during sign out', error: e);
      emit(AuthError('Sign out failed: ${e.toString()}'));
    }
  }
}