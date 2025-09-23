import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../../employee/presentation/bloc/employee_bloc.dart';
import '../../../employee/presentation/bloc/employee_event.dart' as employee_events;
import '../bloc/face_recognition_bloc.dart';
import '../bloc/face_recognition_event.dart';
import '../bloc/face_recognition_state.dart';
import '../widgets/employee_confirmation_dialog.dart';
import '../widgets/face_positioning_overlay.dart';
import '../widgets/recognition_feedback_overlay.dart';

/// Main camera screen for face recognition
class CameraRecognitionScreen extends StatefulWidget {
  const CameraRecognitionScreen({super.key});

  @override
  State<CameraRecognitionScreen> createState() => _CameraRecognitionScreenState();
}

class _CameraRecognitionScreenState extends State<CameraRecognitionScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableClassification: true,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  bool _isDetecting = false;
  Rect? _currentFaceBounds;
  double? _currentFaceQuality;
  DateTime? _lastProcessTime;
  Size? _currentImageSize;
  static const _processingInterval = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Schedule face recognition initialization after the first frame
    // This ensures context is properly built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFaceRecognition();
    });

    // Initialize camera
    _initializeCamera();

    // Set system UI overlays
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _faceDetector.close();
    
    // Restore system UI overlays
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No cameras available');
        return;
      }

      // Use front camera if available, otherwise use the first camera
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // Best for ML processing
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {});
        _startImageStream();
      }
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
      _showError('Camera initialization failed');
    }
  }

  void _initializeFaceRecognition() {
    Logger.info('Initializing face recognition from camera screen');

    // Initialize face recognition with employees from database
    context.read<FaceRecognitionBloc>().add(const InitializeFaceRecognition());

    // Also ensure employees are loaded in EmployeeBloc
    context.read<EmployeeBloc>().add(const employee_events.LoadEmployees());

    Logger.info('Face recognition initialization events dispatched');
  }

  void _startImageStream() {
    if (_cameraController == null || 
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isStreamingImages) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;

      // Throttle processing
      if (_lastProcessTime != null &&
          DateTime.now().difference(_lastProcessTime!) < _processingInterval) {
        return;
      }

      _isDetecting = true;
      _lastProcessTime = DateTime.now();

      try {
        await _processCameraImage(image);
      } catch (e) {
        Logger.error('Error processing camera image', error: e);
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      // Store the image dimensions
      _currentImageSize = Size(image.width.toDouble(), image.height.toDouble());

      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      // Detect faces
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _currentFaceBounds = null;
            _currentFaceQuality = null;
          });
        }
        return;
      }

      // Get the largest face (closest to camera)
      final face = faces.reduce((a, b) => 
        a.boundingBox.width * a.boundingBox.height >
        b.boundingBox.width * b.boundingBox.height ? a : b);

      // Calculate face quality
      final quality = _calculateFaceQuality(face, image);

      // Check if face is in the target area
      final isInTargetArea = _isFaceInTargetArea(face, image);

      if (mounted) {
        setState(() {
          _currentFaceBounds = face.boundingBox;
          _currentFaceQuality = quality;
        });
      }

      // Only process for recognition if quality is good AND face is in target area
      if (quality > 0.6 && isInTargetArea) {
        final recognitionBloc = context.read<FaceRecognitionBloc>();
        final state = recognitionBloc.state;

        // Only process if we're in a ready state (not already processing)
        if (state is FaceRecognitionReady ||
            state is FaceRecognitionNoFace ||
            state is FaceRecognitionUnknown ||
            state is FaceRecognitionScanning) {

          // Start recognition if not already started
          if (state is FaceRecognitionReady) {
            recognitionBloc.add(const StartRecognition());
          } else {
            // Process the frame for face recognition
            recognitionBloc.add(const ProcessCameraFrame());
          }
        }
      }
    } catch (e) {
      Logger.error('Error in face detection', error: e);
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );

      if (rotation == null) return null;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null ||
          (format != InputImageFormat.nv21 && format != InputImageFormat.yv12)) {
        return null;
      }

      // Calculate image dimensions
      final plane = image.planes.first;
      final planeData = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: planeData,
      );
    } catch (e) {
      Logger.error('Error converting camera image', error: e);
      return null;
    }
  }

  double _calculateFaceQuality(Face face, CameraImage image) {
    // Basic quality calculation based on face size and position
    final imageArea = image.width * image.height;
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final faceRatio = faceArea / imageArea;

    // Ideal face should be 15-40% of image
    double sizeScore;
    if (faceRatio < 0.15) {
      sizeScore = faceRatio / 0.15; // Too small
    } else if (faceRatio > 0.4) {
      sizeScore = 0.4 / faceRatio; // Too large
    } else {
      sizeScore = 1.0; // Good size
    }

    // Check if face is centered
    final centerX = image.width / 2;
    final centerY = image.height / 2;
    final faceCenterX = face.boundingBox.center.dx;
    final faceCenterY = face.boundingBox.center.dy;
    
    final distanceFromCenter = ((faceCenterX - centerX).abs() / centerX +
                               (faceCenterY - centerY).abs() / centerY) / 2;
    final centerScore = 1.0 - distanceFromCenter.clamp(0.0, 1.0);

    // Check face angles (should be looking straight)
    double angleScore = 1.0;
    if (face.headEulerAngleY != null) {
      // Penalize if head is turned more than 15 degrees
      angleScore *= (1.0 - (face.headEulerAngleY!.abs() / 45.0)).clamp(0.0, 1.0);
    }
    if (face.headEulerAngleZ != null) {
      // Penalize if head is tilted more than 15 degrees
      angleScore *= (1.0 - (face.headEulerAngleZ!.abs() / 45.0)).clamp(0.0, 1.0);
    }

    // Combine scores
    return (sizeScore * 0.4 + centerScore * 0.3 + angleScore * 0.3).clamp(0.0, 1.0);
  }

  bool _isFaceInTargetArea(Face face, CameraImage image) {
    // Define target area (center-upper portion of screen)
    // This should match the overlay target area
    final targetCenterX = image.width / 2;
    final targetCenterY = image.height * 0.35; // Upper portion
    final targetWidth = image.width * 0.35;
    final targetHeight = targetWidth * 1.3;

    // Get face center - need to account for mirroring
    var faceCenterX = face.boundingBox.center.dx;
    final faceCenterY = face.boundingBox.center.dy;

    // If using front camera (mirrored), flip the X coordinate
    final isFrontCamera = _cameraController?.description.lensDirection ==
        CameraLensDirection.front;
    if (isFrontCamera) {
      faceCenterX = image.width - faceCenterX;
    }

    // Check if face center is within target bounds (with some tolerance)
    final toleranceX = targetWidth * 0.3;
    final toleranceY = targetHeight * 0.3;

    final isInX = (faceCenterX - targetCenterX).abs() < toleranceX;
    final isInY = (faceCenterY - targetCenterY).abs() < toleranceY;

    // Check if face size is appropriate
    final faceWidth = face.boundingBox.width;
    final faceHeight = face.boundingBox.height;
    final sizeRatio = faceWidth / targetWidth;
    final isSizeOk = sizeRatio > 0.6 && sizeRatio < 1.4;

    return isInX && isInY && isSizeOk;
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocListener<FaceRecognitionBloc, FaceRecognitionState>(
        listener: (context, state) {
          if (state is FaceRecognitionMatched) {
            // Show confirmation dialog
            EmployeeConfirmationDialog.show(
              context: context,
              employee: state.employee,
              confidence: state.confidence,
              currentStatus: null, // TODO: Get from employee status
            );
          } else if (state is FaceRecognitionError) {
            _showError(state.message);
          } else if (state is FaceRecognitionConfirmed) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.actionMessage),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
            
            // Reset after success
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                context.read<FaceRecognitionBloc>().add(
                  const InitializeFaceRecognition(),
                );
              }
            });
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview with mirroring for front camera
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(-1.0, 1.0), // Mirror horizontally
                child: CameraPreview(_cameraController!),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),

            // Face positioning overlay with target guide
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              FacePositioningOverlay(
                isFaceDetected: _currentFaceBounds != null,
                isGoodQuality: (_currentFaceQuality ?? 0) > 0.6,
              ),

            // Top bar with back button and settings
            Positioned(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24.sp,
                      ),
                    ),
                    Text(
                      'Face Recognition',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      onPressed: _switchCamera,
                      icon: Icon(
                        Icons.cameraswitch,
                        color: Colors.white,
                        size: 24.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom info panel
            Positioned(
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
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // Manual actions row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionButton(
                          icon: Icons.list_alt,
                          label: 'View Logs',
                          onPressed: () {
                            // TODO: Navigate to logs screen
                          },
                        ),
                        _ActionButton(
                          icon: Icons.people,
                          label: 'Employees',
                          onPressed: () {
                            // TODO: Navigate to employees screen
                          },
                        ),
                        _ActionButton(
                          icon: Icons.sync,
                          label: 'Sync',
                          onPressed: () {
                            context.read<EmployeeBloc>().add(
                              const employee_events.SyncEmployees(),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null) return;

    final cameras = await availableCameras();
    if (cameras.length < 2) return;

    final currentCamera = _cameraController!.description;
    final newCamera = cameras.firstWhere(
      (camera) => camera.lensDirection != currentCamera.lensDirection,
      orElse: () => cameras.first,
    );

    if (newCamera == currentCamera) return;

    // Stop current camera
    await _cameraController!.dispose();

    // Initialize new camera
    _cameraController = CameraController(
      newCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();

    if (mounted) {
      setState(() {});
      _startImageStream();
    }
  }
}

/// Action button widget for bottom panel
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 12.h,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 24.sp,
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}