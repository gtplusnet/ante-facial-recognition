import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/storage/secure_storage_helper.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/data/datasources/manpower_api_service.dart';
import '../../domain/entities/device_auth.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/device_auth_model.dart';

@Singleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final ManpowerApiService _apiService;
  final SecureStorageHelper _secureStorage;

  AuthRepositoryImpl({
    required ManpowerApiService apiService,
    required SecureStorageHelper secureStorage,
  })  : _apiService = apiService,
        _secureStorage = secureStorage;

  @override
  Future<Either<Failure, DeviceAuth>> authenticateDevice(String apiKey) async {
    try {
      Logger.info('Authenticating with API key');

      // Save API key for validation
      await _secureStorage.saveApiKey(apiKey);

      // Validate the API key with health check
      final healthResponse = await _apiService.checkHealth();

      if (healthResponse != null && healthResponse['status'] == 'ok') {
        // Extract device info from health check response
        final deviceInfo = healthResponse['device'] as Map<String, dynamic>?;

        final deviceAuth = DeviceAuthModel(
          deviceId: deviceInfo?['id'] ?? 'unknown',
          deviceName: deviceInfo?['name'] ?? 'ANTE Time Tracking Device',
          location: deviceInfo?['location'] ?? 'Main Office',
          apiKey: apiKey,
          lastActivity: deviceInfo?['lastActivity'] != null
              ? DateTime.parse(deviceInfo!['lastActivity'])
              : DateTime.now(),
          isActive: true,
        );

        // Save device ID from response
        if (deviceInfo?['id'] != null) {
          await _secureStorage.saveDeviceId(deviceInfo!['id']);
        }

        Logger.success('Device authenticated successfully');
        return Right(deviceAuth);
      } else {
        // Clear invalid API key
        await _secureStorage.deleteApiKey();
        Logger.error('Authentication failed - invalid API key');
        return const Left(AuthenticationFailure(message: 'Invalid API key or inactive device'));
      }
    } on AuthenticationException catch (e) {
      Logger.error('Authentication exception', error: e);
      return Left(AuthenticationFailure(message: e.message));
    } on NetworkException catch (e) {
      Logger.error('Network exception during authentication', error: e);
      return Left(NetworkFailure(message: e.message));
    } catch (e) {
      Logger.error('Unexpected error during authentication', error: e);
      return Left(ServerFailure(message: 'Authentication failed: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, DeviceAuth?>> getStoredAuth() async {
    try {
      Logger.debug('Retrieving stored authentication');

      final deviceId = await _secureStorage.getDeviceId();
      final apiKey = await _secureStorage.getApiKey();

      if (deviceId != null && apiKey != null) {
        final deviceAuth = DeviceAuthModel(
          deviceId: deviceId,
          deviceName: 'ANTE Time Tracking Device',
          apiKey: apiKey,
          isActive: true,
        );

        Logger.debug('Stored authentication found');
        return Right(deviceAuth);
      }

      Logger.debug('No stored authentication found');
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to retrieve stored auth', error: e);
      return Left(CacheFailure(message: 'Failed to retrieve stored authentication'));
    }
  }

  @override
  Future<Either<Failure, void>> clearAuth() async {
    try {
      Logger.info('Clearing authentication data');

      await _secureStorage.deleteApiKey();
      await _secureStorage.deleteValue('device_id');

      Logger.success('Authentication cleared');
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to clear auth', error: e);
      return Left(CacheFailure(message: 'Failed to clear authentication'));
    }
  }

  @override
  Future<Either<Failure, bool>> isAuthenticated() async {
    try {
      final authResult = await getStoredAuth();

      return authResult.fold(
        (failure) => Left(failure),
        (auth) => Right(auth != null),
      );
    } catch (e) {
      Logger.error('Failed to check authentication status', error: e);
      return const Right(false);
    }
  }

  @override
  Future<Either<Failure, bool>> validateDeviceHealth() async {
    try {
      Logger.info('Validating device health');

      final healthResponse = await _apiService.checkHealth();

      if (healthResponse != null && healthResponse['status'] == 'ok') {
        Logger.success('Device health check passed');
        return const Right(true);
      } else {
        Logger.warning('Device health check failed');
        return const Right(false);
      }
    } on NetworkException catch (e) {
      Logger.error('Network error during health check', error: e);
      return Left(NetworkFailure(message: e.message));
    } catch (e) {
      Logger.error('Failed to validate device health', error: e);
      return Left(ServerFailure(message: 'Health check failed: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> saveAuth(DeviceAuth auth) async {
    try {
      Logger.info('Saving authentication data');

      if (auth.deviceId.isNotEmpty) {
        await _secureStorage.saveDeviceId(auth.deviceId);
      }

      if (auth.apiKey != null && auth.apiKey!.isNotEmpty) {
        await _secureStorage.saveApiKey(auth.apiKey!);
      }

      Logger.success('Authentication saved');
      return const Right(null);
    } catch (e) {
      Logger.error('Failed to save auth', error: e);
      return Left(CacheFailure(message: 'Failed to save authentication'));
    }
  }
}