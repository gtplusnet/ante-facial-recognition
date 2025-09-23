import 'package:equatable/equatable.dart';

abstract class BaseEvent extends Equatable {
  const BaseEvent();
}

abstract class LoadEvent extends BaseEvent {
  const LoadEvent();

  @override
  List<Object?> get props => [];
}

abstract class RefreshEvent extends BaseEvent {
  const RefreshEvent();

  @override
  List<Object?> get props => [];
}

abstract class ResetEvent extends BaseEvent {
  const ResetEvent();

  @override
  List<Object?> get props => [];
}

abstract class RetryEvent extends BaseEvent {
  const RetryEvent();

  @override
  List<Object?> get props => [];
}

abstract class CreateEvent<T> extends BaseEvent {
  final T data;

  const CreateEvent(this.data);

  @override
  List<Object?> get props => [data];
}

abstract class UpdateEvent<T> extends BaseEvent {
  final T data;

  const UpdateEvent(this.data);

  @override
  List<Object?> get props => [data];
}

abstract class DeleteEvent<T> extends BaseEvent {
  final T id;

  const DeleteEvent(this.id);

  @override
  List<Object?> get props => [id];
}

abstract class SearchEvent extends BaseEvent {
  final String query;

  const SearchEvent(this.query);

  @override
  List<Object?> get props => [query];
}

abstract class FilterEvent<T> extends BaseEvent {
  final T filter;

  const FilterEvent(this.filter);

  @override
  List<Object?> get props => [filter];
}

abstract class PaginationEvent extends BaseEvent {
  final int page;
  final int pageSize;

  const PaginationEvent({
    required this.page,
    this.pageSize = 20,
  });

  @override
  List<Object?> get props => [page, pageSize];
}

abstract class SortEvent extends BaseEvent {
  final String field;
  final bool ascending;

  const SortEvent({
    required this.field,
    this.ascending = true,
  });

  @override
  List<Object?> get props => [field, ascending];
}