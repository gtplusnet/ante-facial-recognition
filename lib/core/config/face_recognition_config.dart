import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

/// Centralized configuration for face recognition parameters
/// Allows runtime adjustment of thresholds for testing and optimization
class FaceRecognitionConfig {
  // Singleton pattern for global access
  static final FaceRecognitionConfig _instance = FaceRecognitionConfig._internal();
  factory FaceRecognitionConfig() => _instance;
  FaceRecognitionConfig._internal();

  // ========== Face Matching Thresholds ==========
  /// Confidence threshold for face matching (0.0 - 1.0)
  /// Higher values require closer matches
  double confidenceThreshold = 0.7;

  /// Minimum face quality score required for processing (0.0 - 1.0)
  /// Lower quality faces will be rejected
  double qualityThreshold = 0.8;

  /// Maximum Euclidean distance for face matching
  /// Lower values require closer matches
  /// Updated to 1.0 based on MobileFaceNet typical thresholds
  double faceMatchDistance = 1.0;

  // ========== Processing Parameters ==========
  /// Maximum time allowed for face processing (milliseconds)
  int maxProcessingTimeMs = 1000;

  /// Number of camera frames to skip between processing
  /// Higher values reduce CPU usage but may miss faces
  int frameSkipCount = 5;

  /// Processing interval between frames (milliseconds)
  int processingIntervalMs = 2000;

  // ========== Face Detection Parameters ==========
  /// Minimum face size as percentage of image (0.0 - 1.0)
  double minFaceSize = 0.05; // 5% of image

  /// Minimum face area ratio relative to image
  double minFaceAreaRatio = 0.1;

  /// Maximum face area ratio relative to image
  double maxFaceAreaRatio = 0.8;

  // ========== Quality Calculation Weights ==========
  /// Weight for face size score in quality calculation
  double sizeScoreWeight = 0.7;

  /// Weight for face center position score in quality calculation
  double centerScoreWeight = 0.3;

  /// Power factor for size score calculation (gentler penalties)
  double sizeScorePower = 0.7;

  // ========== Recognition Cooldowns ==========
  /// Cooldown period after successful recognition
  Duration recognitionCooldown = const Duration(seconds: 5);

  /// Cooldown period after failed recognition
  Duration failedRecognitionCooldown = const Duration(seconds: 3);

  // ========== Error Handling ==========
  /// Maximum consecutive errors before pausing
  int maxConsecutiveErrors = 5;

  /// Cooldown duration after max errors reached
  Duration errorCooldownDuration = const Duration(seconds: 10);

  /// Maximum camera restart attempts
  int maxCameraRestarts = 3;

  // ========== UI Feedback ==========
  /// Duration to display feedback messages
  Duration feedbackDisplayDuration = const Duration(seconds: 3);

  /// Enable/disable auto-dismiss for dialogs
  bool enableAutoDialogDismiss = true;

  /// Auto-dismiss timer for dialogs (seconds)
  int autoDialogDismissSeconds = 5;

  // ========== Storage Keys ==========
  static const String _storagePrefix = 'face_recognition_config_';

