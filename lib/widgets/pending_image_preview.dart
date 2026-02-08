import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Pending image preview shown before sending a message with an image.
class PendingImagePreview extends StatelessWidget {
  final Uint8List imageBytes;
  final VoidCallback onClear;

  const PendingImagePreview({
    super.key,
    required this.imageBytes,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.surface,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Image.memory(
              imageBytes,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Image attached. Type a message or tap send.',
              style: AppTextStyles.bodySmall,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.error),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
