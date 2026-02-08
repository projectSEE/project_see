import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../theme/theme.dart';

/// Reusable chat message bubble widget.
/// Handles user, AI, and system message styling automatically.
class MessageBubble extends StatelessWidget {
  final String role;
  final String text;
  final Uint8List? imageBytes;

  const MessageBubble({
    super.key,
    required this.role,
    required this.text,
    this.imageBytes,
  });

  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';
  bool get isModel => role == 'model';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: _getDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Image.memory(
                    imageBytes!,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (text.isNotEmpty)
              Text(
                text,
                style: _getTextStyle(),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _getDecoration() {
    if (isUser) {
      return AppDecorations.userBubble;
    } else if (isSystem) {
      return AppDecorations.systemBubble;
    } else {
      return AppDecorations.aiBubble;
    }
  }

  TextStyle _getTextStyle() {
    if (isUser) {
      return AppTextStyles.chatMessage.copyWith(color: AppColors.userBubbleText);
    } else if (isSystem) {
      return AppTextStyles.systemMessage.copyWith(color: AppColors.systemBubbleText);
    } else {
      return AppTextStyles.chatMessage.copyWith(color: AppColors.aiBubbleText);
    }
  }
}
