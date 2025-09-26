import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/utils/logger.dart';

class RecognitionResultDialog extends StatefulWidget {
  final bool isRecognized;
  final String? employeeName;
  final String? employeeId;
  final double? confidence;
  final VoidCallback onDismiss;
  final bool enableAutoClose;
  final int autoCloseDuration;

  const RecognitionResultDialog({
    super.key,
    required this.isRecognized,
    this.employeeName,
    this.employeeId,
    this.confidence,
    required this.onDismiss,
    this.enableAutoClose = true,
    this.autoCloseDuration = 3,
  });

  @override
  State<RecognitionResultDialog> createState() => _RecognitionResultDialogState();
}

class _RecognitionResultDialogState extends State<RecognitionResultDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _animationController.forward();

    // Auto-dismiss only if enabled
    if (widget.enableAutoClose) {
      Future.delayed(Duration(seconds: widget.autoCloseDuration), () {
        if (mounted) {
          _dismissDialog();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismissDialog() {
    _animationController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _dismissDialog();
        return false;
      },
      child: Material(
        color: Colors.black.withOpacity(0.7),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 320.w,
                padding: EdgeInsets.all(24.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon/Animation
                    _buildIcon(),
                    SizedBox(height: 20.h),

                    // Title
                    Text(
                      widget.isRecognized
                          ? 'Face Recognized!'
                          : 'Face Not Recognized',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                        color: widget.isRecognized
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Recognition details
                    if (widget.isRecognized) ...[
                      _buildDetailRow('Name:', widget.employeeName ?? 'Unknown'),
                      SizedBox(height: 8.h),
                      _buildDetailRow('ID:', widget.employeeId ?? 'N/A'),
                      SizedBox(height: 8.h),
                      _buildDetailRow(
                        'Confidence:',
                        '${((widget.confidence ?? 0) * 100).toStringAsFixed(1)}%',
                      ),
                      SizedBox(height: 8.h),
                      _buildDetailRow('Status:', 'Ready to clock in'),
                    ] else ...[
                      Text(
                        'Your face was not found in the employee database.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'Please contact your supervisor if you believe this is an error.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],

                    SizedBox(height: 24.h),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (widget.isRecognized) ...[
                          _buildActionButton(
                            'Clock In',
                            Colors.green,
                            () {
                              Logger.info('Clock in tapped');
                              _dismissDialog();
                            },
                          ),
                          _buildActionButton(
                            'Cancel',
                            Colors.grey,
                            _dismissDialog,
                          ),
                        ] else ...[
                          _buildActionButton(
                            'Try Again',
                            Colors.blue,
                            _dismissDialog,
                          ),
                          _buildActionButton(
                            'Cancel',
                            Colors.grey,
                            _dismissDialog,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 80.w,
      height: 80.h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isRecognized
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
      ),
      child: Icon(
        widget.isRecognized
            ? Icons.check_circle_outline
            : Icons.error_outline,
        size: 50.sp,
        color: widget.isRecognized
            ? Colors.green
            : Colors.orange,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(
          horizontal: 24.w,
          vertical: 12.h,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14.sp,
          color: Colors.white,
        ),
      ),
    );
  }
}

// Helper function to show the dialog
Future<void> showRecognitionResultDialog(
  BuildContext context, {
  required bool isRecognized,
  String? employeeName,
  String? employeeId,
  double? confidence,
  required VoidCallback onDismiss,
  bool enableAutoClose = true,
  int autoCloseDuration = 3,
}) async {
  Logger.info('Showing recognition result dialog - Recognized: $isRecognized');

  await Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return RecognitionResultDialog(
          isRecognized: isRecognized,
          employeeName: employeeName,
          employeeId: employeeId,
          confidence: confidence,
          onDismiss: onDismiss,
          enableAutoClose: enableAutoClose,
          autoCloseDuration: autoCloseDuration,
        );
      },
      transitionDuration: Duration.zero,
    ),
  );
}