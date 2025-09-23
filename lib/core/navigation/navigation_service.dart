import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../utils/logger.dart';

@singleton
class NavigationService {
  late GoRouter _router;

  void setRouter(GoRouter router) {
    _router = router;
  }

  GoRouter get router => _router;

  void go(String path, {Object? extra}) {
    Logger.debug('Navigating to: $path');
    _router.go(path, extra: extra);
  }

  void push(String path, {Object? extra}) {
    Logger.debug('Pushing route: $path');
    _router.push(path, extra: extra);
  }

  void pushNamed(
    String name, {
    Map<String, String> pathParameters = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? extra,
  }) {
    Logger.debug('Pushing named route: $name');
    _router.pushNamed(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      extra: extra,
    );
  }

  void goNamed(
    String name, {
    Map<String, String> pathParameters = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? extra,
  }) {
    Logger.debug('Going to named route: $name');
    _router.goNamed(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      extra: extra,
    );
  }

  void pop<T>([T? result]) {
    if (_router.canPop()) {
      Logger.debug('Popping current route');
      _router.pop(result);
    } else {
      Logger.warning('Cannot pop - no routes in stack');
    }
  }

  bool canPop() {
    return _router.canPop();
  }

  void popUntil(String path) {
    while (_router.canPop() &&
           _router.routerDelegate.currentConfiguration.uri.toString() != path) {
      _router.pop();
    }
  }

  void replace(String path, {Object? extra}) {
    Logger.debug('Replacing current route with: $path');
    _router.replace(path, extra: extra);
  }

  void replaceNamed(
    String name, {
    Map<String, String> pathParameters = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? extra,
  }) {
    Logger.debug('Replacing with named route: $name');
    _router.replaceNamed(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      extra: extra,
    );
  }

  void refresh() {
    Logger.debug('Refreshing current route');
    _router.refresh();
  }

  String get currentPath =>
      _router.routerDelegate.currentConfiguration.uri.toString();

  bool isCurrentPath(String path) => currentPath == path;

  void clearStackAndNavigate(String path) {
    Logger.debug('Clearing stack and navigating to: $path');
    while (_router.canPop()) {
      _router.pop();
    }
    _router.go(path);
  }

  // Navigation helpers for specific routes
  void navigateToHome() => go('/');
  void navigateToFaceRecognition() => go('/face-recognition');
  void navigateToEmployees() => go('/employees');
  void navigateToDailyLogs() => go('/daily-logs');
  void navigateToSettings() => go('/settings');
  void navigateToAdmin() => go('/admin');
  void navigateToDeviceSetup() => go('/device-setup');

  // Authentication related navigation
  void navigateToLogin() {
    clearStackAndNavigate('/login');
  }

  void navigateToMainApp() {
    clearStackAndNavigate('/face-recognition');
  }
}