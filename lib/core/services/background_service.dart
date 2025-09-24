import 'package:workmanager/workmanager.dart';
import '../di/injection.dart';
import '../usecases/usecase.dart';
import '../utils/logger.dart';
import '../../features/employee/domain/usecases/sync_employees_usecase.dart';

/// Top-level function for WorkManager callback dispatcher
/// This must be a top-level function or static method
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      Logger.info('[BackgroundService] Executing task: $task');

      // Initialize dependencies for background context
      await configureDependencies();

      switch (task) {
        case 'syncEmployees':
          Logger.info('[BackgroundService] Starting employee sync');
          final syncUseCase = getIt<SyncEmployeesUseCase>();
          final result = await syncUseCase(NoParams());

          result.fold(
            (failure) => Logger.error('[BackgroundService] Sync failed: ${failure.message}'),
            (synced) => Logger.success('[BackgroundService] Sync completed successfully'),
          );
          break;

        default:
          Logger.warning('[BackgroundService] Unknown task: $task');
      }

      return true; // Success
    } catch (e, stackTrace) {
      Logger.error('[BackgroundService] Task execution failed',
        error: e,
        stackTrace: stackTrace
      );
      return false; // Failure
    }
  });
}

class BackgroundService {
  static const String _uniqueName = 'ante_sync';
  static const String _syncTaskName = 'syncEmployees';

  /// Initialize WorkManager for background tasks
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false, // Set to true for debugging
      );
      Logger.success('[BackgroundService] WorkManager initialized');
    } catch (e) {
      Logger.error('[BackgroundService] Failed to initialize WorkManager', error: e);
      rethrow;
    }
  }

  /// Schedule periodic employee sync (every 15 minutes)
  static Future<void> schedulePeriodicSync() async {
    try {
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _syncTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
      Logger.info('[BackgroundService] Periodic sync scheduled');
    } catch (e) {
      Logger.error('[BackgroundService] Failed to schedule periodic sync', error: e);
    }
  }

  /// Cancel all background tasks
  static Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      Logger.info('[BackgroundService] All background tasks cancelled');
    } catch (e) {
      Logger.error('[BackgroundService] Failed to cancel tasks', error: e);
    }
  }

  /// Trigger one-time sync
  static Future<void> triggerOneTimeSync() async {
    try {
      await Workmanager().registerOneOffTask(
        '${_uniqueName}_once_${DateTime.now().millisecondsSinceEpoch}',
        _syncTaskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
      Logger.info('[BackgroundService] One-time sync triggered');
    } catch (e) {
      Logger.error('[BackgroundService] Failed to trigger sync', error: e);
    }
  }
}