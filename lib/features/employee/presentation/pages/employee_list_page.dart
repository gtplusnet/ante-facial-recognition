import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../bloc/employee_bloc.dart';
import '../bloc/employee_event.dart';
import '../bloc/employee_state.dart';
import '../widgets/employee_list_item.dart';
import '../widgets/sync_progress_indicator.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<EmployeeBloc>()..add(const LoadEmployees()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Employees'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          actions: [
            BlocBuilder<EmployeeBloc, EmployeeState>(
              builder: (context, state) {
                if (state is EmployeeLoaded) {
                  return IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: () {
                      context.read<EmployeeBloc>().add(const SyncEmployees());
                    },
                    tooltip: 'Sync Employees',
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            _buildSyncStatus(),
            Expanded(
              child: BlocBuilder<EmployeeBloc, EmployeeState>(
                builder: (context, state) {
                  if (state is EmployeeInitial || state is EmployeeLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (state is EmployeeSyncing) {
                    return Center(
                      child: SyncProgressIndicator(
                        progress: state.progress,
                        message: state.message,
                        totalCount: state.totalEmployees,
                        processedCount: state.processedEmployees,
                      ),
                    );
                  }

                  if (state is EmployeeError) {
                    return _buildErrorState(context, state);
                  }

                  if (state is EmployeeSyncSuccess) {
                    return _buildSyncSuccessState(state);
                  }

                  if (state is EmployeeLoaded) {
                    return _buildEmployeeList(state);
                  }

                  return const Center(
                    child: Text('Unknown state'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search employees...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: (value) {
          context.read<EmployeeBloc>().add(SearchEmployees(value));
        },
      ),
    );
  }

  Widget _buildSyncStatus() {
    return BlocBuilder<EmployeeBloc, EmployeeState>(
      builder: (context, state) {
        if (state is EmployeeLoaded && state.lastSyncTime != null) {
          final timeSince = DateTime.now().difference(state.lastSyncTime!);
          final needsSync = timeSince.inMinutes > 15;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: needsSync
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceVariant,
            child: Row(
              children: [
                Icon(
                  needsSync ? Icons.warning_amber : Icons.check_circle,
                  size: 16,
                  color: needsSync
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Last sync: ${DateFormatter.formatRelative(state.lastSyncTime!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${state.totalCount} employees',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEmployeeList(EmployeeLoaded state) {
    final employees = state.filteredEmployees;

    if (employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              state.searchQuery?.isNotEmpty ?? false
                  ? 'No employees found for "${state.searchQuery}"'
                  : 'No employees available',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Sync to load employees from server',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                context.read<EmployeeBloc>().add(const SyncEmployees());
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                context.read<EmployeeBloc>().add(const GenerateAllFaceEmbeddings());
              },
              icon: const Icon(Icons.face),
              label: const Text('Generate Encodings'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<EmployeeBloc>().add(const RefreshEmployees());
        // Wait for state to change
        await Future.delayed(const Duration(seconds: 1));
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: employees.length + 1,
        itemBuilder: (context, index) {
          if (index == employees.length) {
            // Summary footer
            return _buildSummaryFooter(state);
          }

          final employee = employees[index];
          return EmployeeListItem(
            employee: employee,
            onTap: () {
              context.push('/employees/${employee.id}');
            },
            onGenerateEmbedding: () {
              context
                  .read<EmployeeBloc>()
                  .add(GenerateFaceEmbeddings(employee.id));
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryFooter(EmployeeLoaded state) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Summary',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                context,
                Icons.people,
                state.totalCount.toString(),
                'Total',
              ),
              _buildStatItem(
                context,
                Icons.photo_camera,
                state.withPhotoCount.toString(),
                'With Photo',
              ),
              _buildStatItem(
                context,
                Icons.face,
                state.withEmbeddingsCount.toString(),
                'Ready',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, EmployeeError state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              'Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    context.read<EmployeeBloc>().add(const LoadEmployees());
                  },
                  child: const Text('Retry'),
                ),
                const SizedBox(width: 16),
                if (state.cachedEmployees != null &&
                    state.cachedEmployees!.isNotEmpty)
                  ElevatedButton(
                    onPressed: () {
                      // Show cached data
                    },
                    child: const Text('Show Cached'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSuccessState(EmployeeSyncSuccess state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 64,
              color: AppColors.success,
            ),
            const SizedBox(height: 16),
            Text(
              'Sync Successful',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${state.syncResult.syncedEmployees} of ${state.syncResult.totalEmployees} employees synced',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (state.syncResult.failedEmployees > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${state.syncResult.failedEmployees} failed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}