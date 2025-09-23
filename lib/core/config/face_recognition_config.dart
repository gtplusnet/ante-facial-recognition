import 'package:flutter/material.dart';

/// Configuration for face recognition system
class FaceRecognitionConfig {
  // ============== Recognition Thresholds ==============

  /// Default threshold for face matching (Euclidean distance)
  /// Lower values mean stricter matching
  static const double defaultMatchThreshold = 0.6;

  /// Strict threshold for high-security scenarios
  static const double strictMatchThreshold = 0.4;

  /// Lenient threshold for low-security scenarios
  static const double lenientMatchThreshold = 0.8;

  /// Threshold for cosine similarity (alternative metric)
  /// Higher values mean better match
  static const double cosineSimilarityThreshold = 0.85;

  // ============== Quality Thresholds ==============

  /// Minimum face quality score for recognition
  static const double minFaceQuality = 0.9;

  /// Minimum confidence for face detection
  static const double minDetectionConfidence = 0.8;

  /// Minimum face size relative to image
  static const double minFaceSize = 0.15;

  /// Maximum face angle for recognition (degrees)
  static const double maxFaceAngle = 30.0;

  // ============== Liveness Detection ==============

  /// Liveness detection threshold
  static const double livenessThreshold = 0.9;

  /// Enable passive liveness detection
  static const bool enableLivenessDetection = true;

  /// Number of frames for liveness analysis
  static const int livenessFrameCount = 5;

  // ============== Processing Settings ==============

  /// Face image size for processing (MobileFaceNet input)
  static const int faceImageSize = 112;

  /// Face embedding dimensions (MobileFaceNet output)
  static const int embeddingDimensions = 128;

  /// Maximum faces to detect in a frame
  static const int maxFacesToDetect = 5;

  /// Frame skip interval for performance
  static const int frameSkipInterval = 3;

  /// Enable GPU acceleration
  static const bool useGpuAcceleration = true;

  // ============== Matching Settings ==============

  /// Number of top matches to return
  static const int topKMatches = 3;

  /// Cache face encodings in memory
  static const bool cacheEncodings = true;

  /// Maximum cache size (number of encodings)
  static const int maxCacheSize = 1000;

  /// Cache expiry time (hours)
  static const int cacheExpiryHours = 24;

  // ============== Performance Settings ==============

  /// Process images in isolate
  static const bool useIsolateProcessing = true;

  /// Image processing quality (0.0 - 1.0)
  static const double imageProcessingQuality = 0.8;

  /// Maximum processing time per frame (milliseconds)
  static const int maxProcessingTimeMs = 200;

  /// Batch size for encoding updates
  static const int encodingBatchSize = 10;

  // ============== Security Settings ==============

  /// Enable anti-spoofing checks
  static const bool enableAntiSpoofing = true;

  /// Store face images (privacy consideration)
  static const bool storeFaceImages = false;

  /// Encrypt face encodings
  static const bool encryptEncodings = true;

  /// Require minimum lighting conditions
  static const bool requireGoodLighting = true;

  // ============== User Experience ==============

  /// Show face detection overlay
  static const bool showFaceOverlay = true;

  /// Enable sound feedback
  static const bool enableSoundFeedback = true;

  /// Enable haptic feedback
  static const bool enableHapticFeedback = true;

  /// Auto-capture when face is detected
  static const bool autoCapture = true;

  /// Auto-capture delay (seconds)
  static const int autoCaptureDelaySeconds = 2;

  // ============== Adaptive Thresholds ==============

  /// Get adaptive threshold based on environment
  static double getAdaptiveThreshold({
    required double lightingQuality,
    required double faceQuality,
    required bool isIndoor,
  }) {
    double threshold = defaultMatchThreshold;

    // Adjust for poor lighting
    if (lightingQuality < 0.5) {
      threshold += 0.1;
    }

    // Adjust for face quality
    if (faceQuality < 0.9) {
      threshold += 0.05;
    }

    // Adjust for outdoor conditions
    if (!isIndoor) {
      threshold += 0.05;
    }

    // Clamp to valid range
    return threshold.clamp(strictMatchThreshold, lenientMatchThreshold);
  }

  /// Get confidence score from distance
  static double getConfidenceScore(double distance) {
    if (distance <= 0) return 1.0;
    if (distance >= 1.0) return 0.0;

    // Convert distance to confidence (inverse relationship)
    // Using exponential decay for smoother confidence curve
    return (1.0 - distance).clamp(0.0, 1.0);
  }

  /// Check if match is valid
  static bool isValidMatch(double distance, {double? customThreshold}) {
    final threshold = customThreshold ?? defaultMatchThreshold;
    return distance <= threshold;
  }

  /// Get match quality rating
  static MatchQuality getMatchQuality(double distance) {
    if (distance <= strictMatchThreshold) {
      return MatchQuality.excellent;
    } else if (distance <= defaultMatchThreshold) {
      return MatchQuality.good;
    } else if (distance <= lenientMatchThreshold) {
      return MatchQuality.fair;
    } else {
      return MatchQuality.poor;
    }
  }

  /// Calculate combined confidence from multiple metrics
  static double getCombinedConfidence({
    required double euclideanDistance,
    required double cosineSimilarity,
    required double faceQuality,
  }) {
    // Weight factors for each metric
    const double euclideanWeight = 0.5;
    const double cosineWeight = 0.3;
    const double qualityWeight = 0.2;

    // Convert Euclidean distance to confidence
    final euclideanConfidence = getConfidenceScore(euclideanDistance);

    // Calculate weighted average
    final combinedConfidence =
      (euclideanConfidence * euclideanWeight) +
      (cosineSimilarity * cosineWeight) +
      (faceQuality * qualityWeight);

    return combinedConfidence.clamp(0.0, 1.0);
  }
}

/// Match quality enumeration
enum MatchQuality {
  excellent,
  good,
  fair,
  poor,
}

/// Extension for match quality
extension MatchQualityExtension on MatchQuality {
  String get label {
    switch (this) {
      case MatchQuality.excellent:
        return 'Excellent Match';
      case MatchQuality.good:
        return 'Good Match';
      case MatchQuality.fair:
        return 'Fair Match';
      case MatchQuality.poor:
        return 'Poor Match';
    }
  }

  Color get color {
    switch (this) {
      case MatchQuality.excellent:
        return const Color(0xFF4CAF50); // Green
      case MatchQuality.good:
        return const Color(0xFF8BC34A); // Light Green
      case MatchQuality.fair:
        return const Color(0xFFFFC107); // Amber
      case MatchQuality.poor:
        return const Color(0xFFFF5722); // Deep Orange
    }
  }

  double get minConfidence {
    switch (this) {
      case MatchQuality.excellent:
        return 0.95;
      case MatchQuality.good:
        return 0.85;
      case MatchQuality.fair:
        return 0.70;
      case MatchQuality.poor:
        return 0.0;
    }
  }
}