import 'package:equatable/equatable.dart';

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

    // Very lenient quality scoring - allow almost any face angle
    // Allow angles up to 90 degrees with minimal penalty
    if (rotationX != null) {
      final xScore = 1.0 - (rotationX!.abs() / 90.0).clamp(0.0, 1.0);
      score *= (xScore * 0.5 + 0.5); // Minimum score of 0.5 even at max angle
    }
    if (rotationY != null) {
      final yScore = 1.0 - (rotationY!.abs() / 90.0).clamp(0.0, 1.0);
      score *= (yScore * 0.5 + 0.5); // Minimum score of 0.5 even at max angle
    }
    if (rotationZ != null) {
      final zScore = 1.0 - (rotationZ!.abs() / 90.0).clamp(0.0, 1.0);
      score *= (zScore * 0.5 + 0.5); // Minimum score of 0.5 even at max angle
    }

    // Eyes open check is optional - minimal penalty
    if (leftEyeOpenProbability != null && leftEyeOpenProbability! < 0.2) {
      score *= 0.9; // Very minimal penalty for closed eyes
    }
    if (rightEyeOpenProbability != null && rightEyeOpenProbability! < 0.2) {
      score *= 0.9; // Very minimal penalty for closed eyes
    }

    return score;
  }

  bool get isGoodQuality => qualityScore >= 0.3;

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