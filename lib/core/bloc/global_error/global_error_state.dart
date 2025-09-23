import 'package:equatable/equatable.dart';

import '../../error/failures.dart';

class GlobalErrorState extends Equatable {
  final List<ErrorItem> errors;
  final ErrorItem? currentError;
  final bool isLoading;

  const GlobalErrorState({
    this.errors = const [],
    this.currentError,
    this.isLoading = false,
  });

  @override
  List<Object?> get props => [errors, currentError, isLoading];

  GlobalErrorState copyWith({
    List<ErrorItem>? errors,
    ErrorItem? currentError,
    bool? isLoading,
    bool clearCurrentError = false,
  }) {
    return GlobalErrorState(
      errors: errors ?? this.errors,
      currentError: clearCurrentError ? null : currentError ?? this.currentError,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get hasErrors => errors.isNotEmpty;
  int get errorCount => errors.length;
}

class ErrorItem extends Equatable {
  final String id;
  final Failure failure;
  final String? source;
  final DateTime timestamp;
  final bool isDismissed;

  ErrorItem({
    String? id,
    required this.failure,
    this.source,
    DateTime? timestamp,
    this.isDismissed = false,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [id, failure, source, timestamp, isDismissed];

  ErrorItem copyWith({
    String? id,
    Failure? failure,
    String? source,
    DateTime? timestamp,
    bool? isDismissed,
  }) {
    return ErrorItem(
      id: id ?? this.id,
      failure: failure ?? this.failure,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }

  String get message => failure.message;
  String? get code => failure.code;
}