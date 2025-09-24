import 'package:flutter/material.dart';

import '../di/injection.dart';
import 'render_service.dart';

/// A widget that adapts its behavior based on device rendering capabilities
/// Provides different experiences for devices with SELinux GPU restrictions
class RenderAwareWidget extends StatefulWidget {
  final Widget child;
  final Widget? seLinuxFallback;
  final bool showSeLinuxInfo;

  const RenderAwareWidget({
    super.key,
    required this.child,
    this.seLinuxFallback,
    this.showSeLinuxInfo = false,
  });

  @override
  State<RenderAwareWidget> createState() => _RenderAwareWidgetState();
}

class _RenderAwareWidgetState extends State<RenderAwareWidget> {
  late final RenderService _renderService;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _renderService = getIt<RenderService>();
    _initializeRenderService();
  }

  Future<void> _initializeRenderService() async {
    if (!_renderService.isInitialized) {
      await _renderService.initialize();
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Show SELinux information banner if requested and applicable
        if (widget.showSeLinuxInfo && _renderService.shouldShowSeLinuxInfo())
          _buildSeLinuxInfoBanner(),

        // Main content
        Expanded(
          child: _renderService.hasSeLinuxRestrictions && widget.seLinuxFallback != null
              ? widget.seLinuxFallback!
              : widget.child,
        ),
      ],
    );
  }

  Widget _buildSeLinuxInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(
            color: Colors.blue.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _renderService.getRenderExplanation(),
              style: TextStyle(
                color: Colors.blue.shade800,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: _showDetailedInfo,
            child: Text(
              'Details',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailedInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rendering Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Device', _renderService.getDeviceModel()),
            _buildInfoRow('SELinux Status', _renderService.getSeLinuxStatus()),
            _buildInfoRow('Render Mode', _renderService.renderMode),
            const SizedBox(height: 16),
            const Text(
              'Performance Recommendations:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._renderService.getPerformanceRecommendations().map(
              (recommendation) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(recommendation)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// A convenience widget for showing render-aware notifications
class RenderAwareNotification extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const RenderAwareNotification({
    super.key,
    required this.message,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final renderService = getIt<RenderService>();

    if (!renderService.shouldShowSeLinuxInfo()) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.security,
            color: Colors.amber.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Security-Enhanced Device',
                  style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.amber.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                color: Colors.amber.shade700,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}