import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_recognition/data/services/face_encoding_service.dart';
import '../entities/employee.dart';

/// Parameters for face encoding generation
class GenerateFaceEncodingParams {
  final Employee employee;
  final Uint8List photoBytes;

  const GenerateFaceEncodingParams({
    required this.employee,
    required this.photoBytes,
  });
}

/// Result of face encoding generation
class FaceEncodingResult {
  final Employee employee;
  final FaceEncoding? faceEncoding;
  final bool success;
  final String? errorMessage;

  const FaceEncodingResult({
    required this.employee,
    this.faceEncoding,
    required this.success,
    this.errorMessage,
  });

  /// Create successful result with encoding
  factory FaceEncodingResult.success(Employee employee, FaceEncoding encoding) {
    return FaceEncodingResult(
      employee: employee,
      faceEncoding: encoding,
      success: true,
    );
  }

  /// Create result without encoding (no face detected)
  factory FaceEncodingResult.noFaceDetected(Employee employee) {
    return FaceEncodingResult(
      employee: employee,
      success: true,
      errorMessage: 'No face detected in photo',
    );
  }

  /// Create failed result with error
  factory FaceEncodingResult.failure(Employee employee, String error) {
    return FaceEncodingResult(
      employee: employee,
      success: false,
      errorMessage: error,
    );
  }

  /// Get employee with updated face encoding
  Employee get employeeWithEncoding {
    if (faceEncoding != null) {
      return employee.copyWith(faceEncodings: [faceEncoding!]);
    }
    return employee;
  }
}

/// Use case responsible for generating face encodings from employee photos
///
/// This use case follows Single Responsibility Principle by handling only
/// face encoding generation, separate from employee synchronization logic.
@injectable
class GenerateFaceEncodingUseCase implements UseCase<FaceEncodingResult, GenerateFaceEncodingParams> {
  final FaceEncodingService _faceEncodingService;

  const GenerateFaceEncodingUseCase(this._faceEncodingService);

  @override
  Future<Either<Failure, FaceEncodingResult>> call(GenerateFaceEncodingParams params) async {
    try {
      Logger.debug('  - Generating face encoding for ${params.employee.name}');

      // Initialize face encoding service if needed
      await _faceEncodingService.initialize();

      // Extract face encoding from photo bytes
      final encodingResult = await _faceEncodingService.extractFromImageBytes(params.photoBytes);

      if (encodingResult != null) {
        Logger.success('  - Generated face embedding for ${params.employee.name}');

        // Create face encoding object
        final faceEncoding = FaceEncoding(
          id: '${params.employee.id}_photo_${DateTime.now().millisecondsSinceEpoch}',
          embedding: encodingResult.embedding,
          quality: encodingResult.quality,
          createdAt: DateTime.now(),
          source: 'photo',
          metadata: {
            'processingTime': encodingResult.processingTime.inMilliseconds,
          },
        );

        return Right(FaceEncodingResult.success(params.employee, faceEncoding));
      } else {
        Logger.warning('  - Could not generate face embedding for ${params.employee.name} (no face detected)');
        return Right(FaceEncodingResult.noFaceDetected(params.employee));
      }
    } catch (error) {
      Logger.error('  - Failed to generate embedding for ${params.employee.name}', error: error);
      return Right(FaceEncodingResult.failure(params.employee, error.toString()));
    }
  }

  /// Convenience method for generating encoding with automatic error handling
  /// Returns the employee with encoding applied, or original employee if failed
  Future<Employee> generateAndApplyEncoding(Employee employee, Uint8List photoBytes) async {
    final params = GenerateFaceEncodingParams(employee: employee, photoBytes: photoBytes);
    final result = await call(params);

    return result.fold(
      (failure) {
        Logger.error('Face encoding generation failed', error: failure);
        return employee; // Return original employee on failure
      },
      (encodingResult) => encodingResult.employeeWithEncoding,
    );
  }
}