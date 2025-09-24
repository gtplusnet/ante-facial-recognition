import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../../face_recognition/data/services/simplified_face_recognition_service.dart';
import '../../data/models/face_recognition_log_model.dart';
import '../../data/services/face_recognition_log_service.dart';
import '../widgets/log_card.dart';
import '../widgets/log_image_viewer_dialog.dart';

class FaceRecognitionLogsPage extends StatefulWidget {
  const FaceRecognitionLogsPage({super.key});

  @override
  State<FaceRecognitionLogsPage> createState() => _FaceRecognitionLogsPageState();
}

class _FaceRecognitionLogsPageState extends State<FaceRecognitionLogsPage> {
  final FaceRecognitionLogService _logService = getIt<FaceRecognitionLogService>();

  List<FaceRecognitionLogModel> _logs = [];
  bool _isLoading = true;
  String? _errorMessage;
  FaceRecognitionResultType? _selectedFilter;

  // Pagination
  static const int _pageSize = 20;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _setupScrollListener();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.8) {
        _loadMoreLogs();
      }
    });
  }

  Future<void> _loadLogs() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentPage = 0;
        _hasMore = true;
      });

      Logger.info('Loading face recognition logs...');
      final logs = await _logService.getLogs(
        limit: _pageSize,
        filterByType: _selectedFilter,
      );

      setState(() {
        _logs = logs;
        _isLoading = false;
        _hasMore = logs.length >= _pageSize;
      });

      Logger.info('Loaded ${logs.length} logs');
    } catch (e) {
      Logger.error('Failed to load logs', error: e);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load logs: ${e.toString()}';
      });
    }
  }

  Future<void> _loadMoreLogs() async {
    if (_isLoadingMore || !_hasMore) return;

    try {
      setState(() {
        _isLoadingMore = true;
      });

      final moreLogs = await _logService.getLogs(
        limit: _pageSize,
        filterByType: _selectedFilter,
        // Offset would need to be implemented in the service
        // For now, we'll just refresh all logs when filtering
      );

      // Simple implementation: just avoid duplicates
      final newLogs = <FaceRecognitionLogModel>[];
      for (final log in moreLogs) {
        if (!_logs.any((existingLog) => existingLog.id == log.id)) {
          newLogs.add(log);
        }
      }

      setState(() {
        _logs.addAll(newLogs);
        _isLoadingMore = false;
        _hasMore = newLogs.length >= _pageSize;
        _currentPage++;
      });
    } catch (e) {
      Logger.error('Failed to load more logs', error: e);
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshLogs() async {
    await _loadLogs();
  }

  void _onFilterChanged(FaceRecognitionResultType? filter) {
    if (_selectedFilter != filter) {
      setState(() {
        _selectedFilter = filter;
      });
      _loadLogs();
    }
  }

  void _onLogTapped(FaceRecognitionLogModel log) {
    if (log.hasImage || log.hasThumbnail) {
      LogImageViewerDialog.show(
        context: context,
        log: log,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No image available for this log entry'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAllLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs'),
        content: const Text(
          'Are you sure you want to delete all log entries? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _logService.clearAllLogs();
        await _loadLogs();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All logs cleared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        Logger.error('Failed to clear logs', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear logs: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Face Recognition Logs'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _refreshLogs();
                  break;
                case 'clear':
                  _clearAllLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 12),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Clear All', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(),

          // Logs list
          Expanded(
            child: _buildLogsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 60.h,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        children: [
          _buildFilterChip('All', null),
          SizedBox(width: 8.w),
          _buildFilterChip('Matched', FaceRecognitionResultType.matched),
          SizedBox(width: 8.w),
          _buildFilterChip('Unknown', FaceRecognitionResultType.unknown),
          SizedBox(width: 8.w),
          _buildFilterChip('No Face', FaceRecognitionResultType.noFace),
          SizedBox(width: 8.w),
          _buildFilterChip('Poor Quality', FaceRecognitionResultType.poorQuality),
          SizedBox(width: 8.w),
          _buildFilterChip('Error', FaceRecognitionResultType.error),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, FaceRecognitionResultType? type) {
    final isSelected = _selectedFilter == type;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[700],
          fontSize: 12.sp,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => _onFilterChanged(type),
      backgroundColor: Colors.grey[200],
      selectedColor: Theme.of(context).primaryColor,
      checkmarkColor: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildLogsList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.sp,
              color: Colors.red[300],
            ),
            SizedBox(height: 16.h),
            Text(
              'Error Loading Logs',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                ),
              ),
            ),
            SizedBox(height: 24.h),
            ElevatedButton(
              onPressed: _refreshLogs,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.face_outlined,
              size: 64.sp,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16.h),
            Text(
              'No Logs Found',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _selectedFilter == null
                  ? 'Face recognition logs will appear here'
                  : 'No logs match the selected filter',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24.h),
            ElevatedButton(
              onPressed: _refreshLogs,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshLogs,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(16.w),
        itemCount: _logs.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _logs.length) {
            // Loading indicator at bottom
            return Container(
              padding: EdgeInsets.all(16.h),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            );
          }

          final log = _logs[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: LogCard(
              log: log,
              onTap: () => _onLogTapped(log),
            ),
          );
        },
      ),
    );
  }
}