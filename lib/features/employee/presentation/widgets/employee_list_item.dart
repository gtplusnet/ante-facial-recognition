import 'package:flutter/material.dart';

import '../../domain/entities/employee.dart';

class EmployeeListItem extends StatelessWidget {
  final Employee employee;
  final VoidCallback? onTap;
  final VoidCallback? onGenerateEmbedding;

  const EmployeeListItem({
    super.key,
    required this.employee,
    this.onTap,
    this.onGenerateEmbedding,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildAvatar(context),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEmployeeInfo(context),
              ),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final hasPhoto = employee.photoBytes != null;
    final hasEmbedding = employee.hasFaceEncodings;

    return Stack(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: hasPhoto
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceVariant,
          backgroundImage: hasPhoto && employee.photoBytes != null
              ? MemoryImage(employee.photoBytes!)
              : null,
          child: !hasPhoto
              ? Text(
                  employee.name.isNotEmpty
                      ? employee.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: hasEmbedding
                    ? Theme.of(context).colorScheme.primary
                    : hasPhoto
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.outline,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasEmbedding
                    ? Icons.check
                    : hasPhoto
                        ? Icons.face
                        : Icons.close,
                size: 10,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          employee.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
        const SizedBox(height: 2),
        if (employee.employeeCode != null)
          Text(
            'ID: ${employee.employeeCode}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        if (employee.department != null || employee.position != null)
          Text(
            [employee.department, employee.position]
                .where((e) => e != null)
                .join(' • '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildStatusChip(
              context,
              icon: Icons.photo_camera,
              label: 'Photo',
              active: employee.hasPhoto,
            ),
            const SizedBox(width: 8),
            _buildStatusChip(
              context,
              icon: Icons.face,
              label: 'Face',
              active: employee.hasFaceEncodings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (employee.hasPhoto && !employee.hasFaceEncodings) {
      return IconButton(
        icon: Icon(
          Icons.face_retouching_natural,
          color: Theme.of(context).colorScheme.primary,
        ),
        onPressed: onGenerateEmbedding,
        tooltip: 'Generate Face Embedding',
      );
    }

    if (!employee.isActive) {
      return Icon(
        Icons.block,
        color: Theme.of(context).colorScheme.error,
        size: 20,
      );
    }

    return Icon(
      Icons.chevron_right,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}