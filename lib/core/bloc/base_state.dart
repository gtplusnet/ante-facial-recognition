import 'package:equatable/equatable.dart';

import '../error/failures.dart';

abstract class BaseState extends Equatable {
  const BaseState();
}

abstract class InitialState extends BaseState {
  const InitialState();

  @override
  List<Object?> get props => [];
}

abstract class LoadingState extends BaseState {
  final String? message;

  const LoadingState({this.message});

  @override
  List<Object?> get props => [message];
}

abstract class LoadedState<T> extends BaseState {
  final T data;
  final DateTime? timestamp;

  LoadedState({
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [data, timestamp];
}

abstract class ErrorState extends BaseState {
  final Failure failure;
  final DateTime? timestamp;

  ErrorState({
    required this.failure,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [failure, timestamp];

  String get errorMessage => failure.message;
  String? get errorCode => failure.code;
}

abstract class SuccessState extends BaseState {
  final String? message;
  final DateTime? timestamp;

  SuccessState({
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [message, timestamp];
}

abstract class ProcessingState extends BaseState {
  final double? progress;
  final String? message;

  const ProcessingState({
    this.progress,
    this.message,
  });

  @override
  List<Object?> get props => [progress, message];
}