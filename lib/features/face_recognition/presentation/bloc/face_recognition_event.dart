import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';

import '../../../employee/domain/entities/employee.dart';
import '../../../face_detection/domain/entities/face_detection_result.dart';
import '../../data/services/face_match_scorer.dart';

abstract class FaceRecognitionEvent extends Equatable {
  const FaceRecognitionEvent();

  @override
  List<Object?> get props => [];
}

class InitializeFaceRecognition extends FaceRecognitionEvent {
  const InitializeFaceRecognition();
}

class StartRecognition extends FaceRecognitionEvent {
  const StartRecognition();
}

class StopRecognition extends FaceRecognitionEvent {
  const StopRecognition();
}

class ProcessCameraFrame extends FaceRecognitionEvent {
  final CameraImage cameraImage;

  const ProcessCameraFrame(this.cameraImage);

  @override
  List<Object> get props => [cameraImage];
}

/// Event for recognizing face with top-K matching
class RecognizeFaceWithTopK extends FaceRecognitionEvent {
  final Uint8List imageData;
  final FaceDetectionResult faceDetection;
  final int topK;
  final bool requireLiveness;
  final double? customThreshold;
  final bool useAdaptiveThreshold;
  final double? lightingQuality;
  final bool isIndoor;

  const RecognizeFaceWithTopK({
    required this.imageData,
    required this.faceDetection,
    this.topK = 3,
    this.requireLiveness = false,
    this.customThreshold,
    this.useAdaptiveThreshold = false,
    this.lightingQuality,
    this.isIndoor = true,
  });

  @override
  List<Object?> get props => [
        imageData,
        faceDetection,
        topK,
        requireLiveness,
        customThreshold,
        useAdaptiveThreshold,
        lightingQuality,
        isIndoor,
      ];
}

/// Event for selecting a match from top-K results
class SelectMatchFromTopK extends FaceRecognitionEvent {
  final FaceMatchResult selectedMatch;
  final List<FaceMatchResult> allMatches;

  const SelectMatchFromTopK({
    required this.selectedMatch,
    required this.allMatches,
  });

  @override
  List<Object?> get props => [selectedMatch, allMatches];
}

/// Event for clearing recognition history
class ClearRecognitionHistory extends FaceRecognitionEvent {
  const ClearRecognitionHistory();
}

class AddEmployee extends FaceRecognitionEvent {
  final Employee employee;

  const AddEmployee(this.employee);

  @override
  List<Object> get props => [employee];
}

class RemoveEmployee extends FaceRecognitionEvent {
  final String employeeId;

  const RemoveEmployee(this.employeeId);

  @override
  List<Object> get props => [employeeId];
}

class LoadEmployees extends FaceRecognitionEvent {
  const LoadEmployees();
}

class ConfirmRecognition extends FaceRecognitionEvent {
  final String employeeId;
  final RecognitionAction action;

  const ConfirmRecognition({
    required this.employeeId,
    required this.action,
  });

  @override
  List<Object> get props => [employeeId, action];
}

class ResetRecognition extends FaceRecognitionEvent {
  const ResetRecognition();
}

enum RecognitionAction {
  clockIn,
  clockOut,
  verify,
}