import '../utils/logger.dart';

/// Centralized error handler for consistent error handling patterns
class ErrorHandler {
  /// Handle errors with consistent logging and optional rethrow
  static T handleError<T>(
    String context,
    Object error, {
    StackTrace? stackTrace,
    T? fallbackValue,
    bool shouldRethrow = false,
    String? customMessage,
  }) {
    final message = customMessage ?? 'Failed to $context';

    Logger.error(
      message,
      error: error,
      stackTrace: stackTrace,
    );

    if (shouldRethrow) {
      throw error;
    }

    if (fallbackValue != null) {
      return fallbackValue;
    }

    throw error;
  }

  /// Handle async operations with consistent error handling
  static Future<T> handleAsyncOperation<T>(
    String operationName,
    Future<T> Function() operation, {
    T? fallbackValue,
    bool shouldRethrow = false,
    String? customErrorMessage,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      return handleError<T>(
        operationName,
        e,
        stackTrace: stackTrace,
        fallbackValue: fallbackValue,
        shouldRethrow: shouldRethrow,
        customMessage: customErrorMessage,
      );
    }
  }

  /// Handle sync operations with consistent error handling
  static T handleSyncOperation<T>(
    String operationName,
    T Function() operation, {
    T? fallbackValue,
    bool shouldRethrow = false,
    String? customErrorMessage,
  }) {
    try {
      return operation();
    } catch (e, stackTrace) {
      return handleError<T>(
        operationName,
        e,
        stackTrace: stackTrace,
        fallbackValue: fallbackValue,
        shouldRethrow: shouldRethrow,
        customMessage: customErrorMessage,
      );
    }
  }

  /// Handle operations that should return null on error (with warning log)
  static Future<T?> handleOptionalOperation<T>(
    String operationName,
    Future<T?> Function() operation, {
    String? warningMessage,
  }) async {
    try {
      return await operation();
    } catch (e) {
      final message = warningMessage ?? 'Failed to $operationName';
      Logger.warning('$message: ${e.toString()}');
      return null;
    }
  }

  /// Handle operations that should return default value on error (with warning log)
  static Future<T> handleOperationWithDefault<T>(
    String operationName,
    Future<T> Function() operation,
    T defaultValue, {
    String? warningMessage,
  }) async {
    try {
      return await operation();
    } catch (e) {
      final message = warningMessage ?? 'Failed to $operationName';
      Logger.warning('$message: ${e.toString()}');
      return defaultValue;
    }
  }

  /// Handle operations that should just log warnings and continue
  static Future<void> handleOptionalOperationWithWarning(
    String operationName,
    Future<void> Function() operation, {
    String? warningMessage,
  }) async {
    try {
      await operation();
    } catch (e) {
      final message = warningMessage ?? 'Failed to $operationName, continuing anyway';
      Logger.warning('$message: ${e.toString()}');
    }
  }

  /// Handle batch operations where some items may fail
  static Future<List<T>> handleBatchOperation<T, K>(
    String operationName,
    List<K> items,
    Future<T> Function(K item) operation, {
    bool continueOnError = true,
  }) async {
    final results = <T>[];
    final errors = <String>[];

    for (int i = 0; i < items.length; i++) {
      try {
        final result = await operation(items[i]);
        results.add(result);
      } catch (e) {
        final error = '$operationName failed for item ${i + 1}: ${e.toString()}';
        errors.add(error);
        Logger.error(error, error: e);

        if (!continueOnError) {
          throw Exception('Batch operation failed: $error');
        }
      }
    }

    if (errors.isNotEmpty) {
      Logger.warning(
        'Batch $operationName completed with ${errors.length}/${items.length} errors'
      );
    }

    return results;
  }
}

/// Extension methods for common error handling patterns
extension ErrorHandlingExtensions on Future {
  /// Handle errors with logging and optional fallback
  Future<T> withErrorHandling<T>(
    String context, {
    T? fallbackValue,
    bool shouldRethrow = false,
  }) async {
    try {
      return await this as T;
    } catch (e, stackTrace) {
      return ErrorHandler.handleError<T>(
        context,
        e,
        stackTrace: stackTrace,
        fallbackValue: fallbackValue,
        shouldRethrow: shouldRethrow,
      );
    }
  }
}