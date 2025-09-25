import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Represents an actual face image/photo of an employee
/// This is separate from FaceEncoding which is the mathematical representation
class FaceImage extends Equatable {
  final String id;
  final String employeeId;
  final Uint8List imageBytes;
  final String source; // 'camera', 'registration', 'update', etc.
  final DateTime capturedAt;
  final String? encodingId; // Link to associated face encoding if exists
  final double? quality; // Quality score from face encoding
  final Map<String, dynamic>? metadata;

  const FaceImage({
    required this.id,
    required this.employeeId,
    required this.imageBytes,
    required this.source,
    required this.capturedAt,
    this.encodingId,
    this.quality,
    this.metadata,
  });

  FaceImage copyWith({
    String? id,
    String? employeeId,
    Uint8List? imageBytes,
    String? source,
    DateTime? capturedAt,
    String? encodingId,
    double? quality,
    Map<String, dynamic>? metadata,
  }) {
    return FaceImage(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      imageBytes: imageBytes ?? this.imageBytes,
      source: source ?? this.source,
      capturedAt: capturedAt ?? this.capturedAt,
      encodingId: encodingId ?? this.encodingId,
      quality: quality ?? this.quality,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        employeeId,
        imageBytes,
        source,
        capturedAt,
        encodingId,
        quality,
        metadata,
      ];
}