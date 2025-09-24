import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import '../utils/logger.dart';

/// Service for managing platform-specific rendering capabilities
/// Handles SELinux detection and render mode configuration
@singleton
class RenderService {
  static const MethodChannel _channel = MethodChannel('com.ante.facial_recognition/render');

  bool _hasSeLinuxRestrictions = false;
  String _renderMode = 'hardware';
  Map<String, dynamic> _deviceInfo = {};
  bool _isInitialized = false;

  /// Whether the device has SELinux restrictions that affect GPU rendering
  bool get hasSeLinuxRestrictions => _hasSeLinuxRestrictions;

  /// Current rendering mode (hardware/software)
  String get renderMode => _renderMode;

  /// Comprehensive device rendering information
  Map<String, dynamic> get deviceInfo => _deviceInfo;

  /// Whether the service has been initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the render service and detect platform capabilities
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.warning('RenderService already initialized');
      return;
    }

    try {
      Logger.info('Initializing RenderService...');

      // Get SELinux restriction status
      _hasSeLinuxRestrictions = await _channel.invokeMethod('hasSeLinuxRestrictions') ?? false;

      // Get recommended render mode
      _renderMode = await _channel.invokeMethod('getRenderMode') ?? 'hardware';

      // Get comprehensive device information
      final deviceInfoResult = await _channel.invokeMethod('getDeviceInfo');
      _deviceInfo = Map<String, dynamic>.from(deviceInfoResult ?? {});

      _isInitialized = true;

      // Log initialization results
      _logRenderConfiguration();

    } catch (e) {
      Logger.error('Failed to initialize RenderService', error: e);
      // Fallback to safe defaults
      _hasSeLinuxRestrictions = false;
      _renderMode = 'hardware';
      _deviceInfo = {'error': 'Failed to detect device capabilities'};
      _isInitialized = true;
    }
  }

  /// Log the current render configuration for debugging
  void _logRenderConfiguration() {
    if (_hasSeLinuxRestrictions) {
      Logger.warning('SELinux GPU restrictions detected');
      Logger.info('Device will use software rendering fallback');
      Logger.info('This is normal on devices with strict security policies');
      Logger.info('App functionality is preserved, performance may be reduced');
    } else {
      Logger.success('No SELinux restrictions detected');
      Logger.info('Device will use hardware-accelerated rendering');
    }

    Logger.info('Render mode: $_renderMode');
    Logger.debug('Device info: $_deviceInfo');
  }

  /// Get a user-friendly explanation of the current render configuration
  String getRenderExplanation() {
    if (!_isInitialized) {
      return 'Render service not initialized';
    }

    if (_hasSeLinuxRestrictions) {
      return 'Your device has security policies that limit GPU access. '
             'The app will use software rendering instead, which maintains '
             'full functionality but may be slightly slower.';
    } else {
      return 'Your device supports hardware-accelerated rendering for '
             'optimal performance.';
    }
  }

  /// Get render performance recommendations for the user
  List<String> getPerformanceRecommendations() {
    if (!_isInitialized) {
      return ['Initialize render service first'];
    }

    final recommendations = <String>[];

    if (_hasSeLinuxRestrictions) {
      recommendations.addAll([
        'Device uses software rendering due to security policies',
        'Close background apps to improve performance',
        'Ensure sufficient battery level during face recognition',
        'Consider using the app in well-lit environments for faster processing',
      ]);
    } else {
      recommendations.addAll([
        'Device supports hardware acceleration',
        'GPU-accelerated face recognition available',
        'Optimal performance configuration detected',
      ]);
    }

    return recommendations;
  }

  /// Check if the device should show SELinux-related user information
  bool shouldShowSeLinuxInfo() {
    return _isInitialized && _hasSeLinuxRestrictions;
  }

  /// Get the SELinux status string
  String getSeLinuxStatus() {
    final status = _deviceInfo['selinuxStatus'] as String? ?? 'Unknown';
    return status;
  }

  /// Get device model information
  String getDeviceModel() {
    final model = _deviceInfo['deviceModel'] as String? ?? 'Unknown';
    final manufacturer = _deviceInfo['manufacturer'] as String? ?? '';
    return manufacturer.isNotEmpty ? '$manufacturer $model' : model;
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    Logger.debug('RenderService disposed');
  }
}