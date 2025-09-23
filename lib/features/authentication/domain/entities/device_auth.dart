import 'package:equatable/equatable.dart';

class DeviceAuth extends Equatable {
  final String deviceId;
  final String deviceName;
  final String? location;
  final String? apiKey;
  final DateTime? lastActivity;
  final bool isActive;
  final Map<String, dynamic>? metadata;

  const DeviceAuth({
    required this.deviceId,
    required this.deviceName,
    this.location,
    this.apiKey,
    this.lastActivity,
    this.isActive = true,
    this.metadata,
  });

  @override
  List<Object?> get props => [
        deviceId,
        deviceName,
        location,
        apiKey,
        lastActivity,
        isActive,
        metadata,
      ];

  DeviceAuth copyWith({
    String? deviceId,
    String? deviceName,
    String? location,
    String? apiKey,
    DateTime? lastActivity,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return DeviceAuth(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      location: location ?? this.location,
      apiKey: apiKey ?? this.apiKey,
      lastActivity: lastActivity ?? this.lastActivity,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }
}