  /// Update configuration values
  void updateConfig({
    double? confidenceThreshold,
    double? qualityThreshold,
    double? faceMatchDistance,
    int? maxProcessingTimeMs,
    int? frameSkipCount,
    int? processingIntervalMs,
    double? minFaceSize,
    double? minFaceAreaRatio,
    double? maxFaceAreaRatio,
    double? sizeScoreWeight,
    double? centerScoreWeight,
    double? sizeScorePower,
    Duration? recognitionCooldown,
    Duration? failedRecognitionCooldown,
    int? maxConsecutiveErrors,
    Duration? errorCooldownDuration,
    int? maxCameraRestarts,
    Duration? feedbackDisplayDuration,
    bool? enableAutoDialogDismiss,
    int? autoDialogDismissSeconds,
  }) {
    if (confidenceThreshold != null) this.confidenceThreshold = confidenceThreshold;
    if (qualityThreshold != null) this.qualityThreshold = qualityThreshold;
    if (faceMatchDistance != null) this.faceMatchDistance = faceMatchDistance;
    if (maxProcessingTimeMs != null) this.maxProcessingTimeMs = maxProcessingTimeMs;
    if (frameSkipCount != null) this.frameSkipCount = frameSkipCount;
    if (processingIntervalMs != null) this.processingIntervalMs = processingIntervalMs;
    if (minFaceSize != null) this.minFaceSize = minFaceSize;
    if (minFaceAreaRatio != null) this.minFaceAreaRatio = minFaceAreaRatio;
    if (maxFaceAreaRatio != null) this.maxFaceAreaRatio = maxFaceAreaRatio;
    if (sizeScoreWeight != null) this.sizeScoreWeight = sizeScoreWeight;
    if (centerScoreWeight != null) this.centerScoreWeight = centerScoreWeight;
    if (sizeScorePower != null) this.sizeScorePower = sizeScorePower;
    if (recognitionCooldown != null) this.recognitionCooldown = recognitionCooldown;
    if (failedRecognitionCooldown != null) this.failedRecognitionCooldown = failedRecognitionCooldown;
    if (maxConsecutiveErrors != null) this.maxConsecutiveErrors = maxConsecutiveErrors;
    if (errorCooldownDuration != null) this.errorCooldownDuration = errorCooldownDuration;
    if (maxCameraRestarts != null) this.maxCameraRestarts = maxCameraRestarts;
    if (feedbackDisplayDuration != null) this.feedbackDisplayDuration = feedbackDisplayDuration;
    if (enableAutoDialogDismiss != null) this.enableAutoDialogDismiss = enableAutoDialogDismiss;
    if (autoDialogDismissSeconds != null) this.autoDialogDismissSeconds = autoDialogDismissSeconds;

    Logger.info('Face recognition config updated');
    logCurrentConfig();
  }

  /// Load configuration from persistent storage
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      confidenceThreshold = prefs.getDouble('${_storagePrefix}confidenceThreshold') ?? confidenceThreshold;
      qualityThreshold = prefs.getDouble('${_storagePrefix}qualityThreshold') ?? qualityThreshold;
      faceMatchDistance = prefs.getDouble('${_storagePrefix}faceMatchDistance') ?? faceMatchDistance;
      maxProcessingTimeMs = prefs.getInt('${_storagePrefix}maxProcessingTimeMs') ?? maxProcessingTimeMs;
      frameSkipCount = prefs.getInt('${_storagePrefix}frameSkipCount') ?? frameSkipCount;
      processingIntervalMs = prefs.getInt('${_storagePrefix}processingIntervalMs') ?? processingIntervalMs;
      minFaceSize = prefs.getDouble('${_storagePrefix}minFaceSize') ?? minFaceSize;
      minFaceAreaRatio = prefs.getDouble('${_storagePrefix}minFaceAreaRatio') ?? minFaceAreaRatio;
      maxFaceAreaRatio = prefs.getDouble('${_storagePrefix}maxFaceAreaRatio') ?? maxFaceAreaRatio;
      sizeScoreWeight = prefs.getDouble('${_storagePrefix}sizeScoreWeight') ?? sizeScoreWeight;
      centerScoreWeight = prefs.getDouble('${_storagePrefix}centerScoreWeight') ?? centerScoreWeight;
      sizeScorePower = prefs.getDouble('${_storagePrefix}sizeScorePower') ?? sizeScorePower;
      maxConsecutiveErrors = prefs.getInt('${_storagePrefix}maxConsecutiveErrors') ?? maxConsecutiveErrors;
      maxCameraRestarts = prefs.getInt('${_storagePrefix}maxCameraRestarts') ?? maxCameraRestarts;
      enableAutoDialogDismiss = prefs.getBool('${_storagePrefix}enableAutoDialogDismiss') ?? enableAutoDialogDismiss;
      autoDialogDismissSeconds = prefs.getInt('${_storagePrefix}autoDialogDismissSeconds') ?? autoDialogDismissSeconds;

