import 'package:equatable/equatable.dart';

import '../../domain/entities/employee.dart';
import '../../domain/usecases/sync_employees_usecase.dart';

abstract class EmployeeState extends Equatable {
  const EmployeeState();

  @override
  List<Object?> get props => [];
}

class EmployeeInitial extends EmployeeState {
  const EmployeeInitial();
}

class EmployeeLoading extends EmployeeState {
  const EmployeeLoading();
}

class EmployeeLoaded extends EmployeeState {
  final List<Employee> employees;
  final DateTime? lastSyncTime;
  final String? searchQuery;

  const EmployeeLoaded({
    required this.employees,
    this.lastSyncTime,
    this.searchQuery,
  });

  List<Employee> get filteredEmployees {
    if (searchQuery == null || searchQuery!.isEmpty) {
      return employees;
    }

    final query = searchQuery!.toLowerCase();
    return employees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          (employee.employeeCode?.toLowerCase().contains(query) ?? false) ||
          (employee.department?.toLowerCase().contains(query) ?? false) ||
          (employee.position?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  int get totalCount => employees.length;
  int get withPhotoCount => employees.where((e) => e.hasPhoto).length;
  int get withEmbeddingsCount => employees.where((e) => e.hasFaceEncodings).length;

  @override
  List<Object?> get props => [employees, lastSyncTime, searchQuery];

  EmployeeLoaded copyWith({
    List<Employee>? employees,
    DateTime? lastSyncTime,
    String? searchQuery,
  }) {
    return EmployeeLoaded(
      employees: employees ?? this.employees,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class EmployeeSyncing extends EmployeeState {
  final double progress;
  final String message;
  final int totalEmployees;
  final int processedEmployees;

  const EmployeeSyncing({
    required this.progress,
    required this.message,
    this.totalEmployees = 0,
    this.processedEmployees = 0,
  });

  @override
  List<Object?> get props => [progress, message, totalEmployees, processedEmployees];
}

class EmployeeSyncSuccess extends EmployeeState {
  final SyncResult syncResult;
  final List<Employee> employees;

  const EmployeeSyncSuccess({
    required this.syncResult,
    required this.employees,
  });

  @override
  List<Object?> get props => [syncResult, employees];
}

class EmployeeError extends EmployeeState {
  final String message;
  final List<Employee>? cachedEmployees;

  const EmployeeError({
    required this.message,
    this.cachedEmployees,
  });

  @override
  List<Object?> get props => [message, cachedEmployees];
}

class EmployeeGeneratingEmbedding extends EmployeeState {
  final String employeeId;
  final String employeeName;
  final double progress;

  const EmployeeGeneratingEmbedding({
    required this.employeeId,
    required this.employeeName,
    required this.progress,
  });

  @override
  List<Object?> get props => [employeeId, employeeName, progress];
}

class EmployeeEmbeddingGenerated extends EmployeeState {
  final String employeeId;
  final String message;

  const EmployeeEmbeddingGenerated({
    required this.employeeId,
    required this.message,
  });

  @override
  List<Object?> get props => [employeeId, message];
}

class EmployeeDetailLoaded extends EmployeeState {
  final Employee employee;

  const EmployeeDetailLoaded({
    required this.employee,
  });

  @override
  List<Object?> get props => [employee];
}

class FaceImageAdded extends EmployeeState {
  final String employeeId;
  final String encodingId;

  const FaceImageAdded({
    required this.employeeId,
    required this.encodingId,
  });

  @override
  List<Object?> get props => [employeeId, encodingId];
}

class FaceImageDeleted extends EmployeeState {
  final String employeeId;
  final String encodingId;

  const FaceImageDeleted({
    required this.employeeId,
    required this.encodingId,
  });

  @override
  List<Object?> get props => [employeeId, encodingId];
}

class FaceImageProcessing extends EmployeeState {
  final String message;
  final double progress;

  const FaceImageProcessing({
    required this.message,
    this.progress = 0.0,
  });

  @override
  List<Object?> get props => [message, progress];
}