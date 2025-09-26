import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_info_service.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/bloc/auth_state.dart';
import '../../../employee/domain/usecases/clear_employee_data_usecase.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout? You will need to re-enter your device ID to use the app again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Clear authentication
              context.read<AuthBloc>().add(const Logout());
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showStorageInfo(BuildContext context) async {
    try {
      final storageService = getIt<StorageInfoService>();
      final storageInfo = await storageService.getStorageInfo();

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Storage Information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStorageInfoRow('Total App Size', storageInfo.formattedTotalSize),
                _buildStorageInfoRow('Database Size', storageInfo.formattedDatabaseSize),
                _buildStorageInfoRow('Image Data Size', storageInfo.formattedImageDataSize),
                _buildStorageInfoRow('Cache Size', storageInfo.formattedCacheSize),
                const Divider(),
                _buildStorageInfoRow('Employees', '${storageInfo.employeeCount}'),
                _buildStorageInfoRow('Recognition Logs', '${storageInfo.faceRecognitionLogsCount}'),
                const Divider(),
                _buildStorageInfoRow('Available Space', storageInfo.formattedAvailableSpace),
                if (storageInfo.lastSyncTime.millisecondsSinceEpoch > 0)
                  _buildStorageInfoRow('Last Sync', _formatDateTime(storageInfo.lastSyncTime))
                else
                  _buildStorageInfoRow('Last Sync', 'Never'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading storage info: $e')),
      );
    }
  }

  Widget _buildStorageInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showDataManagement(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Data Management'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Clear Employee Data'),
              subtitle: const Text('Remove all synced employees'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _confirmClearData(context, ClearDataType.employeesOnly);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Clear Recognition Logs'),
              subtitle: const Text('Remove face recognition history'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _confirmClearData(context, ClearDataType.logsOnly);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cached),
              title: const Text('Clear Cache'),
              subtitle: const Text('Free up temporary storage'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _confirmClearData(context, ClearDataType.cacheOnly);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Clear All Data',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('Remove everything (keeps API key)'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _confirmClearData(context, ClearDataType.allData);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirmClearData(BuildContext context, ClearDataType type) {
    String title;
    String content;
    String actionText;

    switch (type) {
      case ClearDataType.employeesOnly:
        title = 'Clear Employee Data';
        content = 'This will remove all synced employee data from your device. You can re-sync later.';
        actionText = 'Clear Employees';
        break;
      case ClearDataType.logsOnly:
        title = 'Clear Recognition Logs';
        content = 'This will remove all face recognition logs from your device.';
        actionText = 'Clear Logs';
        break;
      case ClearDataType.cacheOnly:
        title = 'Clear Cache';
        content = 'This will clear temporary files to free up storage space.';
        actionText = 'Clear Cache';
        break;
      case ClearDataType.allData:
        title = 'Clear All Data';
        content = 'This will remove all data from your device except your API key. You will need to re-sync employees.';
        actionText = 'Clear All';
        break;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _performClearData(context, type);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  void _performClearData(BuildContext context, ClearDataType type) async {
    // Create a variable to track if dialog is showing
    bool dialogShowing = false;

    try {
      final clearDataUseCase = getIt<ClearEmployeeDataUseCase>();
      final messenger = ScaffoldMessenger.of(context);
      final theme = Theme.of(context);

      // Show loading dialog and track it
      dialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Clearing data...'),
              ],
            ),
          ),
        ),
      );

      final result = await clearDataUseCase(ClearEmployeeDataParams(type: type));

      // Close loading dialog if it's showing
      if (dialogShowing && context.mounted) {
        Navigator.of(context).pop();
        dialogShowing = false;
      }

      if (!context.mounted) return;

      result.fold(
        (failure) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Error: ${failure.message}'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        },
        (clearResult) {
          String message;
          switch (type) {
            case ClearDataType.employeesOnly:
              message = 'Cleared ${clearResult.deletedEmployees} employees';
              break;
            case ClearDataType.logsOnly:
              message = 'Cleared ${clearResult.deletedLogs} recognition logs';
              break;
            case ClearDataType.cacheOnly:
              message = 'Freed ${(clearResult.freedBytes / 1024).toStringAsFixed(1)} KB of cache';
              break;
            case ClearDataType.allData:
              message = 'Cleared all data: ${clearResult.deletedEmployees} employees, ${clearResult.deletedLogs} logs';
              break;
          }

          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
            ),
          );
        },
      );
    } catch (e) {
      // Close loading dialog if it's showing
      if (dialogShowing && context.mounted) {
        Navigator.of(context).pop();
        dialogShowing = false;
      }

      if (!context.mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      final theme = Theme.of(context);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Error clearing data: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          // Navigate back to device setup after logout
          context.go('/device-setup');
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              const SizedBox(height: 16),

              // App Info Section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.face,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ANTE Facial Recognition',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: const Text(
                          '🔧 DEVELOPMENT MODE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Divider(height: 32),

              // Settings Options
              ListTile(
                leading: Icon(
                  Icons.devices,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Device Information'),
                subtitle: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthAuthenticated) {
                      return Text('Device ID: ${state.deviceAuth.deviceId}');
                    }
                    return const Text('Not authenticated');
                  },
                ),
                onTap: () {
                  // Show device info dialog
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Device Information'),
                      content: BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) {
                          if (state is AuthAuthenticated) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Device ID: ${state.deviceAuth.deviceId}'),
                                const SizedBox(height: 8),
                                Text('Device Name: ${state.deviceAuth.deviceName ?? 'N/A'}'),
                                const SizedBox(height: 8),
                                Text('Location: ${state.deviceAuth.location ?? 'N/A'}'),
                                if (state.deviceAuth.lastActivity != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Last Activity: ${state.deviceAuth.lastActivity}'),
                                ],
                              ],
                            );
                          }
                          return const Text('Device not authenticated');
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),

              ListTile(
                leading: Icon(
                  Icons.sync,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Sync Settings'),
                subtitle: const Text('Configure offline sync behavior'),
                onTap: () {
                  // TODO: Implement sync settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sync settings coming soon'),
                    ),
                  );
                },
              ),

              ListTile(
                leading: Icon(
                  Icons.tune,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Face Recognition Settings'),
                subtitle: const Text('Adjust quality and matching thresholds'),
                onTap: () {
                  context.push('/settings/face-recognition');
                },
              ),

              ListTile(
                leading: Icon(
                  Icons.storage,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Storage Information'),
                subtitle: const Text('View app storage usage'),
                onTap: () => _showStorageInfo(context),
              ),

              ListTile(
                leading: Icon(
                  Icons.cleaning_services,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Data Management'),
                subtitle: const Text('Clear synced data and cache'),
                onTap: () => _showDataManagement(context),
              ),

              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('About'),
                subtitle: const Text('App information and licenses'),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'ANTE Facial Recognition',
                    applicationVersion: '1.0.0',
                    applicationIcon: Icon(
                      Icons.face,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    children: const [
                      Text('Employee time tracking system with facial recognition.'),
                      SizedBox(height: 8),
                      Text('© 2024 ANTE Systems'),
                    ],
                  );
                },
              ),

              const Divider(height: 32),

              // Logout Button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: OutlinedButton.icon(
                  onPressed: () => _showLogoutConfirmation(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              // Footer
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '© 2024 ANTE Systems',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}