import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../face_recognition/data/services/simplified_face_recognition_service.dart';

class FaceRecognitionLogModel {
  final int? id;
  final DateTime timestamp;
  final FaceRecognitionResultType resultType;
  final String? employeeId;
  final String? employeeName;
  final double? confidence;
  final double? quality;
  final int processingTimeMs;
  final Rect? faceBounds;
  final Uint8List? faceImage;
  final Uint8List? thumbnailImage;
  final int? imageWidth;
  final int? imageHeight;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  final String? deviceId;
  final DateTime createdAt;

  const FaceRecognitionLogModel({
    this.id,
    required this.timestamp,
    required this.resultType,
    this.employeeId,
    this.employeeName,
    this.confidence,
    this.quality,
    required this.processingTimeMs,
    this.faceBounds,
    this.faceImage,
    this.thumbnailImage,
    this.imageWidth,
    this.imageHeight,
    this.errorMessage,
    this.metadata,
    this.deviceId,
    required this.createdAt,
  });

  // Factory constructor from database map
  factory FaceRecognitionLogModel.fromDatabase(Map<String, dynamic> map) {
    return FaceRecognitionLogModel(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      resultType: FaceRecognitionResultType.values.firstWhere(
        (e) => e.name == map['result_type'],
        orElse: () => FaceRecognitionResultType.error,
      ),
      employeeId: map['employee_id'] as String?,
      employeeName: map['employee_name'] as String?,
      confidence: map['confidence'] as double?,
      quality: map['quality'] as double?,
      processingTimeMs: map['processing_time_ms'] as int,
      faceBounds: map['face_bounds'] != null
          ? _rectFromJson(map['face_bounds'] as String)
          : null,
      faceImage: map['face_image'] as Uint8List?,
      thumbnailImage: map['thumbnail_image'] as Uint8List?,
      imageWidth: map['image_width'] as int?,
      imageHeight: map['image_height'] as int?,
      errorMessage: map['error_message'] as String?,
      metadata: map['metadata'] != null
          ? json.decode(map['metadata'] as String) as Map<String, dynamic>
          : null,
      deviceId: map['device_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // Convert to database map
  Map<String, dynamic> toDatabase() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'result_type': resultType.name,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'confidence': confidence,
      'quality': quality,
      'processing_time_ms': processingTimeMs,
      'face_bounds': faceBounds != null ? _rectToJson(faceBounds!) : null,
      'face_image': faceImage,
      'thumbnail_image': thumbnailImage,
      'image_width': imageWidth,
      'image_height': imageHeight,
      'error_message': errorMessage,
      'metadata': metadata != null ? json.encode(metadata) : null,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Create from recognition result
  factory FaceRecognitionLogModel.fromRecognitionResult({
    required FaceRecognitionResult result,
    required int processingTimeMs,
    Rect? faceBounds,
    Uint8List? faceImage,
    Uint8List? thumbnailImage,
    int? imageWidth,
    int? imageHeight,
    Map<String, dynamic>? metadata,
    String? deviceId,
  }) {
    final now = DateTime.now();
    return FaceRecognitionLogModel(
      timestamp: now,
      resultType: result.type,
      employeeId: result.employee?.id,
      employeeName: result.employee?.name,
      confidence: result.confidence,
      quality: result.quality,
      processingTimeMs: processingTimeMs,
      faceBounds: faceBounds,
      faceImage: faceImage,
      thumbnailImage: thumbnailImage,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      errorMessage: result.message,
      metadata: metadata,
      deviceId: deviceId,
      createdAt: now,
    );
  }

  // Copy with method for updates
  FaceRecognitionLogModel copyWith({
    int? id,
    DateTime? timestamp,
    FaceRecognitionResultType? resultType,
    String? employeeId,
    String? employeeName,
    double? confidence,
    double? quality,
    int? processingTimeMs,
    Rect? faceBounds,
    Uint8List? faceImage,
    Uint8List? thumbnailImage,
    int? imageWidth,
    int? imageHeight,
    String? errorMessage,
    Map<String, dynamic>? metadata,
    String? deviceId,
    DateTime? createdAt,
  }) {
    return FaceRecognitionLogModel(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      resultType: resultType ?? this.resultType,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      confidence: confidence ?? this.confidence,
      quality: quality ?? this.quality,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      faceBounds: faceBounds ?? this.faceBounds,
      faceImage: faceImage ?? this.faceImage,
      thumbnailImage: thumbnailImage ?? this.thumbnailImage,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      errorMessage: errorMessage ?? this.errorMessage,
      metadata: metadata ?? this.metadata,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Getters for convenience
  bool get isSuccessful => resultType == FaceRecognitionResultType.matched;
  bool get hasImage => faceImage != null;
  bool get hasThumbnail => thumbnailImage != null;
  bool get hasError => errorMessage != null;

  String get resultTypeDisplayName {
    switch (resultType) {
      case FaceRecognitionResultType.matched:
        return 'Matched';
      case FaceRecognitionResultType.unknown:
        return 'Unknown Face';
      case FaceRecognitionResultType.noFace:
        return 'No Face';
      case FaceRecognitionResultType.poorQuality:
        return 'Poor Quality';
      case FaceRecognitionResultType.noEmployees:
        return 'No Employees';
      case FaceRecognitionResultType.error:
        return 'Error';
    }
  }

  Color get resultColor {
    switch (resultType) {
      case FaceRecognitionResultType.matched:
        return Colors.green;
      case FaceRecognitionResultType.unknown:
        return Colors.orange;
      case FaceRecognitionResultType.noFace:
        return Colors.blue;
      case FaceRecognitionResultType.poorQuality:
        return Colors.amber;
      case FaceRecognitionResultType.noEmployees:
        return Colors.purple;
      case FaceRecognitionResultType.error:
        return Colors.red;
    }
  }

  IconData get resultIcon {
    switch (resultType) {
      case FaceRecognitionResultType.matched:
        return Icons.check_circle;
      case FaceRecognitionResultType.unknown:
        return Icons.help;
      case FaceRecognitionResultType.noFace:
        return Icons.face_outlined;
      case FaceRecognitionResultType.poorQuality:
        return Icons.warning;
      case FaceRecognitionResultType.noEmployees:
        return Icons.people_outline;
      case FaceRecognitionResultType.error:
        return Icons.error;
    }
  }

  // Size calculation
  int get estimatedSize {
    int size = 0;
    if (faceImage != null) size += faceImage!.length;
    if (thumbnailImage != null) size += thumbnailImage!.length;
    return size;
  }

  // JSON serialization helpers
  static Rect _rectFromJson(String rectJson) {
    final map = json.decode(rectJson) as Map<String, dynamic>;
    return Rect.fromLTWH(
      map['left'] as double,
      map['top'] as double,
      map['width'] as double,
      map['height'] as double,
    );
  }

  static String _rectToJson(Rect rect) {
    return json.encode({
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
  }

  @override
  String toString() {
    return 'FaceRecognitionLogModel('
        'id: $id, '
        'timestamp: $timestamp, '
        'resultType: $resultType, '
        'employeeName: $employeeName, '
        'confidence: $confidence, '
        'processingTimeMs: ${processingTimeMs}ms'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FaceRecognitionLogModel &&
        other.id == id &&
        other.timestamp == timestamp &&
        other.resultType == resultType;
  }

  @override
  int get hashCode {
    return Object.hash(id, timestamp, resultType);
  }
}