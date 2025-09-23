import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../error/failures.dart';
import '../../utils/logger.dart';
import 'global_error_event.dart';
import 'global_error_state.dart';

@singleton
class GlobalErrorBloc extends Bloc<GlobalErrorEvent, GlobalErrorState> {
  static const int maxErrors = 10;

  GlobalErrorBloc() : super(const GlobalErrorState()) {
    on<AddErrorEvent>(_onAddError);
    on<ClearErrorEvent>(_onClearError);
    on<ClearAllErrorsEvent>(_onClearAllErrors);
    on<DismissErrorEvent>(_onDismissError);
  }

  void _onAddError(AddErrorEvent event, Emitter<GlobalErrorState> emit) {
    Logger.error(
      'Global Error: ${event.failure.message}',
      error: event.failure,
    );

    final errorItem = ErrorItem(
      failure: event.failure,
      source: event.source,
    );

    final updatedErrors = [errorItem, ...state.errors];

    // Keep only the latest errors
    final limitedErrors = updatedErrors.take(maxErrors).toList();

    emit(state.copyWith(
      errors: limitedErrors,
      currentError: event.showSnackbar ? errorItem : null,
    ));

    // Auto-clear current error after delay
    if (event.showSnackbar) {
      Future.delayed(const Duration(seconds: 5), () {
        if (state.currentError?.id == errorItem.id) {
          add(const ClearErrorEvent());
        }
      });
    }
  }

  void _onClearError(ClearErrorEvent event, Emitter<GlobalErrorState> emit) {
    emit(state.copyWith(clearCurrentError: true));
  }

  void _onClearAllErrors(
    ClearAllErrorsEvent event,
    Emitter<GlobalErrorState> emit,
  ) {
    emit(const GlobalErrorState());
  }

  void _onDismissError(DismissErrorEvent event, Emitter<GlobalErrorState> emit) {
    final updatedErrors = state.errors.map((error) {
      if (error.id == event.errorId) {
        return error.copyWith(isDismissed: true);
      }
      return error;
    }).toList();

    emit(state.copyWith(
      errors: updatedErrors,
      clearCurrentError: state.currentError?.id == event.errorId,
    ));
  }

  // Convenience methods for common error types
  void addNetworkError({String? source}) {
    add(AddErrorEvent(
      failure: const NetworkFailure(
        message: 'Network connection error. Please check your internet.',
      ),
      source: source,
    ));
  }

  void addServerError({String? message, String? source}) {
    add(AddErrorEvent(
      failure: ServerFailure(
        message: message ?? 'Server error. Please try again later.',
      ),
      source: source,
    ));
  }

  void addCameraError({String? message, String? source}) {
    add(AddErrorEvent(
      failure: CameraFailure(
        message: message ?? 'Camera error. Please check permissions.',
      ),
      source: source,
    ));
  }

  void addFaceRecognitionError({String? message, String? source}) {
    add(AddErrorEvent(
      failure: FaceRecognitionFailure(
        message: message ?? 'Face recognition failed. Please try again.',
      ),
      source: source,
    ));
  }

  void addValidationError({String? message, String? source}) {
    add(AddErrorEvent(
      failure: ValidationFailure(
        message: message ?? 'Invalid input. Please check your data.',
      ),
      source: source,
    ));
  }
}