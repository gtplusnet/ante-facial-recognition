import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

import '../utils/logger.dart';

@singleton
class FeedbackService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSoundEnabled = true;
  bool _isVibrationEnabled = true;

  // Sound file paths (will add these to assets later)
  static const String _successSound = 'sounds/success.mp3';
  static const String _errorSound = 'sounds/error.mp3';
  static const String _warningSound = 'sounds/warning.mp3';

  /// Initialize the feedback service
  Future<void> initialize() async {
    try {
      // Check if device supports vibration
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      _isVibrationEnabled = hasVibrator;

      // Set audio mode for better performance
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);

      Logger.info('FeedbackService initialized - Vibration: $_isVibrationEnabled');
    } catch (e) {
      Logger.error('Failed to initialize FeedbackService', error: e);
    }
  }

  /// Play success feedback (recognized face)
  Future<void> playSuccessFeedback() async {
    try {
      // Haptic feedback - light
      if (_isVibrationEnabled) {
        HapticFeedback.lightImpact();
      }

      // Play success sound
      if (_isSoundEnabled) {
        await _playSound(_successSound);
      }
    } catch (e) {
      Logger.error('Failed to play success feedback', error: e);
    }
  }

  /// Play error feedback (unrecognized face)
  Future<void> playErrorFeedback() async {
    try {
      // Haptic feedback - medium impact and vibration pattern
      if (_isVibrationEnabled) {
        HapticFeedback.mediumImpact();
        // Double vibration for error
        await Vibration.vibrate(duration: 100);
        await Future.delayed(const Duration(milliseconds: 100));
        await Vibration.vibrate(duration: 100);
      }

      // Play error sound
      if (_isSoundEnabled) {
        await _playSound(_errorSound);
      }
    } catch (e) {
      Logger.error('Failed to play error feedback', error: e);
    }
  }

  /// Play warning feedback (poor quality face)
  Future<void> playWarningFeedback() async {
    try {
      // Haptic feedback - selection
      if (_isVibrationEnabled) {
        HapticFeedback.selectionClick();
      }

      // Play warning sound
      if (_isSoundEnabled) {
        await _playSound(_warningSound);
      }
    } catch (e) {
      Logger.error('Failed to play warning feedback', error: e);
    }
  }

  /// Play scanning feedback (face detected)
  Future<void> playScanningFeedback() async {
    try {
      // Light haptic feedback
      if (_isVibrationEnabled) {
        HapticFeedback.selectionClick();
      }
    } catch (e) {
      Logger.error('Failed to play scanning feedback', error: e);
    }
  }

  /// Play a specific sound
  Future<void> _playSound(String soundPath) async {
    try {
      await _audioPlayer.play(AssetSource(soundPath));
    } catch (e) {
      Logger.warning('Could not play sound: $soundPath - Error: $e');
      // Don't throw - just log, as sound is not critical
    }
  }

  /// Simple vibration pattern
  Future<void> vibrate({int duration = 50}) async {
    if (_isVibrationEnabled) {
      await Vibration.vibrate(duration: duration);
    }
  }

  /// Pattern vibration (for special feedback)
  Future<void> vibratePattern(List<int> pattern) async {
    if (_isVibrationEnabled) {
      await Vibration.vibrate(pattern: pattern);
    }
  }

  /// Enable/disable sound
  void setSoundEnabled(bool enabled) {
    _isSoundEnabled = enabled;
    Logger.info('Sound feedback ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Enable/disable vibration
  void setVibrationEnabled(bool enabled) {
    _isVibrationEnabled = enabled;
    Logger.info('Vibration feedback ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Check if sound is enabled
  bool get isSoundEnabled => _isSoundEnabled;

  /// Check if vibration is enabled
  bool get isVibrationEnabled => _isVibrationEnabled;

  /// Dispose resources
  void dispose() {
    _audioPlayer.dispose();
  }
}