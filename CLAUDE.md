# ANTE Facial Recognition - Claude Quick Reference

## CRITICAL: Session Start Protocol
1. ALWAYS read PLANNING.md first - Contains vision, architecture, and technology stack
2. Check TASK.md - Review current tasks before starting work.
3. Mark tasks immediately - Update TASK.md as soon as tasks are completed
4. Add discovered tasks - Document new requirements found during development
5. Update PLANNING.md continuously - Improve and refine the plan as you encounter new issues, realize better approaches, or discover requirements during development
6. Always use SOLID principle when developing.

## 🎯 Quick Context
Android face recognition app for employee time tracking using Flutter. All processing on-device for privacy and speed.

**Key Specs**: 99.8% accuracy | <100ms recognition | Fully offline capable | <50MB APK

## 📁 Key File Locations
```
/PRD.md                    # Full requirements document
/PLANNING.md              # Architecture & tech stack details
/INSTRUCTION.md           # Original project brief
/lib/core/ml/             # Face recognition logic
/android/app/src/main/    # Platform channels
/assets/models/           # ML model files (.tflite)
```

## 🔌 API Quick Reference

### Base URL
`http://100.109.133.12:3000/api/public/manpower`

### Essential Endpoints
```dart
GET  /health                     # Device connectivity check
GET  /employees?withPhotos=true  # Employee list with photos
POST /time-in                    # Clock in (body: {employeeId})
POST /time-out                   # Clock out (body: {timeRecordId})
GET  /employee-status            # Check if clocked in/out
GET  /daily-logs                 # Attendance records
```

### Headers
```dart
headers: {
  'x-api-key': deviceApiKey,
  'Content-Type': 'application/json',
}
```

## 💡 Critical Code Patterns

### BLoC Event Handling
```dart
class FaceRecognitionBloc extends Bloc<FaceEvent, FaceState> {
  FaceRecognitionBloc() : super(FaceInitial()) {
    on<ProcessFace>(_onProcessFace);
  }

  Future<void> _onProcessFace(
    ProcessFace event,
    Emitter<FaceState> emit,
  ) async {
    emit(FaceProcessing());
    try {
      // Process in isolate to avoid UI blocking
      final result = await compute(processImage, event.image);
      emit(FaceRecognized(result));
    } catch (e) {
      emit(FaceError(e.toString()));
    }
  }
}
```

### Camera Frame Processing
```dart
// CRITICAL: Use KEEP_ONLY_LATEST to prevent memory issues
controller.startImageStream((CameraImage image) {
  if (!isProcessing) {
    isProcessing = true;
    processImage(image).then((_) {
      isProcessing = false;
    });
  }
});
```

### Face Recognition Pipeline
```dart
// 1. Detect face
final faces = await faceDetector.processImage(inputImage);
if (faces.isEmpty) return null;

// 2. Crop face (112x112 for MobileFaceNet)
final croppedFace = await cropFace(image, faces.first);

// 3. Generate embedding
final embedding = await interpreter.run(croppedFace);

// 4. Match against database
final bestMatch = findBestMatch(embedding, employeeEmbeddings);
if (bestMatch.distance < 0.6) {  // Threshold
  return bestMatch.employee;
}
```

### Offline Queue Pattern
```dart
// Queue failed API calls
await offlineQueue.add(ApiCall(
  endpoint: '/time-in',
  method: 'POST',
  body: {'employeeId': employeeId},
  timestamp: DateTime.now(),
));

// Sync when online
Workmanager().registerOneOffTask(
  "sync-queue",
  "syncTask",
  constraints: Constraints(
    networkType: NetworkType.connected,
  ),
);
```

## ⚠️ Common Pitfalls & Solutions

| Issue | Wrong Way | Right Way |
|-------|-----------|-----------|
| **UI Blocking** | Process ML in main thread | Use `compute()` or isolates |
| **Memory Leak** | Keep all frames in queue | Use `STRATEGY_KEEP_ONLY_LATEST` |
| **Poor Accuracy** | Use raw camera image | Normalize to 112x112, good lighting |
| **Battery Drain** | Process every frame | Skip frames, use quality threshold |
| **Large APK** | Include all TF Lite ops | Use selective ops, ProGuard |
| **Spoofing** | No liveness check | Implement passive liveness |
| **Privacy Risk** | Store face images | Store only embeddings |

## 🐛 Troubleshooting Guide

### Camera Not Working
```bash
# Check permissions
adb shell dumpsys package com.ante.facial_recognition | grep permission

# Verify CameraX in build.gradle
dependencies {
  implementation 'androidx.camera:camera-camera2:1.3.0'
}
```

### Model Not Loading
```dart
// Check asset exists
final modelPath = 'assets/models/mobilefacenet.tflite';
final exists = await rootBundle.load(modelPath);

// Verify in pubspec.yaml
flutter:
  assets:
    - assets/models/
```

### Slow Recognition
```dart
// Enable GPU delegate
final options = InterpreterOptions()
  ..addDelegate(GpuDelegateV2());
final interpreter = await Interpreter.fromAsset(
  'mobilefacenet.tflite',
  options: options,
);
```

### High Memory Usage
```dart
// Dispose resources properly
@override
void dispose() {
  cameraController?.dispose();
  faceDetector.close();
  interpreter.close();
  super.dispose();
}
```

## 🚀 Quick Commands

```bash
# Run app
flutter run --release

# Build APK
flutter build apk --release --split-per-abi

# Check APK size
flutter build apk --analyze-size

# Run tests
flutter test --coverage

# Profile performance
flutter run --profile

# Clean build
flutter clean && flutter pub get
```

## 📊 Performance Checklist

- [ ] ML processing in isolate
- [ ] GPU delegation enabled
- [ ] Camera frames throttled
- [ ] Images resized before processing
- [ ] Embeddings cached locally
- [ ] ProGuard/R8 configured
- [ ] Unused TF ops removed
- [ ] Assets compressed

## 🔑 Key Thresholds

```dart
const double FACE_MATCH_THRESHOLD = 0.6;     // Euclidean distance
const double LIVENESS_THRESHOLD = 0.9;       // Confidence score
const double QUALITY_THRESHOLD = 0.7;        // Face quality
const int FACE_SIZE = 112;                   // MobileFaceNet input
const int EMBEDDING_SIZE = 128;              // Output dimensions
```

## 📱 Device Testing Notes

- **Emulator**: Face detection works, but slow. Use physical device.
- **Low-end**: Test on Snapdragon 450 with 2GB RAM
- **Camera**: Some devices need `CameraCharacteristics.LENS_FACING_FRONT`
- **Permissions**: Android 12+ needs explicit camera permission request

---

**See `/PLANNING.md` for architecture details and `/PRD.md` for full requirements.**