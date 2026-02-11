import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../services/vibration_service.dart';

/// Test page for vibration patterns
class VibrationTestScreen extends StatefulWidget {
  const VibrationTestScreen({super.key});

  @override
  State<VibrationTestScreen> createState() => _VibrationTestScreenState();
}

class _VibrationTestScreenState extends State<VibrationTestScreen> {
  final VibrationService _vibrationService = VibrationService();
  bool _hasVibrator = false;
  bool _hasAmplitudeControl = false;
  String _lastAction = '点击按钮测试振动';
  
  @override
  void initState() {
    super.initState();
    _checkVibrationCapabilities();
  }
  
  Future<void> _checkVibrationCapabilities() async {
    await _vibrationService.initialize();
    
    final hasVibrator = await Vibration.hasVibrator() ?? false;
    final hasAmplitude = await Vibration.hasAmplitudeControl() ?? false;
    
    setState(() {
      _hasVibrator = hasVibrator;
      _hasAmplitudeControl = hasAmplitude;
    });
  }
  
  void _updateStatus(String action) {
    setState(() {
      _lastAction = action;
    });
    debugPrint('🔔 $action');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('振动强度测试'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('设备信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('振动器: ${_hasVibrator ? "✅ 支持" : "❌ 不支持"}'),
                    Text('振幅控制: ${_hasAmplitudeControl ? "✅ 支持" : "❌ 不支持"}'),
                    const SizedBox(height: 8),
                    Text('上次操作: $_lastAction', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // HapticFeedback tests
            const Text('HapticFeedback (系统)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildTestButton(
                    '轻',
                    Colors.green,
                    () async {
                      _updateStatus('HapticFeedback.lightImpact()');
                      await HapticFeedback.lightImpact();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '中',
                    Colors.orange,
                    () async {
                      _updateStatus('HapticFeedback.mediumImpact()');
                      await HapticFeedback.mediumImpact();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '重',
                    Colors.red,
                    () async {
                      _updateStatus('HapticFeedback.heavyImpact()');
                      await HapticFeedback.heavyImpact();
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Vibration plugin tests
            const Text('Vibration 插件 (时长)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildTestButton(
                    '50ms',
                    Colors.green,
                    () async {
                      _updateStatus('Vibration 50ms');
                      await Vibration.vibrate(duration: 50);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '200ms',
                    Colors.orange,
                    () async {
                      _updateStatus('Vibration 200ms');
                      await Vibration.vibrate(duration: 200);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '500ms',
                    Colors.red,
                    () async {
                      _updateStatus('Vibration 500ms');
                      await Vibration.vibrate(duration: 500);
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Amplitude tests (if supported)
            const Text('Vibration 插件 (振幅)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildTestButton(
                    '低 (64)',
                    Colors.green,
                    () async {
                      _updateStatus('Amplitude 64 (低)');
                      await Vibration.vibrate(duration: 300, amplitude: 64);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '中 (128)',
                    Colors.orange,
                    () async {
                      _updateStatus('Amplitude 128 (中)');
                      await Vibration.vibrate(duration: 300, amplitude: 128);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '高 (255)',
                    Colors.red,
                    () async {
                      _updateStatus('Amplitude 255 (高)');
                      await Vibration.vibrate(duration: 300, amplitude: 255);
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Pattern tests
            const Text('振动模式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            _buildTestButton(
              '远距离模式 (单次轻振)',
              Colors.green.shade700,
              () async {
                _updateStatus('远距离: 单次轻振');
                await Vibration.vibrate(duration: 100, amplitude: 64);
              },
              fullWidth: true,
            ),
            
            const SizedBox(height: 8),
            
            _buildTestButton(
              '中距离模式 (两次中振)',
              Colors.orange.shade700,
              () async {
                _updateStatus('中距离: 两次中振');
                await Vibration.vibrate(pattern: [0, 150, 100, 150], intensities: [0, 128, 0, 128]);
              },
              fullWidth: true,
            ),
            
            const SizedBox(height: 8),
            
            _buildTestButton(
              '近距离模式 (连续重振)',
              Colors.red.shade700,
              () async {
                _updateStatus('近距离: 连续重振');
                await Vibration.vibrate(pattern: [0, 200, 80, 200, 80, 200], intensities: [0, 255, 0, 255, 0, 255]);
              },
              fullWidth: true,
            ),
            
            const SizedBox(height: 8),
            
            _buildTestButton(
              '危险模式 (快速连续)',
              Colors.purple.shade700,
              () async {
                _updateStatus('危险: 快速连续振动');
                await Vibration.vibrate(pattern: [0, 100, 50, 100, 50, 100, 50, 100], intensities: [0, 255, 0, 255, 0, 255, 0, 255]);
              },
              fullWidth: true,
            ),
            
            const SizedBox(height: 24),
            
            // Test with VibrationService
            const Text('通过 VibrationService 测试', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildTestButton(
                    '10% 近',
                    Colors.green,
                    () async {
                      _updateStatus('VibrationService proximity=0.1');
                      await _vibrationService.vibrateForProximity(0.1);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '50% 中',
                    Colors.orange,
                    () async {
                      _updateStatus('VibrationService proximity=0.5');
                      await _vibrationService.vibrateForProximity(0.5);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTestButton(
                    '90% 远',
                    Colors.red,
                    () async {
                      _updateStatus('VibrationService proximity=0.9');
                      await _vibrationService.vibrateForProximity(0.9);
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            _buildTestButton(
              '紧急警告',
              Colors.deepPurple,
              () async {
                _updateStatus('VibrationService.emergencyWarning()');
                await _vibrationService.emergencyWarning();
              },
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTestButton(String label, Color color, VoidCallback onPressed, {bool fullWidth = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
