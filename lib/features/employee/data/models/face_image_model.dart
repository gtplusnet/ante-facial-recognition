import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/face_image.dart';

class FaceImageModel extends FaceImage {
  const FaceImageModel({
    required String id,
    required String employeeId,
    required Uint8List imageBytes,
    required String source,
    required DateTime capturedAt,
    String? encodingId,
    double? quality,
    Map<String, dynamic>? metadata,
  }) : super(
          id: id,
          employeeId: employeeId,
          imageBytes: imageBytes,
          source: source,
          capturedAt: capturedAt,
          encodingId: encodingId,
          quality: quality,
          metadata: metadata,
        );

  /// Create from domain entity
  factory FaceImageModel.fromEntity(FaceImage entity) {
    return FaceImageModel(
      id: entity.id,
      employeeId: entity.employeeId,
      imageBytes: entity.imageBytes,
      source: entity.source,
      capturedAt: entity.capturedAt,
      encodingId: entity.encodingId,
      quality: entity.quality,
      metadata: entity.metadata,
    );
  }

  /// Create from database map
  factory FaceImageModel.fromDatabase(Map<String, dynamic> map) {
    return FaceImageModel(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      imageBytes: map['image_bytes'] as Uint8List,
      source: map['source'] as String,
      capturedAt: DateTime.parse(map['captured_at'] as String),
      encodingId: map['encoding_id'] as String?,
      quality: map['quality'] as double?,
      metadata: map['metadata'] != null
          ? json.decode(map['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toDatabase() {
    return {
      'id': id,
      'employee_id': employeeId,
      'image_bytes': imageBytes,
      'source': source,
      'captured_at': capturedAt.toIso8601String(),
      'encoding_id': encodingId,
      'quality': quality,
      'metadata': metadata != null ? json.encode(metadata) : null,
    };
  }

  /// Convert to domain entity
  FaceImage toEntity() => this;
}