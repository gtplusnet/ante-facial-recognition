import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/services/feedback_service.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../../camera/presentation/widgets/camera_preview_widget.dart';
import '../bloc/face_processing_bloc.dart';
import '../widgets/recognition_result_dialog.dart';

class SimpleFaceRecognitionScreen extends StatefulWidget {
  const SimpleFaceRecognitionScreen({super.key});

  @override
  State<SimpleFaceRecognitionScreen> createState() => _SimpleFaceRecognitionScreenState();
}

class _SimpleFaceRecognitionScreenState extends State<SimpleFaceRecognitionScreen> {
  late final FaceProcessingBloc _faceProcessingBloc;
  late final CameraDataSource _cameraDataSource;
  late final FeedbackService _feedbackService;

  bool _isDialogShowing = false;
  DateTime _lastRecognitionTime = DateTime.now();
  static const _recognitionCooldown = Duration(seconds: 3);

  // For FPS calculation
  DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cameraDataSource = getIt<CameraDataSource>();
    _faceProcessingBloc = getIt<FaceProcessingBloc>();
    _feedbackService = getIt<FeedbackService>();

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _feedbackService.initialize();
    _faceProcessingBloc.add(InitializeFaceProcessing());
  }

  @override
  void dispose() {
    _faceProcessingBloc.add(ResetProcessing());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _faceProcessingBloc,
      child: BlocListener<FaceProcessingBloc, FaceProcessingState>(
        listener: _handleStateChange,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _buildCameraView(),
              _buildRecognitionOverlay(),
              _buildTopBar(),
              _buildBottomInfo(),
            ],
          ),
        ),
      ),
    );
  }

  void _handleStateChange(BuildContext context, FaceProcessingState state) {
    if (state is FaceRecognized) {
      // Only show dialog for recognized employees
      final now = DateTime.now();
      if (!_isDialogShowing &&
          now.difference(_lastRecognitionTime) > _recognitionCooldown) {
        _lastRecognitionTime = now;
        _showRecognitionDialog(state);
        _feedbackService.playSuccessFeedback();
      }
    } else if (state is FaceNotRecognized) {
      // For unknown faces, just play warning feedback, no dialog
      _feedbackService.playWarningFeedback();
      Logger.info('Unknown face detected with quality: ${(state.faceQuality * 100).toStringAsFixed(0)}%');
    }
    // Removed FaceProcessingReady handler - CameraPreviewWidget handles stream management
  }


  void _showRecognitionDialog(FaceRecognized state) {
    _isDialogShowing = true;

    showRecognitionResultDialog(
      context,
      isRecognized: true,
      employeeName: state.employee.name,
      employeeId: state.employee.id,
      confidence: state.confidence,
      onDismiss: () {
        _isDialogShowing = false;
        // Reset processing to continue scanning
        _faceProcessingBloc.add(ResetProcessing());
      },
    );
  }

  Widget _buildCameraView() {
    return CameraPreviewWidget(
      cameraDataSource: _cameraDataSource,
      showControls: false,
      autoInitialize: true,  // Let CameraPreviewWidget handle camera initialization
      onImage: (image) {
        if (!_isDialogShowing) {
          _faceProcessingBloc.add(ProcessCameraFrame(image));
        }
      },
    );
  }

  Widget _buildRecognitionOverlay() {
    return BlocBuilder<FaceProcessingBloc, FaceProcessingState>(
      builder: (context, state) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          child: CustomPaint(
            painter: _RecognitionOverlayPainter(state: state),
          ),
        );
      },
    );
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
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
        child: BlocBuilder<FaceProcessingBloc, FaceProcessingState>(
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusIndicator(state),
                SizedBox(height: 10.h),
                _buildInstructions(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(FaceProcessingState state) {
    String status;
    Color color;
    IconData icon;

    if (state is FaceProcessingInitializing) {
      status = 'Initializing...';
      color = Colors.white;
      icon = Icons.hourglass_empty;
    } else if (state is FaceProcessingReady) {
      status = 'Ready - Position your face';
      color = Colors.white;
      icon = Icons.face;
    } else if (state is FaceProcessingActive) {
      final quality = state.faceQuality;
      final fps = _calculateFPS(state.frameCount);
      if (state.faceDetected) {
        status = 'Face Quality: ${(quality * 100).toStringAsFixed(0)}% | ${fps.toStringAsFixed(1)} FPS';
        color = quality > 0.9 ? Colors.green : (quality > 0.5 ? Colors.orange : Colors.red);
        icon = Icons.face;
      } else {
        status = 'Scanning: ${(quality * 100).toStringAsFixed(0)}% | ${fps.toStringAsFixed(1)} FPS';
        color = Colors.white;
        icon = Icons.search;
      }
    } else if (state is FaceRecognized) {
      status = 'Recognized: ${state.employee.name}';
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (state is FaceNotRecognized) {
      status = 'Person not recognized';
      color = Colors.orange;
      icon = Icons.help_outline;
    } else {
      status = 'Scanning...';
      color = Colors.white;
      icon = Icons.search;
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
            status,
            style: TextStyle(
              color: color,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(FaceProcessingState state) {
    String instruction;

    if (state is FaceProcessingActive && state.faceDetected) {
      final quality = state.faceQuality ?? 0;
      if (quality < 0.5) {
        instruction = 'Move closer to the camera';
      } else if (quality < 0.9) {
        instruction = 'Hold still for better recognition';
      } else {
        instruction = 'Processing...';
      }
    } else if (state is FaceNotRecognized) {
      instruction = 'Not in employee database - Access denied';
    } else {
      instruction = 'Look directly at the camera';
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

  double _calculateFPS(int frameCount) {
    final elapsed = DateTime.now().difference(_startTime);
    if (elapsed.inSeconds == 0) return 0.0;
    return frameCount / elapsed.inSeconds;
  }
}

// Custom painter for recognition overlay
class _RecognitionOverlayPainter extends CustomPainter {
  final FaceProcessingState state;

  _RecognitionOverlayPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw face detection frame
    final center = Offset(size.width / 2, size.height / 2.5);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: 250.w,
      height: 320.h,
    );

    // Set color based on state
    if (state is FaceRecognized) {
      paint.color = Colors.green;
    } else if (state is FaceNotRecognized) {
      paint.color = Colors.orange;
    } else if (state is FaceProcessingActive) {
      final activeState = state as FaceProcessingActive;
      final quality = activeState.faceQuality ?? 0;
      paint.color = quality > 0.9 ? Colors.green : Colors.orange;
    } else {
      paint.color = Colors.white.withOpacity(0.5);
    }

    canvas.drawOval(ovalRect, paint);

    // Always draw quality indicator for FaceProcessingActive states
    if (state is FaceProcessingActive) {
      final activeState = state as FaceProcessingActive;
      final quality = activeState.faceQuality;
      final qualityText = '${(quality * 100).toStringAsFixed(0)}%';

      // Choose color based on quality
      Color qualityColor;
      if (quality > 0.9) {
        qualityColor = Colors.green;
      } else if (quality > 0.5) {
        qualityColor = Colors.orange;
      } else if (quality > 0.0) {
        qualityColor = Colors.red;
      } else {
        qualityColor = Colors.white;
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: qualityText,
          style: TextStyle(
            color: qualityColor,
            fontSize: 28.sp, // Larger for better visibility
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black54,
                offset: Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, center.dy - 80.h), // Center above oval
      );
    }

    // Show name for recognized person
    if (state is FaceRecognized) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: (state as FaceRecognized).employee.name,
          style: TextStyle(
            color: Colors.green,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      final textOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy + 180.h,
      );
      textPainter.paint(canvas, textOffset);
    }

    // Show "Unknown" for unrecognized faces
    if (state is FaceNotRecognized) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Unknown Person',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      final textOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy + 180.h,
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(_RecognitionOverlayPainter oldDelegate) {
    return true;
  }
}