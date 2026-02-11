import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Service for haptic feedback with fallback to Flutter HapticFeedback
class VibrationService {
  bool _hasVibrator = false;
  bool _hasAmplitudeControl = false;
  DateTime _lastVibration = DateTime.now();
  bool _useFlutterHaptics = false;

  /// Initialize vibration service
  Future<void> initialize() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      _hasVibrator = hasVibrator == true;
      
      if (_hasVibrator) {
        final hasAmplitude = await Vibration.hasAmplitudeControl();
        _hasAmplitudeControl = hasAmplitude == true;
      }
      
      debugPrint('✅ Vibration: hasVibrator=$_hasVibrator, hasAmplitude=$_hasAmplitudeControl');
      
      // Test vibration
      if (_hasVibrator) {
        await Vibration.vibrate(duration: 200);
        debugPrint('📳 Test vibration sent via Vibration plugin');
      }
    } catch (e) {
      debugPrint('⚠️ Vibration plugin error: $e, falling back to HapticFeedback');
      _useFlutterHaptics = true;
      _hasVibrator = true; // Assume device has vibrator, use haptics
      
      // Test haptic feedback
      await HapticFeedback.heavyImpact();
      debugPrint('📳 Test vibration sent via HapticFeedback');
    }
  }

  /// Vibrate based on proximity (0.0 = far, 1.0 = very close)
  /// intensityBoost: 0.0-0.5 extra boost for approaching objects
  Future<void> vibrateForProximity(double proximity, {double intensityBoost = 0.0}) async {
    if (!_hasVibrator) {
      debugPrint('⚠️ No vibrator!');
      return;
    }
    
    // Throttle vibrations (reduce to 300ms for more responsive feedback)
    final now = DateTime.now();
    if (now.difference(_lastVibration).inMilliseconds < 300) {
      return;
    }
    
    // Apply intensity boost for approaching objects
    final effectiveProximity = (proximity + intensityBoost).clamp(0.0, 1.0);

    debugPrint('📳 Proximity: ${(proximity * 100).toStringAsFixed(1)}% (boost: ${(intensityBoost * 100).toStringAsFixed(0)}%)');

    try {
      if (effectiveProximity > 0.10) {
        // Very close or approaching - strong vibration
        _lastVibration = now;
        await _vibrateHeavy();
        debugPrint('📳 STRONG vibration triggered!');
      } else if (effectiveProximity > 0.05) {
        // Close - medium vibration  
        _lastVibration = now;
        await _vibrateMedium();
        debugPrint('📳 MEDIUM vibration triggered!');
      } else if (effectiveProximity > 0.01) {
        // Any detection - light vibration
        _lastVibration = now;
        await _vibrateLight();
        debugPrint('📳 LIGHT vibration triggered!');
      } else {
        debugPrint('📳 Too small to vibrate: ${(effectiveProximity * 100).toStringAsFixed(2)}%');
      }
    } catch (e) {
      debugPrint('❌ Vibration error: $e');
    }
  }

  Future<void> _vibrateHeavy() async {
    // Always use HapticFeedback since Vibration plugin doesn't work on all devices
    debugPrint('📳 _vibrateHeavy - using HapticFeedback');
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  Future<void> _vibrateMedium() async {
    debugPrint('📳 _vibrateMedium - using HapticFeedback');
    await HapticFeedback.mediumImpact();
  }

  Future<void> _vibrateLight() async {
    debugPrint('📳 _vibrateLight - using HapticFeedback');
    await HapticFeedback.lightImpact();
  }

  /// Force vibration for testing - tries multiple methods
  Future<void> testVibrate() async {
    debugPrint('🔘 Test vibration - trying all methods...');
    
    // Method 1: Flutter HapticFeedback
    try {
      debugPrint('📳 Method 1: HapticFeedback.heavyImpact()');
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('❌ HapticFeedback failed: $e');
    }
    
    // Method 2: Flutter vibrate
    try {
      debugPrint('📳 Method 2: HapticFeedback.vibrate()');
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('❌ HapticFeedback.vibrate failed: $e');
    }
    
    // Method 3: Vibration plugin
    try {
      debugPrint('📳 Method 3: Vibration.vibrate()');
      await Vibration.vibrate(duration: 500);
    } catch (e) {
      debugPrint('❌ Vibration plugin failed: $e');
    }
    
    debugPrint('📳 Test complete');
  }

  /// Emergency warning pattern
  Future<void> emergencyWarning() async {
    if (_useFlutterHaptics) {
      for (int i = 0; i < 3; i++) {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } else if (_hasVibrator) {
      await Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 200]);
    }
  }

  /// Cancel any ongoing vibration
  Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
