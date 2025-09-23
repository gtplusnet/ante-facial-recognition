import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import '../di/injection.dart';
import '../storage/database_helper.dart';
import '../utils/logger.dart';
import 'offline_queue_manager.dart';

/// Callback dispatcher for WorkManager background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      Logger.info('Background task started: $task');
      
      // Initialize dependencies for background context
      await _initializeBackgroundDependencies();
      
      switch (task) {
        case 'sync':
        case 'sync-offline-queue':
          await _syncOfflineQueue();
          break;
        case 'sync-employees':
          await _syncEmployees();
          break;
        case 'cleanup-old-records':
          await _cleanupOldRecords();
          break;
        default:
          Logger.warning('Unknown background task: $task');
      }
      
      Logger.info('Background task completed: $task');
      return Future.value(true);
    } catch (e) {
      Logger.error('Background task failed: $task', error: e);
      return Future.value(false);
    }
  });
}

/// Initialize dependencies needed for background tasks
Future<void> _initializeBackgroundDependencies() async {
  try {
    // Initialize database
    final databaseHelper = DatabaseHelper();
    final database = await databaseHelper.initializeDatabase();
    
    // Initialize Dio for API calls
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://100.109.133.12:3000/api/public',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    
    // Register dependencies if not already registered
    if (!getIt.isRegistered<Database>()) {
      getIt.registerSingleton<Database>(database);
    }
    if (!getIt.isRegistered<Dio>()) {
      getIt.registerSingleton<Dio>(dio);
    }
  } catch (e) {
    Logger.error('Failed to initialize background dependencies', error: e);
    rethrow;
  }
}

/// Sync offline queue in background
Future<void> _syncOfflineQueue() async {
  try {
    final database = getIt<Database>();
    final dio = getIt<Dio>();
    
    final queueManager = OfflineQueueManager(
      database: database,
      dio: dio,
    );
    
    await queueManager.syncQueue();
  } catch (e) {
    Logger.error('Failed to sync offline queue in background', error: e);
  }
}

/// Sync employees from API in background
Future<void> _syncEmployees() async {
  try {
    // This will be implemented when we have the employee sync logic
    Logger.info('Employee sync task - not yet implemented');
  } catch (e) {
    Logger.error('Failed to sync employees in background', error: e);
  }
}

/// Clean up old records from database
Future<void> _cleanupOldRecords() async {
  try {
    final database = getIt<Database>();
    
    // Delete face recognition logs older than 30 days
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    await database.delete(
      'face_recognition_logs',
      where: 'created_at < ?',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
    );
    
    // Delete time records older than 90 days
    final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90));
    await database.delete(
      'time_records',
      where: 'created_at < ? AND synced = ?',
      whereArgs: [ninetyDaysAgo.toIso8601String(), 1],
    );
    
    Logger.info('Cleanup task completed');
  } catch (e) {
    Logger.error('Failed to cleanup old records', error: e);
  }
}

/// Background task service for managing WorkManager
class BackgroundTaskService {
  static const String _uniqueName = 'com.ante.facial_recognition.background';
  
  /// Initialize WorkManager with callback dispatcher
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      
      Logger.info('WorkManager initialized');
      
      // Schedule periodic tasks
      await _schedulePeriodicTasks();
    } catch (e) {
      Logger.error('Failed to initialize WorkManager', error: e);
    }
  }
  
  /// Schedule all periodic background tasks
  static Future<void> _schedulePeriodicTasks() async {
    try {
      // Sync offline queue every 15 minutes when connected
      await Workmanager().registerPeriodicTask(
        '1',
        'sync-offline-queue',
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      
      // Sync employees every hour when connected
      await Workmanager().registerPeriodicTask(
        '2',
        'sync-employees',
        frequency: const Duration(hours: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      
      // Cleanup old records once a day
      await Workmanager().registerPeriodicTask(
        '3',
        'cleanup-old-records',
        frequency: const Duration(days: 1),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      
      Logger.info('Periodic background tasks scheduled');
    } catch (e) {
      Logger.error('Failed to schedule periodic tasks', error: e);
    }
  }
  
  /// Cancel all background tasks
  static Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      Logger.info('All background tasks cancelled');
    } catch (e) {
      Logger.error('Failed to cancel background tasks', error: e);
    }
  }
  
  /// Cancel a specific task by unique name
  static Future<void> cancelTask(String uniqueName) async {
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
      Logger.info('Background task cancelled: $uniqueName');
    } catch (e) {
      Logger.error('Failed to cancel background task: $uniqueName', error: e);
    }
  }
  
  /// Trigger a one-time sync task
  static Future<void> triggerOneTimeSync() async {
    try {
      await Workmanager().registerOneOffTask(
        DateTime.now().millisecondsSinceEpoch.toString(),
        'sync-offline-queue',
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
      Logger.info('One-time sync task triggered');
    } catch (e) {
      Logger.error('Failed to trigger one-time sync', error: e);
    }
  }
}