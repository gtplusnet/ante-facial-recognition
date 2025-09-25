import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/config/face_recognition_config.dart';
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
  final FaceRecognitionConfig _config = FaceRecognitionConfig();

  // In-memory storage for employees and encodings
  final Map<String, Employee> _employees = {};
  final Map<String, Float32List> _encodings = {};
  final Map<String, List<Float32List>> _multiEncodings = {};

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
      _multiEncodings.clear();

      for (final employee in employees) {
        _employees[employee.id] = employee;

        // Load ALL face encodings for better matching
        if (employee.faceEncodings.isNotEmpty) {
          // Store all encodings for multi-encoding matching
          _multiEncodings[employee.id] = employee.faceEncodings
              .map((e) => Float32List.fromList(e.embedding))
              .toList();

          // Keep first encoding for backward compatibility
          _encodings[employee.id] = Float32List.fromList(
            employee.faceEncodings.first.embedding,
          );
        }
      }

      Logger.info('Loaded ${_employees.length} employees');
      Logger.info('${_multiEncodings.length} employees have face encodings');
      Logger.info('Total encodings: ${_multiEncodings.values.expand((e) => e).length}');
    } catch (e) {
      Logger.error('Failed to load employees', error: e);
      throw Exception('Employee loading failed: $e');
    }
  }

  /// Public method to reload employees (for use after adding/deleting face images)
  Future<void> loadEmployees() async {
    await _loadEmployees();
  }

  /// Process camera frame for face recognition
  Future<FaceRecognitionResult?> processFrame(
    CameraImage frame,
    CameraDescription cameraDescription,
  ) async {
    Logger.info('>>> SimplifiedFaceRecognitionService.processFrame START <<<');
    Logger.info('Service initialized: $_isInitialized');
    Logger.info('Total employees: ${_employees.length}');
    Logger.info('Total encodings: ${_encodings.length}');
    Logger.info('Quality threshold: ${_config.qualityThreshold}');
    Logger.info('Confidence threshold: ${_config.confidenceThreshold}');

    if (!_isInitialized) {
      Logger.error('Service not initialized - throwing exception');
      throw Exception('Service not initialized');
    }

    if (_encodings.isEmpty) {
      Logger.warning('No encodings available - returning noEmployees');
      return const FaceRecognitionResult.noEmployees();
    }

    try {
      final frameStopwatch = Stopwatch()..start();

      Logger.info('Processing frame for face recognition');

      // Extract face encoding from frame
      Logger.info('Step 1: Extracting face encoding from camera image...');
      final encodingStopwatch = Stopwatch()..start();
      final encodingResult = await _faceEncodingService.extractFromCameraImage(
        frame,
        cameraDescription,
      );
      encodingStopwatch.stop();

      Logger.info('Face encoding extraction completed in ${encodingStopwatch.elapsedMilliseconds}ms');

      if (encodingResult == null) {
        Logger.info('No face encoding result - returning noFace');
        return const FaceRecognitionResult.noFace();
      }

      Logger.success('Face encoding extracted successfully');
      Logger.info('Encoding quality: ${encodingResult.quality}');
      Logger.info('Encoding face bounds: ${encodingResult.face.bounds.left}, ${encodingResult.face.bounds.top}, ${encodingResult.face.bounds.width}x${encodingResult.face.bounds.height}');
      Logger.info('Embedding length: ${encodingResult.embedding.length}');

      // Check face quality
      Logger.info('Step 2: Checking face quality...');
      if (encodingResult.quality < _config.qualityThreshold) {
        final message = _getQualityMessage(encodingResult.quality);
        Logger.warning('Poor quality detected: ${encodingResult.quality} < ${_config.qualityThreshold}');
        Logger.warning('Quality message: $message');
        return FaceRecognitionResult.poorQuality(
          quality: encodingResult.quality,
          message: message,
        );
      }

      Logger.success('Face quality acceptable: ${encodingResult.quality}');

      // Find best match using multi-encoding approach
      Logger.info('Step 3: Finding best match...');
      Logger.info('Available employee IDs for matching: ${_multiEncodings.keys.toList()}');

      final matchStopwatch = Stopwatch()..start();

      // Try multi-encoding matching first
      // Use faceMatchDistance (0.6) instead of confidenceThreshold (0.7)
      Logger.info('Using distance threshold: ${_config.faceMatchDistance} (not confidence threshold: ${_config.confidenceThreshold})');
      final matchResult = _findBestMultiEncodingMatch(
        encodingResult.embedding,
        threshold: _config.faceMatchDistance,  // Use distance threshold, not confidence
      );

      matchStopwatch.stop();

      Logger.info('Face matching completed in ${matchStopwatch.elapsedMilliseconds}ms');

      if (matchResult == null || !matchResult.isMatch) {
        Logger.warning('No match found or confidence below threshold');
        if (matchResult != null) {
          Logger.info('Best match confidence: ${matchResult.confidence}');
          Logger.info('Best match distance: ${matchResult.distance}');
          Logger.info('Threshold: ${_config.confidenceThreshold}');
        }
        return const FaceRecognitionResult.unknown();
      }

      Logger.success('Match found!');
      Logger.info('Matched ID: ${matchResult.matchedId}');
      Logger.info('Match confidence: ${matchResult.confidence}');
      Logger.info('Match distance: ${matchResult.distance}');

      final employee = _employees[matchResult.matchedId];
      if (employee == null) {
        Logger.error('Employee not found for matched ID: ${matchResult.matchedId}');
        return const FaceRecognitionResult.unknown();
      }

      frameStopwatch.stop();
      Logger.success('RECOGNITION SUCCESS: ${employee.name}');
      Logger.info('Total processing time: ${frameStopwatch.elapsedMilliseconds}ms');
      Logger.info('>>> SimplifiedFaceRecognitionService.processFrame END <<<');

      return FaceRecognitionResult.matched(
        employee: employee,
        confidence: matchResult.confidence,
        quality: encodingResult.quality,
      );
    } catch (e) {
      Logger.error('Failed to process frame for face recognition', error: e);
      Logger.info('>>> SimplifiedFaceRecognitionService.processFrame END (ERROR) <<<');
      return FaceRecognitionResult.error(e.toString());
    }
  }

  /// Process image bytes for face recognition (for re-processing stored images)
  Future<FaceRecognitionResult?> processImageBytes(Uint8List imageBytes) async {
    Logger.info('>>> SimplifiedFaceRecognitionService.processImageBytes START <<<');
    Logger.info('Processing image bytes of size: ${imageBytes.length}');
    Logger.info('Config - Confidence: ${_config.confidenceThreshold}, Quality: ${_config.qualityThreshold}');

    if (!_isInitialized) {
      Logger.error('Service not initialized');
      throw Exception('Service not initialized');
    }

    if (_encodings.isEmpty) {
      Logger.warning('No encodings available - returning noEmployees');
      return const FaceRecognitionResult.noEmployees();
    }

    try {
      final stopwatch = Stopwatch()..start();

      // Extract face encoding from image bytes
      Logger.info('Step 1: Extracting face encoding from image bytes...');
      final encodingResult = await _faceEncodingService.extractFromImageBytes(imageBytes);

      if (encodingResult == null) {
        Logger.info('No face encoding result - returning noFace');
        return const FaceRecognitionResult.noFace();
      }

      Logger.success('Face encoding extracted successfully');
      Logger.info('Encoding quality: ${encodingResult.quality}');
      Logger.info('Embedding length: ${encodingResult.embedding.length}');

      // Check face quality
      Logger.info('Step 2: Checking face quality...');
      if (encodingResult.quality < _config.qualityThreshold) {
        final message = _getQualityMessage(encodingResult.quality);
        Logger.warning('Poor quality detected: ${encodingResult.quality} < ${_config.qualityThreshold}');
        return FaceRecognitionResult.poorQuality(
          quality: encodingResult.quality,
          message: message,
        );
      }

      Logger.success('Face quality acceptable: ${encodingResult.quality}');

      // Find best match
      Logger.info('Step 3: Finding best match...');
      Logger.info('Using distance threshold: ${_config.faceMatchDistance} (not confidence threshold: ${_config.confidenceThreshold})');
      final matchResult = _faceEncodingService.findBestMatch(
        encodingResult.embedding,
        _encodings,
        threshold: _config.faceMatchDistance,  // Use distance threshold, not confidence
      );

      if (matchResult == null || !matchResult.isMatch) {
        Logger.warning('No match found or confidence below threshold');
        if (matchResult != null) {
          Logger.info('Best match confidence: ${matchResult.confidence}');
          Logger.info('Best match distance: ${matchResult.distance}');
        }
        return const FaceRecognitionResult.unknown();
      }

      Logger.success('Match found!');
      Logger.info('Matched ID: ${matchResult.matchedId}');
      Logger.info('Match confidence: ${matchResult.confidence}');

      final employee = _employees[matchResult.matchedId];
      if (employee == null) {
        Logger.error('Employee not found for matched ID: ${matchResult.matchedId}');
        return const FaceRecognitionResult.unknown();
      }

      stopwatch.stop();
      Logger.success('RECOGNITION SUCCESS: ${employee.name}');
      Logger.info('Total processing time: ${stopwatch.elapsedMilliseconds}ms');
      Logger.info('>>> SimplifiedFaceRecognitionService.processImageBytes END <<<');

      return FaceRecognitionResult.matched(
        employee: employee,
        confidence: matchResult.confidence,
        quality: encodingResult.quality,
      );
    } catch (e) {
      Logger.error('Failed to process image bytes for face recognition', error: e);
      Logger.info('>>> SimplifiedFaceRecognitionService.processImageBytes END (ERROR) <<<');
      return FaceRecognitionResult.error(e.toString());
    }
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

  /// Find best match using multiple encodings per employee
  SimpleFaceMatchResult? _findBestMultiEncodingMatch(
    Float32List inputEmbedding, {
    required double threshold,
  }) {
    Logger.info('=== MATCHING PROCESS START ===');
    Logger.info('Input embedding length: ${inputEmbedding.length}');
    Logger.info('Threshold: $threshold');
    Logger.info('Number of employees to match: ${_multiEncodings.length}');

    if (_multiEncodings.isEmpty) {
      Logger.warning('No multi-encodings available, falling back to single encoding matching');
      // Fall back to single encoding matching
      return _faceEncodingService.findBestMatch(
        inputEmbedding,
        _encodings,
        threshold: threshold,
      );
    }

    String? bestEmployeeId;
    double bestConfidence = 0;
    double bestDistance = double.infinity;

    // Log first few values of input embedding for debugging
    final inputSample = inputEmbedding.take(5).map((e) => e.toStringAsFixed(4)).join(', ');
    Logger.debug('Input embedding sample (first 5): [$inputSample]');

    // Check each employee's multiple encodings
    int employeeIndex = 0;
    for (final entry in _multiEncodings.entries) {
      employeeIndex++;
      final employeeId = entry.key;
      final encodings = entry.value;
      final employeeName = _employees[employeeId]?.name ?? 'Unknown';

      Logger.debug('Checking employee $employeeIndex/${_multiEncodings.length}: $employeeName (ID: $employeeId)');
      Logger.debug('  - Number of encodings: ${encodings.length}');

      // Find the best match among all encodings for this employee
      double minDistance = double.infinity;
      int encodingIndex = 0;
      for (final encoding in encodings) {
        encodingIndex++;
        // Compare faces using existing method
        final result = _faceEncodingService.compareFaces(
          inputEmbedding,
          encoding,
          threshold: threshold,
        );

        Logger.debug('    Encoding $encodingIndex/${encodings.length}: distance=${result.distance.toStringAsFixed(4)}, similarity=${result.similarity.toStringAsFixed(4)}');

        if (result.distance < minDistance) {
          minDistance = result.distance;
          Logger.debug('    NEW MIN DISTANCE for $employeeName: ${minDistance.toStringAsFixed(4)}');
        }
      }

      // Convert distance to confidence (0.0 to 1.0)
      // Smaller distance means higher confidence
      final confidence = 1.0 / (1.0 + minDistance);

      Logger.debug('  Final for $employeeName: minDistance=${minDistance.toStringAsFixed(4)}, confidence=${confidence.toStringAsFixed(4)}');
      Logger.debug('  Meets threshold? ${minDistance < threshold} (${minDistance.toStringAsFixed(4)} < $threshold)');

      if (confidence > bestConfidence && minDistance < threshold) {
        Logger.success('  ✓ NEW BEST MATCH: $employeeName');
        bestEmployeeId = employeeId;
        bestConfidence = confidence;
        bestDistance = minDistance;
      }
    }

    if (bestEmployeeId != null) {
      final matchedEmployee = _employees[bestEmployeeId]?.name ?? 'Unknown';
      Logger.success('=== MATCH FOUND ===');
      Logger.success('Employee: $matchedEmployee (ID: $bestEmployeeId)');
      Logger.success('Confidence: ${(bestConfidence * 100).toStringAsFixed(1)}%');
      Logger.success('Distance: ${bestDistance.toStringAsFixed(4)}');
      Logger.info('=== MATCHING PROCESS END ===');

      return SimpleFaceMatchResult(
        isMatch: true,
        distance: bestDistance,
        similarity: 1.0 - bestDistance,
        confidence: bestConfidence,
        threshold: threshold,
        matchedId: bestEmployeeId,
      );
    }

    Logger.warning('=== NO MATCH FOUND ===');
    Logger.warning('Best distance was: ${bestDistance.toStringAsFixed(4)} (threshold: $threshold)');
    Logger.info('=== MATCHING PROCESS END ===');
    return null;
  }

  /// Reload employees and their face encodings
  Future<void> reloadEmployees() async {
    Logger.info('Reloading employees and face encodings...');
    await _loadEmployees();
    Logger.info('Reloaded ${_employees.length} employees, ${_encodings.length} have face encodings');
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