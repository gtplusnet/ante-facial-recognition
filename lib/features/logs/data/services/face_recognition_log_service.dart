import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:injectable/injectable.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/storage/database_helper.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_recognition/data/services/simplified_face_recognition_service.dart';
import '../../utils/camera_image_converter.dart';
import '../models/face_recognition_log_model.dart';

@singleton
class FaceRecognitionLogService {
  final DatabaseHelper _databaseHelper;

  static const String _tableName = 'face_recognition_logs';
  static const int _maxLogsToKeep = 1000; // Keep last 1000 logs
  static const int _cleanupThreshold = 1100; // Start cleanup when over 1100

  FaceRecognitionLogService({
    required DatabaseHelper databaseHelper,
  }) : _databaseHelper = databaseHelper;

  /// Log face recognition result with captured images
  Future<void> logRecognitionResult({
    required FaceRecognitionResult result,
    required int processingTimeMs,
    required CameraImage cameraImage,
    required CameraDescription cameraDescription,
    List<Face>? detectedFaces,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      Logger.info('Logging face recognition result: ${result.type}');
      final logStopwatch = Stopwatch()..start();

      // Convert camera image to JPEG
      final imageStopwatch = Stopwatch()..start();
      final fullImageBytes = await CameraImageConverter.convertCameraImageToJpeg(
        cameraImage,
        cameraDescription,
      );
      imageStopwatch.stop();

      Logger.debug('Camera image conversion took: ${imageStopwatch.elapsedMilliseconds}ms');

      if (fullImageBytes == null) {
        Logger.warning('Failed to convert camera image to JPEG - logging without image');
        await _saveLogWithoutImage(
          result: result,
          processingTimeMs: processingTimeMs,
          deviceId: deviceId,
          metadata: metadata,
        );
        return;
      }

      // Process images asynchronously to avoid blocking
      Uint8List? faceImage;
      Uint8List? thumbnailImage;
      Rect? faceBounds;
      int? imageWidth = cameraImage.width;
      int? imageHeight = cameraImage.height;

      // Extract face region if we have detected faces
      if (detectedFaces != null && detectedFaces.isNotEmpty) {
        final face = detectedFaces.first;
        faceBounds = face.boundingBox;

        // Extract face region with padding
        faceImage = await CameraImageConverter.extractFaceRegion(
          fullImageBytes,
          face,
        );

        // Create thumbnail from face region if available, otherwise from full image
        final imageForThumbnail = faceImage ?? fullImageBytes;
        thumbnailImage = await CameraImageConverter.createThumbnail(imageForThumbnail);
      } else {
        // No face detected, use full image
        faceImage = fullImageBytes;
        thumbnailImage = await CameraImageConverter.createThumbnail(fullImageBytes);
      }

      // Create log model
      final logModel = FaceRecognitionLogModel.fromRecognitionResult(
        result: result,
        processingTimeMs: processingTimeMs,
        faceBounds: faceBounds,
        faceImage: faceImage,
        thumbnailImage: thumbnailImage,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        metadata: metadata,
        deviceId: deviceId,
      );

      // Save to database
      final db = await _databaseHelper.database;
      await _saveLogToDatabase(db, logModel);

      logStopwatch.stop();
      Logger.success('Face recognition log saved successfully in ${logStopwatch.elapsedMilliseconds}ms');

      // Check if cleanup is needed
      await _performCleanupIfNeeded(db);

    } catch (e) {
      Logger.error('Failed to log face recognition result', error: e);
      // Don't throw - logging should not break the main flow
    }
  }

  /// Save log without image data (fallback)
  Future<void> _saveLogWithoutImage({
    required FaceRecognitionResult result,
    required int processingTimeMs,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final logModel = FaceRecognitionLogModel.fromRecognitionResult(
        result: result,
        processingTimeMs: processingTimeMs,
        deviceId: deviceId,
        metadata: metadata,
      );

      final db = await _databaseHelper.database;
      await _saveLogToDatabase(db, logModel);
      Logger.info('Face recognition log saved without images');
    } catch (e) {
      Logger.error('Failed to save log without image', error: e);
    }
  }

  /// Save log model to database
  Future<void> _saveLogToDatabase(Database db, FaceRecognitionLogModel logModel) async {
    final data = logModel.toDatabase();
    await _databaseHelper.insert(db, _tableName, data);

    final imageSize = logModel.estimatedSize;
    Logger.debug('Saved log entry with ${imageSize} bytes of image data');
  }

