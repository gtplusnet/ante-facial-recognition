import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/logger.dart';

/// Represents a queued API request that failed due to network issues
class QueuedRequest {
  final int? id;
  final String endpoint;
  final String method;
  final Map<String, dynamic>? data;
  final Map<String, String>? headers;
  final int retryCount;
  final int maxRetries;
  final DateTime createdAt;

  QueuedRequest({
    this.id,
    required this.endpoint,
    required this.method,
    this.data,
    this.headers,
    this.retryCount = 0,
    this.maxRetries = 3,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'endpoint': endpoint,
      'method': method,
      'data': data != null ? json.encode(data) : null,
      'headers': headers != null ? json.encode(headers) : null,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory QueuedRequest.fromMap(Map<String, dynamic> map) {
    return QueuedRequest(
      id: map['id'],
      endpoint: map['endpoint'],
      method: map['method'],
      data: map['data'] != null ? json.decode(map['data']) : null,
      headers: map['headers'] != null 
          ? Map<String, String>.from(json.decode(map['headers'])) 
          : null,
      retryCount: map['retry_count'] ?? 0,
      maxRetries: map['max_retries'] ?? 3,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class OfflineQueueManager {
  static const String _tableName = 'offline_queue';
  static const String _syncTaskName = 'sync-offline-queue';
  static const String _syncTaskTag = 'sync';
  
  final Database _database;
  final Dio _dio;
  final Connectivity _connectivity;
  
  Timer? _retryTimer;
  bool _isSyncing = false;
  
  OfflineQueueManager({
    @factoryParam Database? database,
    @factoryParam Dio? dio,
  })  : assert(database != null, 'Database is required'),
        assert(dio != null, 'Dio is required'),
        _database = database!,
        _dio = dio!,
        _connectivity = Connectivity() {
    _initializeConnectivityListener();
    _scheduleBackgroundSync();
  }

  /// Initialize connectivity listener to trigger sync when network is available
  void _initializeConnectivityListener() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        Logger.info('Network available, triggering offline queue sync');
        syncQueue();
      }
    });
  }

  /// Schedule background sync using WorkManager
  Future<void> _scheduleBackgroundSync() async {
    try {
      await Workmanager().registerPeriodicTask(
        _syncTaskName,
        _syncTaskTag,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
      Logger.debug('Background sync task scheduled');
    } catch (e) {
      Logger.error('Failed to schedule background sync', error: e);
    }
  }

  /// Add a failed request to the queue
  Future<void> addToQueue(QueuedRequest request) async {
    try {
      await _database.insert(
        _tableName,
        request.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.info('Added request to offline queue: ${request.method} ${request.endpoint}');
      
      // Try to sync immediately if network is available
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        syncQueue();
      }
    } catch (e) {
      Logger.error('Failed to add request to queue', error: e);
    }
  }

  /// Get all pending requests from the queue
  Future<List<QueuedRequest>> getPendingRequests() async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _tableName,
        orderBy: 'created_at ASC',
      );
      
      return maps.map((map) => QueuedRequest.fromMap(map)).toList();
    } catch (e) {
      Logger.error('Failed to get pending requests', error: e);
      return [];
    }
  }

  /// Get count of pending requests
  Future<int> getPendingCount() async {
    try {
      final result = await _database.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );
      return result.first['count'] as int? ?? 0;
    } catch (e) {
      Logger.error('Failed to get pending count', error: e);
      return 0;
    }
  }

  /// Process a single queued request
  Future<bool> _processRequest(QueuedRequest request) async {
    try {
      Logger.debug('Processing queued request: ${request.method} ${request.endpoint}');
      
      final options = Options(
        method: request.method,
        headers: request.headers,
      );
      
      Response response;
      switch (request.method.toUpperCase()) {
        case 'GET':
          response = await _dio.get(
            request.endpoint,
            options: options,
          );
          break;
        case 'POST':
          response = await _dio.post(
            request.endpoint,
            data: request.data,
            options: options,
          );
          break;
        case 'PUT':
          response = await _dio.put(
            request.endpoint,
            data: request.data,
            options: options,
          );
          break;
        case 'PATCH':
          response = await _dio.patch(
            request.endpoint,
            data: request.data,
            options: options,
          );
          break;
        case 'DELETE':
          response = await _dio.delete(
            request.endpoint,
            data: request.data,
            options: options,
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: ${request.method}');
      }
      
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        // Success - remove from queue
        await _removeFromQueue(request.id!);
        Logger.success('Successfully synced queued request: ${request.method} ${request.endpoint}');
        return true;
      } else {
        throw Exception('Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Failed to process queued request', error: e);
      
      // Update retry count
      if (request.id != null) {
        await _updateRetryCount(request);
      }
      
      return false;
    }
  }

  /// Update retry count for a failed request
  Future<void> _updateRetryCount(QueuedRequest request) async {
    try {
      final newRetryCount = request.retryCount + 1;
      
      if (newRetryCount >= request.maxRetries) {
        // Max retries reached, remove from queue
        Logger.warning(
          'Max retries reached for request: ${request.method} ${request.endpoint}. Removing from queue.',
        );
        await _removeFromQueue(request.id!);
      } else {
        // Update retry count
        await _database.update(
          _tableName,
          {'retry_count': newRetryCount},
          where: 'id = ?',
          whereArgs: [request.id],
        );
        Logger.debug('Updated retry count to $newRetryCount for request ${request.id}');
      }
    } catch (e) {
      Logger.error('Failed to update retry count', error: e);
    }
  }

  /// Remove a request from the queue
  Future<void> _removeFromQueue(int id) async {
    try {
      await _database.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      Logger.debug('Removed request $id from offline queue');
    } catch (e) {
      Logger.error('Failed to remove request from queue', error: e);
    }
  }

  /// Sync all pending requests in the queue
  Future<void> syncQueue() async {
    if (_isSyncing) {
      Logger.debug('Sync already in progress, skipping');
      return;
    }
    
    _isSyncing = true;
    
    try {
      // Check network connectivity first
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        Logger.debug('No network connection, skipping sync');
        return;
      }
      
      final pendingRequests = await getPendingRequests();
      if (pendingRequests.isEmpty) {
        Logger.debug('No pending requests to sync');
        return;
      }
      
      Logger.info('Starting offline queue sync: ${pendingRequests.length} pending requests');
      
      int successCount = 0;
      int failedCount = 0;
      
      for (final request in pendingRequests) {
        // Add exponential backoff delay based on retry count
        if (request.retryCount > 0) {
          final delay = Duration(
            seconds: _calculateBackoffDelay(request.retryCount),
          );
          await Future.delayed(delay);
        }
        
        final success = await _processRequest(request);
        if (success) {
          successCount++;
        } else {
          failedCount++;
        }
      }
      
      Logger.info(
        'Offline queue sync completed: $successCount successful, $failedCount failed',
      );
    } catch (e) {
      Logger.error('Failed to sync offline queue', error: e);
    } finally {
      _isSyncing = false;
    }
  }

  /// Calculate exponential backoff delay in seconds
  int _calculateBackoffDelay(int retryCount) {
    // 2^retryCount seconds, max 300 seconds (5 minutes)
    final delay = 1 << retryCount; // 2^retryCount
    return delay > 300 ? 300 : delay;
  }

  /// Clear all pending requests from the queue
  Future<void> clearQueue() async {
    try {
      await _database.delete(_tableName);
      Logger.info('Cleared offline queue');
    } catch (e) {
      Logger.error('Failed to clear offline queue', error: e);
    }
  }

  /// Get requests that have exceeded max retries
  Future<List<QueuedRequest>> getFailedRequests() async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _tableName,
        where: 'retry_count >= max_retries',
        orderBy: 'created_at DESC',
      );
      
      return maps.map((map) => QueuedRequest.fromMap(map)).toList();
    } catch (e) {
      Logger.error('Failed to get failed requests', error: e);
      return [];
    }
  }

  /// Retry failed requests (reset retry count)
  Future<void> retryFailedRequests() async {
    try {
      await _database.update(
        _tableName,
        {'retry_count': 0},
        where: 'retry_count >= max_retries',
      );
      Logger.info('Reset retry count for failed requests');
      
      // Trigger sync
      await syncQueue();
    } catch (e) {
      Logger.error('Failed to retry failed requests', error: e);
    }
  }

  /// Dispose resources
  void dispose() {
    _retryTimer?.cancel();
  }
}