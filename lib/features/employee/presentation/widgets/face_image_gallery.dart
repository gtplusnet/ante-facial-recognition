import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/entities/employee.dart';

class FaceImageGallery extends StatelessWidget {
  final Employee employee;
  final Function(String encodingId) onDeleteImage;

  const FaceImageGallery({
    super.key,
    required this.employee,
    required this.onDeleteImage,
  });

  @override
  Widget build(BuildContext context) {
    // Filter encodings to only show those with actual image data
    final encodingsWithImages = employee.faceEncodings.where((encoding) {
      // Only show encodings that have image bytes stored
      return encoding.imageBytes != null;
    }).toList();

    if (encodingsWithImages.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(context),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final encoding = encodingsWithImages[index];
          return FaceImageItem(
            encoding: encoding,
            imageData: _getImageDataForEncoding(encoding),
            isMainImage: false, // Don't mark any as main since these are camera captures
            onTap: () => _showImageDetail(context, encoding),
            onDelete: () => onDeleteImage(encoding.id),
          );
        },
        childCount: encodingsWithImages.length,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo,
              size: 48,
              color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No face images yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add face images to enable recognition',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Uint8List? _getImageDataForEncoding(FaceEncoding encoding) {
    // Use the image bytes stored with the encoding
    if (encoding.imageBytes != null) {
      return encoding.imageBytes;
    }
    // Fallback to main photo if it's the first encoding
    if (employee.faceEncodings.indexOf(encoding) == 0 && employee.photoBytes != null) {
      return employee.photoBytes;
    }
    return null;
  }

  void _showImageDetail(BuildContext context, FaceEncoding encoding) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Image
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _getImageDataForEncoding(encoding) != null
                    ? Image.memory(
                        _getImageDataForEncoding(encoding)!,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Center(
                          child: Icon(
                            Icons.face,
                            size: 100,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
              ),
            ),
            // Close button
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
            // Quality info
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Quality: ${(encoding.quality * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Source: ${encoding.source ?? 'Unknown'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: encoding.quality,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        encoding.quality > 0.7 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FaceImageItem extends StatelessWidget {
  final FaceEncoding encoding;
  final Uint8List? imageData;
  final bool isMainImage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const FaceImageItem({
    super.key,
    required this.encoding,
    required this.imageData,
    required this.isMainImage,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final qualityColor = encoding.quality > 0.8
        ? Colors.green
        : encoding.quality > 0.6
            ? Colors.orange
            : Colors.red;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          // Image container
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: imageData != null
                  ? Image.memory(
                      imageData!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Center(
                        child: Icon(
                          Icons.face,
                          size: 40,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
            ),
          ),
          // Main image badge
          if (isMainImage)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'MAIN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          // Quality indicator
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.high_quality,
                    size: 12,
                    color: qualityColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${(encoding.quality * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: qualityColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Delete button (not for main image)
          if (!isMainImage)
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}