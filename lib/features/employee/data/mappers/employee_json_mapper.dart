import 'dart:typed_data';

import '../models/employee_model.dart';

/// Handles JSON serialization/deserialization for Employee entities
class EmployeeJsonMapper {
  EmployeeJsonMapper._();

  /// Convert JSON to EmployeeModel
  static EmployeeModel fromJson(Map<String, dynamic> json) {
    // Construct full name from firstName and lastName, or use fullName, or fallback to name
    String fullName = '';
    if (json['fullName'] != null && json['fullName'].toString().isNotEmpty) {
      fullName = json['fullName'];
    } else if (json['firstName'] != null || json['lastName'] != null) {
      final firstName = json['firstName'] ?? '';
      final lastName = json['lastName'] ?? '';
      fullName = '$firstName $lastName'.trim();
    } else if (json['name'] != null) {
      fullName = json['name'];
    }

    return EmployeeModel(
      id: json['id'] ?? json['_id'] ?? '',
      name: fullName,
      email: json['email'],
      phoneNumber: json['phoneNumber'] ?? json['phone_number'],
      department: json['department'],
      position: json['position'],
      employeeCode: json['employeeCode'] ?? json['employee_code'],
      photoUrl: json['photoUrl'] ??
          json['photo_url'] ??
          json['profilePhotoURL'] ??
          json['photo'],
      photoBytes: json['photoBytes'] != null
          ? Uint8List.fromList(List<int>.from(json['photoBytes']))
          : null,
      faceEncodings: (json['faceEncodings'] as List<dynamic>?)
              ?.map((e) => FaceEncodingModel.fromJson(e))
              .toList() ??
          [],
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'])
          : null,
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      metadata: json['metadata'],
    );
  }

  /// Convert EmployeeModel to JSON
  static Map<String, dynamic> toJson(EmployeeModel employee) {
    return {
      'id': employee.id,
      'name': employee.name,
      'email': employee.email,
      'phoneNumber': employee.phoneNumber,
      'department': employee.department,
      'position': employee.position,
      'employeeCode': employee.employeeCode,
      'photoUrl': employee.photoUrl,
      if (employee.photoBytes != null) 'photoBytes': employee.photoBytes!.toList(),
      'faceEncodings': employee.faceEncodings
          .map((e) => FaceEncodingJsonMapper.toJson(e as FaceEncodingModel))
          .toList(),
      'lastSyncedAt': employee.lastSyncedAt?.toIso8601String(),
      'createdAt': employee.createdAt?.toIso8601String(),
      'updatedAt': employee.updatedAt?.toIso8601String(),
      'isActive': employee.isActive,
      'metadata': employee.metadata,
    };
  }
}

/// Handles JSON serialization for Face Encodings
class FaceEncodingJsonMapper {
  FaceEncodingJsonMapper._();

  /// Convert JSON to FaceEncodingModel
  static FaceEncodingModel fromJson(Map<String, dynamic> json) {
    return FaceEncodingModel(
      id: json['id'] ?? '',
      embedding: Float32List.fromList(
        (json['embedding'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
      ),
      quality: (json['quality'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
      source: json['source'],
      metadata: json['metadata'],
    );
  }

  /// Convert FaceEncodingModel to JSON
  static Map<String, dynamic> toJson(FaceEncodingModel encoding) {
    return {
      'id': encoding.id,
      'embedding': encoding.embedding.toList(),
      'quality': encoding.quality,
      'createdAt': encoding.createdAt.toIso8601String(),
      'source': encoding.source,
      'metadata': encoding.metadata,
    };
  }
}