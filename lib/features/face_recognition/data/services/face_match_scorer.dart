import 'dart:math' as math;

import 'package:injectable/injectable.dart';

import '../../../../core/config/face_recognition_config.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/data/models/face_encoding_model.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';

/// Match result with confidence scoring
class FaceMatchResult {
  final String employeeId;
  final String employeeName;
  final double euclideanDistance;
  final double cosineSimilarity;
  final double combinedConfidence;
  final double faceQuality;
  final MatchQuality matchQuality;
  final Map<String, double> scoreBreakdown;
  final DateTime timestamp;

  FaceMatchResult({
    required this.employeeId,
    required this.employeeName,
    required this.euclideanDistance,
    required this.cosineSimilarity,
    required this.combinedConfidence,
    required this.faceQuality,
    required this.matchQuality,
    required this.scoreBreakdown,
    required this.timestamp,
  });

  bool get isMatch => FaceRecognitionConfig.isValidMatch(euclideanDistance);

  @override
  String toString() {
    return 'FaceMatchResult('
        'employee: $employeeName, '
        'confidence: ${(combinedConfidence * 100).toStringAsFixed(1)}%, '
        'quality: ${matchQuality.label})';
  }
}

/// Service for scoring face match confidence
@singleton
class FaceMatchScorer {
  /// Score a single match
  FaceMatchResult scoreMatch({
    required FaceEncodingModel candidate,
    required FaceEncodingModel reference,
    required double faceQuality,
    double? customThreshold,
  }) {
    // Calculate distance metrics
    final euclideanDistance = _calculateEuclideanDistance(
      candidate.encoding,
      reference.encoding,
    );

    final cosineSimilarity = _calculateCosineSimilarity(
      candidate.encoding,
      reference.encoding,
    );

    // Calculate component scores
    final distanceScore = _getDistanceScore(euclideanDistance);
    final similarityScore = _getSimilarityScore(cosineSimilarity);
    final qualityScore = _getQualityScore(faceQuality, reference.qualityScore);

    // Calculate combined confidence
    final combinedConfidence = FaceRecognitionConfig.getCombinedConfidence(
      euclideanDistance: euclideanDistance,
      cosineSimilarity: cosineSimilarity,
      faceQuality: faceQuality,
    );

    // Determine match quality
    final matchQuality = FaceRecognitionConfig.getMatchQuality(euclideanDistance);

    // Create score breakdown
    final scoreBreakdown = {
      'distance': distanceScore,
      'similarity': similarityScore,
      'face_quality': qualityScore,
      'encoding_quality': reference.qualityScore,
      'combined': combinedConfidence,
    };

    Logger.debug(
      'Match scored - Employee: ${reference.employeeName}, '
      'Distance: ${euclideanDistance.toStringAsFixed(3)}, '
      'Confidence: ${(combinedConfidence * 100).toStringAsFixed(1)}%',
    );

    return FaceMatchResult(
      employeeId: reference.employeeId,
      employeeName: reference.employeeName,
      euclideanDistance: euclideanDistance,
      cosineSimilarity: cosineSimilarity,
      combinedConfidence: combinedConfidence,
      faceQuality: faceQuality,
      matchQuality: matchQuality,
      scoreBreakdown: scoreBreakdown,
      timestamp: DateTime.now(),
    );
  }

  /// Score multiple candidates and return top-K matches
  List<FaceMatchResult> scoreMultiple({
    required FaceEncodingModel candidate,
    required List<FaceEncodingModel> references,
    required double faceQuality,
    int topK = FaceRecognitionConfig.topKMatches,
    double? customThreshold,
  }) {
    if (references.isEmpty) {
      Logger.warning('No reference encodings to match against');
      return [];
    }

    // Score all candidates
    final scores = references.map((reference) {
      return scoreMatch(
        candidate: candidate,
        reference: reference,
        faceQuality: faceQuality,
        customThreshold: customThreshold,
      );
    }).toList();

    // Sort by combined confidence (descending)
    scores.sort((a, b) => b.combinedConfidence.compareTo(a.combinedConfidence));

    // Filter by threshold if needed
    final threshold = customThreshold ?? FaceRecognitionConfig.defaultMatchThreshold;
    final validMatches = scores.where((s) => s.euclideanDistance <= threshold).toList();

    // Return top-K matches
    return validMatches.take(topK).toList();
  }

  /// Find best match from multiple candidates
  FaceMatchResult? findBestMatch({
    required FaceEncodingModel candidate,
    required List<FaceEncodingModel> references,
    required double faceQuality,
    double? customThreshold,
  }) {
    final matches = scoreMultiple(
      candidate: candidate,
      references: references,
      faceQuality: faceQuality,
      topK: 1,
      customThreshold: customThreshold,
    );

    return matches.isNotEmpty ? matches.first : null;
  }

  /// Check if match meets quality requirements
  bool isQualityMatch(FaceMatchResult match) {
    return match.matchQuality != MatchQuality.poor &&
        match.combinedConfidence >= match.matchQuality.minConfidence;
  }

