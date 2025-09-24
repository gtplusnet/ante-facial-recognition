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
    if (_previousIndex == 0 && index != 0) {
      // Navigating away from Recognition tab (index 0)
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