import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/logger.dart';

@singleton
class PermissionService {
  Future<bool> checkCameraPermission() async {
    final status = await Permission.camera.status;
    Logger.debug('Camera permission status: $status');
    return status.isGranted;
  }

  Future<bool> requestCameraPermission() async {
    Logger.info('Requesting camera permission');
    final status = await Permission.camera.request();
    Logger.debug('Camera permission request result: $status');
    return status.isGranted;
  }

  Future<bool> checkAndRequestCameraPermission() async {
    if (await checkCameraPermission()) {
      return true;
    }
    return await requestCameraPermission();
  }

  Future<bool> checkStoragePermission() async {
    final status = await Permission.storage.status;
    Logger.debug('Storage permission status: $status');
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    Logger.info('Requesting storage permission');
    final status = await Permission.storage.request();
    Logger.debug('Storage permission request result: $status');
    return status.isGranted;
  }

  Future<bool> checkAndRequestStoragePermission() async {
    if (await checkStoragePermission()) {
      return true;
    }
    return await requestStoragePermission();
  }

  Future<bool> checkAllRequiredPermissions() async {
    final camera = await checkCameraPermission();
    final storage = await checkStoragePermission();
    return camera && storage;
  }

  Future<bool> requestAllRequiredPermissions() async {
    final permissions = await [
      Permission.camera,
      Permission.storage,
    ].request();

    final allGranted = permissions.values.every((status) => status.isGranted);
    Logger.info('All permissions granted: $allGranted');
    return allGranted;
  }

  Future<void> openAppSettings() async {
    Logger.info('Opening app settings');
    await openAppSettings();
  }

  Future<bool> shouldShowRequestRationale(Permission permission) async {
    if (await permission.shouldShowRequestRationale) {
      Logger.debug('Should show rationale for ${permission.toString()}');
      return true;
    }
    return false;
  }

  Future<bool> isPermanentlyDenied(Permission permission) async {
    final status = await permission.status;
    return status.isPermanentlyDenied;
  }

  Future<Map<Permission, PermissionStatus>> checkMultiplePermissions(
    List<Permission> permissions,
  ) async {
    final statuses = <Permission, PermissionStatus>{};
    for (final permission in permissions) {
      statuses[permission] = await permission.status;
    }
    Logger.debug('Multiple permissions status: $statuses');
    return statuses;
  }

  // Convenience methods for specific permissions
  Future<bool> hasCameraPermission() async => checkCameraPermission();
  Future<bool> hasStoragePermission() async => checkStoragePermission();

  Future<PermissionStatus> getCameraPermissionStatus() async {
    return await Permission.camera.status;
  }

  Future<PermissionStatus> getStoragePermissionStatus() async {
    return await Permission.storage.status;
  }
}