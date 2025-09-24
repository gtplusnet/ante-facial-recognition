# Development Notes

## Recent Issues and Solutions

### GetIt Registration Error for RenderService (Fixed)

**Issue**:
```
Bad state: GetIt: Object/factory with type RenderService is not registered inside GetIt.
```

**Root Cause**:
The `RenderService` was added with `@singleton` annotation, but `build_runner` hadn't been executed to regenerate the dependency injection configuration.

**Solution**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This regenerated `lib/core/di/injection.config.dart` with proper RenderService registration:
```dart
gh.singleton<_i799.RenderService>(() => _i799.RenderService());
```

**Prevention**:
After adding any new `@singleton`, `@injectable`, or `@lazySingleton` annotated classes, always run build_runner to update the DI configuration.

## Build Commands

### Dependency Injection
```bash
# Regenerate DI configuration after adding new injectable classes
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for continuous regeneration during development
flutter pub run build_runner watch --delete-conflicting-outputs
```

### Testing
```bash
# Build and test
flutter build apk --debug
flutter test

# Analysis
flutter analyze
```

## Architecture Notes

### Platform-Specific Services
- `RenderService`: Handles SELinux detection and rendering capabilities
- `RenderAwareWidget`: UI component that adapts to device restrictions
- Platform channels: Bridge native Android capabilities to Flutter

### Dependency Injection
- Uses `get_it` with `injectable` code generation
- Generated config file: `lib/core/di/injection.config.dart` (git-ignored)
- Manual registrations in `lib/core/di/injection.dart` for external dependencies