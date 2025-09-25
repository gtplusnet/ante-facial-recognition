import 'package:flutter/services.dart';
import 'package:ante_facial_recognition/core/utils/logger.dart';

/// Utility class to keep screen awake
/// This is a workaround for wakelock_plus build issues
class ScreenKeeper {
  static const platform = MethodChannel('com.ante.facial_recognition/screen');

  /// Enable screen keep-awake
  static Future<void> enableKeepAwake() async {
    try {
      await platform.invokeMethod('keepScreenOn', true);
      Logger.info('Screen keep-awake enabled');
    } catch (e) {
      Logger.error('Failed to enable screen keep-awake: $e');
    }
  }

  /// Disable screen keep-awake
  static Future<void> disableKeepAwake() async {
    try {
      await platform.invokeMethod('keepScreenOn', false);
      Logger.info('Screen keep-awake disabled');
    } catch (e) {
      Logger.error('Failed to disable screen keep-awake: $e');
    }
  }
}