  /// Get adaptive threshold based on conditions
  double getAdaptiveThreshold({
    required FaceDetectionResult faceDetection,
    required double lightingQuality,
    bool isIndoor = true,
  }) {
    return FaceRecognitionConfig.getAdaptiveThreshold(
      lightingQuality: lightingQuality,
      faceQuality: faceDetection.qualityScore,
      isIndoor: isIndoor,
    );
  }

  /// Calculate Euclidean distance between embeddings
  double _calculateEuclideanDistance(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embedding2.length) {
      Logger.error('Embedding size mismatch: ${embedding1.length} vs ${embedding2.length}');
      return double.infinity;
    }

    double sum = 0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      sum += diff * diff;
    }

    return math.sqrt(sum / embedding1.length);
  }

  /// Calculate cosine similarity between embeddings
  double _calculateCosineSimilarity(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embedding2.length) {
      return 0;
    }

    double dotProduct = 0;
    double norm1 = 0;
    double norm2 = 0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    if (norm1 == 0 || norm2 == 0) return 0;

    return dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
  }

  /// Get distance-based score (0-1, higher is better)
  double _getDistanceScore(double distance) {
    if (distance <= 0) return 1.0;
    if (distance >= 1.0) return 0.0;

    // Exponential decay for smoother scoring
    return math.exp(-2 * distance);
  }

  /// Get similarity-based score (0-1, higher is better)
  double _getSimilarityScore(double similarity) {
    // Cosine similarity is already in range [-1, 1]
    // Convert to [0, 1] range
    return (similarity + 1) / 2;
  }

  /// Get quality-based score combining face and encoding quality
  double _getQualityScore(double faceQuality, double encodingQuality) {
    // Weight face quality more heavily as it's current
    const double faceWeight = 0.7;
    const double encodingWeight = 0.3;

    return (faceQuality * faceWeight) + (encodingQuality * encodingWeight);
  }

  /// Get match statistics for analysis
  Map<String, dynamic> getMatchStatistics(List<FaceMatchResult> matches) {
    if (matches.isEmpty) {
      return {
        'count': 0,
        'avg_confidence': 0.0,
        'avg_distance': 0.0,
        'quality_distribution': {},
      };
    }

    final avgConfidence = matches
            .map((m) => m.combinedConfidence)
            .reduce((a, b) => a + b) /
        matches.length;

    final avgDistance = matches
            .map((m) => m.euclideanDistance)
            .reduce((a, b) => a + b) /
        matches.length;

    final qualityDistribution = <MatchQuality, int>{};
    for (final match in matches) {
      qualityDistribution[match.matchQuality] =
          (qualityDistribution[match.matchQuality] ?? 0) + 1;
    }

    return {
      'count': matches.length,
      'avg_confidence': avgConfidence,
      'avg_distance': avgDistance,
      'quality_distribution': qualityDistribution.map(
        (k, v) => MapEntry(k.label, v),
      ),
      'best_match': matches.isNotEmpty ? matches.first.employeeName : null,
      'best_confidence': matches.isNotEmpty ? matches.first.combinedConfidence : 0.0,
    };
  }

  /// Validate encoding quality before matching
  bool isValidEncoding(List<double> encoding) {
    if (encoding.isEmpty) return false;
    if (encoding.length != FaceRecognitionConfig.embeddingDimensions) return false;

    // Check for NaN or infinite values
    for (final value in encoding) {
      if (value.isNaN || value.isInfinite) return false;
    }

    // Check if encoding has reasonable values (not all zeros)
    final sum = encoding.reduce((a, b) => a + b);
    if (sum.abs() < 0.0001) return false;

    return true;
  }

  /// Apply post-processing to improve match accuracy
  FaceMatchResult? applyPostProcessing(
    FaceMatchResult match, {
    required bool requireLiveness,
    required double livenessScore,
    required bool requireGoodLighting,
    required double lightingQuality,
  }) {
    // Check liveness if required
    if (requireLiveness && livenessScore < FaceRecognitionConfig.livenessThreshold) {
      Logger.warning('Match rejected: Failed liveness check');
      return null;
    }

    // Check lighting if required
    if (requireGoodLighting && lightingQuality < 0.5) {
      Logger.warning('Match rejected: Poor lighting conditions');
      return null;
    }

    // Apply confidence boost for high-quality conditions
    if (lightingQuality > 0.8 && match.faceQuality > 0.9) {
      final boostedConfidence = math.min(1.0, match.combinedConfidence * 1.1);

      return FaceMatchResult(
        employeeId: match.employeeId,
        employeeName: match.employeeName,
        euclideanDistance: match.euclideanDistance,
        cosineSimilarity: match.cosineSimilarity,
        combinedConfidence: boostedConfidence,
        faceQuality: match.faceQuality,
        matchQuality: match.matchQuality,
        scoreBreakdown: match.scoreBreakdown,
        timestamp: match.timestamp,
      );
    }

    return match;
  }
}