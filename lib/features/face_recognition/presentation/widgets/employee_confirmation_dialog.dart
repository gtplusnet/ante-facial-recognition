import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../employee/domain/entities/employee.dart';
import '../bloc/face_recognition_bloc.dart';
import '../bloc/face_recognition_event.dart';

/// Dialog that appears after successful face recognition
/// Allows the user to confirm the identity and select an action
class EmployeeConfirmationDialog extends StatefulWidget {
  final Employee employee;
  final double confidence;
  final String? capturedPhoto;
  final EmployeeTimeRecord? currentStatus;
  final bool enableAutoClose;
  final int autoCloseDuration;

  const EmployeeConfirmationDialog({
    super.key,
    required this.employee,
    required this.confidence,
    this.capturedPhoto,
    this.currentStatus,
    this.enableAutoClose = true,
    this.autoCloseDuration = 3,
  });

  static Future<void> show({
    required BuildContext context,
    required Employee employee,
    required double confidence,
    String? capturedPhoto,
    EmployeeTimeRecord? currentStatus,
    bool enableAutoClose = true,
    int autoCloseDuration = 3,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmployeeConfirmationDialog(
        employee: employee,
        confidence: confidence,
        capturedPhoto: capturedPhoto,
        currentStatus: currentStatus,
        enableAutoClose: enableAutoClose,
        autoCloseDuration: autoCloseDuration,
      ),
    );
  }

  @override
  State<EmployeeConfirmationDialog> createState() => _EmployeeConfirmationDialogState();
}

class _EmployeeConfirmationDialogState extends State<EmployeeConfirmationDialog> {
  Timer? _autoDismissTimer;
  late int _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = widget.autoCloseDuration;
    if (widget.enableAutoClose) {
      _startAutoDismissTimer();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _startAutoDismissTimer() {
    _autoDismissTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });

      if (_countdown <= 0) {
        timer.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClockingIn = widget.currentStatus == null ||
        widget.currentStatus?.status == 'clocked_out';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Container(
        width: 0.9.sw,
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button and countdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Auto-dismiss countdown (only show if enabled)
                if (widget.enableAutoClose)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer,
                          size: 16.sp,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'Auto-close: ${_countdown}s',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Close button
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close,
                    size: 24.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            // Employee photo and captured photo side by side
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Employee photo
                Column(
                  children: [
                    _ProfileImage(
                      imageBytes: widget.employee.photoBytes,
                      imageUrl: widget.employee.photoUrl,
                      size: 80.w,
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 30.w),
                // Captured photo
                if (widget.capturedPhoto != null)
                  Column(
                    children: [
                      _ProfileImage(
                        imageBytes: base64Decode(widget.capturedPhoto!),
                        size: 80.w,
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Captured',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 20.h),

            // Employee info
            Text(
              widget.employee.name,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4.h),
            Text(
              widget.employee.position ?? 'Employee',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[600],
              ),
            ),
            if (widget.employee.department != null) ...[
              SizedBox(height: 2.h),
              Text(
                widget.employee.department!,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[500],
                ),
              ),
            ],
            SizedBox(height: 16.h),

            // Confidence indicator
            _ConfidenceIndicator(confidence: widget.confidence),
            SizedBox(height: 20.h),

            // Current status
            if (widget.currentStatus != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 12.h,
                ),
                decoration: BoxDecoration(
                  color: isClockingIn 
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: isClockingIn ? Colors.orange : Colors.green,
                    width: 1.w,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isClockingIn ? Icons.login : Icons.logout,
                      size: 20.sp,
                      color: isClockingIn ? Colors.orange : Colors.green,
                    ),
                    SizedBox(width: 8.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isClockingIn ? 'Last Clock Out' : 'Clocked In',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _formatTime(
                            isClockingIn 
                                ? widget.currentStatus!.clockOutTime 
                                : widget.currentStatus!.clockInTime
                          ),
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            SizedBox(height: 20.h),

            // Action buttons
            Row(
              children: [
                // Cancel button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      side: BorderSide(
                        color: Colors.grey[400]!,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                // Confirm button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      // Dispatch the appropriate event
                      context.read<FaceRecognitionBloc>().add(
                        ConfirmRecognition(
                          employeeId: widget.employee.id,
                          action: isClockingIn
                              ? RecognitionAction.clockIn
                              : RecognitionAction.clockOut,
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isClockingIn ? Colors.green : Colors.orange,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isClockingIn ? Icons.login : Icons.logout,
                          size: 20.sp,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          isClockingIn ? 'Clock In' : 'Clock Out',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Wrong person link
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reset the recognition
                context.read<FaceRecognitionBloc>().add(
                  const InitializeFaceRecognition(),
                );
              },
              child: Text(
                'Not ${widget.employee.name.split(' ').first}?',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: theme.primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return 'N/A';
    final now = DateTime.now();
    if (time.day == now.day && 
        time.month == now.month && 
        time.year == now.year) {
      // Today
      return 'Today ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (time.day == now.day - 1 && 
               time.month == now.month && 
               time.year == now.year) {
      // Yesterday  
      return 'Yesterday ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      // Other days
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// Profile image widget with fallback
class _ProfileImage extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final double size;

  const _ProfileImage({
    this.imageBytes,
    this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey[300]!,
          width: 2.w,
        ),
      ),
      child: ClipOval(
        child: imageBytes != null
            ? Image.memory(
                imageBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
              )
            : imageUrl != null
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
                  )
                : _fallbackAvatar(),
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: Colors.grey[600],
      ),
    );
  }
}

/// Confidence indicator widget
class _ConfidenceIndicator extends StatelessWidget {
  final double confidence;

  const _ConfidenceIndicator({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final percentage = (confidence * 100).toInt();
    final color = _getConfidenceColor();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user,
              size: 16.sp,
              color: color,
            ),
            SizedBox(width: 4.w),
            Text(
              'Confidence: $percentage%',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Container(
          width: 200.w,
          height: 6.h,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(3.r),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: confidence.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3.r),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getConfidenceColor() {
    if (confidence >= 0.85) return Colors.green;
    if (confidence >= 0.70) return Colors.orange;
    return Colors.red;
  }
}