import 'package:flutter/foundation.dart';
import '../models/obstacle_info.dart';
import 'text_recognition_service.dart';
import 'image_labeling_service.dart';

/// Aggregates context from multiple ML Kit APIs
/// Generates natural language descriptions for blind user
class ContextAggregatorService {
  // Timing control
  DateTime _lastContextUpdate = DateTime.now();
  String _lastContextSummary = '';
  
  // Minimum interval between full context updates (seconds)
  static const int _updateIntervalSeconds = 3;
  
  /// Generate a context summary from all available data
  ContextSummary aggregate({
    List<ObstacleInfo>? obstacles,
    List<RecognizedTextBlock>? textBlocks,
    List<DetectedLabel>? labels,
  }) {
    final parts = <String>[];
    
    // Process obstacles (from Object Detection)
    if (obstacles != null && obstacles.isNotEmpty) {
      final closest = obstacles.reduce((a, b) => 
        a.relativeSize > b.relativeSize ? a : b);
      
      final distance = _getDistanceDescription(closest.relativeSize);
      parts.add('${closest.label} $distance on your ${closest.position}');
      
      if (obstacles.length > 1) {
        parts.add('${obstacles.length - 1} other objects nearby');
      }
    }
    
    // Process text (from Text Recognition)
    if (textBlocks != null && textBlocks.isNotEmpty) {
      final importantText = textBlocks
          .where((t) => _isImportantText(t.text))
          .take(3)
          .map((t) => '"${t.text}"')
          .join(', ');
      
      if (importantText.isNotEmpty) {
        parts.add('Text visible: $importantText');
      }
    }
    
    // Process labels (from Image Labeling)
    if (labels != null && labels.isNotEmpty) {
      final labelList = labels.take(3).map((l) => l.label).join(', ');
      parts.add('Scene contains: $labelList');
    }
    
    // Generate summaries
    final summary = parts.isEmpty 
        ? 'Clear path ahead' 
        : parts.join('. ');
    
    // Determine priority for feedback
    final priority = _determinePriority(obstacles, textBlocks);
    
    return ContextSummary(
      summary: summary,
      priority: priority,
      hasObstacles: obstacles?.isNotEmpty ?? false,
      hasText: textBlocks?.isNotEmpty ?? false,
      hasLabels: labels?.isNotEmpty ?? false,
    );
  }
  
  /// Check if enough time has passed for a new context update
  bool shouldUpdate() {
    final now = DateTime.now();
    return now.difference(_lastContextUpdate).inSeconds >= _updateIntervalSeconds;
  }
  
  /// Mark that we've done an update
  void markUpdated(String summary) {
    _lastContextUpdate = DateTime.now();
    _lastContextSummary = summary;
  }
  
  /// Check if the new context is significantly different
  bool isSignificantChange(String newSummary) {
    if (_lastContextSummary.isEmpty) return true;
    
    // Simple change detection - could be improved with NLP
    return newSummary != _lastContextSummary;
  }
  
  String _getDistanceDescription(double relativeSize) {
    if (relativeSize > 0.25) return 'very close';
    if (relativeSize > 0.15) return 'close';
    if (relativeSize > 0.05) return 'nearby';
    return 'in the distance';
  }
  
  bool _isImportantText(String text) {
    // Filter out very short or likely noise
    if (text.length < 2) return false;
    
    // Check for important keywords
    final lowerText = text.toLowerCase();
    final importantKeywords = [
      'exit', 'enter', 'stop', 'danger', 'warning', 'caution',
      'toilet', 'restroom', 'room', 'floor', 'level',
      'open', 'closed', 'push', 'pull',
      'left', 'right', 'up', 'down',
    ];
    
    for (final keyword in importantKeywords) {
      if (lowerText.contains(keyword)) return true;
    }
    
    // Numbers (room numbers, floor numbers)
    if (RegExp(r'\d+').hasMatch(text)) return true;
    
    // If text is reasonably sized, include it
    return text.length >= 3;
  }
  
  ContextPriority _determinePriority(
    List<ObstacleInfo>? obstacles,
    List<RecognizedTextBlock>? textBlocks,
  ) {
    // Very close obstacle = high priority
    if (obstacles != null && obstacles.isNotEmpty) {
      final closest = obstacles.reduce((a, b) => 
        a.relativeSize > b.relativeSize ? a : b);
      
      if (closest.relativeSize > 0.15) {
        return ContextPriority.high;
      }
    }
    
    // Important text = medium priority
    if (textBlocks != null && textBlocks.isNotEmpty) {
      final hasImportant = textBlocks.any((t) => _isImportantText(t.text));
      if (hasImportant) {
        return ContextPriority.medium;
      }
    }
    
    return ContextPriority.low;
  }
}

/// Priority levels for context announcements
enum ContextPriority {
  high,   // Vibrate + speak immediately
  medium, // Speak when convenient
  low,    // Optional, user can query
}

/// Aggregated context summary
class ContextSummary {
  final String summary;
  final ContextPriority priority;
  final bool hasObstacles;
  final bool hasText;
  final bool hasLabels;
  
  ContextSummary({
    required this.summary,
    required this.priority,
    required this.hasObstacles,
    required this.hasText,
    required this.hasLabels,
  });
  
  @override
  String toString() => summary;
}
