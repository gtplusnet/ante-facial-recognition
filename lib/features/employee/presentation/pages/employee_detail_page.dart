import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee.dart';
import '../bloc/employee_bloc.dart';
import '../bloc/employee_event.dart';
import '../bloc/employee_state.dart';
import '../widgets/employee_info_card.dart';
import '../widgets/face_image_gallery.dart';

class EmployeeDetailPage extends StatefulWidget {
  final String employeeId;

  const EmployeeDetailPage({
    super.key,
    required this.employeeId,
  });

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  late final EmployeeBloc _employeeBloc;
  Employee? _employee;

  @override
  void initState() {
    super.initState();
    _employeeBloc = getIt<EmployeeBloc>();
    _loadEmployeeDetail();
  }

  void _loadEmployeeDetail() {
    _employeeBloc.add(LoadEmployeeDetail(widget.employeeId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _employeeBloc,
      child: BlocListener<EmployeeBloc, EmployeeState>(
        listener: (context, state) {
          if (state is EmployeeDetailLoaded) {
            setState(() {
              _employee = state.employee;
            });
          } else if (state is EmployeeError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          } else if (state is FaceImageAdded) {
            _loadEmployeeDetail(); // Reload to show new image
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Face image added successfully'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is FaceImageDeleted) {
            _loadEmployeeDetail(); // Reload after deletion
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Face image removed'),
              ),
            );
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_employee?.name ?? 'Employee Detail'),
            elevation: 0,
            backgroundColor: Theme.of(context).colorScheme.surface,
            actions: [
              if (_employee != null)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadEmployeeDetail,
                  tooltip: 'Refresh',
                ),
            ],
          ),
          body: BlocBuilder<EmployeeBloc, EmployeeState>(
            builder: (context, state) {
              if (state is EmployeeLoading || _employee == null) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  _loadEmployeeDetail();
                  // Wait for the state to update
                  await Future.delayed(const Duration(seconds: 1));
                },
                child: CustomScrollView(
                  slivers: [
                    // Employee Info Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: EmployeeInfoCard(employee: _employee!),
                      ),
                    ),

                    // Face Encodings Summary
                    SliverToBoxAdapter(
                      child: _buildFaceEncodingsSummary(),
                    ),

                    // Additional Face Images Section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Face Images',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              '${_employee!.faceEncodings.length} image${_employee!.faceEncodings.length != 1 ? 's' : ''}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Face Image Gallery
                    SliverPadding(
                      padding: const EdgeInsets.all(16.0),
                      sliver: FaceImageGallery(
                        employee: _employee!,
                        onDeleteImage: (encodingId) {
                          _showDeleteConfirmation(encodingId);
                        },
                      ),
                    ),

                    // Add some bottom padding
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 100),
                    ),
                  ],
                ),
              );
            },
          ),
          floatingActionButton: _employee != null
              ? FloatingActionButton.extended(
                  onPressed: () {
                    // Navigate to camera screen for adding face image
                    context.push('/employees/${widget.employeeId}/add-face').then((result) {
                      if (result == true) {
                        _loadEmployeeDetail();
                      }
                    });
                  },
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add Face Image'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildFaceEncodingsSummary() {
    if (_employee == null) return const SizedBox.shrink();

    final hasMainPhoto = _employee!.photoBytes != null;
    final encodingsCount = _employee!.faceEncodings.length;
    final averageQuality = encodingsCount > 0
        ? _employee!.faceEncodings
                .map((e) => e.quality)
                .reduce((a, b) => a + b) /
            encodingsCount
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                context,
                icon: Icons.photo_camera,
                value: hasMainPhoto ? 'Yes' : 'No',
                label: 'Main Photo',
                color: hasMainPhoto ? Colors.green : Colors.orange,
              ),
              _buildStatItem(
                context,
                icon: Icons.face,
                value: encodingsCount.toString(),
                label: 'Face Encodings',
                color: encodingsCount > 0 ? Colors.green : Colors.red,
              ),
              _buildStatItem(
                context,
                icon: Icons.high_quality,
                value: '${(averageQuality * 100).toStringAsFixed(0)}%',
                label: 'Avg Quality',
                color: averageQuality > 0.7 ? Colors.green : Colors.orange,
              ),
            ],
          ),
          if (encodingsCount == 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No face encodings available. Add face images to enable recognition.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
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

  void _showDeleteConfirmation(String encodingId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Face Image'),
          content: const Text(
            'Are you sure you want to remove this face image? This will affect recognition accuracy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _employeeBloc.add(DeleteFaceImage(
                  employeeId: widget.employeeId,
                  encodingId: encodingId,
                ));
              },
              child: Text(
                'Remove',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}