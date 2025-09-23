import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import '../../../../core/config/face_recognition_config.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/data/datasources/face_encoding_cache.dart';
import '../../../employee/data/models/face_encoding_model.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';
import '../../domain/repositories/face_recognition_repository.dart';
import '../datasources/face_recognition_datasource.dart';
import 'face_match_scorer.dart';

/// Face recognition match result with multiple candidates
class FaceRecognitionMatchResult {
  final List<FaceMatchResult> topMatches;
  final FaceMatchResult? bestMatch;
  final double overallConfidence;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  FaceRecognitionMatchResult({
    required this.topMatches,
    this.bestMatch,
    required this.overallConfidence,
    required this.metadata,
    required this.timestamp,
  });

  bool get hasMatch => bestMatch != null && bestMatch!.isMatch;

  bool get isHighConfidence => bestMatch != null && bestMatch!.combinedConfidence >= 0.85;
}

/// Service for face recognition operations
@singleton
class FaceRecognitionService {
  final FaceRecognitionDatasource _datasource;
  final FaceEncodingCache _encodingCache;
  final FaceMatchScorer _matchScorer;

  FaceRecognitionService({
    required FaceRecognitionDatasource datasource,
    required FaceEncodingCache encodingCache,
    required FaceMatchScorer matchScorer,
  })  : _datasource = datasource,
        _encodingCache = encodingCache,
        _matchScorer = matchScorer;

