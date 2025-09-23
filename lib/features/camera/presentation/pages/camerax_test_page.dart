import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/services/camerax_service.dart';
import '../../../../core/utils/logger.dart';
import '../widgets/camerax_preview_widget.dart';

/// Test page to verify CameraX platform channel integration
class CameraXTestPage extends StatefulWidget {
  const CameraXTestPage({super.key});

  @override
  State<CameraXTestPage> createState() => _CameraXTestPageState();
}

class _CameraXTestPageState extends State<CameraXTestPage> {
  late final CameraXService _cameraXService;
  bool _isStreaming = false;
  int _frameCount = 0;
  String _lastFrameInfo = 'No frames yet';

  @override
  void initState() {
    super.initState();
    _cameraXService = GetIt.instance<CameraXService>();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _cameraXService.checkCameraPermission();
    if (!hasPermission) {
      Logger.warning('Camera permission not granted');
      // In a real app, request permission here
    }
  }

  Future<void> _toggleStream() async {
    try {
      if (_isStreaming) {
        await _cameraXService.stopImageStream();
        setState(() {
          _isStreaming = false;
        });
      } else {
        await _cameraXService.startImageStream();

        // Listen to frame stream
        _cameraXService.frameStream.listen((frame) {
          setState(() {
            _frameCount++;
            _lastFrameInfo = 'Frame #$_frameCount: ${frame.width}x${frame.height}, ${frame.format}';
          });

          // Log every 30th frame
          if (_frameCount % 30 == 0) {
            Logger.debug('Received frame: ${frame.width}x${frame.height}');
          }
        });

        setState(() {
          _isStreaming = true;
        });
      }
    } catch (e) {
      Logger.error('Error toggling stream', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _cameraXService.switchCamera();
      Logger.success('Camera switched');
    } catch (e) {
      Logger.error('Error switching camera', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CameraX Test'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            child: CameraXPreviewWidget(
              cameraXService: _cameraXService,
              fit: BoxFit.cover,
              overlay: Stack(
                children: [
                  // Frame counter overlay
                  Positioned(
                    top: 10.h,
                    left: 10.w,
                    child: Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frames: $_frameCount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                            ),
                          ),
                          Text(
                            _isStreaming ? 'Streaming' : 'Not Streaming',
                            style: TextStyle(
                              color: _isStreaming ? Colors.green : Colors.orange,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Face detection area guide
                  Center(
                    child: Container(
                      width: 250.w,
                      height: 350.h,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white70,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info panel
          Container(
            padding: EdgeInsets.all(16.w),
            color: Colors.grey[900],
            child: Column(
              children: [
                Text(
                  _lastFrameInfo,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'CameraX Integration Test',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Control buttons
          Container(
            padding: EdgeInsets.all(16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleStream,
                  icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                  label: Text(_isStreaming ? 'Stop' : 'Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming ? Colors.red : Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.flip_camera_ios),
                  label: const Text('Switch'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _cameraXService.setFlashMode(CameraXFlashMode.on);
                    Logger.info('Flash turned on');
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Flash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_isStreaming) {
      _cameraXService.stopImageStream();
    }
    super.dispose();
  }
}