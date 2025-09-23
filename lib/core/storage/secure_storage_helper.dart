import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';

class SecureStorageHelper {
  final FlutterSecureStorage _storage;

  SecureStorageHelper(this._storage);

  // API Key
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _storage.write(key: AppConstants.apiKeyStorageKey, value: apiKey);
      Logger.success('API key saved to secure storage');
    } catch (e) {
      Logger.error('Failed to save API key', error: e);
      rethrow;
    }
  }

  Future<String?> getApiKey() async {
    try {
      final apiKey = await _storage.read(key: AppConstants.apiKeyStorageKey);
      Logger.debug('API key retrieved from secure storage');
      return apiKey;
    } catch (e) {
      Logger.error('Failed to retrieve API key', error: e);
      return null;
    }
  }

  Future<void> deleteApiKey() async {
    try {
      await _storage.delete(key: AppConstants.apiKeyStorageKey);
      Logger.success('API key deleted from secure storage');
    } catch (e) {
      Logger.error('Failed to delete API key', error: e);
      rethrow;
    }
  }

  // Device ID
  Future<void> saveDeviceId(String deviceId) async {
    try {
      await _storage.write(key: AppConstants.deviceIdKey, value: deviceId);
      Logger.success('Device ID saved to secure storage');
    } catch (e) {
      Logger.error('Failed to save device ID', error: e);
      rethrow;
    }
  }

  Future<String?> getDeviceId() async {
    try {
      final deviceId = await _storage.read(key: AppConstants.deviceIdKey);
      Logger.debug('Device ID retrieved from secure storage');
      return deviceId;
    } catch (e) {
      Logger.error('Failed to retrieve device ID', error: e);
      return null;
    }
  }

  // Last Sync Time
  Future<void> saveLastSyncTime(DateTime time) async {
    try {
      await _storage.write(
        key: AppConstants.lastSyncKey,
        value: time.toIso8601String(),
      );
      Logger.success('Last sync time saved');
    } catch (e) {
      Logger.error('Failed to save last sync time', error: e);
      rethrow;
    }
  }

  Future<DateTime?> getLastSyncTime() async {
    try {
      final timeString = await _storage.read(key: AppConstants.lastSyncKey);
      if (timeString != null) {
        return DateTime.parse(timeString);
      }
      return null;
    } catch (e) {
      Logger.error('Failed to retrieve last sync time', error: e);
      return null;
    }
  }

  Future<void> deleteLastSyncTime() async {
    try {
      await _storage.delete(key: AppConstants.lastSyncKey);
      Logger.success('Last sync time deleted');
    } catch (e) {
      Logger.error('Failed to delete last sync time', error: e);
      rethrow;
    }
  }

  // Employee Data (for offline caching)
  Future<void> saveEmployeeData(Map<String, dynamic> data) async {
    try {
      final jsonString = jsonEncode(data);
      await _storage.write(key: AppConstants.employeeDataKey, value: jsonString);
      Logger.success('Employee data saved to secure storage');
    } catch (e) {
      Logger.error('Failed to save employee data', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getEmployeeData() async {
    try {
      final jsonString = await _storage.read(key: AppConstants.employeeDataKey);
      if (jsonString != null) {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      Logger.error('Failed to retrieve employee data', error: e);
      return null;
    }
  }

  // Generic methods for custom key-value pairs
  Future<void> saveValue({
    required String key,
    required String value,
  }) async {
    try {
      await _storage.write(key: key, value: value);
      Logger.debug('Value saved for key: $key');
    } catch (e) {
      Logger.error('Failed to save value for key: $key', error: e);
      rethrow;
    }
  }

  Future<String?> getValue(String key) async {
    try {
      final value = await _storage.read(key: key);
      Logger.debug('Value retrieved for key: $key');
      return value;
    } catch (e) {
      Logger.error('Failed to retrieve value for key: $key', error: e);
      return null;
    }
  }

  Future<void> deleteValue(String key) async {
    try {
      await _storage.delete(key: key);
      Logger.debug('Value deleted for key: $key');
    } catch (e) {
      Logger.error('Failed to delete value for key: $key', error: e);
      rethrow;
    }
  }

  // Clear all secure storage
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      Logger.warning('All secure storage cleared');
    } catch (e) {
      Logger.error('Failed to clear secure storage', error: e);
      rethrow;
    }
  }

  // Check if a key exists
  Future<bool> hasKey(String key) async {
    try {
      final value = await _storage.read(key: key);
      return value != null;
    } catch (e) {
      Logger.error('Failed to check key existence: $key', error: e);
      return false;
    }
  }

  // Get all keys
  Future<Map<String, String>> getAllKeys() async {
    try {
      final allValues = await _storage.readAll();
      Logger.debug('Retrieved ${allValues.length} keys from secure storage');
      return allValues;
    } catch (e) {
      Logger.error('Failed to retrieve all keys', error: e);
      return {};
    }
  }
}