  /// Process face image and find top-K matches
  Future<FaceRecognitionMatchResult?> recognizeFace({
    required Uint8List imageData,
    required FaceDetectionResult faceDetection,
    int topK = FaceRecognitionConfig.topKMatches,
    bool requireLiveness = FaceRecognitionConfig.enableLivenessDetection,
    double? customThreshold,
  }) async {
    try {
      // Step 1: Generate face encoding from image
      Logger.debug('Generating face encoding from image...');
      final encoding = await _datasource.generateFaceEncoding(imageData);
      
      if (encoding.isEmpty) {
        Logger.warning('Failed to generate face encoding');
        return null;
      }

      // Step 2: Create candidate model
      final candidate = FaceEncodingModel(
        employeeId: 'candidate',
        employeeName: 'Candidate',
        encoding: encoding,
        qualityScore: faceDetection.qualityScore,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Step 3: Get all cached reference encodings
      final references = _encodingCache.getAllCached().values.toList();
      
      if (references.isEmpty) {
        Logger.warning('No reference encodings available for matching');
        return null;
      }

      Logger.info('Matching against ${references.length} reference encodings');

      // Step 4: Score all matches and get top-K
      final topMatches = _matchScorer.scoreMultiple(
        candidate: candidate,
        references: references,
        faceQuality: faceDetection.qualityScore,
        topK: topK,
        customThreshold: customThreshold,
      );

      if (topMatches.isEmpty) {
        Logger.info('No matches found within threshold');
        return FaceRecognitionMatchResult(
          topMatches: [],
          bestMatch: null,
          overallConfidence: 0.0,
          metadata: {
            'reason': 'no_matches_within_threshold',
            'candidates_checked': references.length,
            'threshold': customThreshold ?? FaceRecognitionConfig.defaultMatchThreshold,
          },
          timestamp: DateTime.now(),
        );
      }

      // Step 5: Apply post-processing if needed
      final bestMatch = topMatches.first;
      FaceMatchResult? processedBestMatch = bestMatch;

      if (requireLiveness) {
        // Calculate liveness score (placeholder for actual implementation)
        final livenessScore = await _calculateLivenessScore(imageData, faceDetection);
        
        processedBestMatch = _matchScorer.applyPostProcessing(
          bestMatch,
          requireLiveness: requireLiveness,
          livenessScore: livenessScore,
          requireGoodLighting: FaceRecognitionConfig.requireGoodLighting,
          lightingQuality: faceDetection.lightingQuality ?? 0.7,
        );
      }

      // Step 6: Calculate overall confidence
      final overallConfidence = _calculateOverallConfidence(topMatches);

      // Step 7: Create result with metadata
      return FaceRecognitionMatchResult(
        topMatches: topMatches,
        bestMatch: processedBestMatch,
        overallConfidence: overallConfidence,
        metadata: {
          'candidates_checked': references.length,
          'matches_found': topMatches.length,
          'processing_time_ms': DateTime.now().difference(faceDetection.timestamp).inMilliseconds,
          'face_quality': faceDetection.qualityScore,
          'lighting_quality': faceDetection.lightingQuality ?? 0.7,
          'threshold_used': customThreshold ?? FaceRecognitionConfig.defaultMatchThreshold,
        },
        timestamp: DateTime.now(),
      );
    } catch (e) {
      Logger.error('Face recognition failed', error: e);
      return null;
    }
  }

  /// Match face against specific employee
  Future<FaceMatchResult?> matchSpecificEmployee({
    required Uint8List imageData,
    required String employeeId,
    required FaceDetectionResult faceDetection,
    double? customThreshold,
  }) async {
    try {
      // Get reference encoding for specific employee
      final reference = await _encodingCache.getEncoding(employeeId);
      
      if (reference == null) {
        Logger.warning('No encoding found for employee $employeeId');
        return null;
      }

      // Generate candidate encoding
      final encoding = await _datasource.generateFaceEncoding(imageData);
      
      if (encoding.isEmpty) {
        Logger.warning('Failed to generate face encoding');
        return null;
      }

      // Create candidate model
      final candidate = FaceEncodingModel(
        employeeId: 'candidate',
        employeeName: 'Candidate',
        encoding: encoding,
        qualityScore: faceDetection.qualityScore,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Score the match
      return _matchScorer.scoreMatch(
        candidate: candidate,
        reference: reference,
        faceQuality: faceDetection.qualityScore,
        customThreshold: customThreshold,
      );
    } catch (e) {
      Logger.error('Failed to match specific employee', error: e);
      return null;
    }
  }

  /// Update employee face encoding
  Future<bool> updateEmployeeEncoding({
    required String employeeId,
    required String employeeName,
    required Uint8List imageData,
    required FaceDetectionResult faceDetection,
    String? photoUrl,
  }) async {
    try {
      // Generate new encoding
      final encoding = await _datasource.generateFaceEncoding(imageData);
      
      if (encoding.isEmpty) {
        Logger.warning('Failed to generate face encoding for update');
        return false;
      }

      // Validate encoding quality
      if (!_matchScorer.isValidEncoding(encoding)) {
        Logger.warning('Generated encoding failed validation');
        return false;
      }

      // Create encoding model
      final encodingModel = FaceEncodingModel(
        employeeId: employeeId,
        employeeName: employeeName,
        encoding: encoding,
        photoUrl: photoUrl,
        qualityScore: faceDetection.qualityScore,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );

      // Save to cache
      await _encodingCache.saveEncoding(encodingModel);

      Logger.info('Updated encoding for employee $employeeName');
      return true;
    } catch (e) {
      Logger.error('Failed to update employee encoding', error: e);
      return false;
    }
  }

  /// Get adaptive threshold for current conditions
  double getAdaptiveThreshold({
    required FaceDetectionResult faceDetection,
    required double lightingQuality,
    bool isIndoor = true,
  }) {
    return _matchScorer.getAdaptiveThreshold(
      faceDetection: faceDetection,
      lightingQuality: lightingQuality,
      isIndoor: isIndoor,
    );
  }

  /// Get match statistics for analysis
  Map<String, dynamic> getMatchStatistics(List<FaceMatchResult> matches) {
    return _matchScorer.getMatchStatistics(matches);
  }

  /// Calculate overall confidence from multiple matches
  double _calculateOverallConfidence(List<FaceMatchResult> matches) {
    if (matches.isEmpty) return 0.0;

    // Use weighted average with more weight on best match
    double weightedSum = 0.0;
    double totalWeight = 0.0;

    for (int i = 0; i < matches.length; i++) {
      final weight = 1.0 / (i + 1); // Decreasing weight for lower matches
      weightedSum += matches[i].combinedConfidence * weight;
      totalWeight += weight;
    }

    return totalWeight > 0 ? (weightedSum / totalWeight) : 0.0;
  }

  /// Calculate liveness score (placeholder)
  Future<double> _calculateLivenessScore(
    Uint8List imageData,
    FaceDetectionResult faceDetection,
  ) async {
    // TODO: Implement actual liveness detection
    // For now, use face quality as a proxy
    return faceDetection.qualityScore * 0.95;
  }

  /// Batch process multiple images for enrollment
  Future<List<bool>> batchEnrollEmployees({
    required List<Map<String, dynamic>> employeeData,
  }) async {
    final results = <bool>[];

    for (final data in employeeData) {
      final success = await updateEmployeeEncoding(
        employeeId: data['employeeId'],
        employeeName: data['employeeName'],
        imageData: data['imageData'],
        faceDetection: data['faceDetection'],
        photoUrl: data['photoUrl'],
      );
      results.add(success);
    }

    return results;
  }

  /// Clear all cached encodings
  Future<void> clearCache() async {
    await _encodingCache.clearCache();
  }

  /// Initialize service and load encodings
  Future<void> initialize() async {
    await _encodingCache.initialize();
    Logger.info('Face recognition service initialized');
  }
}