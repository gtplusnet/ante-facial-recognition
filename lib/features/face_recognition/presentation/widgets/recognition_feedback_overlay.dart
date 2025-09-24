import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/constants/face_recognition_constants.dart';
import '../bloc/face_recognition_bloc.dart';
import '../bloc/face_recognition_state.dart';

/// Overlay widget that provides real-time feedback during face recognition
class RecognitionFeedbackOverlay extends StatelessWidget {
  final Rect? faceBoundingBox;
  final double? faceQuality;
  final bool isDialogShowing;

  const RecognitionFeedbackOverlay({
    super.key,
    this.faceBoundingBox,
    this.faceQuality,
    this.isDialogShowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FaceRecognitionBloc, FaceRecognitionState>(
      builder: (context, state) {
        // Hide all overlays when dialog is showing
        if (isDialogShowing) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // Live quality monitor (always visible in top-right)
            Positioned(
              top: 60.h,
              right: 20.w,
              child: _LiveQualityMonitor(state: state, faceQuality: faceQuality),
            ),

            // Face bounding box overlay
            if (faceBoundingBox != null && state is FaceRecognitionScanning)
              _FaceBoundingBox(
                boundingBox: faceBoundingBox!,
                quality: faceQuality ?? 0.5,
              ),

            // Status indicator (hide error states when dialog would show)
            if (!(state is FaceRecognitionError))
              Positioned(
                top: 100.h,
                left: 0,
                right: 0,
                child: _StatusIndicator(state: state),
              ),

            // Quality threshold reached indicator
            if (faceQuality != null && faceQuality! >= FaceRecognitionConstants.qualityThreshold)
              Positioned(
                top: 160.h,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(25.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 10,
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
                          '🎯 QUALITY: ${(faceQuality! * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
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

            // Instruction text
            Positioned(
              bottom: 120.h,
              left: 20.w,
              right: 20.w,
              child: _InstructionText(state: state),
            ),

            // Processing overlay (only show when actually processing)
            if (state is FaceRecognitionLoading || state is FaceRecognitionProcessing)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: _ProcessingIndicator(),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Face bounding box with quality indicators
class _FaceBoundingBox extends StatelessWidget {
  final Rect boundingBox;
  final double quality;

  const _FaceBoundingBox({
    required this.boundingBox,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getQualityColor(quality);
    
    return Positioned(
      left: boundingBox.left,
      top: boundingBox.top,
      child: Container(
        width: boundingBox.width,
        height: boundingBox.height,
        decoration: BoxDecoration(
          border: Border.all(
            color: color,
            width: 3.w,
          ),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Stack(
          children: [
            // Corner indicators
            _CornerIndicator(color: color, position: Alignment.topLeft),
            _CornerIndicator(color: color, position: Alignment.topRight),
            _CornerIndicator(color: color, position: Alignment.bottomLeft),
            _CornerIndicator(color: color, position: Alignment.bottomRight),

            // Quality badge
            Positioned(
              top: -30.h,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    '${(quality * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getQualityColor(double quality) {
    if (quality >= 0.8) return Colors.green;
    if (quality >= 0.6) return Colors.orange;
    return Colors.red;
  }
}

/// Corner indicator for face bounding box
class _CornerIndicator extends StatelessWidget {
  final Color color;
  final Alignment position;

  const _CornerIndicator({
    required this.color,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: position,
      child: Container(
        width: 20.w,
        height: 20.h,
        decoration: BoxDecoration(
          border: Border(
            top: position.y < 0
                ? BorderSide(color: color, width: 3.w)
                : BorderSide.none,
            bottom: position.y > 0
                ? BorderSide(color: color, width: 3.w)
                : BorderSide.none,
            left: position.x < 0
                ? BorderSide(color: color, width: 3.w)
                : BorderSide.none,
            right: position.x > 0
                ? BorderSide(color: color, width: 3.w)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Status indicator showing current recognition state
class _StatusIndicator extends StatelessWidget {
  final FaceRecognitionState state;

  const _StatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    Widget content;
    Color backgroundColor;

    if (state is FaceRecognitionScanning) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.face,
            color: Colors.white,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Scanning Face',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
      backgroundColor = Colors.blue;
    } else if (state is FaceRecognitionLoading) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16.w,
            height: 16.h,
            child: CircularProgressIndicator(
              strokeWidth: 2.w,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            'Processing...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
      backgroundColor = Colors.orange;
    } else if (state is FaceRecognitionMatched) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.white,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Recognized',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
      backgroundColor = Colors.green;
    } else if (state is FaceRecognitionUnknown) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Not Recognized',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
      backgroundColor = Colors.red;
    } else if (state is FaceRecognitionError) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning,
            color: Colors.white,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Error',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
      backgroundColor = Colors.red;
    } else if (state is FaceRecognitionReady) {
      final readyState = state as FaceRecognitionReady;
      content = Text(
        'Ready (${readyState.employeeCount} employees)',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14.sp,
          fontWeight: FontWeight.w500,
        ),
      );
      backgroundColor = Colors.green;
    } else {
      content = Text(
        'Position your face',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14.sp,
          fontWeight: FontWeight.w500,
        ),
      );
      backgroundColor = Colors.grey;
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 8.h,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: content,
      ),
    );
  }
}

/// Instruction text to guide the user
class _InstructionText extends StatelessWidget {
  final FaceRecognitionState state;

  const _InstructionText({required this.state});

  @override
  Widget build(BuildContext context) {
    String instruction;

    if (state is FaceRecognitionNoFace) {
      instruction = 'Position your face within the frame';
    } else if (state is FaceRecognitionPoorQuality) {
      final qualityState = state as FaceRecognitionPoorQuality;
      instruction = qualityState.message;
    } else if (state is FaceRecognitionScanning) {
      instruction = 'Hold still...';
    } else if (state is FaceRecognitionLoading) {
      instruction = 'Verifying identity...';
    } else if (state is FaceRecognitionMatched) {
      final matchedState = state as FaceRecognitionMatched;
      instruction = 'Welcome, ${matchedState.employee.name}!';
    } else if (state is FaceRecognitionUnknown) {
      instruction = 'Face not recognized. Please try again.';
    } else if (state is FaceRecognitionConfirmed) {
      final confirmedState = state as FaceRecognitionConfirmed;
      instruction = confirmedState.actionMessage;
    } else if (state is FaceRecognitionError) {
      final errorState = state as FaceRecognitionError;
      instruction = errorState.message;
    } else if (state is FaceRecognitionReady) {
      instruction = 'Look at the camera to start';
    } else {
      instruction = 'Initializing...';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20.w,
        vertical: 12.h,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Text(
        instruction,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Processing indicator with animation
class _ProcessingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200.w,
      height: 200.h,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated face scanning icon
          Flexible(
            child: SizedBox(
              width: 80.w,
              height: 80.h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.face,
                    size: 50.sp,
                    color: Colors.blue,
                  ),
                  SizedBox(
                    width: 70.w,
                    height: 70.h,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.w,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Processing',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Please wait...',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live quality monitor showing real-time face detection status
class _LiveQualityMonitor extends StatelessWidget {
  final FaceRecognitionState state;
  final double? faceQuality;

  const _LiveQualityMonitor({
    required this.state,
    this.faceQuality,
  });

  @override
  Widget build(BuildContext context) {
    // Determine display values based on state
    String status = 'No Face';
    double? quality = faceQuality;
    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon = Icons.face_retouching_off;

    if (state is FaceRecognitionScanning) {
      status = quality != null ? 'Detecting' : 'Searching...';
      icon = Icons.face;
    } else if (state is FaceRecognitionPoorQuality) {
      final poorState = state as FaceRecognitionPoorQuality;
      status = 'Low Quality';
      quality = poorState.quality;
      icon = Icons.warning;
    } else if (state is FaceRecognitionMatched) {
      status = 'Recognized';
      icon = Icons.check_circle;
    } else if (state is FaceRecognitionUnknown) {
      status = 'Unknown';
      icon = Icons.error;
    } else if (state is FaceRecognitionNoFace) {
      status = 'No Face';
      icon = Icons.face_retouching_off;
    } else if (state is FaceRecognitionError) {
      status = 'Error';
      icon = Icons.warning;
    } else if (state is FaceRecognitionReady) {
      status = 'Ready';
      icon = Icons.camera_front;
    } else if (state is FaceRecognitionLoading) {
      status = 'Loading...';
      icon = Icons.hourglass_empty;
    }

    // Color-coded background based on quality and status
    if (state is FaceRecognitionMatched) {
      backgroundColor = Colors.green.withOpacity(0.9);
    } else if (state is FaceRecognitionError || state is FaceRecognitionUnknown) {
      backgroundColor = Colors.red.withOpacity(0.9);
    } else if (quality != null) {
      if (quality >= 0.9) {
        backgroundColor = Colors.green.withOpacity(0.9);
      } else if (quality >= 0.7) {
        backgroundColor = Colors.orange.withOpacity(0.9);
      } else {
        backgroundColor = Colors.red.withOpacity(0.9);
      }
    } else {
      backgroundColor = Colors.grey.withOpacity(0.9);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status with icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: textColor,
                size: 16.sp,
              ),
              SizedBox(width: 6.w),
              Text(
                status,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // Quality percentage (if available)
          if (quality != null) ...[
            SizedBox(height: 4.h),
            Text(
              '${(quality * 100).toInt()}%',
              style: TextStyle(
                color: textColor,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          // Quality threshold indicator
          if (quality != null) ...[
            SizedBox(height: 4.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2.r),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: quality.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: textColor,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}