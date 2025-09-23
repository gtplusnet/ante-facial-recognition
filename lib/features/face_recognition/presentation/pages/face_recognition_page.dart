import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraLensDirection, CameraImage;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../../camera/presentation/widgets/camera_preview_widget.dart';
import '../../../face_detection/presentation/bloc/face_detection_bloc.dart';
import '../../../face_detection/presentation/bloc/face_detection_event.dart';
import '../../../face_detection/presentation/bloc/face_detection_state.dart';
import '../../../employee/presentation/bloc/employee_bloc.dart';
import '../../../employee/presentation/bloc/employee_event.dart' as employee_events;
import '../bloc/face_recognition_bloc.dart';
import '../bloc/face_recognition_event.dart';
import '../bloc/face_recognition_state.dart';
import '../widgets/face_positioning_overlay.dart';
import '../widgets/recognition_feedback_overlay.dart';
import '../widgets/recognition_result_dialog.dart';

class FaceRecognitionPage extends StatefulWidget {
  const FaceRecognitionPage({super.key});

  @override
  State<FaceRecognitionPage> createState() => _FaceRecognitionPageState();
}

class _FaceRecognitionPageState extends State<FaceRecognitionPage> {
  late final FaceDetectionBloc _faceDetectionBloc;
  late final FaceRecognitionBloc _faceRecognitionBloc;
  late final EmployeeBloc _employeeBloc;
  late final CameraDataSource _cameraDataSource;
  late final FeedbackService _feedbackService;

  // Track last processed time to avoid processing too frequently
  DateTime _lastProcessedTime = DateTime.now();
  static const _processingInterval = Duration(milliseconds: 1000);

  // Store latest camera image for face recognition
  CameraImage? _latestCameraImage;