  /// Get recent logs with optional filtering
  Future<List<FaceRecognitionLogModel>> getLogs({
    int? limit = 50,
    FaceRecognitionResultType? filterByType,
    DateTime? startDate,
    DateTime? endDate,
    String? employeeId,
  }) async {
    try {
      final db = await _databaseHelper.database;

      String where = '1=1';
      final whereArgs = <dynamic>[];

      if (filterByType != null) {
        where += ' AND result_type = ?';
        whereArgs.add(filterByType.name);
      }

      if (employeeId != null) {
        where += ' AND employee_id = ?';
        whereArgs.add(employeeId);
      }

      if (startDate != null) {
        where += ' AND timestamp >= ?';
        whereArgs.add(startDate.toIso8601String());
      }

      if (endDate != null) {
        where += ' AND timestamp <= ?';
        whereArgs.add(endDate.toIso8601String());
      }

      final results = await _databaseHelper.query(
        db,
        _tableName,
        where: where,
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      final logs = results.map((map) => FaceRecognitionLogModel.fromDatabase(map)).toList();
      Logger.debug('Retrieved ${logs.length} log entries');
      return logs;
    } catch (e) {
      Logger.error('Failed to get logs', error: e);
      return [];
    }
  }

  /// Get logs for today only
  Future<List<FaceRecognitionLogModel>> getTodaysLogs({
    FaceRecognitionResultType? filterByType,
  }) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return await getLogs(
      startDate: startOfDay,
      endDate: endOfDay,
      filterByType: filterByType,
    );
  }

  /// Get statistics for the logs
  Future<FaceRecognitionLogStats> getLogStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final db = await _databaseHelper.database;

      String where = '1=1';
      final whereArgs = <dynamic>[];

      if (startDate != null) {
        where += ' AND timestamp >= ?';
        whereArgs.add(startDate.toIso8601String());
      }

      if (endDate != null) {
        where += ' AND timestamp <= ?';
        whereArgs.add(endDate.toIso8601String());
      }

      // Get counts by result type
      final results = await db.rawQuery('''
        SELECT
          result_type,
          COUNT(*) as count,
          AVG(confidence) as avg_confidence,
          AVG(quality) as avg_quality,
          AVG(processing_time_ms) as avg_processing_time
        FROM $_tableName
        WHERE $where
        GROUP BY result_type
      ''', whereArgs);

      int totalLogs = 0;
      int successfulMatches = 0;
      double totalConfidence = 0;
      double totalQuality = 0;
      double totalProcessingTime = 0;
      final Map<FaceRecognitionResultType, int> typeCounts = {};

      for (final row in results) {
        final type = FaceRecognitionResultType.values.firstWhere(
          (e) => e.name == row['result_type'],
          orElse: () => FaceRecognitionResultType.error,
        );
        final count = row['count'] as int;

        typeCounts[type] = count;
        totalLogs += count;

        if (type == FaceRecognitionResultType.matched) {
          successfulMatches += count;
          totalConfidence += (row['avg_confidence'] as double?) ?? 0.0;
          totalQuality += (row['avg_quality'] as double?) ?? 0.0;
        }
        totalProcessingTime += (row['avg_processing_time'] as double?) ?? 0.0;
      }

