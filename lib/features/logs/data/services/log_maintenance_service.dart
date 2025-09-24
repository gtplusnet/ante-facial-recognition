import 'dart:async';

import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import 'face_recognition_log_service.dart';

@singleton
class LogMaintenanceService {
  final FaceRecognitionLogService _logService;
  Timer? _maintenanceTimer;

  static const Duration _maintenanceInterval = Duration(hours: 6); // Run every 6 hours
  static const int _maxStorageMB = 100; // 100MB max storage
  static const Duration _maxLogAge = Duration(days: 30); // Keep logs for 30 days max

  LogMaintenanceService({
    required FaceRecognitionLogService logService,
  }) : _logService = logService;

  /// Start the maintenance service
  void startMaintenance() {
    Logger.info('Starting log maintenance service...');

    // Run initial maintenance
    _runMaintenance();

    // Schedule periodic maintenance
    _maintenanceTimer = Timer.periodic(_maintenanceInterval, (_) {
      _runMaintenance();
    });

    Logger.info('Log maintenance service started with ${_maintenanceInterval.inHours}h interval');
  }

  /// Stop the maintenance service
  void stopMaintenance() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    Logger.info('Log maintenance service stopped');
  }

  /// Run maintenance tasks
  Future<void> _runMaintenance() async {
    try {
      Logger.info('Running log maintenance tasks...');

      final storageInfo = await _logService.getStorageInfo();
      final storageMB = storageInfo.totalStorageBytes / (1024 * 1024);

      Logger.info('Current storage usage: ${storageMB.toStringAsFixed(2)}MB (${storageInfo.totalLogs} logs)');

      // Check if storage limit is exceeded
      if (storageMB > _maxStorageMB) {
        Logger.warning('Storage limit exceeded (${storageMB.toStringAsFixed(2)}MB > ${_maxStorageMB}MB), cleaning up...');
        await _performStorageCleanup();
      }

      // Clean up old logs
      await _cleanupOldLogs();

      final newStorageInfo = await _logService.getStorageInfo();
      final newStorageMB = newStorageInfo.totalStorageBytes / (1024 * 1024);

      Logger.success('Maintenance completed. Storage: ${newStorageMB.toStringAsFixed(2)}MB (${newStorageInfo.totalLogs} logs)');

    } catch (e) {
      Logger.error('Failed to run log maintenance', error: e);
    }
  }

  /// Force run maintenance (for testing or manual cleanup)
  Future<void> runMaintenanceNow() async {
    Logger.info('Running manual log maintenance...');
    await _runMaintenance();
  }

  /// Clean up storage when limit is exceeded
  Future<void> _performStorageCleanup() async {
    try {
      // Get oldest logs to delete
      final oldLogs = await _logService.getLogs(
        limit: 500, // Get a batch to clean
        // TODO: Add orderBy oldest first functionality to service
      );

      if (oldLogs.isEmpty) {
        Logger.info('No logs to clean up');
        return;
      }

      // Calculate how many logs to delete to get under storage limit
      final storageInfo = await _logService.getStorageInfo();
      final avgLogSize = storageInfo.totalStorageBytes / storageInfo.totalLogs;
      final excessBytes = (storageInfo.totalStorageBytes / (1024 * 1024)) - (_maxStorageMB * 0.8); // Target 80% of limit
      final logsToDelete = (excessBytes * 1024 * 1024 / avgLogSize).ceil();

      Logger.info('Planning to delete approximately $logsToDelete logs to free up space');

      // For now, clear a percentage of old logs
      // In a more sophisticated implementation, we would delete specific old logs
      if (logsToDelete > oldLogs.length * 0.5) {
        Logger.warning('Storage critically full, clearing significant amount of logs');
        await _logService.clearAllLogs();
      }

    } catch (e) {
      Logger.error('Failed to perform storage cleanup', error: e);
    }
  }

  /// Clean up logs older than the maximum age
  Future<void> _cleanupOldLogs() async {
    try {
      // This would require adding date-based cleanup to the log service
      // For now, the automatic cleanup in the log service handles this
      final cutoffDate = DateTime.now().subtract(_maxLogAge);
      Logger.debug('Would clean up logs older than $cutoffDate (not implemented yet)');
    } catch (e) {
      Logger.error('Failed to cleanup old logs', error: e);
    }
  }

  /// Get maintenance statistics
  Future<LogMaintenanceStats> getMaintenanceStats() async {
    try {
      final storageInfo = await _logService.getStorageInfo();
      final logStats = await _logService.getLogStats();

      return LogMaintenanceStats(
        totalLogs: storageInfo.totalLogs,
        totalStorageBytes: storageInfo.totalStorageBytes,
        totalStorageMB: storageInfo.totalStorageBytes / (1024 * 1024),
        storagePercentUsed: (storageInfo.totalStorageBytes / (1024 * 1024)) / _maxStorageMB,
        averageLogSizeBytes: storageInfo.totalLogs > 0
            ? storageInfo.totalStorageBytes ~/ storageInfo.totalLogs
            : 0,
        successRate: logStats.successRate,
        isMaintenanceRunning: _maintenanceTimer != null,
        nextMaintenanceIn: _maintenanceTimer != null
            ? _maintenanceInterval
            : null,
      );
    } catch (e) {
      Logger.error('Failed to get maintenance stats', error: e);
      return LogMaintenanceStats(
        totalLogs: 0,
        totalStorageBytes: 0,
        totalStorageMB: 0.0,
        storagePercentUsed: 0.0,
        averageLogSizeBytes: 0,
        successRate: 0.0,
        isMaintenanceRunning: false,
        nextMaintenanceIn: null,
      );
    }
  }

  /// Dispose resources
  void dispose() {
    stopMaintenance();
  }
}

/// Statistics for log maintenance
class LogMaintenanceStats {
  final int totalLogs;
  final int totalStorageBytes;
  final double totalStorageMB;
  final double storagePercentUsed;
  final int averageLogSizeBytes;
  final double successRate;
  final bool isMaintenanceRunning;
  final Duration? nextMaintenanceIn;

  const LogMaintenanceStats({
    required this.totalLogs,
    required this.totalStorageBytes,
    required this.totalStorageMB,
    required this.storagePercentUsed,
    required this.averageLogSizeBytes,
    required this.successRate,
    required this.isMaintenanceRunning,
    this.nextMaintenanceIn,
  });

  bool get isStorageHealthy => storagePercentUsed < 0.8; // Less than 80%
  bool get isStorageWarning => storagePercentUsed >= 0.8 && storagePercentUsed < 0.95; // 80-95%
  bool get isStorageCritical => storagePercentUsed >= 0.95; // 95%+

  String get storageStatus {
    if (isStorageCritical) return 'Critical';
    if (isStorageWarning) return 'Warning';
    return 'Healthy';
  }
}