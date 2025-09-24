import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../data/models/face_recognition_log_model.dart';

class LogCard extends StatelessWidget {
  final FaceRecognitionLogModel log;
  final VoidCallback? onTap;

  const LogCard({
    super.key,
    required this.log,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              // Thumbnail or placeholder
              _buildThumbnail(),

              SizedBox(width: 16.w),

              // Log details
              Expanded(
                child: _buildLogDetails(context),
              ),

              // Status indicator and time
              _buildStatusSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return Container(
      width: 60.w,
      height: 60.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: Colors.grey[200],
      ),
      child: log.hasThumbnail
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Image.memory(
                log.thumbnailImage!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholderThumbnail();
                },
              ),
            )
          : _buildPlaceholderThumbnail(),
    );
  }

  Widget _buildPlaceholderThumbnail() {
    return Icon(
      log.resultIcon,
      color: log.resultColor.withOpacity(0.7),
      size: 24.sp,
    );
  }

  Widget _buildLogDetails(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result type and employee name
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: log.resultColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4.r),
                border: Border.all(
                  color: log.resultColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                log.resultTypeDisplayName,
                style: TextStyle(
                  color: log.resultColor,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (log.employeeName != null) ...[
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  log.employeeName!,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),

        SizedBox(height: 4.h),

        // Confidence and quality
        if (log.confidence != null || log.quality != null)
          Row(
            children: [
              if (log.confidence != null) ...[
                Icon(
                  Icons.verified,
                  size: 12.sp,
                  color: Colors.grey[600],
                ),
                SizedBox(width: 4.w),
                Text(
                  '${(log.confidence! * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              if (log.confidence != null && log.quality != null)
                Text(
                  ' • ',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[400],
                  ),
                ),
              if (log.quality != null) ...[
                Icon(
                  Icons.high_quality,
                  size: 12.sp,
                  color: Colors.grey[600],
                ),
                SizedBox(width: 4.w),
                Text(
                  '${(log.quality! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),

        SizedBox(height: 4.h),

        // Processing time and image info
        Row(
          children: [
            Icon(
              Icons.timer,
              size: 12.sp,
              color: Colors.grey[500],
            ),
            SizedBox(width: 4.w),
            Text(
              '${log.processingTimeMs}ms',
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey[600],
              ),
            ),
            if (log.hasImage) ...[
              Text(
                ' • ',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey[400],
                ),
              ),
              Icon(
                Icons.image,
                size: 12.sp,
                color: Colors.grey[500],
              ),
              SizedBox(width: 2.w),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Status icon
        Container(
          width: 24.w,
          height: 24.h,
          decoration: BoxDecoration(
            color: log.resultColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            log.resultIcon,
            color: log.resultColor,
            size: 12.sp,
          ),
        ),

        SizedBox(height: 8.h),

        // Timestamp
        Text(
          _formatTimestamp(log.timestamp),
          style: TextStyle(
            fontSize: 10.sp,
            color: Colors.grey[500],
          ),
        ),

        // Date if different from today
        if (!_isToday(log.timestamp))
          Text(
            _formatDate(log.timestamp),
            style: TextStyle(
              fontSize: 9.sp,
              color: Colors.grey[400],
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    return DateFormat('HH:mm:ss').format(dateTime);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (logDate == today) {
      return 'Today';
    } else if (logDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd').format(dateTime);
    }
  }

  bool _isToday(DateTime dateTime) {
    final now = DateTime.now();
    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }
}