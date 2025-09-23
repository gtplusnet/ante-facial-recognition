import 'package:equatable/equatable.dart';

import '../../../employee/domain/entities/employee.dart';
import '../../data/services/face_match_scorer.dart';
import 'face_recognition_event.dart';

abstract class FaceRecognitionState extends Equatable {
  const FaceRecognitionState();

  @override
  List<Object?> get props => [];
}

class FaceRecognitionInitial extends FaceRecognitionState {
  const FaceRecognitionInitial();
}

class FaceRecognitionLoading extends FaceRecognitionState {
  const FaceRecognitionLoading();
}

class FaceRecognitionReady extends FaceRecognitionState {
  final int employeeCount;

  const FaceRecognitionReady({
    required this.employeeCount,
  });

  @override
  List<Object> get props => [employeeCount];
}

class FaceRecognitionScanning extends FaceRecognitionState {
  const FaceRecognitionScanning();
}

class FaceRecognitionNoFace extends FaceRecognitionState {
  const FaceRecognitionNoFace();
}

class FaceRecognitionPoorQuality extends FaceRecognitionState {
  final double quality;
  final String message;

  const FaceRecognitionPoorQuality({
    required this.quality,
    required this.message,
  });

  @override
  List<Object> get props => [quality, message];
}

class FaceRecognitionMatched extends FaceRecognitionState {
  final Employee employee;
  final double confidence;
  final double distance;

  const FaceRecognitionMatched({
    required this.employee,
    required this.confidence,
    required this.distance,
  });

  bool get isHighConfidence => confidence > 0.85;
  bool get isMediumConfidence => confidence >= 0.7 && confidence <= 0.85;
  bool get isLowConfidence => confidence < 0.7;

  @override
  List<Object> get props => [employee, confidence, distance];
}

/// State for multiple match results (top-K matching)
class FaceRecognitionMultipleMatches extends FaceRecognitionState {
  final List<FaceMatchResult> topMatches;
  final FaceMatchResult bestMatch;
  final double overallConfidence;
  final Map<String, dynamic>? metadata;

  const FaceRecognitionMultipleMatches({
    required this.topMatches,
    required this.bestMatch,
    required this.overallConfidence,
    this.metadata,
  });

  bool get hasHighConfidenceMatch => bestMatch.combinedConfidence >= 0.85;
  bool get hasMultipleCandidates => topMatches.length > 1;

  @override
  List<Object?> get props => [topMatches, bestMatch, overallConfidence, metadata];
}

/// State when no matches found
class FaceRecognitionNoMatches extends FaceRecognitionState {
  final String message;
  final List<FaceMatchResult> attemptedMatches;
  final Map<String, dynamic>? metadata;

  const FaceRecognitionNoMatches({
    required this.message,
    this.attemptedMatches = const [],
    this.metadata,
  });

  @override
  List<Object?> get props => [message, attemptedMatches, metadata];
}

/// State when a match is selected from top-K results
class FaceRecognitionMatchSelected extends FaceRecognitionState {
  final FaceMatchResult selectedMatch;
  final List<FaceMatchResult> allMatches;

  const FaceRecognitionMatchSelected({
    required this.selectedMatch,
    required this.allMatches,
  });

  @override
  List<Object?> get props => [selectedMatch, allMatches];
}

/// State for processing/loading
class FaceRecognitionProcessing extends FaceRecognitionState {
  const FaceRecognitionProcessing();
}

class FaceRecognitionUnknown extends FaceRecognitionState {
  const FaceRecognitionUnknown();
}

class FaceRecognitionConfirmed extends FaceRecognitionState {
  final Employee employee;
  final RecognitionAction action;

  const FaceRecognitionConfirmed({
    required this.employee,
    required this.action,
  });

  String get actionMessage {
    switch (action) {
      case RecognitionAction.clockIn:
        return '${employee.name} clocked in successfully';
      case RecognitionAction.clockOut:
        return '${employee.name} clocked out successfully';
      case RecognitionAction.verify:
        return '${employee.name} verified successfully';
    }
  }

  @override
  List<Object> get props => [employee, action];
}

class FaceRecognitionError extends FaceRecognitionState {
  final String message;

  const FaceRecognitionError(this.message);

  @override
  List<Object> get props => [message];
}