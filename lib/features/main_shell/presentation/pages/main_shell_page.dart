import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class MainShellPage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellPage({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.face_outlined, size: 24.w),
            selectedIcon: Icon(Icons.face, size: 24.w),
            label: 'Recognition',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, size: 24.w),
            selectedIcon: Icon(Icons.people, size: 24.w),
            label: 'Employees',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, size: 24.w),
            selectedIcon: Icon(Icons.history, size: 24.w),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, size: 24.w),
            selectedIcon: Icon(Icons.settings, size: 24.w),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class MainShellScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBackButton;

  const MainShellScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              automaticallyImplyLeading: showBackButton,
              actions: actions,
            )
          : null,
      body: child,
      floatingActionButton: floatingActionButton,
    );
  }
}