import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../camera/data/datasources/camera_data_source.dart';
import '../../../camera/presentation/widgets/camera_preview_widget.dart';
import '../../../face_detection/presentation/bloc/face_detection_bloc.dart';
import '../../../face_detection/presentation/bloc/face_detection_event.dart';
import '../../../face_detection/presentation/bloc/face_detection_state.dart';
import '../widgets/face_positioning_overlay.dart';

class FaceRecognitionPage extends StatefulWidget {
  const FaceRecognitionPage({super.key});

  @override
  State<FaceRecognitionPage> createState() => _FaceRecognitionPageState();
}

class _FaceRecognitionPageState extends State<FaceRecognitionPage> {
  late final FaceDetectionBloc _faceDetectionBloc;
  late final CameraDataSource _cameraDataSource;

  @override
  void initState() {
    super.initState();
    _cameraDataSource = getIt<CameraDataSource>();
    _faceDetectionBloc = getIt<FaceDetectionBloc>();
    _initializeFaceDetection();
  }

  Future<void> _initializeFaceDetection() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _faceDetectionBloc.add(const StartFaceDetection());
    }
  }

  @override
  void dispose() {
    _faceDetectionBloc.add(const StopFaceDetection());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _faceDetectionBloc,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildCameraView(),
            _buildFacePositioningOverlay(),
            _buildOverlay(),
            _buildTopBar(),
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    return CameraPreviewWidget(
      cameraDataSource: _cameraDataSource,
      showControls: false,
      onImage: (image) {
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
    return BlocBuilder<FaceDetectionBloc, FaceDetectionState>(
      builder: (context, state) {
        if (state is FaceDetected) {
          // Check if we're using the front camera
          final isFrontCamera = _cameraDataSource.currentCamera?.lensDirection ==
              CameraLensDirection.front;

          return FaceBoundingBoxOverlay(
            faceRect: Rect.fromLTWH(
              state.face.bounds.left,
              state.face.bounds.top,
              state.face.bounds.width,
              state.face.bounds.height,
            ),
            imageSize: ui.Size(state.imageSize.width, state.imageSize.height),
            isDetecting: true,
            isFrontCamera: isFrontCamera,
          );
        }
        return const SizedBox.shrink();
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
}