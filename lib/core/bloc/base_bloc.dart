import 'package:flutter_bloc/flutter_bloc.dart';

import '../error/failures.dart';
import '../utils/logger.dart';
import 'base_event.dart';
import 'base_state.dart';

abstract class BaseBloc<E extends BaseEvent, S extends BaseState>
    extends Bloc<E, S> {
  BaseBloc(super.initialState) {
    on<E>(_mapEventToState);
  }

  void _mapEventToState(E event, Emitter<S> emit) {
    Logger.debug('${runtimeType}: Processing event ${event.runtimeType}');
    handleEvent(event, emit);
  }

  /// Override this method to handle events
  void handleEvent(E event, Emitter<S> emit);

  /// Helper method to emit error state
  void emitError(
    Emitter<S> emit,
    Failure failure, {
    String? operation,
  }) {
    if (operation != null) {
      Logger.error('$runtimeType: $operation failed', error: failure);
    }
    emit(createErrorState(failure));
  }

  /// Helper method to emit loading state
  void emitLoading(
    Emitter<S> emit, {
    String? message,
  }) {
    if (message != null) {
      Logger.debug('$runtimeType: $message');
    }
    emit(createLoadingState(message: message));
  }

  /// Helper method to emit success state
  void emitSuccess<T>(
    Emitter<S> emit,
    T data, {
    String? message,
  }) {
    if (message != null) {
      Logger.success('$runtimeType: $message');
    }
    emit(createSuccessState(data, message: message));
  }

  /// Helper method to handle either results
  void handleEither<T>(
    Emitter<S> emit,
    dynamic either, {
    required Function(T data) onSuccess,
    Function(Failure failure)? onFailure,
    String? operation,
  }) {
    either.fold(
      (failure) {
        if (onFailure != null) {
          onFailure(failure);
        } else {
          emitError(emit, failure, operation: operation);
        }
      },
      (data) => onSuccess(data as T),
    );
  }

  /// Abstract methods to be implemented by concrete BLoCs
  S createErrorState(Failure failure);
  S createLoadingState({String? message});
  S createSuccessState<T>(T data, {String? message});

  /// Helper method for performance tracking
  Future<T> trackPerformance<T>(
    String operation,
    Future<T> Function() function,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await function();
      stopwatch.stop();
      Logger.performance(
        '$runtimeType: $operation completed',
        duration: stopwatch.elapsed,
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      Logger.performance(
        '$runtimeType: $operation failed',
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  /// Helper method for debouncing events
  Future<void> debounce(
    Duration duration,
    Function() callback,
  ) async {
    await Future.delayed(duration);
    callback();
  }
}