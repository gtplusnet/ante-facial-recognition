import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../bloc/employee_bloc.dart';
import '../bloc/employee_event.dart';
import '../bloc/employee_state.dart';

class AddFaceCameraScreen extends StatefulWidget {
  final String employeeId;

  const AddFaceCameraScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<AddFaceCameraScreen> createState() => _AddFaceCameraScreenState();
}

class _AddFaceCameraScreenState extends State<AddFaceCameraScreen> {
  CameraController? _cameraController;
  late final FaceDetector _faceDetector;
  late final EmployeeBloc _employeeBloc;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isTakingPicture = false;
  bool _faceDetected = false;
  double _faceQuality = 0.0;
  String _qualityMessage = 'Position your face in the circle';

  Timer? _autoCaptuarTimer;
  int _autoCaptuarCountdown = 3;

  @override
  void initState() {
    super.initState();
    _employeeBloc = getIt<EmployeeBloc>();
    _initializeFaceDetector();
    _initializeCamera();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.fast,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No cameras available');
        return;
      }

      // Prefer front camera for face capture
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // Start face detection
        _startFaceDetection();
      }
    } catch (e) {
      Logger.error('Failed to initialize camera', error: e);
      _showError('Failed to initialize camera');
    }
  }

  void _startFaceDetection() {
    Logger.info('Starting face detection...');
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      Logger.error('Camera controller not ready for face detection');
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing || _isTakingPicture) return;

      _isProcessing = true;
      await _detectFace(image);
      _isProcessing = false;
    });
  }

  Future<void> _detectFace(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      Logger.debug('Detected ${faces.length} face(s)');

      if (faces.isEmpty) {
        _updateFaceStatus(false, 0, 'Position your face in the circle');
        return;
      }

      if (faces.length > 1) {
        _updateFaceStatus(false, 0, 'Multiple faces detected');
        return;
      }

      final face = faces.first;
      final quality = _calculateFaceQuality(face, image);
      final message = _getQualityMessage(quality, face, image);

      _updateFaceStatus(quality > 0.7, quality, message);

      // Auto capture if quality is good for 3 seconds
      if (quality > 0.8 && !_isTakingPicture) {
        _startAutoCapture();
      } else {
        _cancelAutoCapture();
      }
    } catch (e) {
      Logger.error('Face detection error', error: e);
    }
  }

  double _calculateFaceQuality(Face face, CameraImage image) {
    double quality = 1.0;

    // Check face size (should be 20-80% of frame)
    final faceWidth = face.boundingBox.width;
    final faceHeight = face.boundingBox.height;
    final frameWidth = image.width.toDouble();
    final frameHeight = image.height.toDouble();

    final faceSizeRatio = (faceWidth * faceHeight) / (frameWidth * frameHeight);
    if (faceSizeRatio < 0.1) {
      quality *= 0.5; // Too far
    } else if (faceSizeRatio > 0.6) {
      quality *= 0.7; // Too close
    }

    // Check face position (should be centered)
    final faceCenterX = face.boundingBox.center.dx;
    final faceCenterY = face.boundingBox.center.dy;
    final frameCenterX = frameWidth / 2;
    final frameCenterY = frameHeight / 2;

    final centerOffset = ((faceCenterX - frameCenterX).abs() / frameWidth) +
        ((faceCenterY - frameCenterY).abs() / frameHeight);
    if (centerOffset > 0.3) {
      quality *= 0.6; // Not centered
    }

    // Check face angles
    if (face.headEulerAngleY != null) {
      final yaw = face.headEulerAngleY!.abs();
      if (yaw > 30) quality *= 0.5; // Face turned too much
    }

    if (face.headEulerAngleZ != null) {
      final roll = face.headEulerAngleZ!.abs();
      if (roll > 30) quality *= 0.5; // Face tilted too much
    }

    // Check if eyes are open
    if (face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.5) {
      quality *= 0.7;
    }
    if (face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < 0.5) {
      quality *= 0.7;
    }

    return quality.clamp(0.0, 1.0);
  }

  String _getQualityMessage(double quality, Face face, CameraImage image) {
    if (quality < 0.3) {
      final faceSize = (face.boundingBox.width * face.boundingBox.height) /
          (image.width * image.height);
      if (faceSize < 0.1) return 'Move closer';
      if (faceSize > 0.6) return 'Move further away';
      return 'Center your face';
    }

    if (quality < 0.5) {
      if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
        return 'Face forward';
      }
      if (face.headEulerAngleZ != null && face.headEulerAngleZ!.abs() > 30) {
        return 'Keep head straight';
      }
      return 'Improve lighting';
    }

    if (quality < 0.7) {
      return 'Almost ready...';
    }

    return 'Perfect! Hold still';
  }

  void _updateFaceStatus(bool detected, double quality, String message) {
    if (mounted) {
      setState(() {
        _faceDetected = detected;
        _faceQuality = quality;
        _qualityMessage = message;
      });
    }
  }

  void _startAutoCapture() {
    if (_autoCaptuarTimer != null) return;

    _autoCaptuarCountdown = 3;
    _autoCaptuarTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_autoCaptuarCountdown > 1) {
        setState(() {
          _autoCaptuarCountdown--;
        });
      } else {
        timer.cancel();
        _autoCaptuarTimer = null;
        _takePicture();
      }
    });
  }

  void _cancelAutoCapture() {
    _autoCaptuarTimer?.cancel();
    _autoCaptuarTimer = null;
    if (mounted) {
      setState(() {
        _autoCaptuarCountdown = 3;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isTakingPicture) return;

    setState(() {
      _isTakingPicture = true;
    });

    try {
      // Stop image stream before taking picture
      await _cameraController!.stopImageStream();

      // Take the picture
      final XFile picture = await _cameraController!.takePicture();

      // Read image bytes
      final Uint8List imageBytes = await picture.readAsBytes();

      // Show preview and confirm
      if (mounted) {
        _showPreviewDialog(imageBytes);
      }
    } catch (e) {
      Logger.error('Failed to take picture', error: e);
      _showError('Failed to capture image');
    } finally {
      setState(() {
        _isTakingPicture = false;
      });

      // Restart face detection
      _startFaceDetection();
    }
  }

  void _showPreviewDialog(Uint8List imageBytes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Image.memory(imageBytes),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Use this image?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('Retake'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _saveFaceImage(imageBytes);
                        },
                        child: const Text('Use Image'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveFaceImage(Uint8List imageBytes) {
    _employeeBloc.add(
      AddFaceImage(
        employeeId: widget.employeeId,
        imageBytes: imageBytes,
        source: 'registration', // Mark as registration to differentiate from API photo
      ),
    );

    // Listen for result
    _employeeBloc.stream.listen((state) {
      if (state is FaceImageAdded && state.employeeId == widget.employeeId) {
        // Success - go back with result
        context.pop(true);
      } else if (state is EmployeeError) {
        _showError(state.message);
      }
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      // Convert YUV420 to NV21 for ML Kit
      final bytes = _convertYuv420ToNv21(image);

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation rotation = _getImageRotation();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      Logger.error('Failed to convert camera image', error: e);
      return null;
    }
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final nv21 = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    // Copy Y plane
    final yPlane = image.planes[0].bytes;
    nv21.setRange(0, yPlane.length, yPlane);

    // Interleave U and V planes
    final uPlane = image.planes[1].bytes;
    final vPlane = image.planes[2].bytes;

    int nv21Index = width * height;
    for (int i = 0; i < height ~/ 2; i++) {
      for (int j = 0; j < width ~/ 2; j++) {
        final int uvIndex = i * uvRowStride + j * uvPixelStride;
        nv21[nv21Index++] = vPlane[uvIndex];
        nv21[nv21Index++] = uPlane[uvIndex];
      }
    }

    return nv21;
  }

  InputImageRotation _getImageRotation() {
    if (_cameraController == null) return InputImageRotation.rotation0deg;

    final sensorOrientation = _cameraController!.description.sensorOrientation;

    InputImageRotation? rotation;
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
    }

    return rotation;
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _employeeBloc,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Add Face Image'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: BlocListener<EmployeeBloc, EmployeeState>(
          listener: (context, state) {
            if (state is FaceImageProcessing) {
              // Show loading overlay
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(state.message),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            } else if (state is FaceImageAdded) {
              // Dismiss loading dialog
              Navigator.of(context, rootNavigator: true).pop();
              // Show success and navigate back
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Face image added successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              // Navigate back with success result
              context.pop(true);
            } else if (state is EmployeeError) {
              // Dismiss loading dialog
              Navigator.of(context, rootNavigator: true).pop();
              // Show error
              _showError(state.message);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview with mirror effect for front camera
              if (_isInitialized && _cameraController != null)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(-1.0, 1.0), // Mirror horizontally
                  child: CameraPreview(_cameraController!),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),

              // Face detection overlay
              CustomPaint(
                painter: FaceOverlayPainter(
                  detected: _faceDetected,
                  quality: _faceQuality,
                ),
              ),

              // Quality indicators
              Positioned(
                top: 50,
                left: 0,
                right: 0,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _faceDetected
                        ? Colors.green.withOpacity(0.9)
                        : Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _qualityMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_faceDetected) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _faceQuality,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _faceQuality > 0.7 ? Colors.white : Colors.orange,
                          ),
                        ),
                      ],
                      if (_autoCaptuarTimer != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Capturing in $_autoCaptuarCountdown...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Capture button
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: !_isTakingPicture ? _takePicture : null, // Allow manual capture
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _faceDetected
                            ? Colors.white
                            : Colors.white.withOpacity(0.7), // More visible when face not detected
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                      ),
                      child: _isTakingPicture
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 3,
                              ),
                            )
                          : Icon(
                              Icons.camera,
                              size: 35,
                              color: _faceDetected
                                  ? Colors.black
                                  : Colors.black.withOpacity(0.7), // More visible icon
                            ),
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

  @override
  void dispose() {
    _cancelAutoCapture();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}

// Custom painter for face overlay
class FaceOverlayPainter extends CustomPainter {
  final bool detected;
  final double quality;

  FaceOverlayPainter({
    required this.detected,
    required this.quality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    if (detected) {
      paint.color = quality > 0.7
          ? Colors.green.withOpacity(0.8)
          : Colors.orange.withOpacity(0.8);
    } else {
      paint.color = Colors.white.withOpacity(0.5);
    }

    // Draw oval guide
    final center = Offset(size.width / 2, size.height / 2.5);
    final rect = Rect.fromCenter(
      center: center,
      width: size.width * 0.7,
      height: size.height * 0.35,
    );

    canvas.drawOval(rect, paint);

    // Draw corner indicators
    if (detected && quality > 0.7) {
      paint.strokeWidth = 4.0;
      paint.color = Colors.green;

      const cornerLength = 20.0;

      // Top-left corner
      canvas.drawLine(
        Offset(rect.left, rect.top + cornerLength),
        Offset(rect.left, rect.top),
        paint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top),
        Offset(rect.left + cornerLength, rect.top),
        paint,
      );

      // Top-right corner
      canvas.drawLine(
        Offset(rect.right - cornerLength, rect.top),
        Offset(rect.right, rect.top),
        paint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + cornerLength),
        paint,
      );

      // Bottom-left corner
      canvas.drawLine(
        Offset(rect.left, rect.bottom - cornerLength),
        Offset(rect.left, rect.bottom),
        paint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.left + cornerLength, rect.bottom),
        paint,
      );

      // Bottom-right corner
      canvas.drawLine(
        Offset(rect.right - cornerLength, rect.bottom),
        Offset(rect.right, rect.bottom),
        paint,
      );
      canvas.drawLine(
        Offset(rect.right, rect.bottom - cornerLength),
        Offset(rect.right, rect.bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) {
    return oldDelegate.detected != detected || oldDelegate.quality != quality;
  }
}