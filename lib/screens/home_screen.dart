import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart'; 
import '../services/vision_service.dart';
import '../services/guardian_service.dart';
import '../services/safety_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GuardianService _guardianService = GuardianService();
  final VisionService _visionService = VisionService();
  final SafetyManager _safetyManager = SafetyManager();
  
  CameraController? _cameraController;
  Timer? _visionTimer;
  
  bool isMonitoring = false;
  String statusMessage = "Initializing...";
  Color statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    
    // Auto-Start after 2 seconds (Blind Friendly)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !isMonitoring) {
        toggleMonitoring(); 
      }
    });
  }

  Future<void> _initializeCamera() async {
      if (cameras.isEmpty) return;
    
      // CHANGED FROM .low TO .high (1080p) or .max (4K if supported)
      _cameraController = CameraController(cameras[0], ResolutionPreset.high);
    
      await _cameraController!.initialize();
      if (mounted) setState(() {});
  }

  void toggleMonitoring() {
    setState(() {
      isMonitoring = !isMonitoring;
    });

    if (isMonitoring) {
      _safetyManager.startSystem(context);
      
      _visionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _analyzeScene();
      });
      
      setState(() {
        statusMessage = "Guardian Active\nDrop Phone on Bed to Test";
        statusColor = Colors.green;
      });
    } else {
      _safetyManager.stopSystem();
      _visionTimer?.cancel();
      setState(() {
        statusMessage = "Guardian Paused";
        statusColor = Colors.orange;
      });
    }
  }

  Future<void> _analyzeScene() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final image = await _cameraController!.takePicture();
      final result = await _visionService.analyzeImage(image.path);
      _safetyManager.handleVisionResult(result);
    } catch (e) {
      print("Vision Error: $e");
    }
  }

  @override
  void dispose() {
    _safetyManager.stopSystem();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Project S.E.E.")),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _cameraController != null && _cameraController!.value.isInitialized
                ? CameraPreview(_cameraController!)
                : const Center(child: Text("Loading Eyes...")),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}