# ANTE Facial Recognition - Project Planning Document

## 🎯 Project Vision

### Mission Statement
Build a state-of-the-art Android mobile application for employee time tracking that leverages on-device facial recognition to provide the fastest, most secure, and privacy-focused attendance management solution in the market.

### Core Values
1. **Privacy First**: All biometric processing happens on-device
2. **Speed Excellence**: Sub-100ms recognition for zero-friction experience
3. **Offline Resilient**: Full functionality without internet connectivity
4. **User Centric**: 95%+ completion rate with passive interaction
5. **Enterprise Ready**: 99.8% accuracy with anti-spoofing protection

### Success Vision
By Q1 2025, deploy an Android application that becomes the standard for facial recognition time tracking in ANTE's ecosystem, processing 10,000+ daily transactions with zero privacy breaches and minimal user friction.

## 🏗️ Architecture Strategy

### Clean Architecture with BLoC Pattern

We'll implement Clean Architecture with BLoC (Business Logic Component) for state management, chosen for its:
- **Separation of Concerns**: Clear boundaries between layers
- **Testability**: 80%+ unit test coverage achievable
- **Scalability**: Handles complex business logic elegantly
- **Maintainability**: New developers can understand quickly

### Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │   Widgets   │  │   Screens   │  │    BLoCs    │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                       DOMAIN LAYER                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │  Use Cases  │  │   Entities  │  │ Repositories│       │
│  │             │  │             │  │ (Abstract)  │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                        DATA LAYER                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │Repositories │  │Data Sources │  │   Models    │       │
│  │   (Impl)    │  │ Local/Remote│  │             │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Module Structure

```dart
// Feature-based modular structure
lib/
├── core/                       // Core utilities & shared code
│   ├── di/                    // Dependency injection
│   ├── error/                 // Error handling
│   ├── network/               // Network utilities
│   └── utils/                 // Common utilities
│
├── features/
│   ├── authentication/
│   │   ├── presentation/      // UI layer
│   │   │   ├── bloc/         // BLoC state management
│   │   │   ├── pages/        // Screen widgets
│   │   │   └── widgets/      // Reusable widgets
│   │   ├── domain/           // Business logic
│   │   │   ├── entities/     // Core business objects
│   │   │   ├── repositories/ // Abstract repositories
│   │   │   └── usecases/     // Business operations
│   │   └── data/             // Data implementation
│   │       ├── datasources/  // API/Local data sources
│   │       ├── models/       // Data models
│   │       └── repositories/ // Repository implementations
│   │
│   ├── face_recognition/     // Similar structure
│   ├── time_tracking/        // Similar structure
│   └── employee_management/  // Similar structure
```

### Isolate Architecture for ML Processing

```dart
// Main Isolate (UI Thread)
class FaceRecognitionBloc extends Bloc<FaceEvent, FaceState> {
  final ComputePort _computePort;

  Stream<FaceState> mapEventToState(FaceEvent event) async* {
    if (event is ProcessFaceImage) {
      // Send to compute isolate
      final result = await _computePort.compute(
        processImage,
        event.cameraImage
      );
      yield FaceProcessed(result);
    }
  }
}

// Compute Isolate (Background Thread)
Future<FaceResult> processImage(CameraImage image) async {
  // Heavy ML processing here
  final face = await detector.detectFace(image);
  final embedding = await recognizer.generateEmbedding(face);
  final match = await matcher.findMatch(embedding);
  return FaceResult(match);
}
```

## 💻 Technology Stack

### Core Technologies

#### Mobile Framework
- **Flutter 3.24+** - Latest stable version
- **Dart 3.0+** - With null safety and pattern matching
- **Material Design 3** - Google's latest design system

#### State Management
- **flutter_bloc: ^8.1.0** - BLoC pattern implementation
- **equatable: ^2.0.0** - Value equality for states/events
- **hydrated_bloc: ^9.0.0** - Automatic state persistence

