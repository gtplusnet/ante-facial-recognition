import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/services/camerax_service.dart';
import '../../../../core/utils/logger.dart';

/// Widget to display CameraX preview using platform texture
class CameraXPreviewWidget extends StatefulWidget {
  final CameraXService cameraXService;
  final Widget? overlay;
  final BoxFit fit;

  const CameraXPreviewWidget({
    super.key,
    required this.cameraXService,
    this.overlay,
    this.fit = BoxFit.cover,
  });

  @override
  State<CameraXPreviewWidget> createState() => _CameraXPreviewWidgetState();
}

class _CameraXPreviewWidgetState extends State<CameraXPreviewWidget> {
  CameraXInitResult? _initResult;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
    });

    try {
      if (!widget.cameraXService.isInitialized) {
        final result = await widget.cameraXService.initializeCamera();
        setState(() {
          _initResult = result;
          _isInitializing = false;
        });
      } else if (widget.cameraXService.textureId != null) {
        setState(() {
          _initResult = CameraXInitResult(
            textureId: widget.cameraXService.textureId!,
            previewWidth: 1920,
            previewHeight: 1080,
          );
          _isInitializing = false;
        });
      }
    } catch (e) {
      Logger.error('Failed to initialize CameraX preview', error: e);
      setState(() {
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (_initResult == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 48.sp,
                color: Colors.white54,
              ),
              SizedBox(height: 16.h),
              Text(
                'Camera not available',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16.sp,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Get device orientation
        final orientation = MediaQuery.of(context).orientation;

        // Camera dimensions are typically in landscape orientation
        // For portrait mode, we need to swap width and height
        final double cameraWidth = orientation == Orientation.portrait
            ? _initResult!.previewHeight.toDouble()
            : _initResult!.previewWidth.toDouble();
        final double cameraHeight = orientation == Orientation.portrait
            ? _initResult!.previewWidth.toDouble()
            : _initResult!.previewHeight.toDouble();

        // Calculate aspect ratios
        final double cameraAspectRatio = cameraWidth / cameraHeight;
        final double screenAspectRatio =
            constraints.maxWidth / constraints.maxHeight;

        // Calculate scale and dimensions to maintain aspect ratio
        double scale;
        double previewWidth;
        double previewHeight;

        if (widget.fit == BoxFit.cover) {
          // Fill the container, cropping if necessary
          if (screenAspectRatio > cameraAspectRatio) {
            // Screen is wider than camera
            scale = constraints.maxWidth / cameraWidth;
          } else {
            // Screen is taller than camera
            scale = constraints.maxHeight / cameraHeight;
          }
          previewWidth = cameraWidth * scale;
          previewHeight = cameraHeight * scale;
        } else {
          // Fit entire preview, with black bars if necessary
          if (screenAspectRatio > cameraAspectRatio) {
            // Screen is wider than camera
            scale = constraints.maxHeight / cameraHeight;
          } else {
            // Screen is taller than camera
            scale = constraints.maxWidth / cameraWidth;
          }
          previewWidth = cameraWidth * scale;
          previewHeight = cameraHeight * scale;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // Black background
            Container(color: Colors.black),

            // Camera preview with proper clipping
            ClipRect(
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: OverflowBox(
                  maxWidth: previewWidth,
                  maxHeight: previewHeight,
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: Transform(
                      alignment: Alignment.center,
                      // Mirror the preview for front camera
                      transform: widget.cameraXService.currentLensFacing == 1
                          ? (Matrix4.identity()..scale(-1.0, 1.0))
                          : Matrix4.identity(),
                      child: Texture(textureId: _initResult!.textureId),
                    ),
                  ),
                ),
              ),
            ),

            // Overlay widget if provided
            if (widget.overlay != null) widget.overlay!,
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // Don't dispose CameraXService here as it's managed at a higher level
    super.dispose();
  }
}