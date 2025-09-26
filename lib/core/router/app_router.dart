import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/device_setup_page.dart';
import '../../features/employee/presentation/pages/employee_detail_page.dart';
import '../../features/employee/presentation/pages/employee_list_page.dart';
import '../../features/employee/presentation/screens/add_face_camera_screen.dart';
import '../../features/face_recognition/presentation/pages/simplified_camera_screen.dart';
import '../../features/logs/presentation/pages/face_recognition_logs_page.dart';
import '../../features/main_shell/presentation/pages/main_shell_page.dart';
import '../../features/settings/presentation/pages/face_recognition_settings_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');
  static final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'shell');

  // Route observer for tracking navigation
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/device-setup',
        name: 'deviceSetup',
        builder: (context, state) => const DeviceSetupPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellPage(navigationShell: navigationShell);
        },
        branches: [
          // Logs is now first (index 0) - default page
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/daily-logs',
                name: 'dailyLogs',
                builder: (context, state) => const FaceRecognitionLogsPage(),
              ),
            ],
          ),
          // Recognition is now second (index 1)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/face-recognition',
                name: 'faceRecognition',
                builder: (context, state) => const SimplifiedCameraScreen(),
              ),
            ],
          ),
          // Employees is now third (index 2)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employees',
                name: 'employees',
                builder: (context, state) => const EmployeeListPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'employeeDetail',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final employeeId = state.pathParameters['id']!;
                      return EmployeeDetailPage(employeeId: employeeId);
                    },
                    routes: [
                      GoRoute(
                        path: 'add-face',
                        name: 'addEmployeeFace',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) {
                          final employeeId = state.pathParameters['id']!;
                          // We'll create this screen next
                          return AddFaceCameraScreen(employeeId: employeeId);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Settings remains fourth (index 3)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'face-recognition',
                    name: 'faceRecognitionSettings',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const FaceRecognitionSettingsPage(),
                  ),
                  GoRoute(
                    path: 'admin',
                    name: 'admin',
                    builder: (context, state) => const MainShellScaffold(
                      title: 'Admin Panel',
                      showBackButton: true,
                      child: Center(child: Text('Admin Panel')),
                    ),
                    redirect: (context, state) {
                      // TODO(auth): Check admin authentication
                      return null;
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Navigation Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.error?.toString() ?? 'Unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
}