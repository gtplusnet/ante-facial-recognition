import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/widgets/app_error_widget.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../data/datasources/camera_data_source.dart';
import '../../domain/entities/camera_image.dart';
import '../../domain/repositories/camera_repository.dart';

class CameraPreviewWidget extends StatefulWidget {
  final CameraDataSource cameraDataSource;
  final Function(camera.CameraImage)? onImage;
  final Widget? overlay;
  final bool showControls;

  const CameraPreviewWidget({
    super.key,
    required this.cameraDataSource,
    this.onImage,
    this.overlay,
    this.showControls = true,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with WidgetsBindingObserver {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = widget.cameraDataSource.controller;

    // App lifecycle management for camera
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await widget.cameraDataSource.initializeCamera();
      if (widget.onImage != null) {
        await _startImageStream();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _startImageStream() async {
    if (widget.onImage != null && !_isProcessing) {
      await widget.cameraDataSource.startImageStream((image) {
        if (!_isProcessing && mounted) {
          _isProcessing = true;
          widget.onImage!(image);
          Future.delayed(const Duration(milliseconds: 100), () {
            _isProcessing = false;
          });
        }
      });
    }
  }

  Future<void> _stopImageStream() async {
    await widget.cameraDataSource.stopImageStream();
  }

  Future<void> _disposeCamera() async {
    await widget.cameraDataSource.dispose();
  }

  Future<void> _switchCamera() async {
    await widget.cameraDataSource.switchCamera();
    if (widget.onImage != null) {
      await _startImageStream();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CameraState>(
      stream: widget.cameraDataSource.stateStream,
      initialData: CameraState.uninitialized,
      builder: (context, snapshot) {
        final state = snapshot.data ?? CameraState.uninitialized;

        switch (state) {
          case CameraState.uninitialized:
          case CameraState.initializing:
            return const Center(child: AppLoadingIndicator());

          case CameraState.ready:
          case CameraState.streaming:
            return _buildCameraPreview();

          case CameraState.error:
            return AppErrorWidget(
              message: 'Camera error occurred',
              icon: Icons.camera_alt_outlined,
              onRetry: _initializeCamera,
            );

          case CameraState.disposed:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildCameraPreview() {
    final controller = widget.cameraDataSource.controller;

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: AppLoadingIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCamera(controller),
        if (widget.overlay != null) widget.overlay!,
        if (widget.showControls) _buildControls(),
      ],
    );
  }

  Widget _buildCamera(camera.CameraController controller) {
    // Get the device orientation
    final orientation = MediaQuery.of(context).orientation;

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get the camera aspect ratio (width/height in landscape mode)
          // Note: CameraController aspectRatio is always in landscape orientation
          final cameraAspectRatio = controller.value.aspectRatio;

          // Calculate the preview aspect ratio based on device orientation
          final previewAspectRatio = orientation == Orientation.portrait
              ? 1 / cameraAspectRatio  // Invert for portrait
              : cameraAspectRatio;      // Keep as is for landscape

          // Calculate the container aspect ratio
          final containerAspectRatio = constraints.maxWidth / constraints.maxHeight;

          // Calculate scale to fill the container while maintaining aspect ratio
          double scale;
          if (containerAspectRatio > previewAspectRatio) {
            // Container is wider than preview - scale based on width
            scale = containerAspectRatio / previewAspectRatio;
          } else {
            // Container is taller than preview - scale based on height
            scale = 1.0; // No additional scaling needed
          }

          // Check if we're using the front camera (usually index 1)
          final isFrontCamera = controller.description.lensDirection ==
              camera.CameraLensDirection.front;

          return Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            color: Colors.black,
            child: Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(scale * (isFrontCamera ? -1.0 : 1.0), scale),
                child: AspectRatio(
                  aspectRatio: previewAspectRatio,
                  child: camera.CameraPreview(controller),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 40.h,
      right: 20.w,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.black54,
            radius: 24.r,
            child: IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
              onPressed: _switchCamera,
            ),
          ),
        ],
      ),
    );
  }
}

class FaceBoundingBoxOverlay extends StatelessWidget {
  final Rect? faceRect;
  final Size imageSize;
  final bool isDetecting;
  final bool isFrontCamera;

  const FaceBoundingBoxOverlay({
    super.key,
    this.faceRect,
    required this.imageSize,
    this.isDetecting = false,
    this.isFrontCamera = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FaceBoundingBoxPainter(
        faceRect: faceRect,
        imageSize: imageSize,
        isDetecting: isDetecting,
        isFrontCamera: isFrontCamera,
      ),
      child: Container(),
    );
  }
}

class FaceBoundingBoxPainter extends CustomPainter {
  final Rect? faceRect;
  final Size imageSize;
  final bool isDetecting;
  final bool isFrontCamera;

  FaceBoundingBoxPainter({
    this.faceRect,
    required this.imageSize,
    this.isDetecting = false,
    this.isFrontCamera = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faceRect == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = isDetecting ? Colors.green : Colors.blue;

    // Calculate the camera preview aspect ratio (always landscape orientation)
    // Note: imageSize is the camera image dimensions
    final cameraAspectRatio = imageSize.width / imageSize.height;

    // Calculate the display aspect ratio (portrait mode)
    final displayAspectRatio = size.width / size.height;

    // Calculate how the camera preview is scaled to fill the display
    // The preview uses AspectRatio with 1/cameraAspectRatio for portrait
    final previewAspectRatio = 1 / cameraAspectRatio;

    // Determine the scale to fill the container (same logic as camera preview)
    double scale;
    double offsetX = 0;
    double offsetY = 0;

    if (displayAspectRatio > previewAspectRatio) {
      // Display is wider than preview - scale based on width
      scale = displayAspectRatio / previewAspectRatio;
      // Preview is taller, so it's cropped at top and bottom
      final scaledHeight = size.height * scale;
      final actualHeight = size.width / previewAspectRatio;
      offsetY = (scaledHeight - actualHeight) / 2;
    } else {
      // Display is taller than preview - no additional scaling
      scale = 1.0;
      // Preview might be wider, so calculate any horizontal offset
      final actualWidth = size.height * previewAspectRatio;
      offsetX = (size.width - actualWidth) / 2;
    }

    // Calculate the actual scale factors for coordinates
    // We need to swap width and height because camera is in landscape, display is in portrait
    final scaleX = size.width / imageSize.height;  // Swapped
    final scaleY = size.height / imageSize.width;  // Swapped

    // Apply transformation
    Rect transformedRect;
    if (isFrontCamera) {
      // For front camera, we need to:
      // 1. Swap coordinates (because of rotation)
      // 2. Mirror horizontally
      transformedRect = Rect.fromLTRB(
        size.width - (faceRect!.bottom * scaleX),  // Mirror and swap
        faceRect!.left * scaleY,                   // Swap coordinates
        size.width - (faceRect!.top * scaleX),     // Mirror and swap
        faceRect!.right * scaleY,                  // Swap coordinates
      );
    } else {
      // For back camera, just swap coordinates (because of rotation)
      transformedRect = Rect.fromLTRB(
        faceRect!.top * scaleX,     // Swap coordinates
        faceRect!.left * scaleY,    // Swap coordinates
        faceRect!.bottom * scaleX,  // Swap coordinates
        faceRect!.right * scaleY,   // Swap coordinates
      );
    }

    final scaledRect = transformedRect;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scaledRect, const Radius.circular(10)),
      paint,
    );

    // Draw corner indicators
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = isDetecting ? Colors.green : Colors.blue;

    final cornerLength = 20.0;

    // Top-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top + cornerLength),
      Offset(scaledRect.left, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top),
      Offset(scaledRect.left + cornerLength, scaledRect.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(scaledRect.right - cornerLength, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom - cornerLength),
      Offset(scaledRect.left, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom),
      Offset(scaledRect.left + cornerLength, scaledRect.bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(scaledRect.right - cornerLength, scaledRect.bottom),
      Offset(scaledRect.right, scaledRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom - cornerLength),
      Offset(scaledRect.right, scaledRect.bottom),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(FaceBoundingBoxPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect ||
           oldDelegate.isDetecting != isDetecting ||
           oldDelegate.isFrontCamera != isFrontCamera;
  }
}