#### Dependency Injection
- **get_it: ^7.6.0** - Service locator
- **injectable: ^2.3.0** - Code generation for DI
- **injectable_generator: ^2.4.0** - Build runner for DI

#### Face Detection & Recognition
- **google_mlkit_face_detection: ^0.11.0** - Google's ML Kit
- **tflite_flutter: ^0.10.0** - TensorFlow Lite runtime
- **tflite_flutter_helper: ^0.4.0** - Helper utilities
- **camera: ^0.11.0** - Camera plugin

#### Networking
- **dio: ^5.4.0** - HTTP client with interceptors
- **retrofit: ^4.1.0** - Type-safe HTTP client
- **pretty_dio_logger: ^1.3.0** - Request/response logging
- **dio_certificate_pinning: ^5.0.0** - SSL pinning

#### Local Storage
- **sqflite: ^2.3.0** - SQLite database
- **sqflite_sqlcipher: ^3.0.0** - Encrypted SQLite
- **flutter_secure_storage: ^9.0.0** - Secure key storage
- **hive: ^2.2.0** - NoSQL for preferences
- **cached_network_image: ^3.3.0** - Image caching

#### Background Processing
- **workmanager: ^0.5.2** - Background jobs
- **android_alarm_manager_plus: ^4.0.0** - Scheduled tasks
- **flutter_isolate: ^2.0.0** - Isolate management

#### Navigation & UI
- **go_router: ^13.0.0** - Declarative routing
- **flutter_screenutil: ^5.9.0** - Responsive UI
- **lottie: ^3.0.0** - Animations
- **flutter_svg: ^2.0.0** - SVG support

#### Utilities
- **connectivity_plus: ^5.0.0** - Network monitoring
- **device_info_plus: ^10.0.0** - Device information
- **permission_handler: ^11.0.0** - Permission management
- **local_auth: ^2.1.0** - Biometric authentication
- **path_provider: ^2.1.0** - File system paths

### Development Dependencies

#### Code Generation
- **build_runner: ^2.4.0** - Build system
- **freezed: ^2.4.0** - Data class generation
- **freezed_annotation: ^2.4.0** - Annotations
- **json_serializable: ^6.7.0** - JSON serialization

#### Testing
- **flutter_test** - Core testing framework
- **bloc_test: ^9.1.0** - BLoC testing utilities
- **mockito: ^5.4.0** - Mocking framework
- **integration_test** - E2E testing

#### Code Quality
- **flutter_lints: ^3.0.0** - Lint rules
- **dart_code_metrics: ^5.7.0** - Code metrics
- **test_coverage: ^1.0.0** - Coverage reports

### ML Models

#### Face Recognition Model Requirements
- **Model Architecture**: MobileFaceNet or FaceNet
- **Input Size**: 112x112x3 (RGB images)
- **Output Size**: 128-dimensional embedding vector
- **File Size**: 4-23MB for TFLite format
- **Format**: Standard TensorFlow Lite (.tflite) with valid FlatBuffer structure

#### Current Model Status
⚠️ **Known Issue**: The current model files in `assets/models/mobilefacenet.tflite` have structural issues:
- **Problem**: Downloaded TFLite models often have non-standard headers (TFL3 magic bytes at offset 4 instead of 0)
- **Workaround**: App gracefully falls back to Mock Embedding Strategy for development/testing
- **Solution Needed**: Obtain properly formatted TFLite model or convert existing model to standard format

#### Model Sources Investigated
1. **GitHub Repositories**:
   - `MCarlomagno/FaceRecognitionAuth` - Contains mobilefacenet.tflite but non-standard format
   - `shubham0204/FaceRecognition_With_FaceNet_Android` - 22.6MB FaceNet model, header issues

2. **TensorFlow Hub**:
   - Official MobileNet models available but are for image classification, not face recognition

