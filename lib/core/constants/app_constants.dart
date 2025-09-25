class AppConstants {
  static const String appName = 'ANTE Facial Recognition';
  static const String packageName = 'com.ante.facial_recognition';

  // API Configuration
  static const String baseUrl = 'http://100.109.133.12:3000';
  static const String apiPath = '/api/public/manpower';
  static const String apiKeyHeader = 'x-api-key';

  // Face Recognition
  static const double faceMatchThreshold = 0.6;
  static const double livenessThreshold = 0.9;
  static const double qualityThreshold = 0.9;
  static const int faceImageSize = 112;
  static const int embeddingSize = 192; // Updated to match verified MobileFaceNet model

  // Performance
  static const int maxRecognitionTime = 100; // milliseconds
  static const int maxMemoryUsage = 200; // MB
  static const int targetFps = 30;

  // Camera
  static const double cameraResolutionPreset = 0.7; // 0.0 to 1.0
  static const int frameSkipCount = 3; // Process every Nth frame

  // Storage Keys
  static const String deviceIdKey = 'device_id';
  static const String apiKeyStorageKey = 'api_key';
  static const String lastSyncKey = 'last_sync';
  static const String employeeDataKey = 'employee_data';

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration sessionTimeout = Duration(hours: 8);

  // Limits
  static const int maxOfflineQueueSize = 1000;
  static const int maxRetryAttempts = 3;
  static const int maxCacheAge = 7; // days
}