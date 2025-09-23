import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/storage/database_helper.dart';
import '../../../../core/utils/logger.dart';
import '../models/face_encoding_model.dart';

class FaceEncodingCache {
  static const String _tableName = 'face_encodings_cache';
  static const String _storageKey = 'face_encoding_cache_version';

  final DatabaseHelper _databaseHelper;
  final FlutterSecureStorage _secureStorage;

  Database? _database;
  Map<String, FaceEncodingModel>? _memoryCache;

  FaceEncodingCache({
    required DatabaseHelper databaseHelper,
    @factoryParam FlutterSecureStorage? secureStorage,
  })  : _databaseHelper = databaseHelper,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Initialize the cache and database table
  Future<void> initialize() async {
    try {
      _database = await _databaseHelper.database;
      await _createTable();
      await _loadToMemory();
      Logger.info('Face encoding cache initialized');
    } catch (e) {
      Logger.error('Failed to initialize face encoding cache', error: e);
    }
  }

  /// Create the face encodings cache table
  Future<void> _createTable() async {
    await _database?.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        employee_id TEXT PRIMARY KEY,
        employee_name TEXT NOT NULL,
        encoding BLOB NOT NULL,
        photo_url TEXT,
        quality_score REAL DEFAULT 1.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'synced'
      )
    ''');
  }

  /// Load all encodings to memory for faster access
  Future<void> _loadToMemory() async {
    try {
      final List<Map<String, dynamic>> maps = await _database?.query(
        _tableName,
        orderBy: 'quality_score DESC',
      ) ?? [];

      _memoryCache = {};
      for (final map in maps) {
        final encoding = FaceEncodingModel.fromJson(map);
        _memoryCache![encoding.employeeId] = encoding;
      }

      Logger.info('Loaded ${_memoryCache!.length} face encodings to memory');
    } catch (e) {
      Logger.error('Failed to load face encodings to memory', error: e);
      _memoryCache = {};
    }
  }

  /// Get all cached encodings from memory
  Map<String, FaceEncodingModel> getAllCached() {
    return Map.from(_memoryCache ?? {});
  }

  /// Get encoding for a specific employee
  Future<FaceEncodingModel?> getEncoding(String employeeId) async {
    // First check memory cache
    if (_memoryCache?.containsKey(employeeId) ?? false) {
      return _memoryCache![employeeId];
    }

    // Fallback to database
    try {
      final List<Map<String, dynamic>> maps = await _database?.query(
        _tableName,
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        limit: 1,
      ) ?? [];

      if (maps.isNotEmpty) {
        final encoding = FaceEncodingModel.fromJson(maps.first);
        // Update memory cache
        _memoryCache?[employeeId] = encoding;
        return encoding;
      }
    } catch (e) {
      Logger.error('Failed to get encoding for employee $employeeId', error: e);
    }

    return null;
  }

  /// Save or update encoding
  Future<void> saveEncoding(FaceEncodingModel encoding) async {
    try {
      await _database?.insert(
        _tableName,
        encoding.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update memory cache
      _memoryCache?[encoding.employeeId] = encoding;

      Logger.debug('Saved encoding for employee ${encoding.employeeId}');
    } catch (e) {
      Logger.error('Failed to save encoding', error: e);
    }
  }

  /// Save multiple encodings
  Future<void> saveEncodings(List<FaceEncodingModel> encodings) async {
    if (encodings.isEmpty) return;

    try {
      final batch = _database!.batch();

      for (final encoding in encodings) {
        batch.insert(
          _tableName,
          encoding.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);

      // Update memory cache
      for (final encoding in encodings) {
        _memoryCache?[encoding.employeeId] = encoding;
      }

      Logger.info('Saved ${encodings.length} encodings to cache');
    } catch (e) {
      Logger.error('Failed to save encodings batch', error: e);
    }
  }

  /// Delete encoding for an employee
  Future<void> deleteEncoding(String employeeId) async {
    try {
      await _database?.delete(
        _tableName,
        where: 'employee_id = ?',
        whereArgs: [employeeId],
      );

      // Remove from memory cache
      _memoryCache?.remove(employeeId);

      Logger.debug('Deleted encoding for employee $employeeId');
    } catch (e) {
      Logger.error('Failed to delete encoding', error: e);
    }
  }

  /// Clear all cached encodings
  Future<void> clearCache() async {
    try {
      await _database?.delete(_tableName);
      _memoryCache?.clear();
      await _secureStorage.delete(key: _storageKey);

      Logger.info('Cleared face encoding cache');
    } catch (e) {
      Logger.error('Failed to clear cache', error: e);
    }
  }

  /// Get encodings that need sync
  Future<List<FaceEncodingModel>> getUnsyncedEncodings() async {
    try {
      final List<Map<String, dynamic>> maps = await _database?.query(
        _tableName,
        where: 'sync_status = ?',
        whereArgs: ['pending'],
      ) ?? [];

      return maps.map((map) => FaceEncodingModel.fromJson(map)).toList();
    } catch (e) {
      Logger.error('Failed to get unsynced encodings', error: e);
      return [];
    }
  }

  /// Mark encodings as synced
  Future<void> markAsSynced(List<String> employeeIds) async {
    if (employeeIds.isEmpty) return;

    try {
      final batch = _database!.batch();

      for (final id in employeeIds) {
        batch.update(
          _tableName,
          {'sync_status': 'synced', 'updated_at': DateTime.now().toIso8601String()},
          where: 'employee_id = ?',
          whereArgs: [id],
        );
      }

      await batch.commit(noResult: true);

      // Update memory cache
      for (final id in employeeIds) {
        final encoding = _memoryCache?[id];
        if (encoding != null) {
          _memoryCache![id] = encoding.copyWith(syncStatus: 'synced');
        }
      }

      Logger.debug('Marked ${employeeIds.length} encodings as synced');
    } catch (e) {
      Logger.error('Failed to mark encodings as synced', error: e);
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final totalCount = await _database?.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );

      final syncedCount = await _database?.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE sync_status = ?',
        ['synced'],
      );

      final avgQuality = await _database?.rawQuery(
        'SELECT AVG(quality_score) as avg_quality FROM $_tableName',
      );

      return {
        'total_encodings': totalCount?.first['count'] ?? 0,
        'synced_encodings': syncedCount?.first['count'] ?? 0,
        'average_quality': avgQuality?.first['avg_quality'] ?? 0.0,
        'memory_cache_size': _memoryCache?.length ?? 0,
      };
    } catch (e) {
      Logger.error('Failed to get cache stats', error: e);
      return {};
    }
  }

  /// Optimize cache by removing low-quality encodings
  Future<void> optimizeCache({double minQuality = 0.5}) async {
    try {
      final deleted = await _database?.delete(
        _tableName,
        where: 'quality_score < ?',
        whereArgs: [minQuality],
      );

      // Reload memory cache
      await _loadToMemory();

      Logger.info('Optimized cache, removed $deleted low-quality encodings');
    } catch (e) {
      Logger.error('Failed to optimize cache', error: e);
    }
  }

  /// Check if cache needs update based on version
  Future<bool> needsUpdate(String currentVersion) async {
    try {
      final storedVersion = await _secureStorage.read(key: _storageKey);
      return storedVersion != currentVersion;
    } catch (e) {
      return true;
    }
  }

  /// Update cache version
  Future<void> updateVersion(String version) async {
    await _secureStorage.write(key: _storageKey, value: version);
  }
}