import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/device_auth.dart';

abstract class AuthRepository {
  /// Authenticate device using API key
  Future<Either<Failure, DeviceAuth>> authenticateDevice(String apiKey);

  /// Get stored device authentication
  Future<Either<Failure, DeviceAuth?>> getStoredAuth();

  /// Clear stored authentication
  Future<Either<Failure, void>> clearAuth();

  /// Check if device is authenticated
  Future<Either<Failure, bool>> isAuthenticated();

  /// Validate device health/connectivity
  Future<Either<Failure, bool>> validateDeviceHealth();

  /// Save device authentication locally
  Future<Either<Failure, void>> saveAuth(DeviceAuth auth);
}