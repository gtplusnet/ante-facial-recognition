import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../services/face_encoding_service.dart';

/// Datasource for face recognition operations
@singleton
class FaceRecognitionDatasource {
  final FaceEncodingService _faceEncodingService;

  FaceRecognitionDatasource({
    required FaceEncodingService faceEncodingService,
  }) : _faceEncodingService = faceEncodingService;

  /// Generate face encoding from image bytes
  Future<List<double>> generateFaceEncoding(Uint8List imageData) async {
    try {
      // Convert image data to face encoding using ML model
      final result = await _faceEncodingService.extractFromImageBytes(imageData);

      if (result == null) {
        Logger.warning('Failed to generate face encoding');
        return [];
      }

      return result.embedding.toList();
    } catch (e) {
      Logger.error('Error generating face encoding', error: e);
      return [];
    }
  }

  /// Verify if encoding is valid
  bool isValidEncoding(List<double> encoding) {
    if (encoding.isEmpty) return false;
    if (encoding.length != 192) return false; // Verified MobileFaceNet model output size

    // Check for NaN or infinite values
    for (final value in encoding) {
      if (value.isNaN || value.isInfinite) return false;
    }

    return true;
  }
}