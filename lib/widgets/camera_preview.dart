import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/ml_kit_service.dart';

/// Camera preview widget with obstacle overlay
class CameraPreviewWidget extends StatelessWidget {
  final CameraController controller;
  final List<DetectedObstacle> obstacles;

  const CameraPreviewWidget({
    super.key,
    required this.controller,
    required this.obstacles,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: CameraPreview(controller),
        ),
        
        // Obstacle overlay
        if (obstacles.isNotEmpty)
          CustomPaint(
            painter: ObstacleOverlayPainter(
              obstacles: obstacles,
              previewSize: controller.value.previewSize ?? const Size(480, 640),
            ),
          ),
        
        // Status indicator
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    obstacles.isEmpty ? 'Scanning...' : '${obstacles.length} detected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for drawing obstacle bounding boxes
class ObstacleOverlayPainter extends CustomPainter {
  final List<DetectedObstacle> obstacles;
  final Size previewSize;

  ObstacleOverlayPainter({
    required this.obstacles,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final obstacle in obstacles) {
      // Determine color based on proximity
      Color boxColor;
      if (obstacle.isVeryClose) {
        boxColor = Colors.red;
      } else if (obstacle.isClose) {
        boxColor = Colors.orange;
      } else {
        boxColor = Colors.green;
      }

      final paint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // Scale bounding box to screen size
      final scaleX = size.width / previewSize.height;
      final scaleY = size.height / previewSize.width;

      final scaledRect = Rect.fromLTRB(
        obstacle.boundingBox.left * scaleX,
        obstacle.boundingBox.top * scaleY,
        obstacle.boundingBox.right * scaleX,
        obstacle.boundingBox.bottom * scaleY,
      );

      // Draw rounded rectangle
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(8)),
        paint,
      );

      // Draw label background
      final labelPaint = Paint()
        ..color = boxColor.withAlpha(200);
      
      final labelRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - 28,
        scaledRect.width.clamp(80, 200),
        26,
      );
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        labelPaint,
      );

      // Draw label text
      final textPainter = TextPainter(
        text: TextSpan(
          text: obstacle.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: labelRect.width - 8);
      textPainter.paint(
        canvas,
        Offset(labelRect.left + 4, labelRect.top + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ObstacleOverlayPainter oldDelegate) {
    return obstacles != oldDelegate.obstacles;
  }
}
