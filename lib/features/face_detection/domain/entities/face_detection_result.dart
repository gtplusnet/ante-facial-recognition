import 'dart:ui' as ui;

import 'package:equatable/equatable.dart';

import '../../../../core/config/face_quality_config.dart';

class FaceDetectionResult extends Equatable {
  final String? id;
  final FaceBounds bounds;
  final double? rotationX;
  final double? rotationY;
  final double? rotationZ;
  final Map<FaceLandmarkType, FaceLandmark> landmarks;
  final Map<FaceContourType, List<FacePoint>> contours;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final int? trackingId;
  final double? lightingQuality;
  final DateTime timestamp;

  FaceDetectionResult({
    this.id,
    required this.bounds,
    this.rotationX,
    this.rotationY,
    this.rotationZ,
    this.landmarks = const {},
    this.contours = const {},
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.trackingId,
    this.lightingQuality,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  double get qualityScore {
    double score = 1.0;

    // Apply angle-based scoring using configuration
    if (rotationX != null) {
      score *= FaceQualityConfig.calculateAngleScoreFactor(rotationX!);
    }
    if (rotationY != null) {
      score *= FaceQualityConfig.calculateAngleScoreFactor(rotationY!);
    }
    if (rotationZ != null) {
      score *= FaceQualityConfig.calculateAngleScoreFactor(rotationZ!);
    }

    // Apply eye closed penalties using configuration
    if (FaceQualityConfig.isEyeClosed(leftEyeOpenProbability)) {
      score = FaceQualityConfig.applyEyeClosedPenalty(score);
    }
    if (FaceQualityConfig.isEyeClosed(rightEyeOpenProbability)) {
      score = FaceQualityConfig.applyEyeClosedPenalty(score);
    }

    return score;
  }

  bool get isGoodQuality => qualityScore >= FaceQualityConfig.minQualityThreshold;

  @override
  List<Object?> get props => [
        id,
        bounds,
        rotationX,
        rotationY,
        rotationZ,
        landmarks,
        contours,
        smilingProbability,
        leftEyeOpenProbability,
        rightEyeOpenProbability,
        trackingId,
        lightingQuality,
        timestamp,
      ];
}

class FaceBounds extends Equatable {
  final double left;
  final double top;
  final double width;
  final double height;

  const FaceBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory FaceBounds.fromRect(ui.Rect rect) {
    return FaceBounds(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  @override
  List<Object> get props => [left, top, width, height];
}

class FaceLandmark extends Equatable {
  final FaceLandmarkType type;
  final double x;
  final double y;

  const FaceLandmark({
    required this.type,
    required this.x,
    required this.y,
  });

  @override
  List<Object> get props => [type, x, y];
}

class FacePoint extends Equatable {
  final double x;
  final double y;

  const FacePoint({
    required this.x,
    required this.y,
  });

  @override
  List<Object> get props => [x, y];
}

enum FaceLandmarkType {
  leftEye,
  rightEye,
  leftEar,
  rightEar,
  leftCheek,
  rightCheek,
  noseBase,
  mouthLeft,
  mouthRight,
  mouthBottom,
}

enum FaceContourType {
  face,
  leftEyebrowTop,
  leftEyebrowBottom,
  rightEyebrowTop,
  rightEyebrowBottom,
  leftEye,
  rightEye,
  upperLipTop,
  upperLipBottom,
  lowerLipTop,
  lowerLipBottom,
  noseBridge,
  noseBottom,
  leftCheek,
  rightCheek,
}