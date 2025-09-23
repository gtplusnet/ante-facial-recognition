import 'dart:convert';

import '../models/employee_model.dart';

/// Handles database mapping for Employee entities
class EmployeeDatabaseMapper {
  EmployeeDatabaseMapper._();

  /// Convert database map to EmployeeModel
  static EmployeeModel fromDatabase(Map<String, dynamic> map) {
    return EmployeeModel(
      id: map['id'],
      name: map['name'] ?? '',
      email: map['email'],
      phoneNumber: map['phone_number'],
      department: map['department'],
      position: map['position'],
      employeeCode: map['employee_code'],
      photoUrl: map['photo_url'],
      photoBytes: map['photo_bytes'],
      faceEncodings: const [], // Face encodings loaded separately
      isActive: map['is_active'] == 1, // Convert int to bool
      metadata: map['metadata'] != null
          ? (map['metadata'] is String
              ? json.decode(map['metadata'])
              : map['metadata'])
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : null,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.parse(map['last_synced_at'])
          : null,
    );
  }

  /// Convert EmployeeModel to database map
  static Map<String, dynamic> toDatabase(EmployeeModel employee) {
    return {
      'id': employee.id,
      'name': employee.name,
      'email': employee.email,
      'phone_number': employee.phoneNumber,
      'department': employee.department,
      'position': employee.position,
      'employee_code': employee.employeeCode,
      'photo_url': employee.photoUrl,
      'photo_bytes': employee.photoBytes,
      'is_active': employee.isActive ? 1 : 0, // Convert bool to int
      'metadata': employee.metadata != null
          ? json.encode(employee.metadata)
          : null,
      'created_at': employee.createdAt?.toIso8601String(),
      'updated_at': employee.updatedAt?.toIso8601String(),
      'last_synced_at': employee.lastSyncedAt?.toIso8601String(),
    };
  }
}