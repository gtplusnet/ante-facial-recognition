import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import '../../features/employee/data/datasources/employee_local_datasource.dart';
import '../../features/employee/presentation/bloc/employee_bloc.dart';
import '../../features/employee/presentation/bloc/employee_event.dart';
import '../../features/face_recognition/data/services/face_encoding_service.dart';
import '../../features/face_recognition/data/services/simplified_face_recognition_service.dart';
import '../ml/tflite_service.dart';
import '../utils/logger.dart';
import 'background_task_service.dart';

/// Service responsible for initializing all required services at app startup
@singleton
class InitializationService {
  final TFLiteService _tfliteService;
  final FaceEncodingService _faceEncodingService;
  final SimplifiedFaceRecognitionService _faceRecognitionService;
  final EmployeeLocalDataSource _employeeDataSource;
  final EmployeeBloc _employeeBloc;

  InitializationService({
    required TFLiteService tfliteService,
    required FaceEncodingService faceEncodingService,
    required SimplifiedFaceRecognitionService faceRecognitionService,
    required EmployeeLocalDataSource employeeDataSource,
    required EmployeeBloc employeeBloc,
  })  : _tfliteService = tfliteService,
        _faceEncodingService = faceEncodingService,
        _faceRecognitionService = faceRecognitionService,
        _employeeDataSource = employeeDataSource,
        _employeeBloc = employeeBloc;

  /// Initialize all services with progress callback
  Future<InitializationResult> initializeApp({
    required Function(InitializationStep) onProgress,
    required Function(String) onStatusUpdate,
  }) async {
    final errors = <String>[];

    try {
      // Step 1: Initialize database
      onProgress(InitializationStep.database);
      onStatusUpdate('Initializing database...');
      try {
        // Database is initialized automatically in EmployeeLocalDataSource
        Logger.success('Database initialized');
        onStatusUpdate('Database ready');
      } catch (e) {
        Logger.error('Database initialization failed', error: e);
        errors.add('Database: ${e.toString()}');
        onStatusUpdate('Database initialization failed');
      }

      // Step 2: Initialize TFLite model - CRITICAL STEP
      onProgress(InitializationStep.mlModel);
      onStatusUpdate('Loading ML model...');
      try {
        await _tfliteService.initialize();
        Logger.success('TFLite model loaded');
        onStatusUpdate('ML model ready');
      } catch (e) {
        Logger.error('TFLite initialization failed', error: e);
        errors.add('ML Model: ${e.toString()}');
        onStatusUpdate('ML model failed to load');

        // This is a critical error - face recognition cannot work without the model
        // Return immediately with critical failure
        return InitializationResult(
          success: false,
          message: 'Critical: Face recognition model failed to load',
          errors: ['ML Model failed to initialize: ${e.toString()}'],
          isCritical: true,
        );
      }

      // Step 3: Initialize face encoding service
      onProgress(InitializationStep.faceEncoding);
      onStatusUpdate('Setting up face encoding...');
      try {
        await _faceEncodingService.initialize();
        Logger.success('Face encoding service initialized');
        onStatusUpdate('Face encoding ready');
      } catch (e) {
        Logger.error('Face encoding initialization failed', error: e);
        errors.add('Face Encoding: ${e.toString()}');
        onStatusUpdate('Face encoding setup failed');
      }

      // Step 4: Initialize face recognition service
      onProgress(InitializationStep.faceRecognition);
      onStatusUpdate('Initializing face recognition...');
      try {
        await _faceRecognitionService.initialize();
        Logger.success('Face recognition service initialized');
        onStatusUpdate('Face recognition ready');
      } catch (e) {
        Logger.error('Face recognition initialization failed', error: e);
        errors.add('Face Recognition: ${e.toString()}');
        onStatusUpdate('Face recognition failed');
      }

      // Step 5: Load employee data
      onProgress(InitializationStep.employeeData);
      onStatusUpdate('Loading employee data...');
      try {
        final employees = await _employeeDataSource.getAllEmployees();
        final employeesWithEncodings = employees.where((e) => e.faceEncodings.isNotEmpty).length;
        Logger.success('Loaded ${employees.length} employees ($employeesWithEncodings with face encodings)');
        onStatusUpdate('${employees.length} employees loaded');
      } catch (e) {
        Logger.error('Employee data loading failed', error: e);
        errors.add('Employee Data: ${e.toString()}');
        onStatusUpdate('Failed to load employees');
      }

      // Step 6: Initialize background services
      onProgress(InitializationStep.backgroundServices);
      onStatusUpdate('Starting background services...');
      try {
        await BackgroundTaskService.initialize();
        Logger.success('Background services started');
        onStatusUpdate('Background services ready');
      } catch (e) {
        Logger.error('Background services initialization failed', error: e);
        errors.add('Background Services: ${e.toString()}');
        onStatusUpdate('Background services failed');
      }

      // Step 7: Sync employee data
      onProgress(InitializationStep.syncData);
      onStatusUpdate('Syncing employee data...');
      try {
        // Trigger employee sync
        _employeeBloc.add(const SyncEmployees());
        await Future.delayed(const Duration(seconds: 2)); // Give sync some time
        Logger.success('Employee sync initiated');
        onStatusUpdate('Data sync complete');
      } catch (e) {
        Logger.error('Employee sync failed', error: e);
        errors.add('Data Sync: ${e.toString()}');
        onStatusUpdate('Data sync failed');
      }

      // Step 8: Finalize
      onProgress(InitializationStep.complete);
      onStatusUpdate('Initialization complete!');

      if (errors.isEmpty) {
        return const InitializationResult(
          success: true,
          message: 'All services initialized successfully',
        );
      } else {
        return InitializationResult(
          success: false,
          message: 'Some services failed to initialize',
          errors: errors,
        );
      }

    } catch (e) {
      Logger.error('Critical initialization error', error: e);
      return InitializationResult(
        success: false,
        message: 'Initialization failed: ${e.toString()}',
        errors: ['Critical error: ${e.toString()}'],
      );
    }
  }

