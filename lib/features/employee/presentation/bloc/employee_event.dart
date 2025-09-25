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

class LoadEmployeeDetail extends EmployeeEvent {
  final String employeeId;

  const LoadEmployeeDetail(this.employeeId);

  @override
  List<Object?> get props => [employeeId];
}

class AddFaceImage extends EmployeeEvent {
  final String employeeId;
  final List<int> imageBytes;
  final String source; // 'camera', 'gallery'

  const AddFaceImage({
    required this.employeeId,
    required this.imageBytes,
    required this.source,
  });

  @override
  List<Object?> get props => [employeeId, imageBytes, source];
}

class DeleteFaceImage extends EmployeeEvent {
  final String employeeId;
  final String encodingId;

  const DeleteFaceImage({
    required this.employeeId,
    required this.encodingId,
  });

  @override
  List<Object?> get props => [employeeId, encodingId];
}