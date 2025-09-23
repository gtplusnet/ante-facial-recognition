import 'package:dartz/dartz.dart';

import '../error/exceptions.dart';
import '../error/failures.dart';
import '../utils/logger.dart';

abstract class BaseRepository {
  /// Executes a function and handles exceptions, returning Either<Failure, T>
  Future<Either<Failure, T>> execute<T>(
    Future<T> Function() function, {
    String? operation,
  }) async {
    try {
      final result = await function();
      if (operation != null) {
        Logger.debug('$operation succeeded');
      }
      return Right(result);
    } on ServerException catch (e) {
      Logger.error('Server exception in ${operation ?? "operation"}', error: e);
      return Left(ServerFailure(message: e.message, code: e.code));
    } on CacheException catch (e) {
      Logger.error('Cache exception in ${operation ?? "operation"}', error: e);
      return Left(CacheFailure(message: e.message));
    } on NetworkException catch (e) {
      Logger.error('Network exception in ${operation ?? "operation"}', error: e);
      return Left(NetworkFailure(message: e.message));
    } on ValidationException catch (e) {
      Logger.error('Validation exception in ${operation ?? "operation"}', error: e);
      return Left(ValidationFailure(message: e.message));
    } on AuthenticationException catch (e) {
      Logger.error('Authentication exception in ${operation ?? "operation"}', error: e);
      return Left(AuthenticationFailure(message: e.message, code: e.code));
    } on FaceRecognitionException catch (e) {
      Logger.error('Face recognition exception in ${operation ?? "operation"}', error: e);
      return Left(FaceRecognitionFailure(message: e.message));
    } on CameraException catch (e) {
      Logger.error('Camera exception in ${operation ?? "operation"}', error: e);
      return Left(CameraFailure(message: e.message));
    } catch (e) {
      Logger.error('Unexpected error in ${operation ?? "operation"}', error: e);
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  /// Executes a stream function and handles exceptions, returning Stream<Either<Failure, T>>
  Stream<Either<Failure, T>> executeStream<T>(
    Stream<T> Function() function, {
    String? operation,
  }) async* {
    try {
      await for (final result in function()) {
        yield Right(result);
      }
    } on ServerException catch (e) {
      Logger.error('Server exception in stream ${operation ?? "operation"}', error: e);
      yield Left(ServerFailure(message: e.message, code: e.code));
    } on CacheException catch (e) {
      Logger.error('Cache exception in stream ${operation ?? "operation"}', error: e);
      yield Left(CacheFailure(message: e.message));
    } on NetworkException catch (e) {
      Logger.error('Network exception in stream ${operation ?? "operation"}', error: e);
      yield Left(NetworkFailure(message: e.message));
    } catch (e) {
      Logger.error('Unexpected error in stream ${operation ?? "operation"}', error: e);
      yield Left(UnexpectedFailure(message: e.toString()));
    }
  }
}