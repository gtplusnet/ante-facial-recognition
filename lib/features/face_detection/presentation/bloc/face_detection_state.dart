import 'package:equatable/equatable.dart';

import '../../domain/entities/face_detection_result.dart';

abstract class FaceDetectionState extends Equatable {
  const FaceDetectionState();

  @override
  List<Object?> get props => [];
}

class FaceDetectionInitial extends FaceDetectionState {
  const FaceDetectionInitial();
}

class FaceDetectionLoading extends FaceDetectionState {
  const FaceDetectionLoading();
}

class FaceDetectionReady extends FaceDetectionState {
  const FaceDetectionReady();
}

class FaceDetected extends FaceDetectionState {
  final FaceDetectionResult face;
  final ImageSize imageSize;

  const FaceDetected({
    required this.face,
    required this.imageSize,
  });

  @override
  List<Object> get props => [face, imageSize];
}

class FaceDetectionNoFace extends FaceDetectionState {
  const FaceDetectionNoFace();
}

class FaceDetectionMultipleFaces extends FaceDetectionState {
  final int count;

  const FaceDetectionMultipleFaces({required this.count});

  @override
  List<Object> get props => [count];
}

class FaceDetectionLowQuality extends FaceDetectionState {
  final FaceDetectionResult face;
  final double qualityScore;

  const FaceDetectionLowQuality({
    required this.face,
    required this.qualityScore,
  });

  @override
  List<Object> get props => [face, qualityScore];
}

class FaceDetectionError extends FaceDetectionState {
  final String message;

  const FaceDetectionError(this.message);

  @override
  List<Object> get props => [message];
}

class FaceDetectionStopped extends FaceDetectionState {
  const FaceDetectionStopped();
}

class ImageSize {
  final double width;
  final double height;

  const ImageSize(this.width, this.height);
}