  // Flag to prevent face processing when dialog is showing
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _cameraDataSource = getIt<CameraDataSource>();
    _faceDetectionBloc = getIt<FaceDetectionBloc>();
    _faceRecognitionBloc = getIt<FaceRecognitionBloc>();
    _employeeBloc = getIt<EmployeeBloc>();
    _feedbackService = getIt<FeedbackService>();
    _initializeServices();
    _initializeCamera();
    _initializeFaceRecognition();
  }

  Future<void> _initializeServices() async {
    await _feedbackService.initialize();
  }

  Future<void> _initializeCamera() async {
    try {
      // Initialize camera first
      await _cameraDataSource.initializeCamera();
      Logger.info('Camera initialized, starting face detection');

      // Then start face detection after camera is ready
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _faceDetectionBloc.add(const StartFaceDetection());
      }
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
    }
  }

  Future<void> _initializeFaceRecognition() async {
    Logger.info('Initializing face recognition from FaceRecognitionPage');
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      _faceRecognitionBloc.add(const InitializeFaceRecognition());
      _employeeBloc.add(const employee_events.LoadEmployees());
      Logger.info('Face recognition initialization events dispatched');
    }
  }

  @override
  void dispose() {
    _faceDetectionBloc.add(const StopFaceDetection());
    _faceRecognitionBloc.add(const StopRecognition());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _faceDetectionBloc),
        BlocProvider.value(value: _faceRecognitionBloc),
        BlocProvider.value(value: _employeeBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          // Listen to face detection and trigger recognition
          BlocListener<FaceDetectionBloc, FaceDetectionState>(
            listener: _handleFaceDetection,
          ),
          // Listen to face recognition results for feedback
          BlocListener<FaceRecognitionBloc, FaceRecognitionState>(
            listener: _handleFaceRecognition,
          ),
          // Listen for FaceRecognitionReady state to start recognition
          BlocListener<FaceRecognitionBloc, FaceRecognitionState>(
            listenWhen: (previous, current) =>
                previous is! FaceRecognitionReady && current is FaceRecognitionReady,
            listener: (context, state) {
              if (state is FaceRecognitionReady) {
                Logger.info('Face recognition ready, starting recognition scanning');
                _faceRecognitionBloc.add(const StartRecognition());
              }
            },
          ),
        ],
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _buildCameraView(),
              _buildFacePositioningOverlay(),
              _buildRecognitionFeedbackOverlay(),
              _buildOverlay(),
              _buildTopBar(),
              _buildBottomInfo(),
            ],
          ),
        ),
      ),
    );
  }

  // Handle face detection results
  void _handleFaceDetection(BuildContext context, FaceDetectionState state) {
    // Don't process faces when dialog is showing
    if (_isDialogShowing) return;

    if (state is FaceDetected) {
      final now = DateTime.now();
      final timeSinceLastProcess = now.difference(_lastProcessedTime);
      final qualityPercent = (state.face.qualityScore * 100).toStringAsFixed(0);

      // Get the camera image from the face detection bloc
      final cameraImage = _faceDetectionBloc.latestCameraImage;
      if (cameraImage != null) {
        _latestCameraImage = cameraImage;
        Logger.success('📸 Camera image retrieved from face detection bloc (size: ${cameraImage.width}x${cameraImage.height})');
      }

      // Log all face detections with quality for debugging
      Logger.debug('Face detected with quality: ${qualityPercent}%');

      // Special log for 90% quality as requested by user
      if (state.face.qualityScore >= 0.9) {
        Logger.info('🎯 FACE QUALITY REACHED 90%! Quality: ${qualityPercent}%');
      }

      // Use 90% threshold for face recognition trigger
      if (state.face.qualityScore >= 0.9 && timeSinceLastProcess > _processingInterval) {
        _lastProcessedTime = now;
        Logger.info('Face detected with good quality (${qualityPercent}%), triggering recognition');

        // Trigger face recognition with the current camera frame
        if (_faceRecognitionBloc.state is FaceRecognitionScanning) {
          // Now we have the camera image from face detection
          Logger.info('📸 Sending camera image to recognition (size: ${_latestCameraImage!.width}x${_latestCameraImage!.height})');
          _faceRecognitionBloc.add(ProcessCameraFrame(_latestCameraImage!));
          Logger.success('✅ ProcessCameraFrame event sent to FaceRecognitionBloc');

          // Show recognition dialog with mock data after a brief delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDialogShowing) {
              _showRecognitionDialog();
            }
          });
        } else if (_faceRecognitionBloc.state is FaceRecognitionReady) {
          // Start recognition scanning
          _faceRecognitionBloc.add(const StartRecognition());
          Logger.info('Starting recognition scanning (transitioning from Ready to Scanning)');
        } else if (_faceRecognitionBloc.state is FaceRecognitionError ||
                   _faceRecognitionBloc.state is FaceRecognitionPoorQuality ||
                   _faceRecognitionBloc.state is FaceRecognitionNoFace) {
          // Try to restart recognition from error, poor quality, or no face state
          Logger.info('Attempting to restart recognition from ${_faceRecognitionBloc.state.runtimeType}');
          _faceRecognitionBloc.add(const StartRecognition());
        } else {
          Logger.warning('FaceRecognitionBloc in unexpected state: ${_faceRecognitionBloc.state.runtimeType}');
        }
      } else if (state.face.qualityScore <= 0.3) {
        Logger.debug('Face quality too low for recognition: ${qualityPercent}% (threshold: 30%)');
      } else {
        Logger.debug('Face detection rate limited - too soon since last processing');
      }
    }
  }

  // Handle face recognition results
  void _handleFaceRecognition(BuildContext context, FaceRecognitionState state) {
    Logger.debug('_handleFaceRecognition called with state: ${state.runtimeType}');

    if (state is FaceRecognitionMatched) {
      // Play success feedback
      Logger.info('Triggering success feedback for recognized face');
      _feedbackService.playSuccessFeedback();
      Logger.success('Face recognized: ${state.employee.name}');

    } else if (state is FaceRecognitionUnknown) {
      // Play error feedback for unknown face
      Logger.info('Triggering error feedback for unknown face');
      _feedbackService.playErrorFeedback();
      Logger.warning('Unknown face detected');

    } else if (state is FaceRecognitionNoFace) {
      // No feedback needed, just scanning
      Logger.debug('No face detected, skipping feedback');

    } else if (state is FaceRecognitionPoorQuality) {
      // Play warning feedback for poor quality
      Logger.info('Triggering warning feedback for poor quality');
      _feedbackService.playWarningFeedback();
      Logger.warning('Face quality too low: ${(state.quality * 100).toStringAsFixed(0)}%');
    }
  }

  Widget _buildRecognitionFeedbackOverlay() {
    return BlocBuilder<FaceDetectionBloc, FaceDetectionState>(
      builder: (context, detectionState) {
        Rect? faceBounds;
        double? faceQuality;

        if (detectionState is FaceDetected) {
          // Convert face bounds to screen coordinates
          // This would need proper coordinate transformation
          faceBounds = Rect.fromLTWH(
            detectionState.face.bounds.left,
            detectionState.face.bounds.top,
            detectionState.face.bounds.width,
            detectionState.face.bounds.height,
          );
          faceQuality = detectionState.face.qualityScore;
        }

        return RecognitionFeedbackOverlay(
          faceBoundingBox: faceBounds,
          faceQuality: faceQuality,
          isDialogShowing: _isDialogShowing,
        );
      },
    );
  }

  Widget _buildCameraView() {
    return CameraPreviewWidget(
      cameraDataSource: _cameraDataSource,
      showControls: false,
      onImage: (image) {
        // Store the latest camera image for face recognition with detailed logging
        final wasNull = _latestCameraImage == null;
        _latestCameraImage = image;

        if (wasNull) {
          Logger.success('📸 First camera image received! Size: ${image.width}x${image.height}, Format: ${image.format.group}');
        }

        // Send image to face detection
        _faceDetectionBloc.add(ProcessCameraImage(image));
      },
    );
  }

  Widget _buildFacePositioningOverlay() {
    return BlocBuilder<FaceDetectionBloc, FaceDetectionState>(
      builder: (context, state) {
        final isFaceDetected = state is FaceDetected;
        final isGoodQuality = isFaceDetected && state.face.qualityScore > 0.6;

        return FacePositioningOverlay(
          isFaceDetected: isFaceDetected,
          isGoodQuality: isGoodQuality,
        );
      },
    );
  }

  Widget _buildOverlay() {
    // Green rectangle overlay disabled - using oval positioning guide instead
    return const SizedBox.shrink();
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 10.h,
          left: 20.w,
          right: 20.w,
          bottom: 10.h,
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                'Face Recognition',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: BlocBuilder<FaceDetectionBloc, FaceDetectionState>(
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusMessage(state),
                SizedBox(height: 10.h),
                _buildInstructions(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusMessage(FaceDetectionState state) {
    String message;
    Color color;
    IconData icon;

    if (state is FaceDetectionLoading) {
      message = 'Initializing camera...';
      color = Colors.white;
      icon = Icons.hourglass_empty;
    } else if (state is FaceDetectionReady) {
      message = 'Ready to detect faces';
      color = Colors.white;
      icon = Icons.face;
    } else if (state is FaceDetected) {
      message = 'Face detected - Quality: ${(state.face.qualityScore * 100).toStringAsFixed(0)}%';
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (state is FaceDetectionNoFace) {
      message = 'No face detected';
      color = Colors.yellow;
      icon = Icons.face_retouching_off;
    } else if (state is FaceDetectionMultipleFaces) {
      message = 'Multiple faces detected (${state.count})';
      color = Colors.orange;
      icon = Icons.group;
    } else if (state is FaceDetectionLowQuality) {
      message = 'Face quality too low (${(state.qualityScore * 100).toStringAsFixed(0)}%)';
      color = Colors.orange;
      icon = Icons.warning;
    } else if (state is FaceDetectionError) {
      message = 'Error: ${state.message}';
      color = Colors.red;
      icon = Icons.error;
    } else {
      message = 'Preparing...';
      color = Colors.white;
      icon = Icons.hourglass_empty;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24.sp),
          SizedBox(width: 10.w),
          Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(FaceDetectionState state) {
    String instruction;

    if (state is FaceDetectionNoFace) {
      instruction = 'Position your face within the frame';
    } else if (state is FaceDetectionMultipleFaces) {
      instruction = 'Please ensure only one person is visible';
    } else if (state is FaceDetectionLowQuality) {
      instruction = 'Move closer and face the camera directly';
    } else if (state is FaceDetected) {
      instruction = 'Hold steady for recognition';
    } else {
      instruction = 'Align your face with the camera';
    }

    return Text(
      instruction,
      style: TextStyle(
        color: Colors.white70,
        fontSize: 14.sp,
      ),
      textAlign: TextAlign.center,
    );
  }

  void _showRecognitionDialog() {
    // Set flag to stop face detection
    _isDialogShowing = true;
    Logger.info('🎯 Showing recognition dialog - face detection paused');

    // Simulate different recognition results randomly
    final isRecognized = DateTime.now().millisecond % 2 == 0; // 50% chance

    showRecognitionResultDialog(
      context,
      isRecognized: isRecognized,
      employeeName: isRecognized ? 'Guillermo Tabligan' : null,
      employeeId: isRecognized ? 'EMP-001' : null,
      confidence: isRecognized ? 0.94 : null,
      onDismiss: () {
        // Resume face detection when dialog is dismissed
        _isDialogShowing = false;
        Logger.info('✅ Recognition dialog dismissed - face detection resumed');

        // Reset face detection bloc to clear any stuck states
        Logger.info('🔄 Resetting face detection to clear stuck state');
        _faceDetectionBloc.add(const ResetFaceDetection());

        // Reset face recognition state to allow new attempts
        final currentState = _faceRecognitionBloc.state;
        if (currentState is FaceRecognitionPoorQuality ||
            currentState is FaceRecognitionError ||
            currentState is FaceRecognitionUnknown ||
            currentState is FaceRecognitionMatched ||
            currentState is FaceRecognitionNoFace) {
          Logger.info('Resetting recognition state from ${currentState.runtimeType} to Scanning');
          _faceRecognitionBloc.add(const StartRecognition());
        }
      },
    );
  }
}