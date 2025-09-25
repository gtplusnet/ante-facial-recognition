import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'face_image.dart';

class Employee extends Equatable {
  final String id;
  final String name;
  final String? email;
  final String? phoneNumber;
  final String? department;
  final String? position;
  final String? employeeCode;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final List<FaceEncoding> faceEncodings;
  final List<FaceImage> faceImages; // Actual face photos captured
  final DateTime? lastSyncedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final Map<String, dynamic>? metadata;

  const Employee({
    required this.id,
    required this.name,
    this.email,
    this.phoneNumber,
    this.department,
    this.position,
    this.employeeCode,
    this.photoUrl,
    this.photoBytes,
    this.faceEncodings = const [],
    this.faceImages = const [],
    this.lastSyncedAt,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.metadata,
  });

  bool get hasFaceEncodings => faceEncodings.isNotEmpty;
  bool get hasPhoto => photoUrl != null || photoBytes != null;

  Employee copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? department,
    String? position,
    String? employeeCode,
    String? photoUrl,
    Uint8List? photoBytes,
    List<FaceEncoding>? faceEncodings,
    List<FaceImage>? faceImages,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      department: department ?? this.department,
      position: position ?? this.position,
      employeeCode: employeeCode ?? this.employeeCode,
      photoUrl: photoUrl ?? this.photoUrl,
      photoBytes: photoBytes ?? this.photoBytes,
      faceEncodings: faceEncodings ?? this.faceEncodings,
      faceImages: faceImages ?? this.faceImages,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phoneNumber,
        department,
        position,
        employeeCode,
        photoUrl,
        faceEncodings,
        faceImages,
        lastSyncedAt,
        createdAt,
        updatedAt,
        isActive,
        metadata,
      ];
}

class FaceEncoding extends Equatable {
  final String id;
  final Float32List embedding;
  final double quality;
  final DateTime createdAt;
  final String? source; // 'photo', 'registration', 'update'
  final Uint8List? imageBytes; // Actual image data for this encoding
  final Map<String, dynamic>? metadata;

  const FaceEncoding({
    required this.id,
    required this.embedding,
    required this.quality,
    required this.createdAt,
    this.source,
    this.imageBytes,
    this.metadata,
  });

  @override
  List<Object?> get props => [
        id,
        embedding,
        quality,
        createdAt,
        source,
        imageBytes,
        metadata,
      ];
}

class EmployeeTimeRecord extends Equatable {
  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime? clockInTime;
  final DateTime? clockOutTime;
  final String? clockInPhoto;
  final String? clockOutPhoto;
  final double? clockInConfidence;
  final double? clockOutConfidence;
  final Map<String, dynamic>? clockInLocation;
  final Map<String, dynamic>? clockOutLocation;
  final String status; // 'clocked_in', 'clocked_out'
  final Duration? totalHours;
  final Map<String, dynamic>? metadata;

  const EmployeeTimeRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.clockInTime,
    this.clockOutTime,
    this.clockInPhoto,
    this.clockOutPhoto,
    this.clockInConfidence,
    this.clockOutConfidence,
    this.clockInLocation,
    this.clockOutLocation,
    required this.status,
    this.totalHours,
    this.metadata,
  });

  bool get isClockedIn => status == 'clocked_in';
  bool get isClockedOut => status == 'clocked_out';

  EmployeeTimeRecord copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    DateTime? clockInTime,
    DateTime? clockOutTime,
    String? clockInPhoto,
    String? clockOutPhoto,
    double? clockInConfidence,
    double? clockOutConfidence,
    Map<String, dynamic>? clockInLocation,
    Map<String, dynamic>? clockOutLocation,
    String? status,
    Duration? totalHours,
    Map<String, dynamic>? metadata,
  }) {
    return EmployeeTimeRecord(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      clockInTime: clockInTime ?? this.clockInTime,
      clockOutTime: clockOutTime ?? this.clockOutTime,
      clockInPhoto: clockInPhoto ?? this.clockInPhoto,
      clockOutPhoto: clockOutPhoto ?? this.clockOutPhoto,
      clockInConfidence: clockInConfidence ?? this.clockInConfidence,
      clockOutConfidence: clockOutConfidence ?? this.clockOutConfidence,
      clockInLocation: clockInLocation ?? this.clockInLocation,
      clockOutLocation: clockOutLocation ?? this.clockOutLocation,
      status: status ?? this.status,
      totalHours: totalHours ?? this.totalHours,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        employeeId,
        employeeName,
        clockInTime,
        clockOutTime,
        clockInPhoto,
        clockOutPhoto,
        clockInConfidence,
        clockOutConfidence,
        clockInLocation,
        clockOutLocation,
        status,
        totalHours,
        metadata,
      ];
}