import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/platform/render_aware_widget.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../../employee/presentation/bloc/employee_bloc.dart';
import '../../../employee/presentation/bloc/employee_event.dart' as employee_events;
import '../../data/services/simplified_face_recognition_service.dart';
import '../widgets/employee_confirmation_dialog.dart';

/// Simplified camera screen for face recognition
/// Clean interface focused on face detection and recognition
class SimplifiedCameraScreen extends StatefulWidget {
  const SimplifiedCameraScreen({super.key});

  @override
  State<SimplifiedCameraScreen> createState() => _SimplifiedCameraScreenState();
}

class _SimplifiedCameraScreenState extends State<SimplifiedCameraScreen>
    with WidgetsBindingObserver {
  // Camera and face detection
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  // Face recognition service
  late final SimplifiedFaceRecognitionService _faceRecognitionService;

  // Processing control
  bool _isProcessing = false;
  bool _isDisposing = false;
  DateTime? _lastProcessTime;
  static const _processingInterval = Duration(milliseconds: 800);

  // Frame management
  int _frameDropCount = 0;
  static const int _maxFrameDrops = 5;

  // Error handling and retry logic
  int _consecutiveErrors = 0;
  DateTime? _lastErrorTime;
  static const int _maxConsecutiveErrors = 5;
  static const Duration _errorCooldownDuration = Duration(seconds: 10);

  // Camera restart logic
  bool _isRestartingCamera = false;
  int _cameraRestartAttempts = 0;
  static const int _maxCameraRestarts = 3;

  // Current face state
  bool _isFaceDetected = false;
  double _faceQuality = 0.0;
  String _statusMessage = 'Initializing...';
  bool _isFaceNotRecognized = false;
  DateTime? _lastRecognitionTime;
  FaceRecognitionStats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize face recognition service
    _faceRecognitionService = getIt<SimplifiedFaceRecognitionService>();

    // Initialize services
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });

    _initializeCamera();
    _setSystemUI();
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _faceDetector.close();
    _restoreSystemUI();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposing || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _safePauseCamera();
    } else if (state == AppLifecycleState.resumed && !_isDisposing) {
      _initializeCamera();
    }
  }

  Future<void> _safePauseCamera() async {
    try {
      Logger.info('Pausing camera due to app lifecycle change');
      await _stopImageStream();
      // Small delay to ensure all frames are processed
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      Logger.error('Error pausing camera', error: e);
    }
  }

  void _setSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  Future<void> _initializeServices() async {
    try {
      setState(() {
        _statusMessage = 'Initializing face recognition...';
      });

      // Initialize face recognition service
      await _faceRecognitionService.initialize();

      // Load employees using BLoC for UI updates
      context.read<EmployeeBloc>().add(const employee_events.LoadEmployees());

      // Get stats
      _stats = _faceRecognitionService.stats;

      setState(() {
        _statusMessage = 'Ready (${_stats?.totalEmployees ?? 0} employees)';
      });

      Logger.info('Simplified camera services initialized');
    } catch (e) {
      Logger.error('Failed to initialize services', error: e);
      setState(() {
        _statusMessage = 'Initialization failed';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Ensure previous camera is properly disposed
      await _disposeCamera();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        Logger.error('No cameras available');
        _showSnackBar('No cameras available', Colors.red);
        return;
      }

      // Use front camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      Logger.info('Initializing camera: ${camera.name}');

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // Use medium for better performance
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // Required for ML Kit face detection
      );

      await _cameraController!.initialize();

      if (!mounted || _isDisposing) {
        Logger.warning('Widget no longer mounted or disposing, cleaning up camera');
        await _disposeCamera();
        return;
      }

      if (_cameraController!.value.isInitialized) {
        Logger.success('Camera initialized successfully');
        setState(() {});

        // Add small delay to ensure camera is fully ready
        await Future.delayed(const Duration(milliseconds: 100));
        _startImageStream();
      } else {
        throw Exception('Camera failed to initialize properly');
      }
    } catch (e) {
      Logger.error('Camera initialization failed', error: e);
      _showSnackBar('Camera initialization failed: ${e.toString()}', Colors.red);

      // Attempt cleanup on error
      await _disposeCamera();
    }
  }

  void _startImageStream() {
    if (_isDisposing || _cameraController?.value.isInitialized != true) return;

    try {
      _cameraController!.startImageStream((CameraImage image) {
        // Comprehensive lifecycle and disposal checks
        if (_isDisposing ||
            !mounted ||
            _cameraController?.value.isInitialized != true ||
            _cameraController?.value.isStreamingImages != true) {
          return;
        }

        // Skip frame if already processing (prevent backlog)
        if (_isProcessing) {
          _frameDropCount++;
          if (_frameDropCount > _maxFrameDrops) {
            Logger.warning('Dropping frames due to slow processing: $_frameDropCount');
            _frameDropCount = 0; // Reset counter
          }
          return;
        }

        // Reset frame drop counter on successful processing
        _frameDropCount = 0;

        // Throttle processing
        if (_lastProcessTime != null &&
            DateTime.now().difference(_lastProcessTime!) < _processingInterval) {
          return;
        }

        _isProcessing = true;
        _lastProcessTime = DateTime.now();

        // Process frame with enhanced error handling
        _processFrameSafely(image).then((_) {
          // Success - processing complete
        }).catchError((e) {
          Logger.error('Frame processing error', error: e);
          _handleProcessingError('Frame processing', e);
        }).whenComplete(() {
          if (!_isDisposing) {
            _isProcessing = false;
          }
        });
      });
    } catch (e) {
      Logger.error('Failed to start image stream', error: e);
      _showSnackBar('Failed to start camera stream', Colors.red);
    }
  }

  /// Safe wrapper for frame processing with disposal checks
  Future<void> _processFrameSafely(CameraImage image) async {
    if (_isDisposing || !mounted) {
      return;
    }
    return _processFrame(image);
  }

  Future<void> _stopImageStream() async {
    try {
      if (_cameraController?.value.isStreamingImages == true) {
        Logger.info('Stopping image stream...');
        await _cameraController!.stopImageStream();

        // Wait for any pending frame processing to complete
        int attempts = 0;
        while (_isProcessing && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 50));
          attempts++;
        }

        Logger.success('Image stream stopped successfully');
      } else {
        Logger.info('Image stream was not active');
      }
    } catch (e) {
      Logger.error('Error stopping image stream', error: e);
      // Continue with disposal even if stop fails
    }
  }

  Future<void> _disposeCamera() async {
    try {
      Logger.info('Starting camera disposal...');

      // Stop image stream first
      await _stopImageStream();

      // Add delay to ensure all ImageProxy instances are closed
      // This prevents the NullPointerException in camera_android_camerax
      await Future.delayed(const Duration(milliseconds: 500));

      if (_cameraController != null) {
        Logger.info('Disposing camera controller...');
        await _cameraController!.dispose();
        _cameraController = null;
        Logger.success('Camera disposed successfully');
      } else {
        Logger.info('Camera controller was already null');
      }
    } catch (e) {
      Logger.error('Error disposing camera', error: e);
      // Force null the controller even if disposal fails
      _cameraController = null;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    // Enhanced verification with disposal check
    if (_isDisposing ||
        !mounted ||
        _cameraController?.value.isInitialized != true ||
        _cameraController?.value.isStreamingImages != true) {
      return;
    }

    // Skip processing if we're in error cooldown
    if (_isInErrorCooldown()) {
      return;
    }

    try {
      // TEMPORARY: Simulate face detection for testing quality indicator
      // This will cycle through different quality levels every few seconds
      final now = DateTime.now();
      final seconds = now.second;

      // Simulate face detection based on time
      final wasDetected = _isFaceDetected;
      final oldQuality = _faceQuality;

      if (seconds % 10 < 3) {
        // First 3 seconds: No face
        _isFaceDetected = false;
        _faceQuality = 0.0;
      } else if (seconds % 10 < 6) {
        // Next 3 seconds: Poor quality face
        _isFaceDetected = true;
        _faceQuality = 0.4;
      } else if (seconds % 10 < 9) {
        // Next 3 seconds: Medium quality face
        _isFaceDetected = true;
        _faceQuality = 0.7;
      } else {
        // Last 1 second: High quality face (90%+)
        _isFaceDetected = true;
        _faceQuality = 0.95;
      }

      // Update UI if state changed significantly
      if (wasDetected != _isFaceDetected || (oldQuality - _faceQuality).abs() > 0.1) {
        if (mounted) {
          setState(() {});
        }
      }

      // Reset error state on successful processing
      if (_consecutiveErrors > 0) {
        _resetErrorState();
      }

      // Trigger face recognition if quality is good and enough time has passed
      if (_faceQuality >= 0.8 && _canTriggerRecognition()) {
        await _triggerFaceRecognition(image);
      }

    } catch (e) {
      _handleProcessingError('Frame processing', e);

      // Reset face detection state on error
      if (_isFaceDetected && mounted) {
        _isFaceDetected = false;
        _faceQuality = 0.0;
        setState(() {});
      }
    }
  }

  Future<void> _triggerFaceRecognition(CameraImage image) async {
    try {
      setState(() {
        _statusMessage = 'Processing face...';
      });

      Logger.info('=== FACE RECOGNITION TRIGGERED ===');
      Logger.info('Face recognition triggered - Quality: ${(_faceQuality * 100).toInt()}%');
      Logger.info('Can trigger recognition: ${_canTriggerRecognition()}');
      Logger.info('Last recognition time: $_lastRecognitionTime');
      Logger.info('Is face not recognized: $_isFaceNotRecognized');

      // Process frame using simplified service
      final cameraDescription = _cameraController?.description;
      if (cameraDescription == null) {
        Logger.error('Camera description is null, cannot process frame');
        return;
      }

      Logger.info('Camera description: ${cameraDescription.name}, lens: ${cameraDescription.lensDirection}');
      Logger.info('Image dimensions: ${image.width}x${image.height}, format: ${image.format.group}');

      final stopwatch = Stopwatch()..start();

      Logger.info('Calling face recognition service...');
      final result = await _faceRecognitionService.processFrame(image, cameraDescription);

      stopwatch.stop();
      Logger.info('Face recognition service completed in ${stopwatch.elapsedMilliseconds}ms');

      if (result == null) {
        Logger.warning('Face recognition service returned null result');
        return;
      }

      Logger.info('Recognition result type: ${result.type}');
      Logger.info('Recognition result confidence: ${result.confidence}');
      Logger.info('Recognition result quality: ${result.quality}');
      Logger.info('Recognition result message: ${result.message}');
      if (result.employee != null) {
        Logger.info('Recognized employee: ${result.employee!.name} (ID: ${result.employee!.id})');
      }

      // Handle different result types
      Logger.info('=== PROCESSING RECOGNITION RESULT ===');
      switch (result.type) {
        case FaceRecognitionResultType.matched:
          Logger.success('MATCH FOUND: ${result.employee?.name}');
          if (result.employee != null) {
            Logger.info('Showing success dialog for: ${result.employee!.name}');
            setState(() {
              _statusMessage = 'Welcome, ${result.employee!.name}!';
              _isFaceNotRecognized = false; // Reset unrecognized state
              _lastRecognitionTime = DateTime.now();
            });
            _showSuccessDialog(result.employee!, result.confidence ?? 0.0);
          }
          break;

        case FaceRecognitionResultType.unknown:
          Logger.warning('UNKNOWN FACE: Face not recognized in database');
          setState(() {
            _statusMessage = 'Face not recognized';
            _isFaceNotRecognized = true;
            _lastRecognitionTime = DateTime.now();
          });
          _showUnrecognizedFaceOverlay();
          break;

        case FaceRecognitionResultType.poorQuality:
          Logger.warning('POOR QUALITY: ${result.message}');
          setState(() {
            _statusMessage = result.message ?? 'Poor face quality';
            _isFaceNotRecognized = false; // Reset unrecognized state
          });
          break;

        case FaceRecognitionResultType.noFace:
          Logger.debug('NO FACE: No face detected in image');
          setState(() {
            _statusMessage = 'No face detected';
            _isFaceNotRecognized = false; // Reset unrecognized state
          });
          break;

        case FaceRecognitionResultType.noEmployees:
          Logger.error('NO EMPLOYEES: No employees loaded for matching');
          setState(() {
            _statusMessage = 'No employees loaded';
            _isFaceNotRecognized = false; // Reset unrecognized state
          });
          break;

        case FaceRecognitionResultType.error:
          Logger.error('RECOGNITION ERROR: ${result.message}');
          _showSnackBar(result.message ?? 'Recognition error', Colors.red);
          setState(() {
            _statusMessage = 'Recognition error occurred';
            _isFaceNotRecognized = false; // Reset unrecognized state
          });
          break;
      }
      Logger.info('=== RECOGNITION RESULT PROCESSING COMPLETE ===');
    } catch (e) {
      _handleProcessingError('Face recognition', e);
    }
  }

  void _showSuccessDialog(Employee employee, double confidence) {
    EmployeeConfirmationDialog.show(
      context: context,
      employee: employee,
      confidence: confidence,
      currentStatus: null,
    );
  }

  /// Check if enough time has passed since the last recognition to allow a new one
  bool _canTriggerRecognition() {
    if (_lastRecognitionTime == null) return true;

    final timeSinceLastRecognition = DateTime.now().difference(_lastRecognitionTime!);

    // Allow new recognition after 5 seconds for successful matches
    // Allow new recognition after 3 seconds for failed matches
    final cooldownDuration = _isFaceNotRecognized
        ? const Duration(seconds: 3)
        : const Duration(seconds: 5);

    return timeSinceLastRecognition >= cooldownDuration;
  }


  double _calculateFaceQuality(Face face, CameraImage image) {
    final imageArea = image.width * image.height;
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final faceRatio = faceArea / imageArea;

    // Size score (ideal: 20-40% of image)
    double sizeScore = 1.0;
    if (faceRatio < 0.2) {
      sizeScore = faceRatio / 0.2;
    } else if (faceRatio > 0.4) {
      sizeScore = 0.4 / faceRatio;
    }

    // Center score
    final centerX = image.width / 2;
    final centerY = image.height / 2;
    final faceCenter = face.boundingBox.center;
    final distanceFromCenter = (faceCenter.dx - centerX).abs() / centerX +
                               (faceCenter.dy - centerY).abs() / centerY;
    final centerScore = (1.0 - distanceFromCenter / 2).clamp(0.0, 1.0);

    return (sizeScore * 0.6 + centerScore * 0.4).clamp(0.0, 1.0);
  }

  /// Handle processing errors with retry logic
  void _handleProcessingError(String operation, Object error) {
    _consecutiveErrors++;
    _lastErrorTime = DateTime.now();

    Logger.error('$operation failed (attempt $_consecutiveErrors)', error: error);

    // Check if this is a critical camera error that requires restart
    final errorStr = error.toString().toLowerCase();
    final isCriticalError = errorStr.contains('nullpointerexception') ||
                           errorStr.contains('imageproxy') ||
                           errorStr.contains('camera is closed') ||
                           errorStr.contains('camera not initialized');

    if (isCriticalError && !_isRestartingCamera) {
      Logger.warning('Critical camera error detected, attempting restart');
      _showSnackBar('Critical camera error - restarting camera...', Colors.orange);
      _restartCamera();
      return;
    }

    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _showSnackBar(
        'Multiple errors detected. Processing paused for ${_errorCooldownDuration.inSeconds}s',
        Colors.red,
      );

      setState(() {
        _statusMessage = 'Processing paused - multiple errors';
        _isFaceDetected = false;
        _faceQuality = 0.0;
      });

      // Auto-resume after cooldown
      Future.delayed(_errorCooldownDuration, () {
        if (mounted && !_isDisposing) {
          _resetErrorState();
          setState(() {
            _statusMessage = 'Ready (${_stats?.totalEmployees ?? 0} employees)';
          });
          Logger.info('Error recovery: Processing resumed');
        }
      });
    } else {
      // Show transient error message
      _showSnackBar('Processing error (${_consecutiveErrors}/$_maxConsecutiveErrors)', Colors.orange);

      setState(() {
        _statusMessage = 'Processing error - retrying...';
      });
    }
  }

  /// Reset error state on successful operations
  void _resetErrorState() {
    _consecutiveErrors = 0;
    _lastErrorTime = null;
  }

  /// Check if we're in error cooldown period
  bool _isInErrorCooldown() {
    if (_lastErrorTime == null || _consecutiveErrors < _maxConsecutiveErrors) {
      return false;
    }

    final timeSinceLastError = DateTime.now().difference(_lastErrorTime!);
    return timeSinceLastError < _errorCooldownDuration;
  }

  /// Restart camera when critical errors occur
  Future<void> _restartCamera() async {
    if (_isRestartingCamera || _isDisposing || _cameraRestartAttempts >= _maxCameraRestarts) {
      return;
    }

    _isRestartingCamera = true;
    _cameraRestartAttempts++;

    try {
      Logger.info('Attempting camera restart (attempt $_cameraRestartAttempts/$_maxCameraRestarts)');

      setState(() {
        _statusMessage = 'Restarting camera...';
      });

      // Force dispose current camera
      await _disposeCamera();

      // Wait a bit before reinitializing
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted || _isDisposing) {
        return;
      }

      // Reinitialize camera
      await _initializeCamera();

      // Reset error counters on successful restart
      _resetErrorState();
      _cameraRestartAttempts = 0;

      Logger.success('Camera restarted successfully');

      setState(() {
        _statusMessage = 'Camera restarted successfully';
      });

    } catch (e) {
      Logger.error('Camera restart failed (attempt $_cameraRestartAttempts)', error: e);

      if (_cameraRestartAttempts >= _maxCameraRestarts) {
        setState(() {
          _statusMessage = 'Camera restart failed - please restart app';
        });
        _showSnackBar('Camera restart failed multiple times. Please restart the app.', Colors.red);
      } else {
        // Schedule another restart attempt
        Future.delayed(const Duration(seconds: 5), _restartCamera);
      }
    } finally {
      _isRestartingCamera = false;
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RenderAwareWidget(
      showSeLinuxInfo: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview
            _buildCameraPreview(),

            // Face positioning guide
            _buildPositioningGuide(),

            // Quality indicator overlay
            _buildQualityIndicator(),

            // Unrecognized face overlay
            _buildUnrecognizedFaceOverlay(),

            // Top bar
            _buildTopBar(),

            // Bottom status
            _buildBottomStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController?.value.isInitialized != true) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0), // Mirror front camera
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildPositioningGuide() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(
          isFaceDetected: _isFaceDetected,
          faceQuality: _faceQuality,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildQualityIndicator() {
    if (!_isFaceDetected) {
      return const SizedBox.shrink();
    }

    final qualityPercent = (_faceQuality * 100).toInt();
    Color indicatorColor;
    IconData icon;

    if (_faceQuality >= 0.8) {
      indicatorColor = Colors.green;
      icon = Icons.check_circle;
    } else if (_faceQuality >= 0.6) {
      indicatorColor = Colors.orange;
      icon = Icons.warning;
    } else {
      indicatorColor = Colors.red;
      icon = Icons.error_outline;
    }

    return Stack(
      children: [
        // Regular quality indicator
        Positioned(
          top: MediaQuery.of(context).size.height * 0.25,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: indicatorColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: indicatorColor.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 18.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Quality: $qualityPercent%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Special 90%+ celebration indicator
        if (_faceQuality >= 0.9)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.18,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(25.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      color: Colors.white,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '🎯 EXCELLENT: $qualityPercent%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(
                      Icons.star,
                      color: Colors.white,
                      size: 20.sp,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUnrecognizedFaceOverlay() {
    if (!_isFaceNotRecognized) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.red.withOpacity(0.8),
              width: 4.0,
            ),
          ),
          child: Stack(
            children: [
              // Red overlay with opacity
              Container(
                color: Colors.red.withOpacity(0.1),
              ),

              // Center message
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_off,
                        color: Colors.white,
                        size: 48.sp,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'Face Not Recognized',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Please try again or contact administrator',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14.sp,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // Scanning animation indicator
              Positioned(
                bottom: MediaQuery.of(context).size.height * 0.2,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16.w,
                          height: 16.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Retrying...',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnrecognizedFaceOverlay() {
    // Auto-hide the overlay after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isFaceNotRecognized = false;
        });
      }
    });
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16.h,
          left: 20.w,
          right: 20.w,
          bottom: 16.h,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                'Face Recognition',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48), // Balance the back button
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatus() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 20.h,
          left: 20.w,
          right: 20.w,
          bottom: MediaQuery.of(context).padding.bottom + 20.h,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusIndicator(),
            SizedBox(height: 12.h),
            _buildInstructionText(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    String status;
    Color color;
    IconData icon;

    if (_statusMessage.contains('Processing') || _statusMessage.contains('Initializing')) {
      status = _statusMessage;
      color = Colors.orange;
      icon = Icons.hourglass_empty;
    } else if (_isFaceDetected) {
      status = 'Quality: ${(_faceQuality * 100).toInt()}%';
      color = _faceQuality >= 0.8 ? Colors.green : Colors.orange;
      icon = Icons.face;
    } else if (_statusMessage.contains('Ready')) {
      status = _statusMessage;
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (_statusMessage.contains('error') || _statusMessage.contains('failed')) {
      status = _statusMessage;
      color = Colors.red;
      icon = Icons.error;
    } else {
      status = _statusMessage;
      color = Colors.blue;
      icon = Icons.face_retouching_off;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20.sp),
          SizedBox(width: 8.w),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionText() {
    String instruction;

    if (!_isFaceDetected) {
      instruction = 'Position your face in the oval frame';
    } else if (_faceQuality < 0.8) {
      instruction = 'Move closer and look directly at camera';
    } else if (_statusMessage.contains('Processing')) {
      instruction = 'Hold steady for recognition...';
    } else if (_statusMessage.contains('Welcome')) {
      instruction = 'Recognition successful!';
    } else if (_statusMessage.contains('not recognized')) {
      instruction = 'Face not found in database';
    } else {
      instruction = 'Look at the camera to begin';
    }

    return Text(
      instruction,
      style: TextStyle(
        color: Colors.white70,
        fontSize: 16.sp,
        fontWeight: FontWeight.w400,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Simple face guide painter
class _FaceGuidePainter extends CustomPainter {
  final bool isFaceDetected;
  final double faceQuality;

  _FaceGuidePainter({
    required this.isFaceDetected,
    required this.faceQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate oval position and size
    final center = Offset(size.width / 2, size.height * 0.4);
    final ovalWidth = size.width * 0.7;
    final ovalHeight = ovalWidth * 1.3;

    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // Dark overlay with oval cutout
    final screenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);
    final overlayPath = Path.combine(PathOperation.difference, screenPath, ovalPath);

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withOpacity(0.6),
    );

    // Oval border color based on state
    Color borderColor = Colors.white;
    if (isFaceDetected) {
      if (faceQuality >= 0.8) {
        borderColor = Colors.green;
      } else if (faceQuality >= 0.6) {
        borderColor = Colors.orange;
      } else {
        borderColor = Colors.red;
      }
    }

    // Draw oval border
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) {
    return oldDelegate.isFaceDetected != isFaceDetected ||
           oldDelegate.faceQuality != faceQuality;
  }
}