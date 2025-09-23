import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';
import '../../data/services/face_match_scorer.dart';
import '../../data/services/face_recognition_service.dart';

/// Repository interface for face recognition operations
abstract class FaceRecognitionRepository {
  /// Recognize face from image
  Future<Either<Failure, FaceRecognitionMatchResult?>> recognizeFace({
    required Uint8List imageData,
    required FaceDetectionResult faceDetection,
    int topK = 3,
    bool requireLiveness = false,
    double? customThreshold,
  });

  /// Match face against specific employee
  Future<Either<Failure, FaceMatchResult?>> matchSpecificEmployee({
    required Uint8List imageData,
    required String employeeId,
    required FaceDetectionResult faceDetection,
    double? customThreshold,
  });

  /// Update employee face encoding
  Future<Either<Failure, bool>> updateEmployeeEncoding({
    required String employeeId,
    required String employeeName,
    required Uint8List imageData,
    required FaceDetectionResult faceDetection,
    String? photoUrl,
  });

  /// Initialize repository
  Future<Either<Failure, void>> initialize();

  /// Clear cache
  Future<Either<Failure, void>> clearCache();
}