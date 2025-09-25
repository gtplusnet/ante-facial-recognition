/// Constants for face recognition thresholds and configuration
class FaceRecognitionConstants {
  // Prevent instantiation
  FaceRecognitionConstants._();

  // Face matching thresholds
  static const double faceMatchThreshold = 0.6; // Euclidean distance threshold
  static const double qualityThreshold = 0.9; // Minimum face quality score
  static const double livenessThreshold = 0.9; // Liveness detection confidence

  // Model dimensions
  static const int faceSize = 112; // MobileFaceNet input size (112x112)
  static const int embeddingSize = 192; // Output embedding dimensions - verified MobileFaceNet model

  // Performance thresholds
  static const double highConfidenceThreshold = 0.85;
  static const double mediumConfidenceThreshold = 0.70;
  static const double lowConfidenceThreshold = 0.50;

  // Processing parameters
  static const int maxDetectionRetries = 3;
  static const int frameSkipCount = 5; // Process every 5th frame
  static const Duration processingTimeout = Duration(seconds: 5);

  // Image processing
  static const double minFaceAreaRatio = 0.1; // Minimum face area relative to image
  static const double maxFaceAreaRatio = 0.8; // Maximum face area relative to image
  static const double faceAspectRatioTolerance = 0.3; // Face aspect ratio variance

  // Cache and storage
  static const int maxCachedEmbeddings = 1000;
  static const Duration embeddingCacheExpiry = Duration(hours: 24);
  static const int maxOfflineQueueSize = 100;

  // API timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Background processing
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration cleanupInterval = Duration(days: 1);
  static const int maxBackgroundTasks = 5;

  // UI feedback
  static const Duration feedbackDisplayDuration = Duration(seconds: 3);
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const double overlayOpacity = 0.8;

  // Recognition states
  static const Duration scanningTimeout = Duration(seconds: 10);
  static const Duration verificationTimeout = Duration(seconds: 5);
  static const int maxConsecutiveFailures = 3;
}