      return FaceRecognitionLogStats(
        totalLogs: totalLogs,
        successfulMatches: successfulMatches,
        averageConfidence: successfulMatches > 0 ? totalConfidence / results.length : 0.0,
        averageQuality: successfulMatches > 0 ? totalQuality / results.length : 0.0,
        averageProcessingTimeMs: totalLogs > 0 ? totalProcessingTime / results.length : 0.0,
        typeCounts: typeCounts,
      );
    } catch (e) {
      Logger.error('Failed to get log stats', error: e);
      return const FaceRecognitionLogStats(
        totalLogs: 0,
        successfulMatches: 0,
        averageConfidence: 0.0,
        averageQuality: 0.0,
        averageProcessingTimeMs: 0.0,
        typeCounts: {},
      );
    }
  }

  /// Delete old logs to manage storage
  Future<void> _performCleanupIfNeeded(Database db) async {
    try {
      // Check total count
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      final totalLogs = countResult.first['count'] as int;

      if (totalLogs <= _cleanupThreshold) return;

      Logger.info('Starting log cleanup - $totalLogs logs exceed threshold of $_cleanupThreshold');

      // Delete oldest logs, keeping the most recent ones
      final logsToDelete = totalLogs - _maxLogsToKeep;
      await db.rawDelete('''
        DELETE FROM $_tableName
        WHERE id IN (
          SELECT id FROM $_tableName
          ORDER BY timestamp ASC
          LIMIT ?
        )
      ''', [logsToDelete]);

      Logger.info('Cleaned up $logsToDelete old log entries');
    } catch (e) {
      Logger.error('Failed to cleanup old logs', error: e);
    }
  }

  /// Clear all logs (for debugging/testing)
  Future<void> clearAllLogs() async {
    try {
      final db = await _databaseHelper.database;
      await _databaseHelper.clearTable(db, _tableName);
      Logger.info('Cleared all face recognition logs');
    } catch (e) {
      Logger.error('Failed to clear logs', error: e);
      throw Exception('Failed to clear logs: $e');
    }
  }

  /// Get storage usage information
  Future<LogStorageInfo> getStorageInfo() async {
    try {
      final db = await _databaseHelper.database;

      final sizeResult = await db.rawQuery('''
        SELECT
          COUNT(*) as log_count,
          SUM(LENGTH(face_image)) as face_images_size,
          SUM(LENGTH(thumbnail_image)) as thumbnail_images_size,
          AVG(LENGTH(face_image)) as avg_face_image_size,
          AVG(LENGTH(thumbnail_image)) as avg_thumbnail_size
        FROM $_tableName
        WHERE face_image IS NOT NULL OR thumbnail_image IS NOT NULL
      ''');

      final row = sizeResult.first;
      final logCount = row['log_count'] as int;
      final faceImagesSize = (row['face_images_size'] as int?) ?? 0;
      final thumbnailImagesSize = (row['thumbnail_images_size'] as int?) ?? 0;
      final avgFaceImageSize = (row['avg_face_image_size'] as double?) ?? 0.0;
      final avgThumbnailSize = (row['avg_thumbnail_size'] as double?) ?? 0.0;

      return LogStorageInfo(
        totalLogs: logCount,
        totalStorageBytes: faceImagesSize + thumbnailImagesSize,
        faceImagesStorageBytes: faceImagesSize,
        thumbnailImagesStorageBytes: thumbnailImagesSize,
        averageFaceImageSizeBytes: avgFaceImageSize.toInt(),
        averageThumbnailSizeBytes: avgThumbnailSize.toInt(),
      );
    } catch (e) {
      Logger.error('Failed to get storage info', error: e);
      return const LogStorageInfo(
        totalLogs: 0,
        totalStorageBytes: 0,
        faceImagesStorageBytes: 0,
        thumbnailImagesStorageBytes: 0,
        averageFaceImageSizeBytes: 0,
        averageThumbnailSizeBytes: 0,
      );
    }
  }
}

/// Statistics for face recognition logs
class FaceRecognitionLogStats {
  final int totalLogs;
  final int successfulMatches;
  final double averageConfidence;
  final double averageQuality;
  final double averageProcessingTimeMs;
  final Map<FaceRecognitionResultType, int> typeCounts;

  const FaceRecognitionLogStats({
    required this.totalLogs,
    required this.successfulMatches,
    required this.averageConfidence,
    required this.averageQuality,
    required this.averageProcessingTimeMs,
    required this.typeCounts,
  });

  double get successRate => totalLogs > 0 ? successfulMatches / totalLogs : 0.0;
}

/// Storage usage information for logs
class LogStorageInfo {
  final int totalLogs;
  final int totalStorageBytes;
  final int faceImagesStorageBytes;
  final int thumbnailImagesStorageBytes;
  final int averageFaceImageSizeBytes;
  final int averageThumbnailSizeBytes;

  const LogStorageInfo({
    required this.totalLogs,
    required this.totalStorageBytes,
    required this.faceImagesStorageBytes,
    required this.thumbnailImagesStorageBytes,
    required this.averageFaceImageSizeBytes,
    required this.averageThumbnailSizeBytes,
  });

  String get totalStorageMB => (totalStorageBytes / (1024 * 1024)).toStringAsFixed(2);
  String get averageLogSizeMB => totalLogs > 0
      ? (totalStorageBytes / totalLogs / (1024 * 1024)).toStringAsFixed(3)
      : '0.000';
}