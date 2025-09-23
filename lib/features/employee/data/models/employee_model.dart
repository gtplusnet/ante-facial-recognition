import 'dart:typed_data';

import '../../domain/entities/employee.dart';

class EmployeeModel extends Employee {
  const EmployeeModel({
    required super.id,
    required super.name,
    super.email,
    super.phoneNumber,
    super.department,
    super.position,
    super.employeeCode,
    super.photoUrl,
    super.photoBytes,
    super.faceEncodings,
    super.lastSyncedAt,
    super.createdAt,
    super.updatedAt,
    super.isActive,
    super.metadata,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phoneNumber: json['phoneNumber'] ?? json['phone_number'],
      department: json['department'],
      position: json['position'],
      employeeCode: json['employeeCode'] ?? json['employee_code'],
      photoUrl: json['photoUrl'] ?? json['photo_url'] ?? json['photo'],
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'department': department,
      'position': position,
      'employeeCode': employeeCode,
      'photoUrl': photoUrl,
      if (photoBytes != null) 'photoBytes': photoBytes!.toList(),
      'faceEncodings': faceEncodings.map((e) => (e as FaceEncodingModel).toJson()).toList(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isActive': isActive,
      'metadata': metadata,
    };
  }

  factory EmployeeModel.fromEntity(Employee employee) {
    return EmployeeModel(
      id: employee.id,
      name: employee.name,
      email: employee.email,
      phoneNumber: employee.phoneNumber,
      department: employee.department,
      position: employee.position,
      employeeCode: employee.employeeCode,
      photoUrl: employee.photoUrl,
      photoBytes: employee.photoBytes,
      faceEncodings: employee.faceEncodings,
      lastSyncedAt: employee.lastSyncedAt,
      createdAt: employee.createdAt,
      updatedAt: employee.updatedAt,
      isActive: employee.isActive,
      metadata: employee.metadata,
    );
  }
}

class FaceEncodingModel extends FaceEncoding {
  const FaceEncodingModel({
    required super.id,
    required super.embedding,
    required super.quality,
    required super.createdAt,
    super.source,
    super.metadata,
  });

  factory FaceEncodingModel.fromJson(Map<String, dynamic> json) {
    return FaceEncodingModel(
      id: json['id'] ?? '',
      embedding: Float32List.fromList(
        (json['embedding'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
      ),
      quality: (json['quality'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
      source: json['source'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'embedding': embedding.toList(),
      'quality': quality,
      'createdAt': createdAt.toIso8601String(),
      'source': source,
      'metadata': metadata,
    };
  }
}

class EmployeeTimeRecordModel extends EmployeeTimeRecord {
  const EmployeeTimeRecordModel({
    required super.id,
    required super.employeeId,
    required super.employeeName,
    super.clockInTime,
    super.clockOutTime,
    super.clockInPhoto,
    super.clockOutPhoto,
    super.clockInConfidence,
    super.clockOutConfidence,
    super.clockInLocation,
    super.clockOutLocation,
    required super.status,
    super.totalHours,
    super.metadata,
  });

  factory EmployeeTimeRecordModel.fromJson(Map<String, dynamic> json) {
    return EmployeeTimeRecordModel(
      id: json['id'] ?? json['_id'] ?? '',
      employeeId: json['employeeId'] ?? json['employee_id'] ?? '',
      employeeName: json['employeeName'] ?? json['employee_name'] ?? '',
      clockInTime: json['clockInTime'] != null || json['clock_in_time'] != null
          ? DateTime.parse(json['clockInTime'] ?? json['clock_in_time'])
          : null,
      clockOutTime: json['clockOutTime'] != null || json['clock_out_time'] != null
          ? DateTime.parse(json['clockOutTime'] ?? json['clock_out_time'])
          : null,
      clockInPhoto: json['clockInPhoto'] ?? json['clock_in_photo'],
      clockOutPhoto: json['clockOutPhoto'] ?? json['clock_out_photo'],
      clockInConfidence: json['clockInConfidence'] != null
          ? (json['clockInConfidence'] as num).toDouble()
          : json['clock_in_confidence'] != null
              ? (json['clock_in_confidence'] as num).toDouble()
              : null,
      clockOutConfidence: json['clockOutConfidence'] != null
          ? (json['clockOutConfidence'] as num).toDouble()
          : json['clock_out_confidence'] != null
              ? (json['clock_out_confidence'] as num).toDouble()
              : null,
      clockInLocation: json['clockInLocation'] ?? json['clock_in_location'],
      clockOutLocation: json['clockOutLocation'] ?? json['clock_out_location'],
      status: json['status'] ?? 'clocked_out',
      totalHours: json['totalHours'] != null
          ? Duration(milliseconds: json['totalHours'])
          : null,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'clockInTime': clockInTime?.toIso8601String(),
      'clockOutTime': clockOutTime?.toIso8601String(),
      'clockInPhoto': clockInPhoto,
      'clockOutPhoto': clockOutPhoto,
      'clockInConfidence': clockInConfidence,
      'clockOutConfidence': clockOutConfidence,
      'clockInLocation': clockInLocation,
      'clockOutLocation': clockOutLocation,
      'status': status,
      'totalHours': totalHours?.inMilliseconds,
      'metadata': metadata,
    };
  }

  factory EmployeeTimeRecordModel.fromEntity(EmployeeTimeRecord record) {
    return EmployeeTimeRecordModel(
      id: record.id,
      employeeId: record.employeeId,
      employeeName: record.employeeName,
      clockInTime: record.clockInTime,
      clockOutTime: record.clockOutTime,
      clockInPhoto: record.clockInPhoto,
      clockOutPhoto: record.clockOutPhoto,
      clockInConfidence: record.clockInConfidence,
      clockOutConfidence: record.clockOutConfidence,
      clockInLocation: record.clockInLocation,
      clockOutLocation: record.clockOutLocation,
      status: record.status,
      totalHours: record.totalHours,
      metadata: record.metadata,
    );
  }
}