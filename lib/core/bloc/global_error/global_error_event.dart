import 'package:equatable/equatable.dart';

import '../../error/failures.dart';

abstract class GlobalErrorEvent extends Equatable {
  const GlobalErrorEvent();
}

class AddErrorEvent extends GlobalErrorEvent {
  final Failure failure;
  final String? source;
  final bool showSnackbar;

  const AddErrorEvent({
    required this.failure,
    this.source,
    this.showSnackbar = true,
  });

  @override
  List<Object?> get props => [failure, source, showSnackbar];
}

class ClearErrorEvent extends GlobalErrorEvent {
  const ClearErrorEvent();

  @override
  List<Object?> get props => [];
}

class ClearAllErrorsEvent extends GlobalErrorEvent {
  const ClearAllErrorsEvent();

  @override
  List<Object?> get props => [];
}

class DismissErrorEvent extends GlobalErrorEvent {
  final String errorId;

  const DismissErrorEvent(this.errorId);

  @override
  List<Object?> get props => [errorId];
}