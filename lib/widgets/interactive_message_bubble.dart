import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme.dart';

/// Interactive chat message bubble with accessibility features.
///
/// Supports:
/// - Tap to read aloud (AI messages only)
/// - Long-press to copy text
/// - Swipe to delete
/// - Tap image to zoom
class InteractiveMessageBubble extends StatelessWidget {
  final String role;
  final String text;
  final Uint8List? imageBytes;
  final String? imageUrl; // <--- Add this
  final VoidCallback? onTapReadAloud;
  final VoidCallback? onDelete;
  final VoidCallback? onImageTap;

  const InteractiveMessageBubble({
    super.key,
    required this.role,
    required this.text,
    this.imageBytes,
    this.imageUrl, // <--- Add this
    this.onTapReadAloud,
    this.onDelete,
    this.onImageTap,
  });

  bool get _isUser => role == 'user';
  bool get _isSystem => role == 'system';
  bool get _isModel => role == 'model';

  @override
  Widget build(BuildContext context) {
    final bubble = _buildBubble(context);
    return onDelete != null ? _wrapWithDismissible(context, bubble) : bubble;
  }

  Widget _buildBubble(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyToClipboard(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: _getDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageBytes != null || imageUrl != null) _buildImage(),
              if (text.isNotEmpty) _buildText(),
              if (_isModel && onTapReadAloud != null) _buildReadAloudButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Semantics(
      label: 'Image attachment, tap to open fullscreen',
      button: true,
      child: GestureDetector(
        onTap: onImageTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child:
                imageBytes != null
                    ? Image.memory(
                      imageBytes!,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                    )
                    : Image.network(
                      imageUrl!,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey[200],
                          alignment: Alignment.center,
                          child: CircularProgressIndicator(
                            value:
                                loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                          ),
                        );
                      },
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    return Text(text, style: _getTextStyle());
  }

  Widget _buildReadAloudButton() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        label: 'Read this message aloud',
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTapReadAloud,
            borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 32,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Read Aloud',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapWithDismissible(BuildContext context, Widget child) {
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete?.call(),
      child: child,
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Delete Message?'),
                content: const Text('This action cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  void _copyToClipboard(BuildContext context) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  BoxDecoration _getDecoration() {
    if (_isUser) return AppDecorations.userBubble;
    if (_isSystem) return AppDecorations.systemBubble;
    return AppDecorations.aiBubble;
  }

  TextStyle _getTextStyle() {
    if (_isUser) {
      return AppTextStyles.chatMessage.copyWith(
        color: AppColors.userBubbleText,
      );
    }
    if (_isSystem) {
      return AppTextStyles.systemMessage.copyWith(
        color: AppColors.systemBubbleText,
      );
    }
    return AppTextStyles.chatMessage.copyWith(color: AppColors.aiBubbleText);
  }
}

/// Fullscreen image viewer with pinch-to-zoom.
class ImageViewerDialog extends StatelessWidget {
  final Uint8List imageBytes;

  const ImageViewerDialog({super.key, required this.imageBytes});

  static void show(BuildContext context, Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (_) => ImageViewerDialog(imageBytes: imageBytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              tooltip: 'Close fullscreen image',
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
