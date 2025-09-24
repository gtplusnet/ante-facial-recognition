import 'package:equatable/equatable.dart';

abstract class EmployeeEvent extends Equatable {
  const EmployeeEvent();

  @override
  List<Object?> get props => [];
}

class LoadEmployees extends EmployeeEvent {
  const LoadEmployees();
}

class SyncEmployees extends EmployeeEvent {
  const SyncEmployees();
}

class RefreshEmployees extends EmployeeEvent {
  const RefreshEmployees();
}

class SearchEmployees extends EmployeeEvent {
  final String query;

  const SearchEmployees(this.query);

  @override
  List<Object?> get props => [query];
}

class GenerateFaceEmbeddings extends EmployeeEvent {
  final String employeeId;

  const GenerateFaceEmbeddings(this.employeeId);

  @override
  List<Object?> get props => [employeeId];
}

class GenerateAllFaceEmbeddings extends EmployeeEvent {
  const GenerateAllFaceEmbeddings();
}

class ClearEmployeeCache extends EmployeeEvent {
  const ClearEmployeeCache();
}