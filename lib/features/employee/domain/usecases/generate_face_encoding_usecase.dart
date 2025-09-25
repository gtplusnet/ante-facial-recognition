import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_recognition/data/services/face_encoding_service.dart';
import '../../data/datasources/employee_local_datasource.dart';
import '../../data/models/employee_model.dart';
import '../entities/employee.dart';

/// Parameters for face encoding generation
class GenerateFaceEncodingParams {
  final String? employeeId;
  final Employee? employee;
  final Uint8List? photoBytes;
  final List<int>? imageBytes;
  final String? source;

  const GenerateFaceEncodingParams({
    this.employeeId,
    this.employee,
    this.photoBytes,
    this.imageBytes,
    this.source,
  });

  Uint8List get actualPhotoBytes {
    if (photoBytes != null) return photoBytes!;
    if (imageBytes != null) return Uint8List.fromList(imageBytes!);
    throw Exception('No photo bytes available');
  }
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
  final EmployeeLocalDataSource _employeeDataSource;

  const GenerateFaceEncodingUseCase(
    this._faceEncodingService,
    this._employeeDataSource,
  );

  /// Execute method that returns just the encoding ID for compatibility
  Future<Either<Failure, String>> execute(GenerateFaceEncodingParams params) async {
    try {
      final name = params.employee?.name ?? params.employeeId ?? 'Unknown';
      Logger.debug('  - Generating face encoding for $name');

      // Initialize face encoding service if needed
      await _faceEncodingService.initialize();

      // Extract face encoding from photo bytes
      final encodingResult = await _faceEncodingService.extractFromImageBytes(params.actualPhotoBytes);

      if (encodingResult != null) {
        Logger.success('  - Generated face embedding for $name');

        // Create face encoding ID
        final employeeId = params.employeeId ?? params.employee?.id ?? 'unknown';
        final encodingId = '${employeeId}_${params.source ?? 'photo'}_${DateTime.now().millisecondsSinceEpoch}';

        // Save to database
        try {
          // Get employee to verify it exists
          final employee = await _employeeDataSource.getEmployeeById(employeeId);
          if (employee != null) {
            // Create FaceEncodingModel with image bytes
            final encodingModel = FaceEncodingModel(
              id: encodingId,
              embedding: encodingResult.embedding,
              quality: encodingResult.quality,
              createdAt: DateTime.now(),
              source: params.source ?? 'registration',
              imageBytes: params.actualPhotoBytes, // Store the actual image
              metadata: {
                'processingTime': encodingResult.processingTime.inMilliseconds,
              },
            );

            // Save the face encoding with image directly
            await _employeeDataSource.saveFaceEncoding(employeeId, encodingModel);
            Logger.success('Saved face encoding to database for $name');
          }
        } catch (e) {
          Logger.error('Failed to save face encoding to database', error: e);
          // Continue anyway, encoding was generated
        }

        return Right(encodingId);
      } else {
        Logger.warning('  - Could not generate face embedding for $name (no face detected)');
        return const Left(ServerFailure(message: 'No face detected in image'));
      }
    } catch (error) {
      Logger.error('  - Failed to generate embedding', error: error);
      return Left(ServerFailure(message: error.toString()));
    }
  }

  @override
  Future<Either<Failure, FaceEncodingResult>> call(GenerateFaceEncodingParams params) async {
    if (params.employee == null) {
      return const Left(ServerFailure(message: 'Employee data is required'));
    }

    try {
      Logger.debug('  - Generating face encoding for ${params.employee!.name}');

      // Initialize face encoding service if needed
      await _faceEncodingService.initialize();

      // Extract face encoding from photo bytes
      final encodingResult = await _faceEncodingService.extractFromImageBytes(params.actualPhotoBytes);

      if (encodingResult != null) {
        Logger.success('  - Generated face embedding for ${params.employee!.name}');

        // Create face encoding object
        final faceEncoding = FaceEncoding(
          id: '${params.employee!.id}_${params.source ?? 'photo'}_${DateTime.now().millisecondsSinceEpoch}',
          embedding: encodingResult.embedding,
          quality: encodingResult.quality,
          createdAt: DateTime.now(),
          source: params.source ?? 'photo',
          metadata: {
            'processingTime': encodingResult.processingTime.inMilliseconds,
          },
        );

        return Right(FaceEncodingResult.success(params.employee!, faceEncoding));
      } else {
        Logger.warning('  - Could not generate face embedding for ${params.employee!.name} (no face detected)');
        return Right(FaceEncodingResult.noFaceDetected(params.employee!));
      }
    } catch (error) {
      Logger.error('  - Failed to generate embedding for ${params.employee!.name}', error: error);
      return Right(FaceEncodingResult.failure(params.employee!, error.toString()));
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