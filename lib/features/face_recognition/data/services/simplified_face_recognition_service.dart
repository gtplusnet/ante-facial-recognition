import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/utils/logger.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../../employee/data/models/face_encoding_model.dart';
import '../../../employee/data/datasources/employee_local_datasource.dart';
import 'face_encoding_service.dart';

/// Simplified face recognition service for clean integration
/// Handles face recognition logic with a streamlined interface
@singleton
class SimplifiedFaceRecognitionService {
  final FaceEncodingService _faceEncodingService;
  final EmployeeLocalDataSource _employeeDataSource;

  // In-memory storage for employees and encodings
  final Map<String, Employee> _employees = {};
  final Map<String, Float32List> _encodings = {};

  // Recognition settings
  static const double _confidenceThreshold = 0.7;
  static const double _qualityThreshold = 0.8;

  bool _isInitialized = false;

  SimplifiedFaceRecognitionService({
    required FaceEncodingService faceEncodingService,
    required EmployeeLocalDataSource employeeDataSource,
  })  : _faceEncodingService = faceEncodingService,
        _employeeDataSource = employeeDataSource;

  /// Initialize the service and load employees
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.info('Initializing simplified face recognition service');

      // Initialize face encoding service
      await _faceEncodingService.initialize();

      // Load employees from database
      await _loadEmployees();

      _isInitialized = true;
      Logger.success('Simplified face recognition service initialized with ${_employees.length} employees');
    } catch (e) {
      Logger.error('Failed to initialize simplified face recognition service', error: e);
      throw Exception('Face recognition initialization failed: $e');
    }
  }

  /// Load employees and their face encodings
  Future<void> _loadEmployees() async {
    try {
      final employees = await _employeeDataSource.getAllEmployees();

      _employees.clear();
      _encodings.clear();

      for (final employee in employees) {
        _employees[employee.id] = employee;

        // Load face encoding if available
        if (employee.faceEncodings.isNotEmpty) {
          // Use the first face encoding for simplicity
          final encoding = employee.faceEncodings.first;
          _encodings[employee.id] = Float32List.fromList(encoding.embedding);
        }
      }

      Logger.info('Loaded ${_employees.length} employees, ${_encodings.length} have face encodings');
    } catch (e) {
      Logger.error('Failed to load employees', error: e);
      throw Exception('Employee loading failed: $e');
    }
  }

  /// Process camera frame for face recognition
  Future<FaceRecognitionResult?> processFrame(
    CameraImage frame,
    CameraDescription cameraDescription,
  ) async {
    if (!_isInitialized) {
      throw Exception('Service not initialized');
    }

    if (_encodings.isEmpty) {
      return const FaceRecognitionResult.noEmployees();
    }

    try {
      Logger.debug('Processing frame for face recognition');

      // Extract face encoding from frame
      final encodingResult = await _faceEncodingService.extractFromCameraImage(
        frame,
        cameraDescription,
      );

      if (encodingResult == null) {
        return const FaceRecognitionResult.noFace();
      }

      // Check face quality
      if (encodingResult.quality < _qualityThreshold) {
        return FaceRecognitionResult.poorQuality(
          quality: encodingResult.quality,
          message: _getQualityMessage(encodingResult.quality),
        );
      }

      // Find best match
      final matchResult = _faceEncodingService.findBestMatch(
        encodingResult.embedding,
        _encodings,
        threshold: _confidenceThreshold,
      );

      if (matchResult == null || !matchResult.isMatch) {
        return const FaceRecognitionResult.unknown();
      }

      final employee = _employees[matchResult.matchedId];
      if (employee == null) {
        return const FaceRecognitionResult.unknown();
      }

      return FaceRecognitionResult.matched(
        employee: employee,
        confidence: matchResult.confidence,
        quality: encodingResult.quality,
      );
    } catch (e) {
      Logger.error('Failed to process frame for face recognition', error: e);
      return FaceRecognitionResult.error(e.toString());
    }
  }

  /// Reload employees (useful for sync updates)
  Future<void> reloadEmployees() async {
    await _loadEmployees();
  }

  /// Get quality improvement message based on quality score
  String _getQualityMessage(double quality) {
    if (quality < 0.3) {
      return 'Please move closer to the camera';
    } else if (quality < 0.5) {
      return 'Look directly at the camera';
    } else if (quality < 0.8) {
      return 'Hold steady and ensure good lighting';
    } else {
      return 'Face quality good';
    }
  }

  /// Get current stats
  FaceRecognitionStats get stats => FaceRecognitionStats(
        totalEmployees: _employees.length,
        employeesWithEncodings: _encodings.length,
        isInitialized: _isInitialized,
      );

  /// Cleanup resources
  Future<void> dispose() async {
    _employees.clear();
    _encodings.clear();
    _isInitialized = false;
    Logger.info('Simplified face recognition service disposed');
  }
}

/// Result of face recognition processing
class FaceRecognitionResult {
  final FaceRecognitionResultType type;
  final Employee? employee;
  final double? confidence;
  final double? quality;
  final String? message;

  const FaceRecognitionResult._({
    required this.type,
    this.employee,
    this.confidence,
    this.quality,
    this.message,
  });

  const FaceRecognitionResult.noFace() : this._(type: FaceRecognitionResultType.noFace);

  const FaceRecognitionResult.noEmployees() : this._(type: FaceRecognitionResultType.noEmployees);

  const FaceRecognitionResult.poorQuality({
    required double quality,
    required String message,
  }) : this._(
          type: FaceRecognitionResultType.poorQuality,
          quality: quality,
          message: message,
        );

  const FaceRecognitionResult.unknown() : this._(type: FaceRecognitionResultType.unknown);

  const FaceRecognitionResult.matched({
    required Employee employee,
    required double confidence,
    required double quality,
  }) : this._(
          type: FaceRecognitionResultType.matched,
          employee: employee,
          confidence: confidence,
          quality: quality,
        );

  const FaceRecognitionResult.error(String message)
      : this._(type: FaceRecognitionResultType.error, message: message);

  bool get isSuccess => type == FaceRecognitionResultType.matched;
  bool get isError => type == FaceRecognitionResultType.error;
  bool get needsBetterQuality => type == FaceRecognitionResultType.poorQuality;
}

/// Type of face recognition result
enum FaceRecognitionResultType {
  noFace,
  noEmployees,
  poorQuality,
  unknown,
  matched,
  error,
}

/// Face recognition service statistics
class FaceRecognitionStats {
  final int totalEmployees;
  final int employeesWithEncodings;
  final bool isInitialized;

  const FaceRecognitionStats({
    required this.totalEmployees,
    required this.employeesWithEncodings,
    required this.isInitialized,
  });

  double get encodingCoverage => totalEmployees > 0
      ? employeesWithEncodings / totalEmployees
      : 0.0;
}