      // Duration values stored as milliseconds
      final recognitionCooldownMs = prefs.getInt('${_storagePrefix}recognitionCooldownMs');
      if (recognitionCooldownMs != null) {
        recognitionCooldown = Duration(milliseconds: recognitionCooldownMs);
      }

      final failedRecognitionCooldownMs = prefs.getInt('${_storagePrefix}failedRecognitionCooldownMs');
      if (failedRecognitionCooldownMs != null) {
        failedRecognitionCooldown = Duration(milliseconds: failedRecognitionCooldownMs);
      }

      final errorCooldownDurationMs = prefs.getInt('${_storagePrefix}errorCooldownDurationMs');
      if (errorCooldownDurationMs != null) {
        errorCooldownDuration = Duration(milliseconds: errorCooldownDurationMs);
      }

      final feedbackDisplayDurationMs = prefs.getInt('${_storagePrefix}feedbackDisplayDurationMs');
      if (feedbackDisplayDurationMs != null) {
        feedbackDisplayDuration = Duration(milliseconds: feedbackDisplayDurationMs);
      }

      Logger.info('Face recognition config loaded from storage');
      logCurrentConfig();
    } catch (e) {
      Logger.error('Failed to load config from storage', error: e);
    }
  }

  /// Save configuration to persistent storage
  Future<void> saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble('${_storagePrefix}confidenceThreshold', confidenceThreshold);
      await prefs.setDouble('${_storagePrefix}qualityThreshold', qualityThreshold);
      await prefs.setDouble('${_storagePrefix}faceMatchDistance', faceMatchDistance);
      await prefs.setInt('${_storagePrefix}maxProcessingTimeMs', maxProcessingTimeMs);
      await prefs.setInt('${_storagePrefix}frameSkipCount', frameSkipCount);
      await prefs.setInt('${_storagePrefix}processingIntervalMs', processingIntervalMs);
      await prefs.setDouble('${_storagePrefix}minFaceSize', minFaceSize);
      await prefs.setDouble('${_storagePrefix}minFaceAreaRatio', minFaceAreaRatio);
      await prefs.setDouble('${_storagePrefix}maxFaceAreaRatio', maxFaceAreaRatio);
      await prefs.setDouble('${_storagePrefix}sizeScoreWeight', sizeScoreWeight);
      await prefs.setDouble('${_storagePrefix}centerScoreWeight', centerScoreWeight);
      await prefs.setDouble('${_storagePrefix}sizeScorePower', sizeScorePower);
      await prefs.setInt('${_storagePrefix}maxConsecutiveErrors', maxConsecutiveErrors);
      await prefs.setInt('${_storagePrefix}maxCameraRestarts', maxCameraRestarts);
      await prefs.setBool('${_storagePrefix}enableAutoDialogDismiss', enableAutoDialogDismiss);
      await prefs.setInt('${_storagePrefix}autoDialogDismissSeconds', autoDialogDismissSeconds);

      // Save durations as milliseconds
      await prefs.setInt('${_storagePrefix}recognitionCooldownMs', recognitionCooldown.inMilliseconds);
      await prefs.setInt('${_storagePrefix}failedRecognitionCooldownMs', failedRecognitionCooldown.inMilliseconds);
      await prefs.setInt('${_storagePrefix}errorCooldownDurationMs', errorCooldownDuration.inMilliseconds);
      await prefs.setInt('${_storagePrefix}feedbackDisplayDurationMs', feedbackDisplayDuration.inMilliseconds);

      Logger.info('Face recognition config saved to storage');
    } catch (e) {
      Logger.error('Failed to save config to storage', error: e);
    }
  }

  /// Reset configuration to default values
  void resetToDefaults() {
    confidenceThreshold = 0.7;
    qualityThreshold = 0.8;
    faceMatchDistance = 1.0;  // Updated to reasonable threshold for MobileFaceNet
    maxProcessingTimeMs = 1000;
    frameSkipCount = 5;
    processingIntervalMs = 2000;
    minFaceSize = 0.05;
    minFaceAreaRatio = 0.1;
    maxFaceAreaRatio = 0.8;
    sizeScoreWeight = 0.7;
    centerScoreWeight = 0.3;
    sizeScorePower = 0.7;
    recognitionCooldown = const Duration(seconds: 5);
    failedRecognitionCooldown = const Duration(seconds: 3);
    maxConsecutiveErrors = 5;
    errorCooldownDuration = const Duration(seconds: 10);
    maxCameraRestarts = 3;
    feedbackDisplayDuration = const Duration(seconds: 3);
    enableAutoDialogDismiss = true;
    autoDialogDismissSeconds = 5;

    Logger.info('Face recognition config reset to defaults');
    logCurrentConfig();
  }

  /// Log current configuration values
  void logCurrentConfig() {
    Logger.info('=== Face Recognition Configuration ===');
    Logger.info('Confidence Threshold: $confidenceThreshold');
    Logger.info('Quality Threshold: $qualityThreshold');
    Logger.info('Face Match Distance: $faceMatchDistance');
    Logger.info('Max Processing Time: ${maxProcessingTimeMs}ms');
    Logger.info('Frame Skip Count: $frameSkipCount');
    Logger.info('Processing Interval: ${processingIntervalMs}ms');
    Logger.info('Min Face Size: ${(minFaceSize * 100).toStringAsFixed(1)}%');
    Logger.info('Face Area Ratio: ${(minFaceAreaRatio * 100).toStringAsFixed(1)}% - ${(maxFaceAreaRatio * 100).toStringAsFixed(1)}%');
    Logger.info('Quality Weights - Size: ${(sizeScoreWeight * 100).toStringAsFixed(0)}%, Center: ${(centerScoreWeight * 100).toStringAsFixed(0)}%');
    Logger.info('Recognition Cooldown: ${recognitionCooldown.inSeconds}s');
    Logger.info('Failed Recognition Cooldown: ${failedRecognitionCooldown.inSeconds}s');
    Logger.info('=====================================');
  }

  // ========== Legacy Properties (for backward compatibility) ==========
  // These are used by old code that hasn't been migrated yet
  static const double defaultMatchThreshold = 1.0;  // Updated to match new threshold
  static const int topKMatches = 3;
  static const bool enableLivenessDetection = false;
  static const double livenessThreshold = 0.9;
  static const int embeddingDimensions = 192; // Updated for verified MobileFaceNet model
  static const bool requireGoodLighting = false;

  // Legacy methods for old code compatibility
  static bool isValidMatch(double distance, {double? customThreshold}) {
    final threshold = customThreshold ?? defaultMatchThreshold;
    return distance <= threshold;
  }

  static double getCombinedConfidence({
    required double euclideanDistance,
    required double cosineSimilarity,
    required double faceQuality,
  }) {
    const double euclideanWeight = 0.5;
    const double cosineWeight = 0.3;
    const double qualityWeight = 0.2;

    final euclideanConfidence = 1.0 - euclideanDistance.clamp(0.0, 1.0);

    return (euclideanConfidence * euclideanWeight) +
           (cosineSimilarity * cosineWeight) +
           (faceQuality * qualityWeight);
  }

  static MatchQuality getMatchQuality(double distance) {
    if (distance <= 0.4) {
      return MatchQuality.excellent;
    } else if (distance <= 0.6) {
      return MatchQuality.good;
    } else if (distance <= 0.8) {
      return MatchQuality.fair;
    } else {
      return MatchQuality.poor;
    }
  }

  static double getAdaptiveThreshold({
    required double lightingQuality,
    required double faceQuality,
    required bool isIndoor,
  }) {
    double threshold = defaultMatchThreshold;

    if (lightingQuality < 0.5) {
      threshold += 0.1;
    }

    if (faceQuality < 0.9) {
      threshold += 0.05;
    }

    if (!isIndoor) {
      threshold += 0.05;
    }

    return threshold.clamp(0.4, 0.8);
  }
}

/// Match quality enumeration (for backward compatibility)
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