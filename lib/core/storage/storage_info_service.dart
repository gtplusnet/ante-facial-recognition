import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/logger.dart';
import 'database_helper.dart';
import 'secure_storage_helper.dart';

class StorageInfo {
  final int totalAppSize;
  final int databaseSize;
  final int imageDataSize;
  final int cacheSize;
  final int employeeCount;
  final int faceRecognitionLogsCount;
  final DateTime lastSyncTime;
  final double availableSpaceGB;
  final double usedSpaceGB;

  const StorageInfo({
    required this.totalAppSize,
    required this.databaseSize,
    required this.imageDataSize,
    required this.cacheSize,
    required this.employeeCount,
    required this.faceRecognitionLogsCount,
    required this.lastSyncTime,
    required this.availableSpaceGB,
    required this.usedSpaceGB,
  });

  String get formattedTotalSize => _formatBytes(totalAppSize);
  String get formattedDatabaseSize => _formatBytes(databaseSize);
  String get formattedImageDataSize => _formatBytes(imageDataSize);
  String get formattedCacheSize => _formatBytes(cacheSize);
  String get formattedAvailableSpace => '${availableSpaceGB.toStringAsFixed(2)} GB';
  String get formattedUsedSpace => '${usedSpaceGB.toStringAsFixed(2)} GB';

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

@singleton
class StorageInfoService {
  final DatabaseHelper _databaseHelper;
  final SecureStorageHelper _secureStorage;

  const StorageInfoService(this._databaseHelper, this._secureStorage);

  Future<StorageInfo> getStorageInfo() async {
    try {
      Logger.info('Calculating storage info');

      // Get database info
      final db = await _databaseHelper.database;
      final databasePath = db.path;
      final databaseSize = await _getFileSize(databasePath);

      // Get employee count
      final employeeCount = await _getEmployeeCount(db);

      // Get face recognition logs count
      final logsCount = await _getFaceRecognitionLogsCount(db);

      // Calculate image data size (employee photos stored as BLOB)
      final imageDataSize = await _calculateImageDataSize(db);

      // Get app directories
      final appDocDir = await getApplicationDocumentsDirectory();
      final appSupportDir = await getApplicationSupportDirectory();
      final tempDir = await getTemporaryDirectory();

      // Calculate cache size
      final cacheSize = await _getDirectorySize(tempDir);

      // Calculate total app size
      final appDocSize = await _getDirectorySize(appDocDir);
      final appSupportSize = await _getDirectorySize(appSupportDir);
      final totalAppSize = databaseSize + appDocSize + appSupportSize + cacheSize;

      // Get device storage info
      final availableSpace = await _getAvailableSpace();
      final usedSpace = totalAppSize / (1024 * 1024 * 1024); // Convert to GB

      // Get last sync time (default to epoch if not available)
      final lastSyncTime = await _getLastSyncTime() ?? DateTime.fromMillisecondsSinceEpoch(0);

      final storageInfo = StorageInfo(
        totalAppSize: totalAppSize,
        databaseSize: databaseSize,
        imageDataSize: imageDataSize,
        cacheSize: cacheSize,
        employeeCount: employeeCount,
        faceRecognitionLogsCount: logsCount,
        lastSyncTime: lastSyncTime,
        availableSpaceGB: availableSpace,
        usedSpaceGB: usedSpace,
      );

      Logger.success('Storage info calculated successfully');
      return storageInfo;
    } catch (e) {
      Logger.error('Failed to calculate storage info', error: e);
      rethrow;
    }
  }

  Future<int> _getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.size;
      }
      return 0;
    } catch (e) {
      Logger.warning('Failed to get file size for: $filePath');
      return 0;
    }
  }

  Future<int> _getDirectorySize(Directory directory) async {
    try {
      if (!await directory.exists()) return 0;

      int totalSize = 0;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
          } catch (e) {
            // Skip files that can't be accessed
            continue;
          }
        }
      }
      return totalSize;
    } catch (e) {
      Logger.warning('Failed to calculate directory size for: ${directory.path}');
      return 0;
    }
  }

  Future<int> _getEmployeeCount(Database db) async {
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM employees');
      return result.first['count'] as int? ?? 0;
    } catch (e) {
      Logger.warning('Failed to get employee count');
      return 0;
    }
  }

  Future<int> _getFaceRecognitionLogsCount(Database db) async {
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM face_recognition_logs');
      return result.first['count'] as int? ?? 0;
    } catch (e) {
      Logger.warning('Failed to get face recognition logs count');
      return 0;
    }
  }

  Future<int> _calculateImageDataSize(Database db) async {
    try {
      // Calculate total size of photo_bytes BLOB fields
      final result = await db.rawQuery('''
        SELECT SUM(LENGTH(photo_bytes)) as total_size
        FROM employees
        WHERE photo_bytes IS NOT NULL
      ''');
      return result.first['total_size'] as int? ?? 0;
    } catch (e) {
      Logger.warning('Failed to calculate image data size');
      return 0;
    }
  }

  Future<double> _getAvailableSpace() async {
    try {
      // For Android, we can check available space on internal storage
      final directory = await getApplicationDocumentsDirectory();
      final stat = await directory.stat();

      // This is a simplified approach - in a real app you might want to use
      // platform channels to get more accurate storage information

      // Return a reasonable default (in GB) if we can't determine
      return 10.0; // 10GB default
    } catch (e) {
      Logger.warning('Failed to get available space');
      return 0.0;
    }
  }

  Future<DateTime?> _getLastSyncTime() async {
    try {
      return await _secureStorage.getLastSyncTime();
    } catch (e) {
      Logger.warning('Failed to get last sync time');
      return null;
    }
  }

  /// Clear cached data to free up space
  Future<int> clearCache() async {
    try {
      Logger.info('Clearing cache');

      final tempDir = await getTemporaryDirectory();
      int freedBytes = 0;

      if (await tempDir.exists()) {
        freedBytes = await _getDirectorySize(tempDir);
        await tempDir.delete(recursive: true);
        await tempDir.create(); // Recreate the directory
      }

      Logger.success('Cache cleared, freed ${StorageInfo._formatBytes(freedBytes)}');
      return freedBytes;
    } catch (e) {
      Logger.error('Failed to clear cache', error: e);
      return 0;
    }
  }

  /// Clear face recognition logs older than specified days
  Future<int> clearOldLogs({int olderThanDays = 30}) async {
    try {
      Logger.info('Clearing face recognition logs older than $olderThanDays days');

      final db = await _databaseHelper.database;
      final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));

      final deletedCount = await db.delete(
        'face_recognition_logs',
        where: 'created_at < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );

      Logger.success('Cleared $deletedCount old face recognition logs');
      return deletedCount;
    } catch (e) {
      Logger.error('Failed to clear old logs', error: e);
      return 0;
    }
  }
}