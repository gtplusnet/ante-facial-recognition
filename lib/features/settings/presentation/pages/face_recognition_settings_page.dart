import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/config/face_recognition_config.dart';
import '../../../../core/utils/logger.dart';

class FaceRecognitionSettingsPage extends StatefulWidget {
  const FaceRecognitionSettingsPage({super.key});

  @override
  State<FaceRecognitionSettingsPage> createState() =>
      _FaceRecognitionSettingsPageState();
}

class _FaceRecognitionSettingsPageState
    extends State<FaceRecognitionSettingsPage> {
  final FaceRecognitionConfig _config = FaceRecognitionConfig();

  double _qualityThreshold = 0.8;
  double _faceMatchDistance = 1.0;
  int _processingIntervalMs = 800;
  int _frameSkipCount = 5;
  bool _enableAutoDialogDismiss = true;
  int _autoDialogDismissSeconds = 5;

  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    try {
      await _config.loadFromStorage();

      setState(() {
        _qualityThreshold = _config.qualityThreshold;
        _faceMatchDistance = _config.faceMatchDistance;
        _processingIntervalMs = _config.processingIntervalMs;
        _frameSkipCount = _config.frameSkipCount;
        _enableAutoDialogDismiss = _config.enableAutoDialogDismiss;
        _autoDialogDismissSeconds = _config.autoDialogDismissSeconds;
        _isLoading = false;
      });

      Logger.info('Face recognition settings loaded');
    } catch (e) {
      Logger.error('Failed to load settings', error: e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    try {
      _config.updateConfig(
        qualityThreshold: _qualityThreshold,
        faceMatchDistance: _faceMatchDistance,
        processingIntervalMs: _processingIntervalMs,
        frameSkipCount: _frameSkipCount,
        enableAutoDialogDismiss: _enableAutoDialogDismiss,
        autoDialogDismissSeconds: _autoDialogDismissSeconds,
      );

      await _config.saveToStorage();

      setState(() => _hasChanges = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Logger.info('Face recognition settings saved');
    } catch (e) {
      Logger.error('Failed to save settings', error: e);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all face recognition settings to their default values. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      _config.resetToDefaults();
      await _config.saveToStorage();

      setState(() {
        _qualityThreshold = _config.qualityThreshold;
        _faceMatchDistance = _config.faceMatchDistance;
        _processingIntervalMs = _config.processingIntervalMs;
        _frameSkipCount = _config.frameSkipCount;
        _enableAutoDialogDismiss = _config.enableAutoDialogDismiss;
        _autoDialogDismissSeconds = _config.autoDialogDismissSeconds;
        _hasChanges = false;
        _isLoading = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings reset to defaults'),
          backgroundColor: Colors.green,
        ),
      );

      Logger.info('Face recognition settings reset to defaults');
    } catch (e) {
      Logger.error('Failed to reset settings', error: e);
      setState(() => _isLoading = false);
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Recognition Settings'),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveConfig,
              tooltip: 'Save Changes',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                _buildInfoCard(theme),
                SizedBox(height: 24.h),

                _buildSectionHeader('Recognition Thresholds', theme),
                SizedBox(height: 16.h),

                _buildQualityThresholdSlider(theme),
                SizedBox(height: 24.h),

                _buildMatchDistanceSlider(theme),
                SizedBox(height: 32.h),

                _buildSectionHeader('Performance Settings', theme),
                SizedBox(height: 16.h),

                _buildProcessingIntervalSlider(theme),
                SizedBox(height: 24.h),

                _buildFrameSkipSlider(theme),
                SizedBox(height: 32.h),

                _buildSectionHeader('UI Feedback', theme),
                SizedBox(height: 16.h),

                _buildAutoDialogDismissToggle(theme),
                if (_enableAutoDialogDismiss) ...[
                  SizedBox(height: 16.h),
                  _buildAutoDialogDismissSlider(theme),
                ],
                SizedBox(height: 32.h),

                _buildActionButtons(theme),
                SizedBox(height: 16.h),
              ],
            ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: theme.colorScheme.primary,
            size: 24.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Adjust these settings to optimize face recognition for your environment and camera setup.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildQualityThresholdSlider(ThemeData theme) {
    return _buildSliderCard(
      theme: theme,
      title: 'Face Quality Threshold',
      description:
          'Minimum face quality required for recognition. Higher values require better quality faces.',
      value: _qualityThreshold,
      min: 0.0,
      max: 1.0,
      divisions: 20,
      valueLabel: '${(_qualityThreshold * 100).toInt()}%',
      onChanged: (value) {
        setState(() => _qualityThreshold = value);
        _markChanged();
      },
      infoText: _getQualityThresholdInfo(_qualityThreshold),
    );
  }

  Widget _buildMatchDistanceSlider(ThemeData theme) {
    return _buildSliderCard(
      theme: theme,
      title: 'Match Distance Threshold',
      description:
          'Maximum Euclidean distance for face matching. Lower values require closer matches (more strict).',
      value: _faceMatchDistance,
      min: 0.5,
      max: 2.0,
      divisions: 30,
      valueLabel: _faceMatchDistance.toStringAsFixed(2),
      onChanged: (value) {
        setState(() => _faceMatchDistance = value);
        _markChanged();
      },
      infoText: _getMatchDistanceInfo(_faceMatchDistance),
    );
  }

  Widget _buildProcessingIntervalSlider(ThemeData theme) {
    return _buildSliderCard(
      theme: theme,
      title: 'Processing Interval',
      description:
          'Time between processing camera frames. Lower values process more frequently (higher CPU usage).',
      value: _processingIntervalMs.toDouble(),
      min: 1000,
      max: 5000,
      divisions: 40,
      valueLabel: '${_processingIntervalMs}ms',
      onChanged: (value) {
        setState(() => _processingIntervalMs = value.round());
        _markChanged();
      },
      infoText: _getProcessingIntervalInfo(_processingIntervalMs),
    );
  }

  Widget _buildFrameSkipSlider(ThemeData theme) {
    return _buildSliderCard(
      theme: theme,
      title: 'Frame Skip Count',
      description:
          'Number of camera frames to skip between processing. Higher values reduce CPU usage but may miss faces.',
      value: _frameSkipCount.toDouble(),
      min: 1,
      max: 10,
      divisions: 9,
      valueLabel: '$_frameSkipCount frames',
      onChanged: (value) {
        setState(() => _frameSkipCount = value.round());
        _markChanged();
      },
      infoText: _getFrameSkipInfo(_frameSkipCount),
    );
  }

  Widget _buildAutoDialogDismissToggle(ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Dismiss Dialogs',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Automatically close recognition result dialogs',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enableAutoDialogDismiss,
            onChanged: (value) {
              setState(() => _enableAutoDialogDismiss = value);
              _markChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAutoDialogDismissSlider(ThemeData theme) {
    return _buildSliderCard(
      theme: theme,
      title: 'Auto-Dismiss Duration',
      description:
          'Time before recognition dialogs automatically close. Longer durations give more time to read the message.',
      value: _autoDialogDismissSeconds.toDouble(),
      min: 3,
      max: 20,
      divisions: 17,
      valueLabel: '${_autoDialogDismissSeconds}s',
      onChanged: (value) {
        setState(() => _autoDialogDismissSeconds = value.round());
        _markChanged();
      },
      infoText: _getAutoDialogDismissInfo(_autoDialogDismissSeconds),
    );
  }

  Widget _buildSliderCard({
    required ThemeData theme,
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
    String? infoText,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  valueLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 12.h),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              showValueIndicator: ShowValueIndicator.always,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          if (infoText != null) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: _getInfoColor(infoText, theme).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(
                    _getInfoIcon(infoText),
                    size: 16.sp,
                    color: _getInfoColor(infoText, theme),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      infoText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _getInfoColor(infoText, theme),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Column(
      children: [
        if (_hasChanges)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.h),
              ),
            ),
          ),
        if (_hasChanges) SizedBox(height: 12.h),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16.h),
            ),
          ),
        ),
      ],
    );
  }

  String _getQualityThresholdInfo(double value) {
    if (value < 0.6) {
      return '⚠️ Very Low - May accept poor quality images';
    } else if (value < 0.8) {
      return 'ℹ️ Moderate - Balanced quality acceptance';
    } else if (value <= 0.9) {
      return '✓ Good - Recommended for most setups';
    } else {
      return '⚠️ Very High - May reject valid faces';
    }
  }

  String _getMatchDistanceInfo(double value) {
    if (value < 0.8) {
      return '⚠️ Very Strict - May reject valid matches';
    } else if (value < 1.2) {
      return '✓ Recommended - Balanced accuracy';
    } else if (value < 1.5) {
      return 'ℹ️ Lenient - More accepting of variations';
    } else {
      return '⚠️ Very Lenient - May accept false matches';
    }
  }

  String _getProcessingIntervalInfo(int value) {
    if (value < 1500) {
      return '⚠️ Higher CPU Usage - Faster recognition';
    } else if (value <= 3000) {
      return '✓ Balanced - Good performance and battery';
    } else {
      return 'ℹ️ Low CPU Usage - Battery friendly';
    }
  }

  String _getFrameSkipInfo(int value) {
    if (value <= 2) {
      return '⚠️ High CPU Usage - Processes most frames';
    } else if (value <= 6) {
      return '✓ Balanced - Good performance';
    } else {
      return 'ℹ️ Low CPU Usage - May miss quick movements';
    }
  }

  String _getAutoDialogDismissInfo(int value) {
    if (value <= 5) {
      return '⚡ Fast - Quick workflow';
    } else if (value <= 10) {
      return '✓ Balanced - Good readability';
    } else {
      return 'ℹ️ Slow - More time to read';
    }
  }

  IconData _getInfoIcon(String infoText) {
    if (infoText.startsWith('⚠️')) {
      return Icons.warning_amber;
    } else if (infoText.startsWith('✓')) {
      return Icons.check_circle;
    } else {
      return Icons.info;
    }
  }

  Color _getInfoColor(String infoText, ThemeData theme) {
    if (infoText.startsWith('⚠️')) {
      return Colors.orange;
    } else if (infoText.startsWith('✓')) {
      return Colors.green;
    } else {
      return theme.colorScheme.primary;
    }
  }
}