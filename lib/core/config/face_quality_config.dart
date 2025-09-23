/// Configuration constants for face quality scoring and validation
class FaceQualityConfig {
  // Prevent instantiation
  FaceQualityConfig._();

  // ============== Face Angle Thresholds ==============

  /// Maximum allowed rotation angle for face detection (degrees)
  /// Faces beyond this angle receive minimum quality score
  static const double maxRotationAngle = 90.0;

  /// Minimum quality score factor for faces at maximum angle
  /// Ensures even faces at extreme angles get some base score
  static const double minAngleScoreFactor = 0.5;

  // ============== Eye Detection Thresholds ==============

  /// Minimum probability threshold for detecting closed eyes
  /// Below this threshold, eyes are considered closed
  static const double eyeClosedThreshold = 0.2;

  /// Penalty factor applied when eyes are detected as closed
  /// Multiplied with current score (0.9 = 10% penalty)
  static const double eyeClosedPenaltyFactor = 0.9;

  // ============== Overall Quality Thresholds ==============

  /// Minimum quality threshold for considering a face as "good quality"
  /// Used in business logic to determine if face is acceptable for processing
  static const double minQualityThreshold = 0.3;

  // ============== Mock Embedding Generation ==============

  /// Number of image bytes to sample when generating mock embeddings
  /// Used to create consistent but pseudo-random embeddings for testing
  static const int embeddingSeedSampleSize = 100;

  /// Modulo value for seed generation in mock embeddings
  /// Keeps generated values within byte range (0-255)
  static const int embeddingSeedModulo = 256;

  /// Multiplier used in mock embedding generation algorithm
  /// Creates variation in generated embedding values
  static const int embeddingValueMultiplier = 7;

  // ============== Helper Methods ==============

  /// Calculate angle score factor for a given rotation angle
  /// Returns a value between minAngleScoreFactor and 1.0
  static double calculateAngleScoreFactor(double rotationAngle) {
    final normalizedAngle = (rotationAngle.abs() / maxRotationAngle).clamp(0.0, 1.0);
    final scoreReduction = 1.0 - normalizedAngle;
    return (scoreReduction * minAngleScoreFactor) + minAngleScoreFactor;
  }

  /// Check if an eye probability indicates the eye is closed
  static bool isEyeClosed(double? eyeOpenProbability) {
    return eyeOpenProbability != null && eyeOpenProbability < eyeClosedThreshold;
  }

  /// Apply penalty for closed eyes to the current quality score
  static double applyEyeClosedPenalty(double currentScore) {
    return currentScore * eyeClosedPenaltyFactor;
  }
}