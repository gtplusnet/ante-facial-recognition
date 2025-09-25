import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/face_recognition_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_recognition/data/services/simplified_face_recognition_service.dart';
import '../../../face_recognition/presentation/widgets/employee_confirmation_dialog.dart';
import '../../data/models/face_recognition_log_model.dart';
import '../../data/services/face_recognition_log_service.dart';

class LogImageViewerDialog extends StatefulWidget {
  final FaceRecognitionLogModel log;

  const LogImageViewerDialog({
    super.key,
    required this.log,
  });

  static Future<void> show({
    required BuildContext context,
    required FaceRecognitionLogModel log,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) => LogImageViewerDialog(log: log),
    );
  }

  @override
  State<LogImageViewerDialog> createState() => _LogImageViewerDialogState();
}

class _LogImageViewerDialogState extends State<LogImageViewerDialog>
    with TickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  bool _showDetails = true;
  bool _showImageError = false;
  bool _isReprocessing = false;
  FaceRecognitionResult? _reprocessedResult;
  final FaceRecognitionConfig _config = FaceRecognitionConfig();

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Auto-hide details after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showDetails = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _animationController.reset();
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animation!.addListener(() {
      _transformationController.value = _animation!.value;
    });

    _animationController.forward();
  }

  void _toggleDetails() {
    setState(() {
      _showDetails = !_showDetails;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dismiss on tap background
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              color: Colors.transparent,
            ),
          ),

          // Image viewer
          Center(
            child: _buildImageViewer(),
          ),

          // Top overlay with details
          if (_showDetails) _buildTopOverlay(),

          // Bottom overlay with metadata
          if (_showDetails) _buildBottomOverlay(),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16.h,
            right: 16.w,
            child: _buildCloseButton(),
          ),

          // Controls overlay
          _buildControlsOverlay(),
        ],
      ),
    );
  }

  Widget _buildImageViewer() {
    if (!widget.log.hasImage && !widget.log.hasThumbnail) {
      return _buildNoImagePlaceholder();
    }

    // Use full image if available, otherwise use thumbnail
    final imageData = widget.log.faceImage ?? widget.log.thumbnailImage!;

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 5.0,
      onInteractionStart: (_) {
        // Show details when user starts interacting
        if (!_showDetails) {
          setState(() {
            _showDetails = true;
          });
        }
      },
      child: GestureDetector(
        onTap: _toggleDetails,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Image.memory(
              imageData,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                Logger.error('Failed to display log image', error: error);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _showImageError = true;
                    });
                  }
                });
                return _buildImageErrorPlaceholder();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoImagePlaceholder() {
    return Container(
      width: 200.w,
      height: 200.h,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 48.sp,
            color: Colors.grey[400],
          ),
          SizedBox(height: 12.h),
          Text(
            'No Image Available',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      width: 200.w,
      height: 200.h,
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.red[200]!, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 48.sp,
            color: Colors.red[400],
          ),
          SizedBox(height: 12.h),
          Text(
            'Failed to Load Image',
            style: TextStyle(
              color: Colors.red[600],
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16.h,
          left: 16.w,
          right: 60.w, // Space for close button
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Result type badge
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: widget.log.resultColor,
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.log.resultIcon,
                    color: Colors.white,
                    size: 16.sp,
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    widget.log.resultTypeDisplayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            if (widget.log.employeeName != null) ...[
              SizedBox(height: 8.h),
              Text(
                widget.log.employeeName!,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            SizedBox(height: 4.h),
            Text(
              DateFormat('MMM dd, yyyy • HH:mm:ss').format(widget.log.timestamp),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: 16.h,
          left: 16.w,
          right: 16.w,
          bottom: MediaQuery.of(context).padding.bottom + 16.h,
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
        child: _buildMetadataGrid(),
      ),
    );
  }

  Widget _buildMetadataGrid() {
    final metadataItems = <Widget>[];

    // Confidence
    if (widget.log.confidence != null) {
      metadataItems.add(_buildMetadataItem(
        icon: Icons.verified,
        label: 'Confidence',
        value: '${(widget.log.confidence! * 100).toStringAsFixed(1)}%',
      ));
    }

    // Quality
    if (widget.log.quality != null) {
      metadataItems.add(_buildMetadataItem(
        icon: Icons.high_quality,
        label: 'Quality',
        value: '${(widget.log.quality! * 100).toStringAsFixed(0)}%',
      ));
    }

    // Processing time
    metadataItems.add(_buildMetadataItem(
      icon: Icons.timer,
      label: 'Processing',
      value: '${widget.log.processingTimeMs}ms',
    ));

    // Image size
    if (widget.log.imageWidth != null && widget.log.imageHeight != null) {
      metadataItems.add(_buildMetadataItem(
        icon: Icons.aspect_ratio,
        label: 'Resolution',
        value: '${widget.log.imageWidth}×${widget.log.imageHeight}',
      ));
    }

    // Storage size
    final imageSize = widget.log.estimatedSize;
    if (imageSize > 0) {
      metadataItems.add(_buildMetadataItem(
        icon: Icons.storage,
        label: 'Size',
        value: _formatBytes(imageSize),
      ));
    }

    return Wrap(
      spacing: 16.w,
      runSpacing: 12.h,
      children: metadataItems,
    );
  }

  Widget _buildMetadataItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white70,
          size: 16.sp,
        ),
        SizedBox(width: 6.w),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.sp,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(
          Icons.close,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80.h,
      right: 16.w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reset zoom button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _resetZoom,
              icon: const Icon(
                Icons.zoom_out_map,
                color: Colors.white,
              ),
            ),
          ),

          SizedBox(height: 8.h),

          // Re-process face recognition button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _isReprocessing || !widget.log.hasImage
                  ? null
                  : _reprocessFaceRecognition,
              icon: _isReprocessing
                ? SizedBox(
                    width: 20.sp,
                    height: 20.sp,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    Icons.face_retouching_natural,
                    color: widget.log.hasImage ? Colors.white : Colors.grey,
                  ),
              tooltip: 'Re-process face recognition',
            ),
          ),

          SizedBox(height: 8.h),

          // Toggle details button
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _toggleDetails,
              icon: Icon(
                _showDetails ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reprocessFaceRecognition() async {
    if (!widget.log.hasImage || widget.log.faceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No image available for re-processing'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isReprocessing = true);

    try {
      // Get services
      final faceRecognitionService = getIt<SimplifiedFaceRecognitionService>();
      final logService = getIt<FaceRecognitionLogService>();

      Logger.info('Re-processing face recognition for log ${widget.log.id}');
      Logger.info('Using config - Confidence: ${_config.confidenceThreshold}, Quality: ${_config.qualityThreshold}');

      // Process the stored image
      final stopwatch = Stopwatch()..start();
      final result = await faceRecognitionService.processImageBytes(
        widget.log.faceImage!,
      );
      stopwatch.stop();

      if (result != null) {
        // Update the log with new results
        await logService.updateLog(
          widget.log.id!,
          result: result,
          processingTimeMs: stopwatch.elapsedMilliseconds,
          additionalMetadata: {
            'reprocess_reason': 'manual_retry',
            'config_confidence': _config.confidenceThreshold,
            'config_quality': _config.qualityThreshold,
          },
        );

        setState(() => _reprocessedResult = result);

        // Show appropriate feedback based on result
        if (result.type == FaceRecognitionResultType.matched && result.employee != null) {
          // Show success dialog
          if (mounted) {
            EmployeeConfirmationDialog.show(
              context: context,
              employee: result.employee!,
              confidence: result.confidence ?? 0.0,
              currentStatus: null,
            );
          }
        } else if (result.type == FaceRecognitionResultType.unknown) {
          _showResultDialog(
            title: 'Face Not Recognized',
            message: 'The face in this image was not found in the employee database.',
            resultType: result.type,
            quality: result.quality,
          );
        } else if (result.type == FaceRecognitionResultType.poorQuality) {
          _showResultDialog(
            title: 'Poor Image Quality',
            message: result.message ?? 'Poor image quality',
            resultType: result.type,
            quality: result.quality,
          );
        } else if (result.type == FaceRecognitionResultType.noFace) {
          _showResultDialog(
            title: 'No Face Detected',
            message: 'No face was detected in this image. The image may be unclear or the face may be too small.',
            resultType: result.type,
            quality: result.quality,
          );
        } else if (result.type == FaceRecognitionResultType.error) {
          _showResultDialog(
            title: 'Processing Error',
            message: result.message ?? 'An error occurred during processing',
            resultType: result.type,
            quality: result.quality,
            isError: true,
          );
        }

        Logger.success('Re-processing complete: ${result.type}');
      } else {
        _showResultDialog(
          title: 'Processing Failed',
          message: 'Failed to process the image. Please try again.',
          resultType: FaceRecognitionResultType.error,
          isError: true,
        );
      }
    } catch (e) {
      Logger.error('Re-processing failed', error: e);
      _showResultDialog(
        title: 'Processing Error',
        message: 'Re-processing failed: ${e.toString()}',
        resultType: FaceRecognitionResultType.error,
        isError: true,
      );
    } finally {
      setState(() => _isReprocessing = false);
    }
  }

  void _showResultDialog({
    required String title,
    required String message,
    required FaceRecognitionResultType resultType,
    double? quality,
    double? confidence,
    bool isError = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getResultIcon(resultType),
              color: _getResultColor(resultType),
              size: 28.sp,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey[700],
                ),
              ),
              if (quality != null) ...[
                SizedBox(height: 16.h),
                _buildQualityInfo(quality),
              ],
              if (confidence != null) ...[
                SizedBox(height: 12.h),
                _buildConfidenceInfo(confidence),
              ],
              if (resultType == FaceRecognitionResultType.poorQuality) ...[
                SizedBox(height: 16.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why is the quality low?',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'The stored image may have:\n'
                        '• Face too small in the frame\n'
                        '• Poor lighting conditions\n'
                        '• Blurry or out of focus\n'
                        '• Face at an angle',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.orange[800],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (resultType == FaceRecognitionResultType.poorQuality)
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
                // Temporarily lower quality threshold and retry
                final originalThreshold = _config.qualityThreshold;
                _config.qualityThreshold = 0.3; // Lower threshold
                _reprocessFaceRecognition().then((_) {
                  // Restore original threshold
                  _config.qualityThreshold = originalThreshold;
                });
              },
              child: const Text('Retry with Lower Threshold'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityInfo(double quality) {
    final qualityPercent = (quality * 100).toStringAsFixed(1);
    final thresholdPercent = (_config.qualityThreshold * 100).toStringAsFixed(0);
    final isAcceptable = quality >= _config.qualityThreshold;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isAcceptable ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Icon(
            isAcceptable ? Icons.check_circle : Icons.warning,
            color: isAcceptable ? Colors.green : Colors.red,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Face Quality Score',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 4.h),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$qualityPercent%',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: isAcceptable ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                      TextSpan(
                        text: ' (Required: $thresholdPercent%)',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceInfo(double confidence) {
    final confidencePercent = (confidence * 100).toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified,
            color: Colors.blue,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Match Confidence: ',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[700],
            ),
          ),
          Text(
            '$confidencePercent%',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getResultIcon(FaceRecognitionResultType type) {
    switch (type) {
      case FaceRecognitionResultType.matched:
        return Icons.check_circle;
      case FaceRecognitionResultType.unknown:
        return Icons.help_outline;
      case FaceRecognitionResultType.poorQuality:
        return Icons.image_not_supported;
      case FaceRecognitionResultType.noFace:
        return Icons.face_retouching_off;
      case FaceRecognitionResultType.error:
        return Icons.error_outline;
      default:
        return Icons.info_outline;
    }
  }

  Color _getResultColor(FaceRecognitionResultType type) {
    switch (type) {
      case FaceRecognitionResultType.matched:
        return Colors.green;
      case FaceRecognitionResultType.unknown:
        return Colors.orange;
      case FaceRecognitionResultType.poorQuality:
        return Colors.orange;
      case FaceRecognitionResultType.noFace:
        return Colors.grey;
      case FaceRecognitionResultType.error:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
}