3. **Recommended Solution**:
   - Use TensorFlow Model Maker to create custom face recognition model
   - Or obtain pre-trained InsightFace/ArcFace model and convert to TFLite
   - Ensure model follows standard TFLite FlatBuffer format

#### Planned Models
- **MobileFaceNet** (4MB) - Face recognition ⚠️ *Needs valid TFLite file*
- **Custom Liveness Model** (2-5MB) - Anti-spoofing *Future implementation*
- **Face Quality Model** (1MB) - Image quality assessment *Future implementation*

### Android Native Configuration

```gradle
android {
    compileSdkVersion 34
    ndkVersion "25.1.8937393"

    defaultConfig {
        minSdkVersion 23         // Android 6.0
        targetSdkVersion 34      // Android 14
        multiDexEnabled true

        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a'
        }
    }

    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android.txt')
        }
    }
}

dependencies {
    implementation 'androidx.camera:camera-camera2:1.3.0'
    implementation 'org.tensorflow:tensorflow-lite:2.14.0'
    implementation 'org.tensorflow:tensorflow-lite-gpu:2.14.0'
    implementation 'org.tensorflow:tensorflow-lite-support:0.4.4'
}
```

## 🛠️ Development Environment

### Required Tools

#### IDE Setup
1. **Android Studio 2024.1+** (Hedgehog or later)
   - Flutter plugin 75.0+
   - Dart plugin 231.0+
   - Android SDK 34
   - NDK 25.1+

2. **Visual Studio Code** (Alternative)
   - Flutter extension
   - Dart extension
   - Error Lens
   - GitLens
   - Better Comments

#### Flutter Setup
```bash
# Install Flutter
flutter channel stable
flutter upgrade
flutter doctor

# Verify setup
flutter doctor -v
```

#### Development Tools
- **Flutter DevTools** - Debugging and profiling
- **Android Debug Bridge (ADB)** - Device management
- **Flipper** - Network debugging (optional)
- **Charles Proxy** - API debugging (optional)
- **Postman** - API testing

### Development Machine Requirements
- **OS**: Windows 10+, macOS 11+, or Ubuntu 20.04+
- **RAM**: 16GB minimum (32GB recommended)
- **Storage**: 20GB free space
- **Processor**: Intel i5/AMD Ryzen 5 or better
- **Android Device**: Physical device for testing (recommended)

## 🚀 Implementation Roadmap

### Sprint 0: Setup & Foundation (Week 0)
- [ ] Development environment setup
- [ ] Flutter project initialization
- [ ] CI/CD pipeline setup (GitHub Actions)
- [ ] Code quality tools configuration
- [ ] Architecture scaffolding

### Sprint 1: Core Infrastructure (Week 1-2)
- [ ] Clean Architecture setup
- [ ] BLoC pattern implementation
- [ ] Dependency injection configuration
- [ ] Navigation structure
- [ ] Theme and design system

### Sprint 2: Camera & ML Integration (Week 3-4)
- [ ] CameraX integration via platform channels
- [ ] ML Kit face detection setup
- [ ] TensorFlow Lite integration
- [ ] Isolate implementation for ML processing
- [ ] Face quality assessment

### Sprint 3: Face Recognition Pipeline (Week 5-6)
- [ ] MobileFaceNet model integration
- [ ] Face encoding generation
- [ ] Face matching algorithm
- [ ] Employee database synchronization
- [ ] Recognition result caching

### Sprint 4: Liveness & Security (Week 7)
- [ ] Passive liveness detection
- [ ] Anti-spoofing measures
- [ ] Data encryption implementation
- [ ] Biometric app lock
- [ ] Certificate pinning

### Sprint 5: Business Logic (Week 8)
- [ ] Time tracking API integration
- [ ] Offline queue management
- [ ] Background sync service
- [ ] Conflict resolution
- [ ] Admin features

