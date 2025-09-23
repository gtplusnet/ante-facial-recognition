import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';

abstract class FaceDetectionEvent extends Equatable {
  const FaceDetectionEvent();

  @override
  List<Object?> get props => [];
}

class StartFaceDetection extends FaceDetectionEvent {
  const StartFaceDetection();
}

class StopFaceDetection extends FaceDetectionEvent {
  const StopFaceDetection();
}

class ProcessCameraImage extends FaceDetectionEvent {
  final CameraImage image;

  const ProcessCameraImage(this.image);

  @override
  List<Object> get props => [image];
}

class ResetFaceDetection extends FaceDetectionEvent {
  const ResetFaceDetection();
}