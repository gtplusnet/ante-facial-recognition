import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class MainShellPage extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellPage({
    super.key,
    required this.navigationShell,
  });

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;
  }

  void _onDestinationSelected(int index) {
    // Notify about navigation change
    if (_previousIndex == 1 && index != 1) {
      // Navigating away from Recognition tab (now index 1)
      // This will be handled by the visibility detector in SimplifiedCameraScreen
    }
    _previousIndex = index;

    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          // Logs is now first (index 0) - default page
          NavigationDestination(
            icon: Icon(Icons.history_outlined, size: 24.w),
            selectedIcon: Icon(Icons.history, size: 24.w),
            label: 'Logs',
          ),
          // Recognition is now second (index 1)
          NavigationDestination(
            icon: Icon(Icons.face_outlined, size: 24.w),
            selectedIcon: Icon(Icons.face, size: 24.w),
            label: 'Recognition',
          ),
          // Employees is now third (index 2)
          NavigationDestination(
            icon: Icon(Icons.people_outline, size: 24.w),
            selectedIcon: Icon(Icons.people, size: 24.w),
            label: 'Employees',
          ),
          // Settings remains fourth (index 3)
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