### Sprint 6: Polish & Optimization (Week 9)
- [ ] Performance optimization
- [ ] Battery usage optimization
- [ ] APK size reduction (<50MB)
- [ ] Error handling improvements
- [ ] Accessibility features

### Sprint 7: Testing & Deployment (Week 10)
- [ ] Unit test completion (>80% coverage)
- [ ] Integration testing
- [ ] Device matrix testing
- [ ] Security audit
- [ ] Play Store deployment

## 🎯 Performance Benchmarks

### Target Metrics
```yaml
recognition_pipeline:
  face_detection: <50ms
  face_encoding: <30ms
  face_matching: <20ms
  liveness_check: <100ms
  total_time: <200ms

accuracy:
  false_acceptance_rate: <0.01%
  false_rejection_rate: <2%
  true_positive_rate: >99.8%
  liveness_accuracy: >99.67%

app_performance:
  cold_start: <3s
  warm_start: <1s
  memory_usage: <200MB
  battery_drain: <2%/hour
  fps_during_camera: 30fps

reliability:
  crash_free_rate: >99.9%
  anr_rate: <0.05%
  network_failure_handling: 100%
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow
```yaml
name: Flutter CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - run: flutter build apk --release

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJson: ${{ secrets.PLAY_STORE_KEY }}
          packageName: com.ante.facial_recognition
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: internal
```

## 📊 Monitoring & Analytics

### Crashlytics Integration
```dart
// Initialize in main.dart
await Firebase.initializeApp();
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
```

### Performance Monitoring
```dart
// Track custom traces
final trace = FirebasePerformance.instance.newTrace('face_recognition');
await trace.start();
// ... recognition process
await trace.stop();
```

### Analytics Events
```dart
// Track key events
await analytics.logEvent(
  name: 'face_recognition_success',
  parameters: {
    'duration_ms': processingTime,
    'confidence': confidenceScore,
    'device_model': deviceModel,
  },
);
```

## 🔐 Security Checklist

- [ ] Biometric data never leaves device
- [ ] Face encodings encrypted with AES-256
- [ ] API keys in Android Keystore
- [ ] Certificate pinning implemented
- [ ] ProGuard rules configured
- [ ] Code obfuscation enabled
- [ ] Sensitive logs removed
- [ ] Security audit completed

## 🔑 Device Authentication Flow

### API Key Authentication
The device authentication uses a pre-assigned API key that must be obtained from the backend administrator:

1. **API Key Setup**:
   - Each device is assigned a unique API key (format: `ante_device_[hash]`)
   - The API key must be obtained from the backend admin before device setup
   - API key is entered during initial device configuration

2. **Authentication Process**:
   - User enters API key in device setup page
   - App validates API key against backend `/health` endpoint
   - Backend returns device info (ID, name, location) if API key is valid
   - API key is stored securely using flutter_secure_storage

3. **API Request Flow**:
   - All API requests include `x-api-key` header
   - No separate device ID is needed - API key identifies the device
   - Backend validates API key and returns appropriate device-scoped data

4. **Security Considerations**:
   - API keys are never hardcoded in the app
   - Keys are stored in encrypted secure storage
   - Invalid API keys result in authentication failure
   - API keys can be revoked by backend admin

## 📝 Documentation Requirements

- [ ] API documentation (OpenAPI/Swagger)
- [ ] Architecture decision records (ADRs)
- [ ] Code documentation (DartDoc)
- [ ] User manual
- [ ] Admin guide
- [ ] Deployment guide
- [ ] Troubleshooting guide

## ✅ Definition of Done

A feature is considered complete when:
1. Code is written and follows style guide
2. Unit tests written with >80% coverage
3. Integration tests pass
4. Code review approved
5. Documentation updated
6. Performance benchmarks met
7. Security scan passed
8. Deployed to staging environment
9. QA testing passed
10. Product owner approval received

---

**Last Updated**: December 2024
**Version**: 1.0.0
**Status**: Planning Phase