import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class Logger {
  Logger._();

  static const String _name = 'ANTE';

  static void debug(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      final logMessage = '[DEBUG] $message';
      print(logMessage);
      developer.log(
        message,
        name: _name,
        time: DateTime.now(),
        error: data,
      );
    }
  }

  static void info(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      final logMessage = '[INFO] $message';
      print(logMessage);
      if (data != null) print('  Data: $data');
      developer.log(
        '📘 $message',
        name: _name,
        time: DateTime.now(),
        error: data,
        level: 800,
      );
    }
  }

  static void warning(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      final logMessage = '[WARNING] $message';
      print(logMessage);
      if (data != null) print('  Data: $data');
      developer.log(
        '⚠️ $message',
        name: _name,
        time: DateTime.now(),
        error: data,
        level: 900,
      );
    }
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      final logMessage = '[ERROR] $message';
      print(logMessage);
      if (error != null) print('  Error: $error');
      if (stackTrace != null) print('  StackTrace: $stackTrace');
      developer.log(
        '❌ $message',
        name: _name,
        time: DateTime.now(),
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
    }
  }

  static void success(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      final logMessage = '[SUCCESS] $message';
      print(logMessage);
      if (data != null) print('  Data: $data');
      developer.log(
        '✅ $message',
        name: _name,
        time: DateTime.now(),
        error: data,
        level: 700,
      );
    }
  }

  static void network(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      final logMessage = '[NETWORK] $message';
      print(logMessage);
      developer.log(
        '🌐 $message',
        name: '$_name-NETWORK',
        time: DateTime.now(),
        error: data,
      );
    }
  }

  static void database(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      developer.log(
        '💾 $message',
        name: '$_name-DATABASE',
        time: DateTime.now(),
        error: data,
      );
    }
  }

  static void faceRecognition(
    String message, {
    Object? data,
  }) {
    if (kDebugMode) {
      developer.log(
        '👤 $message',
        name: '$_name-FACE',
        time: DateTime.now(),
        error: data,
      );
    }
  }

  static void performance(
    String message, {
    Duration? duration,
    Object? data,
  }) {
    if (kDebugMode) {
      final durationText = duration != null
          ? ' (${duration.inMilliseconds}ms)'
          : '';
      developer.log(
        '⚡ $message$durationText',
        name: '$_name-PERF',
        time: DateTime.now(),
        error: data,
      );
    }
  }
}