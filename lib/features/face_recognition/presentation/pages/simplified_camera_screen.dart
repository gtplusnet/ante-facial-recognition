import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:visibility_detector/visibility_detector.dart';
// import 'package:wakelock_plus/wakelock_plus.dart'; // Temporarily disabled

import '../../../../core/config/face_recognition_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/platform/render_aware_widget.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/screen_keeper.dart';
import '../../../employee/domain/entities/employee.dart';
import '../../../employee/presentation/bloc/employee_bloc.dart';
import '../../../employee/presentation/bloc/employee_event.dart' as employee_events;
import '../../../logs/data/services/face_recognition_log_service.dart';
import '../../data/services/simplified_face_recognition_service.dart';
import '../widgets/employee_confirmation_dialog.dart';

/// Simplified camera screen for face recognition
/// Clean interface focused on face detection and recognition
class SimplifiedCameraScreen extends StatefulWidget {
  const SimplifiedCameraScreen({super.key});

  @override
  State<SimplifiedCameraScreen> createState() => _SimplifiedCameraScreenState();
}

// Camera state enum
enum CameraState {
  idle,
  initializing,
  streaming,
  paused,
  error,
}

class _SimplifiedCameraScreenState extends State<SimplifiedCameraScreen>
    with WidgetsBindingObserver, RouteAware {
  // Camera and face detection
  CameraController? _cameraController;
  CameraState _cameraState = CameraState.idle;
  bool _isVisible = false;
  Timer? _visibilityDebounceTimer;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate, // Changed to accurate mode for better detection
      enableClassification: true,
      enableContours: true,
      enableTracking: true,
      enableLandmarks: true, // Added landmarks for better feature detection
      minFaceSize: 0.05, // Further reduced to 5% to detect very small faces
    ),
  );

  // Face recognition service
  late final SimplifiedFaceRecognitionService _faceRecognitionService;

  // Face recognition log service
  late final FaceRecognitionLogService _logService;

  // Face recognition config
  final FaceRecognitionConfig _config = FaceRecognitionConfig();

  // Processing control
  bool _isProcessing = false;
  bool _isRecognizing = false;  // Separate flag for face recognition
  bool _isDisposing = false;
  bool _isDialogOpen = false;  // Track if success dialog is visible
  DateTime? _lastProcessTime;
  static const _processingInterval = Duration(milliseconds: 200);

  // Frame management
  int _frameDropCount = 0;
  int _frameCounter = 0;
  static const int _maxFrameDrops = 5;
  int _frameSkipInterval = 1; // Process every Nth frame, increases with load

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
  FaceRecognitionStats? _stats;
  bool _mlKitError = false;

  // Face detection for logging
  List<Face>? _detectedFaces;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Keep screen on using platform channel
    ScreenKeeper.enableKeepAwake();

    // Initialize face recognition service
    _faceRecognitionService = getIt<SimplifiedFaceRecognitionService>();

    // Initialize log service
    _logService = getIt<FaceRecognitionLogService>();

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
    AppRouter.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _faceDetector.close();
    _restoreSystemUI();

    // Disable screen keep-awake when leaving the screen
    ScreenKeeper.disableKeepAwake();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer
    AppRouter.routeObserver.subscribe(this, ModalRoute.of(context) as ModalRoute<void>);
  }

  // RouteAware methods
  @override
  void didPush() {
    // Called when this route has been pushed
    Logger.info('SimplifiedCameraScreen route pushed');
  }

  @override
  void didPopNext() {
    // Called when the route above this one has been popped off
    Logger.info('SimplifiedCameraScreen became visible - resuming camera');
    if (!_isDisposing && mounted) {
      _initializeCamera();
    }
  }

  @override
  void didPushNext() {
    // Called when a new route has been pushed on top of this one
    Logger.info('SimplifiedCameraScreen hidden by new route - pausing camera');
    _safePauseCamera();
  }

  @override
  void didPop() {
    // Called when this route has been popped off
    Logger.info('SimplifiedCameraScreen route popped');
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
      _cameraState = CameraState.initializing;

      // Ensure previous camera is properly disposed
      await _disposeCamera();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        Logger.error('No cameras available');
        _showSnackBar('No cameras available', Colors.red);
        return;
      }

      // Log all available cameras
      Logger.info('Available cameras: ${cameras.length}');
      for (int i = 0; i < cameras.length; i++) {
        Logger.info('Camera $i: ${cameras[i].name}, Direction: ${cameras[i].lensDirection}, Orientation: ${cameras[i].sensorOrientation}');
      }

      // Use front camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final cameraIndex = cameras.indexOf(camera);
      Logger.info('Selected camera index: $cameraIndex');
      Logger.info('Selected camera: ${camera.name}, Direction: ${camera.lensDirection}, Orientation: ${camera.sensorOrientation}');

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high, // Using high resolution for better compatibility
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Force consistent format
      );

      await _cameraController!.initialize();

      if (!mounted || _isDisposing) {
        Logger.warning('Widget no longer mounted or disposing, cleaning up camera');
        await _disposeCamera();
        return;
      }

      if (_cameraController!.value.isInitialized) {
        Logger.success('Camera initialized successfully');
        _cameraState = CameraState.streaming;
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
    Logger.info('=== STARTING IMAGE STREAM ===');

    if (_isDisposing) {
      Logger.warning('Cannot start stream - widget is disposing');
      return;
    }

    if (_cameraController?.value.isInitialized != true) {
      Logger.warning('Cannot start stream - camera not initialized');
      return;
    }

    try {
      Logger.info('Calling startImageStream on camera controller...');
      _cameraController!.startImageStream((CameraImage image) {
        Logger.debug('Camera frame received: ${image.width}x${image.height}, format: ${image.format.group}');
        // Comprehensive lifecycle and disposal checks
        if (_isDisposing ||
            !mounted ||
            _cameraController?.value.isInitialized != true ||
            _cameraController?.value.isStreamingImages != true) {
          return;
        }

        // Dynamic frame skipping based on processing load
        _frameCounter++;

        // Skip frame if already processing or dialog is open
        if (_isProcessing || _isDialogOpen) {
          _frameDropCount++;
          // Increase skip interval if dropping too many frames
          if (_frameDropCount > _maxFrameDrops) {
            Logger.warning('Dropping frames due to slow processing: $_frameDropCount');
            _frameSkipInterval = (_frameSkipInterval * 2).clamp(1, 8);
            Logger.info('Increased frame skip interval to: $_frameSkipInterval');
            _frameDropCount = 0; // Reset counter
          }
          return;
        }

        // Skip frames based on interval to reduce load
        if (_frameCounter % _frameSkipInterval != 0) {
          return;
        }

        // Reset frame drop counter and adjust skip interval on successful processing
        _frameDropCount = 0;
        // Gradually reduce skip interval when processing is smooth
        if (_frameSkipInterval > 1 && _frameCounter % 30 == 0) {
          _frameSkipInterval = (_frameSkipInterval - 1).clamp(1, 8);
          Logger.debug('Reduced frame skip interval to: $_frameSkipInterval');
        }

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
      Logger.success('Camera stream started successfully');
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

  /// Pause camera stream without disposing the controller
  Future<void> _pauseCameraStream() async {
    if (_cameraState == CameraState.paused || _isDisposing) {
      return;
    }

    try {
      Logger.info('Pausing camera stream...');
      _cameraState = CameraState.paused;
      await _stopImageStream();
      // Don't dispose the controller, just stop the stream
      Logger.success('Camera stream paused');
    } catch (e) {
      Logger.error('Error pausing camera stream', error: e);
      _cameraState = CameraState.error;
    }
  }

  /// Resume camera operation after being paused
  Future<void> _resumeCamera() async {
    if (_cameraState == CameraState.streaming || _isDisposing) {
      return;
    }

    try {
      Logger.info('Resuming camera...');

      // Check if camera controller exists and is initialized
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        // Camera is initialized, just restart the stream
        Logger.info('Restarting image stream...');
        _cameraState = CameraState.streaming;
        _startImageStream();
        setState(() {
          _statusMessage = 'Ready';
        });
      } else {
        // Camera needs to be initialized
        Logger.info('Camera not initialized, initializing...');
        await _initializeCamera();
      }
    } catch (e) {
      Logger.error('Error resuming camera', error: e);
      _cameraState = CameraState.error;
      // Try full reinitialization on error
      await _initializeCamera();
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    Logger.debug('Processing frame...');
    _frameCounter++;

    // Enhanced verification with disposal and dialog check
    if (_isDisposing ||
        !mounted ||
        _isDialogOpen ||  // Skip if dialog is open
        _cameraController?.value.isInitialized != true ||
        _cameraController?.value.isStreamingImages != true) {
      Logger.warning('Skipping frame processing - widget state not ready or dialog open');
      return;
    }

    // Skip processing if we're in error cooldown
    if (_isInErrorCooldown()) {
      return;
    }

    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _createInputImageFromCamera(image);
      if (inputImage == null) {
        Logger.warning('Failed to create InputImage from CameraImage');
        return;
      }

      // Detect faces using ML Kit
      List<Face> faces = [];
      try {
        Logger.debug('Calling ML Kit face detector...');
        Logger.debug('InputImage metadata: size=${inputImage.metadata?.size}, '
                     'rotation=${inputImage.metadata?.rotation}, '
                     'format=${inputImage.metadata?.format}, '
                     'bytesPerRow=${inputImage.metadata?.bytesPerRow}');

        faces = await _faceDetector.processImage(inputImage);
        Logger.info('ML Kit detected ${faces.length} face(s)');

        // Log face details if detected
        if (faces.isNotEmpty) {
          for (int i = 0; i < faces.length; i++) {
            final face = faces[i];
            Logger.info('Face $i: boundingBox=${face.boundingBox}, '
                       'trackingId=${face.trackingId}, '
                       'headEulerAngleY=${face.headEulerAngleY}, '
                       'headEulerAngleZ=${face.headEulerAngleZ}');
          }
        }

        _mlKitError = false; // Reset error flag on success
      } catch (mlKitError) {
        Logger.warning('ML Kit face detection error: $mlKitError');
        // Even if ML Kit fails, we still want to log the attempt
        // Set empty faces list so logging knows there was no face detected
        faces = [];
        _mlKitError = true; // Set error flag
      }

      // Store detected faces for logging
      _detectedFaces = faces;

      final wasDetected = _isFaceDetected;
      final oldQuality = _faceQuality;

      if (faces.isEmpty) {
        _isFaceDetected = false;
        _faceQuality = 0.0;
        Logger.debug('No face detected in frame');
      } else {
        // Use the first (largest) face for quality calculation
        final face = faces.first;
        _isFaceDetected = true;
        _faceQuality = _calculateFaceQuality(face, image);
        Logger.info('Face detected with quality: ${(_faceQuality * 100).toInt()}%');
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

      // Trigger face recognition if quality is good, dialog not open, and enough time has passed
      if (_faceQuality >= 0.7 && !_isDialogOpen && _canTriggerRecognition()) {
        Logger.success('🎯 Quality threshold met: ${(_faceQuality * 100).toInt()}% >= 70%');
        // Don't await - process asynchronously to avoid blocking camera stream
        _triggerFaceRecognition(image).catchError((e) {
          Logger.error('Face recognition error', error: e);
        });
      } else if (_faceQuality >= 0.6 && _frameCounter % 30 == 0) {
        Logger.debug('Quality approaching threshold: ${(_faceQuality * 100).toInt()}%');
      } else if (_isFaceDetected && _frameCounter % 60 == 0) {
        // Log why recognition isn't triggering
        Logger.info('Face detected but not triggering - Quality: ${(_faceQuality * 100).toInt()}%, Can trigger: ${_canTriggerRecognition()}');
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
    // Skip if already recognizing to prevent queue buildup
    if (_isRecognizing) {
      Logger.debug('Skipping face recognition - already processing');
      return;
    }

    _isRecognizing = true;
    try {
      // Update status without blocking
      if (mounted) {
        setState(() {
          _statusMessage = 'Processing face...';
        });
      }

      Logger.info('=== FACE RECOGNITION TRIGGERED ===');
      Logger.info('Face recognition triggered - Quality: ${(_faceQuality * 100).toInt()}%');
      Logger.info('Can trigger recognition: ${_canTriggerRecognition()}');
      Logger.info('Frame counter: $_frameCounter');
      Logger.info('Detected faces count: ${_detectedFaces?.length ?? 0}');
      Logger.info('Starting face encoding extraction...');
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

      Logger.info('Calling face recognition service asynchronously...');

      // Process asynchronously without blocking the UI thread
      _faceRecognitionService.processFrame(image, cameraDescription).then((result) {
        if (!mounted || _isDisposing) return;

        stopwatch.stop();
        Logger.info('Face recognition completed in ${stopwatch.elapsedMilliseconds}ms');

        if (result != null) {
          _handleRecognitionResult(result, image);
        } else {
          Logger.warning('Face recognition service returned null');
          setState(() {
            _statusMessage = 'Ready';
          });
        }
      }).catchError((e) {
        Logger.error('Face recognition failed', error: e);
        if (mounted) {
          setState(() {
            _statusMessage = 'Recognition error';
          });
        }
      }).whenComplete(() {
        _isRecognizing = false;
      });

    } catch (e, stackTrace) {
      Logger.error('Face recognition error', error: e);
      Logger.error('Stack trace: $stackTrace');
      _isRecognizing = false;
      if (mounted) {
        setState(() {
          _statusMessage = 'Recognition error';
        });
      }
    }
  }

  /// Handle recognition result in a separate method
  void _handleRecognitionResult(FaceRecognitionResult result, CameraImage image) {
    if (!mounted || _isDisposing) return;

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
            });
            _showSuccessDialog(result.employee!, result.confidence ?? 0.0);

            // Reset status message after 3 seconds
            Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _statusMessage = 'Ready (${_stats?.totalEmployees ?? 0} employees)';
                });
              }
            });
          }
          break;

        case FaceRecognitionResultType.unknown:
          Logger.warning('UNKNOWN FACE: Face not recognized in database');
          setState(() {
            _statusMessage = 'Face not recognized';
            _isFaceNotRecognized = true;
          });

          // Auto-hide indicator and reset status after 2 seconds
          Timer(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _isFaceNotRecognized = false;
                _statusMessage = 'Ready (${_stats?.totalEmployees ?? 0} employees)';
              });
            }
          });
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

      // Only log successful face matches to the database
      if (result.type == FaceRecognitionResultType.matched && result.employee != null) {
        _logRecognitionResult(result, 0, image).catchError((e) {
          Logger.error('Failed to log recognition result', error: e);
        });
      }
      // Skip logging for unrecognized faces, poor quality, no face, or errors
  }

  void _showSuccessDialog(Employee employee, double confidence) {
    setState(() {
      _isDialogOpen = true;  // Disable processing while dialog is shown
    });

    EmployeeConfirmationDialog.show(
      context: context,
      employee: employee,
      confidence: confidence,
      currentStatus: null,
      enableAutoClose: _config.enableAutoDialogDismiss,
      autoCloseDuration: _config.autoDialogDismissSeconds,
    ).then((_) {
      // Dialog closed (either by user or auto-dismiss after 3 seconds)
      if (mounted) {
        setState(() {
          _isDialogOpen = false;  // Re-enable processing
        });
      }
    });
  }

  /// Check if enough time has passed since the last recognition to allow a new one
  bool _canTriggerRecognition() {
    // Always allow recognition - no cooldown needed
    return true;
  }

  /// Log recognition result with camera image and detected faces
  Future<void> _logRecognitionResult(
    FaceRecognitionResult result,
    int processingTimeMs,
    CameraImage cameraImage,
  ) async {
    try {
      Logger.info('Logging face recognition result to database...');

      final cameraDescription = _cameraController?.description;
      if (cameraDescription == null) {
        Logger.warning('Camera description is null, cannot log with proper orientation');
        return;
      }

      // Create metadata with app context
      final metadata = <String, dynamic>{
        'app_version': '1.0.0',
        'screen': 'simplified_camera_screen',
        'camera_name': cameraDescription.name,
        'camera_lens': cameraDescription.lensDirection.name,
        'image_format': cameraImage.format.group.name,
        'processed_at': DateTime.now().toIso8601String(),
      };

      // Log the result with image data
      await _logService.logRecognitionResult(
        result: result,
        processingTimeMs: processingTimeMs,
        cameraImage: cameraImage,
        cameraDescription: cameraDescription,
        detectedFaces: _detectedFaces,
        deviceId: 'device_${DateTime.now().millisecondsSinceEpoch}', // Simple device ID
        metadata: metadata,
      );

      Logger.info('Recognition result logged successfully');
    } catch (e) {
      Logger.error('Failed to log recognition result', error: e);
      // Don't rethrow - logging failures should not break the main flow
    }
  }


  /// Convert YUV420 format to NV21 for ML Kit
  Uint8List _convertYuv420ToNv21(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    // Calculate the correct NV21 buffer size
    // Y plane: width * height
    // UV plane (interleaved): (width * height) / 2
    final int ySize = width * height;
    final int uvSize = (width * height) ~/ 2;

    final nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane directly
    final yPlane = cameraImage.planes[0];
    final yBytes = yPlane.bytes;

    // Handle Y plane based on stride
    if (yPlane.bytesPerRow == width) {
      // Direct copy if no padding
      nv21.setRange(0, ySize, yBytes);
    } else {
      // Copy row by row if there's padding
      int nv21Offset = 0;
      for (int row = 0; row < height; row++) {
        final start = row * yPlane.bytesPerRow;
        final end = start + width;
        if (start < yBytes.length && end <= yBytes.length) {
          nv21.setRange(nv21Offset, nv21Offset + width, yBytes, start);
        }
        nv21Offset += width;
      }
    }

    // Handle U and V planes
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

    // Start writing UV data after Y data
    int nv21Offset = ySize;

    // Interleave U and V for NV21 format (V first, then U)
    if (uvPixelStride == 2) {
      // UV planes are already interleaved (common on many devices)
      // Just need to ensure V comes before U
      for (int i = 0; i < uvSize ~/ 2; i++) {
        if (i * 2 < vBytes.length && i * 2 < uBytes.length) {
          nv21[nv21Offset++] = vBytes[i * 2];
          nv21[nv21Offset++] = uBytes[i * 2];
        }
      }
    } else {
      // UV planes are separate, need to interleave manually
      for (int row = 0; row < height ~/ 2; row++) {
        for (int col = 0; col < width ~/ 2; col++) {
          final int uvIndex = row * uvRowStride + col * uvPixelStride;
          if (uvIndex < vBytes.length && uvIndex < uBytes.length && nv21Offset + 1 < nv21.length) {
            nv21[nv21Offset++] = vBytes[uvIndex];
            nv21[nv21Offset++] = uBytes[uvIndex];
          }
        }
      }
    }

    return nv21;
  }

  /// Create InputImage from CameraImage for ML Kit processing
  InputImage? _createInputImageFromCamera(CameraImage cameraImage) {
    try {
      final cameraDescription = _cameraController?.description;
      if (cameraDescription == null) return null;

      // Log camera image details for debugging
      Logger.info('CameraImage format: ${cameraImage.format.group.name}, '
                  'planes: ${cameraImage.planes.length}, '
                  'dimensions: ${cameraImage.width}x${cameraImage.height}');
      Logger.debug('Camera sensor orientation: ${cameraDescription.sensorOrientation}, '
                   'lens direction: ${cameraDescription.lensDirection}');

      // Get image orientation - Android front camera typically needs special handling
      final sensorOrientation = cameraDescription.sensorOrientation;
      InputImageRotation rotation;

      // For Android devices in portrait mode
      if (cameraDescription.lensDirection == CameraLensDirection.front) {
        // Front camera - mirror and rotate
        switch (sensorOrientation) {
          case 0:
            rotation = InputImageRotation.rotation0deg;
            break;
          case 90:
            rotation = InputImageRotation.rotation90deg;
            break;
          case 180:
            rotation = InputImageRotation.rotation180deg;
            break;
          case 270:
            rotation = InputImageRotation.rotation270deg;
            break;
          default:
            rotation = InputImageRotation.rotation0deg;
            Logger.warning('Unknown sensor orientation: $sensorOrientation, using 0deg');
        }
      } else {
        // Back camera
        switch (sensorOrientation) {
          case 0:
            rotation = InputImageRotation.rotation0deg;
            break;
          case 90:
            rotation = InputImageRotation.rotation90deg;
            break;
          case 180:
            rotation = InputImageRotation.rotation180deg;
            break;
          case 270:
            rotation = InputImageRotation.rotation270deg;
            break;
          default:
            rotation = InputImageRotation.rotation0deg;
            Logger.warning('Unknown sensor orientation: $sensorOrientation, using 0deg');
        }
      }

      Logger.debug('Using rotation: $rotation for sensor orientation: $sensorOrientation');

      // Convert image bytes based on format
      Uint8List imageBytes;
      if (cameraImage.planes.length > 1) {
        // YUV420 format with separate planes - convert to NV21
        Logger.info('Converting YUV420 to NV21 for ML Kit');
        imageBytes = _convertYuv420ToNv21(cameraImage);
      } else {
        // Already in NV21 format or single plane
        Logger.info('Using single plane bytes directly');
        imageBytes = cameraImage.planes[0].bytes;
      }

      // Create InputImage with converted bytes
      // IMPORTANT: For NV21 format after conversion, bytesPerRow should be width
      // The converted NV21 buffer doesn't have padding, unlike the original planes
      final bytesPerRow = cameraImage.width; // Use width for NV21, not plane's bytesPerRow

      // Log buffer sizes for debugging
      Logger.info('Buffer size: ${imageBytes.length}, Expected: ${(cameraImage.width * cameraImage.height * 3) ~/ 2}');
      Logger.info('Using bytesPerRow: $bytesPerRow (width) for NV21 format');

      return InputImage.fromBytes(
        bytes: imageBytes,
        metadata: InputImageMetadata(
          size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21, // Always use NV21 after conversion
          bytesPerRow: bytesPerRow,
        ),
      );
    } catch (e) {
      Logger.error('Failed to create InputImage from CameraImage', error: e);
      return null;
    }
  }

  double _calculateFaceQuality(Face face, CameraImage image) {
    final imageArea = image.width * image.height;
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final faceRatio = faceArea / imageArea;

    // Size score (ideal: 15-50% of image, more lenient)
    double sizeScore = 1.0;
    if (faceRatio < 0.15) {
      // Gentler penalty for smaller faces
      sizeScore = math.pow(faceRatio / 0.15, 0.7).toDouble();
    } else if (faceRatio > 0.5) {
      // Gentler penalty for larger faces
      sizeScore = math.pow(0.5 / faceRatio, 0.7).toDouble();
    }

    // Center score (more forgiving)
    final centerX = image.width / 2;
    final centerY = image.height / 2;
    final faceCenter = face.boundingBox.center;
    final distanceFromCenter = (faceCenter.dx - centerX).abs() / centerX +
                               (faceCenter.dy - centerY).abs() / centerY;
    final centerScore = (1.0 - distanceFromCenter / 3).clamp(0.0, 1.0); // Reduced penalty

    // Give more weight to size score for better UX
    final quality = (sizeScore * 0.7 + centerScore * 0.3).clamp(0.0, 1.0);

    // Log quality details for debugging
    if (_frameCounter % 30 == 0) { // Log every 30 frames
      Logger.debug('Face quality details - Ratio: ${(faceRatio * 100).toStringAsFixed(1)}%, '
                   'Size score: ${(sizeScore * 100).toStringAsFixed(0)}%, '
                   'Center score: ${(centerScore * 100).toStringAsFixed(0)}%, '
                   'Total: ${(quality * 100).toStringAsFixed(0)}%');
    }

    return quality;
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
    return VisibilityDetector(
      key: const Key('camera_screen'),
      onVisibilityChanged: (visibilityInfo) {
        // Cancel any pending debounce timer
        _visibilityDebounceTimer?.cancel();

        // Debounce visibility changes to prevent rapid firing
        _visibilityDebounceTimer = Timer(const Duration(milliseconds: 100), () {
          final visiblePercentage = visibilityInfo.visibleFraction * 100;
          final wasVisible = _isVisible;
          _isVisible = visiblePercentage > 0;

          // Only act on actual state changes
          if (wasVisible != _isVisible) {
            if (!_isVisible) {
              // Page is now hidden
              Logger.info('Camera screen hidden - pausing camera stream');
              _pauseCameraStream();
            } else if (_isVisible && !_isDisposing) {
              // Page became visible
              Logger.info('Camera screen visible - resuming camera');
              _resumeCamera();
            }
          }
        });
      },
      child: RenderAwareWidget(
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
      final statusText = _mlKitError
          ? 'Camera processing error'
          : 'Position your face in the circle';
      final statusIcon = _mlKitError
          ? Icons.error_outline
          : Icons.face_retouching_off;
      final statusColor = _mlKitError
          ? Colors.orange.withOpacity(0.8)
          : Colors.grey.withOpacity(0.8);

      return Positioned(
        top: MediaQuery.of(context).size.height * 0.25,
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  statusIcon,
                  color: Colors.white,
                  size: 18.sp,
                ),
                SizedBox(width: 8.w),
                Text(
                  statusText,
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
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildUnrecognizedFaceOverlay() {
    if (!_isFaceNotRecognized) {
      return const SizedBox.shrink();
    }

    // Simple non-blocking indicator at the top
    return Positioned(
      top: MediaQuery.of(context).padding.top + 100.h,
      left: 20.w,
      right: 20.w,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _isFaceNotRecognized ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 20.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Face not recognized',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
      status = 'Face detected';
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