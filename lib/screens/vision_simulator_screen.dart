import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

class VisionSimulatorScreen extends StatefulWidget {
  const VisionSimulatorScreen({super.key});

  @override
  State<VisionSimulatorScreen> createState() => _VisionSimulatorScreenState();
}

class _VisionSimulatorScreenState extends State<VisionSimulatorScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  String _currentMode = "Glaucoma";
  double _splitPosition = 0.5; // 0.0 to 1.0
  final LanguageNotifier _langNotifier = LanguageNotifier();

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_onLangChanged);
    _initializeCamera();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.high);
    await _controller!.initialize();
    if (mounted) setState(() => _isCameraInitialized = true);
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_onLangChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    if (!_isCameraInitialized) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final double splitX = screenWidth * _splitPosition;
    final bool hideLine = _splitPosition > 0.5;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // LAYER 1: Single clean camera preview (full screen — always clear)
          CameraPreview(_controller!),

          // LAYER 2: Vision filter positioned to RIGHT side only
          Positioned(
            left: splitX,
            top: 0,
            right: 0,
            bottom: 0,
            child: _buildVisionFilter(),
          ),

          // Label for Normal Side
          Positioned(
            top: 50,
            left: 10,
            child: Chip(
              label: Text(
                strings.get('normalVision'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              backgroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          ),

          // Label for Impaired Side
          Positioned(
            top: 50,
            right: 10,
            child: Chip(
              label: Text(
                _currentMode.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              backgroundColor: Colors.black, // From the merged code styling
              visualDensity: VisualDensity.compact,
            ),
          ),

          // LAYER 3: The Slider Handle
          Positioned(
            left: splitX - 25,
            top: 0,
            bottom: 0,
            child: Semantics(
              label: 'Adjust vision split slider',
              slider: true,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitPosition += details.delta.dx / screenWidth;
                    _splitPosition = _splitPosition.clamp(0.0, 1.0);
                  });
                },
                child: Container(
                  width: 50,
                  color: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          width: 2,
                          color: hideLine ? Colors.transparent : Colors.white70,
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            const BoxShadow(
                              blurRadius: 8,
                              color: Colors.black45,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.chevron_left,
                              size: 20,
                              color: Colors.black,
                            ),
                            Text(
                              strings.get('slide'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: hideLine ? Colors.transparent : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Full-screen drag detector (so dragging works anywhere)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _splitPosition += details.delta.dx / screenWidth;
                  _splitPosition = _splitPosition.clamp(0.0, 1.0);
                });
              },
            ),
          ),

          // LAYER 4: Mode Selector
          Positioned(
            bottom: 30,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  _buildModeBtn(
                    strings.get('glaucoma'),
                    Colors.black,
                    "Glaucoma",
                  ),
                  _buildModeBtn(
                    strings.get('cataracts'),
                    Colors.black,
                    "Cataracts",
                  ),
                  _buildModeBtn(
                    strings.get('retinopathy'),
                    Colors.black,
                    "Retinopathy",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisionFilter() {
    if (_currentMode == "Glaucoma") {
      return Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Colors.transparent, Colors.black],
            stops: [0.2, 0.7],
            radius: 0.9,
          ),
        ),
      );
    } else if (_currentMode == "Cataracts") {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.white.withValues(alpha: 0.45)),
          Container(color: Colors.yellow.withValues(alpha: 0.08)),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.35),
                ],
                stops: const [0.3, 1.0],
                radius: 1.2,
              ),
            ),
          ),
        ],
      );
    } else if (_currentMode == "Retinopathy") {
      return CustomPaint(painter: RetinopathyPainter(), child: Container());
    }
    return const SizedBox.shrink();
  }

  // UPDATED BUTTON BUILDER: Uses Expanded to fit perfectly
  Widget _buildModeBtn(String label, Color color, String modeKey) {
    bool isSelected = _currentMode == modeKey;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: () => setState(() => _currentMode = modeKey),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class RetinopathyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.7)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final random = Random(42);
    for (int i = 0; i < 20; i++) {
      double x = random.nextDouble() * size.width;
      double y = random.nextDouble() * size.height;
      double radius = random.nextDouble() * 40 + 20;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