  /// Retry initialization for failed services
  Future<void> retryInitialization({
    required Function(InitializationStep) onProgress,
    required Function(String) onStatusUpdate,
  }) async {
    await initializeApp(
      onProgress: onProgress,
      onStatusUpdate: onStatusUpdate,
    );
  }
}

/// Steps in the initialization process
enum InitializationStep {
  database,
  mlModel,
  faceEncoding,
  faceRecognition,
  employeeData,
  backgroundServices,
  syncData,
  complete,
}

/// Result of initialization process
class InitializationResult {
  final bool success;
  final String message;
  final List<String> errors;
  final bool isCritical;

  const InitializationResult({
    required this.success,
    required this.message,
    this.errors = const [],
    this.isCritical = false,
  });
}

/// Extension to get display names for initialization steps
extension InitializationStepExtension on InitializationStep {
  String get displayName {
    switch (this) {
      case InitializationStep.database:
        return 'Database';
      case InitializationStep.mlModel:
        return 'ML Model';
      case InitializationStep.faceEncoding:
        return 'Face Encoding';
      case InitializationStep.faceRecognition:
        return 'Face Recognition';
      case InitializationStep.employeeData:
        return 'Employee Data';
      case InitializationStep.backgroundServices:
        return 'Background Services';
      case InitializationStep.syncData:
        return 'Data Sync';
      case InitializationStep.complete:
        return 'Complete';
    }
  }

  IconData get icon {
    switch (this) {
      case InitializationStep.database:
        return Icons.storage;
      case InitializationStep.mlModel:
        return Icons.psychology;
      case InitializationStep.faceEncoding:
        return Icons.fingerprint;
      case InitializationStep.faceRecognition:
        return Icons.face_retouching_natural;
      case InitializationStep.employeeData:
        return Icons.people;
      case InitializationStep.backgroundServices:
        return Icons.settings_applications;
      case InitializationStep.syncData:
        return Icons.sync;
      case InitializationStep.complete:
        return Icons.check_circle;
    }
  }
}