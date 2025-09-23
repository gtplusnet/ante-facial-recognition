import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/device_auth.dart';
import '../repositories/auth_repository.dart';

@injectable
class AuthenticateDeviceUseCase implements UseCase<DeviceAuth, String> {
  final AuthRepository repository;

  const AuthenticateDeviceUseCase(this.repository);

  @override
  Future<Either<Failure, DeviceAuth>> call(String apiKey) async {
    if (apiKey.isEmpty) {
      return const Left(ValidationFailure(message: 'API key cannot be empty'));
    }

    // Authenticate with API using the API key
    final authResult = await repository.authenticateDevice(apiKey);

    // If successful, save to local storage
    return authResult.fold(
      (failure) => Left(failure),
      (deviceAuth) async {
        await repository.saveAuth(deviceAuth);
        return Right(deviceAuth);
      },
    );
  }
}