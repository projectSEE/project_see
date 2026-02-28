import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
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
    if (!_isCameraInitialized)
      return const Scaffold(backgroundColor: Colors.black);

    bool hideLine = _splitPosition > 0.5;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // LAYER 1: Impaired Vision (Background)
          CameraPreview(_controller!),
          _buildVisionFilter(),

          // LAYER 2: Normal Vision (Foreground - Left Side)
          ClipRect(
            clipper: _SplitClipper(_splitPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),
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
              ],
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
              backgroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
            ),
          ),

          // LAYER 3: The "Bar" Slider Handle
          LayoutBuilder(
            builder: (context, constraints) {
              double position = constraints.maxWidth * _splitPosition;
              return Positioned(
                left: position - 25, // Center the 50px wide bar
                top: 0,
                bottom: 0,
                child: Semantics(
                  label: 'Adjust vision split slider',
                  slider: true,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _splitPosition +=
                            details.delta.dx / constraints.maxWidth;
                        _splitPosition = _splitPosition.clamp(0.0, 1.0);
                      });
                    },
                    child: Container(
                      width: 50, // Wide touch area
                      color: Colors.transparent,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Top Line
                          Expanded(
                            child: Container(
                              width: 2,
                              color:
                                  hideLine
                                      ? Colors.transparent
                                      : Colors.white70,
                            ),
                          ),

                          // THE NEW HANDLE: Horizontal Bar with Arrows
                          Container(
                            height: 40,
                            width:
                                80, // Wider than the touch column to look like a bar
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

                          // Bottom Line
                          Expanded(
                            child: Container(
                              width: 2,
                              color:
                                  hideLine
                                      ? Colors.transparent
                                      : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // LAYER 4: Mode Selector (Perfectly Fitted)
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
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        // FIXED: .withOpacity() is deprecated, using .withValues() instead
        child: Container(color: Colors.white.withValues(alpha: 0.1)),
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
          // FIXED: .withOpacity() is deprecated, using .withValues() instead
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

class _SplitClipper extends CustomClipper<Rect> {
  final double splitFactor;
  _SplitClipper(this.splitFactor);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * splitFactor, size.height);

  @override
  bool shouldReclip(_SplitClipper oldClipper) =>
      splitFactor != oldClipper.splitFactor;
}
