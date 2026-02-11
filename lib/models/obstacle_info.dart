/// Represents detected obstacle information for context aggregation
class ObstacleInfo {
  final String label;
  final String position;
  final double relativeSize;
  
  ObstacleInfo({
    required this.label,
    required this.position,
    required this.relativeSize,
  });
  
  @override
  String toString() => '$label ($position, ${(relativeSize * 100).toStringAsFixed(1)}%)';
}
