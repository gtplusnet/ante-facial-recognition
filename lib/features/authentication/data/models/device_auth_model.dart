import '../../domain/entities/device_auth.dart';

class DeviceAuthModel extends DeviceAuth {
  const DeviceAuthModel({
    required super.deviceId,
    required super.deviceName,
    super.location,
    super.apiKey,
    super.lastActivity,
    super.isActive,
    super.metadata,
  });

  factory DeviceAuthModel.fromJson(Map<String, dynamic> json) {
    return DeviceAuthModel(
      deviceId: json['id'] ?? json['deviceId'] ?? '',
      deviceName: json['name'] ?? json['deviceName'] ?? '',
      location: json['location'],
      apiKey: json['apiKey'] ?? json['api_key'],
      lastActivity: json['lastActivity'] != null
          ? DateTime.parse(json['lastActivity'])
          : null,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      metadata: json['metadata'],
    );
  }

  factory DeviceAuthModel.fromHealthResponse(Map<String, dynamic> json) {
    final device = json['device'] ?? {};
    return DeviceAuthModel(
      deviceId: device['id'] ?? '',
      deviceName: device['name'] ?? '',
      location: device['location'],
      apiKey: json['apiKey'], // This might come from headers or separate auth
      lastActivity: device['lastActivity'] != null
          ? DateTime.parse(device['lastActivity'])
          : null,
      isActive: true,
      metadata: {
        'status': json['status'],
        'timestamp': json['timestamp'],
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'location': location,
      'apiKey': apiKey,
      'lastActivity': lastActivity?.toIso8601String(),
      'isActive': isActive,
      'metadata': metadata,
    };
  }

  factory DeviceAuthModel.fromEntity(DeviceAuth entity) {
    return DeviceAuthModel(
      deviceId: entity.deviceId,
      deviceName: entity.deviceName,
      location: entity.location,
      apiKey: entity.apiKey,
      lastActivity: entity.lastActivity,
      isActive: entity.isActive,
      metadata: entity.metadata,
    );
  }
}