import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class FaceEncodingModel extends Equatable {
  final String employeeId;
  final String employeeName;
  final List<double> encoding;
  final String? photoUrl;
  final double qualityScore;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  const FaceEncodingModel({
    required this.employeeId,
    required this.employeeName,
    required this.encoding,
    this.photoUrl,
    this.qualityScore = 1.0,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
  });

  /// Create from JSON map
  factory FaceEncodingModel.fromJson(Map<String, dynamic> json) {
    return FaceEncodingModel(
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
      encoding: _decodeEncoding(json['encoding']),
      photoUrl: json['photo_url'] as String?,
      qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 1.0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      syncStatus: json['sync_status'] as String? ?? 'synced',
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'employee_id': employeeId,
      'employee_name': employeeName,
      'encoding': _encodeEncoding(encoding),
      'photo_url': photoUrl,
      'quality_score': qualityScore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  /// Copy with new values
  FaceEncodingModel copyWith({
    String? employeeId,
    String? employeeName,
    List<double>? encoding,
    String? photoUrl,
    double? qualityScore,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return FaceEncodingModel(
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      encoding: encoding ?? this.encoding,
      photoUrl: photoUrl ?? this.photoUrl,
      qualityScore: qualityScore ?? this.qualityScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  /// Decode encoding from database blob
  static List<double> _decodeEncoding(dynamic encodingData) {
    if (encodingData == null) return [];

    try {
      if (encodingData is Uint8List) {
        // Convert bytes to double list
        final buffer = encodingData.buffer.asByteData();
        final encoding = <double>[];
        for (int i = 0; i < buffer.lengthInBytes; i += 4) {
          encoding.add(buffer.getFloat32(i, Endian.little));
        }
        return encoding;
      } else if (encodingData is String) {
        // Decode from base64
        final bytes = base64Decode(encodingData);
        final buffer = bytes.buffer.asByteData();
        final encoding = <double>[];
        for (int i = 0; i < buffer.lengthInBytes; i += 4) {
          encoding.add(buffer.getFloat32(i, Endian.little));
        }
        return encoding;
      } else if (encodingData is List) {
        // Already a list
        return List<double>.from(encodingData);
      }
    } catch (e) {
      // Log error but don't crash
    }

    return [];
  }

  /// Encode encoding for database storage
  static Uint8List _encodeEncoding(List<double> encoding) {
    final buffer = Uint8List(encoding.length * 4);
    final byteData = buffer.buffer.asByteData();

    for (int i = 0; i < encoding.length; i++) {
      byteData.setFloat32(i * 4, encoding[i], Endian.little);
    }

    return buffer;
  }

  /// Calculate Euclidean distance to another encoding
  double distanceTo(FaceEncodingModel other) {
    if (encoding.length != other.encoding.length) {
      return double.infinity;
    }

    double sum = 0;
    for (int i = 0; i < encoding.length; i++) {
      final diff = encoding[i] - other.encoding[i];
      sum += diff * diff;
    }

    return sum > 0 ? (sum / encoding.length) : 0;
  }

  /// Calculate cosine similarity to another encoding
  double cosineSimilarity(FaceEncodingModel other) {
    if (encoding.length != other.encoding.length) {
      return 0;
    }

    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < encoding.length; i++) {
      dotProduct += encoding[i] * other.encoding[i];
      normA += encoding[i] * encoding[i];
      normB += other.encoding[i] * other.encoding[i];
    }

    if (normA == 0 || normB == 0) return 0;

    return dotProduct / (normA * normB);
  }

  @override
  List<Object?> get props => [
        employeeId,
        employeeName,
        encoding,
        photoUrl,
        qualityScore,
        createdAt,
        updatedAt,
        syncStatus,
      ];

  @override
  String toString() {
    return 'FaceEncodingModel('
        'employeeId: $employeeId, '
        'employeeName: $employeeName, '
        'encodingSize: ${encoding.length}, '
        'qualityScore: $qualityScore, '
        'syncStatus: $syncStatus)';
  }
}