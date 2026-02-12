import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Search bar widget for filtering chat history
class ChatSearchBar extends StatefulWidget {
  final Function(String) onSearch;
  final VoidCallback? onClear;

  const ChatSearchBar({
    super.key,
    required this.onSearch,
    this.onClear,
  });

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _hasText = value.isNotEmpty;
    });
    widget.onSearch(value);
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _hasText = false;
    });
    widget.onSearch('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
          suffixIcon: _hasText
              ? IconButton(
                  icon: Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: _clear,
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
    );
  }
}

/// Mixin for adding search functionality to chat history
mixin ChatSearchMixin<T extends StatefulWidget> on State<T> {
  String _searchQuery = '';
  
  String get searchQuery => _searchQuery;

  /// Filter topics by search query
  List<Map<String, dynamic>> filterTopics(
    List<Map<String, dynamic>> topics,
    String query,
  ) {
    if (query.isEmpty) return topics;
    
    final lowerQuery = query.toLowerCase();
    return topics.where((topic) {
      final firstMessage = topic['firstMessage']?.toString().toLowerCase() ?? '';
      return firstMessage.contains(lowerQuery);
    }).toList();
  }

  /// Filter messages by search query
  List<Map<String, dynamic>> filterMessages(
    List<Map<String, dynamic>> messages,
    String query,
  ) {
    if (query.isEmpty) return messages;
    
    final lowerQuery = query.toLowerCase();
    return messages.where((msg) {
      final text = msg['text']?.toString().toLowerCase() ?? '';
      return text.contains(lowerQuery);
    }).toList();
  }

  void updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
    });
  }
}
