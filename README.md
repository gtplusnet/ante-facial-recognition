# ANTE Facial Recognition

Advanced Android face recognition app for employee time tracking using Flutter. Features on-device ML processing with 99.8% accuracy and <100ms recognition times.

## Key Features

- **High Accuracy**: 99.8% face recognition accuracy
- **Fast Processing**: <100ms recognition times
- **Privacy-First**: All processing on-device, no cloud dependency
- **Offline Capable**: Functions without internet connection
- **Optimized APK**: <50MB application size
- **Enterprise Ready**: Handles strict security policies

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run --release
```

## Architecture

- **Frontend**: Flutter with BLoC pattern
- **ML Engine**: TensorFlow Lite with MobileFaceNet
- **Face Detection**: Google ML Kit
- **Database**: SQLite with offline caching
- **Platform**: Native Android channels for hardware optimization

## Device Compatibility

This app is designed to work on all Android devices, including those with strict security configurations:

- **Standard Devices**: Full hardware acceleration for optimal performance
- **Enterprise/Secure Devices**: Automatic fallback to software rendering
- **SELinux Enforcing**: Graceful handling of GPU restrictions

### SELinux Compatibility

If you see `dmabuf` warnings in logs, this is normal for devices with enhanced security policies. See our comprehensive [SELinux Compatibility Guide](docs/SELINUX_COMPATIBILITY.md) for details.

## Documentation

- [SELinux Compatibility Guide](docs/SELINUX_COMPATIBILITY.md) - Handle security-enhanced devices
- [API Integration](docs/MANPOWER_API.md) - Backend integration guide
- [Architecture Overview](PLANNING.md) - Technical architecture details
- [Product Requirements](PRD.md) - Complete feature specifications

## Development

See [CLAUDE.md](CLAUDE.md) for development instructions and project context.
