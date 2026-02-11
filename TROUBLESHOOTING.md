# Troubleshooting Guide

This document covers common issues and solutions for the Blind Assist app.

---

## 1. Vibration Not Working

### Problem
The `vibration` Flutter plugin doesn't trigger vibration on some Android devices (especially newer ones like Xiaomi with Android 15), even though the phone can vibrate normally in other apps.

### Symptoms
- Test shows "vibration triggered" in logs but phone doesn't vibrate
- `Vibration.vibrate()` silently fails
- Device reports `hasVibrator = true`

### Solution
Use Flutter's built-in `HapticFeedback` API instead of the `vibration` plugin:

```dart
import 'package:flutter/services.dart';

// Instead of:
await Vibration.vibrate(duration: 300);

// Use:
await HapticFeedback.heavyImpact();  // Strong
await HapticFeedback.mediumImpact(); // Medium
await HapticFeedback.lightImpact();  // Light
```

**Note:** `HapticFeedback` provides shorter, haptic-style vibrations. For longer patterns, call multiple times with delays.

---

## 2. ML Kit Object Detection Returns 0 Objects

### Problem
Camera stream processing with `InputImage.fromBytes()` fails on Android 15 with `InputImageConverterError: IllegalArgumentException`.

### Symptoms
- `📷 Frame X: Detected 0 objects` in logs
- `E/ImageError: Getting Image failed` errors
- `PlatformException(InputImageConverterError, java.lang.IllegalArgumentException)`

### Solution
Use **file-based detection** instead of stream-based:

```dart
// Instead of startImageStream:
final XFile imageFile = await _cameraController!.takePicture();
final inputImage = InputImage.fromFilePath(imageFile.path);
final objects = await _objectDetector!.processImage(inputImage);

// Delete temp file after processing
await File(imageFile.path).delete();
```

**Trade-off:** File-based detection is slower (~2 second intervals) but more reliable.

---

## 3. Gradle Build Fails with Kotlin Version Error

### Problem
```
The class was compiled with an incompatible version of Kotlin.
Binary version of metadata is 2.2.0, expected version is 2.0.0.
```

### Solution
Update Kotlin version in `android/settings.gradle.kts`:

```kotlin
plugins {
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}
```

---

## 4. Camera Disconnects / App Crashes

### Problem
App loses camera connection with errors like:
- `Device error received, code 5`
- `BufferQueue has been abandoned`

### Possible Causes
1. Using unsupported image format
2. Processing frames too slowly
3. Memory pressure

### Solutions
1. Use `ImageFormatGroup.yuv420` (not `nv21`)
2. Skip frames if processing is slow
3. Use `ResolutionPreset.medium` or `low`

```dart
_cameraController = CameraController(
  camera,
  ResolutionPreset.medium,
  enableAudio: false,
  imageFormatGroup: ImageFormatGroup.yuv420,
);
```

---

## 5. Permission Issues

### Problem
App can't access camera or vibration.

### Solution
Ensure AndroidManifest.xml has:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-feature android:name="android.hardware.camera" android:required="true"/>
```

---

## 6. TTS (Text-to-Speech) Not Working

### Problem
No audio output from TTS announcements.

### Checklist
1. Check device volume is not muted
2. Ensure TTS engine is installed (Settings → Accessibility → TTS)
3. Check if another app is using audio

### Solution
Initialize TTS properly and wait for it:

```dart
await _flutterTts.setLanguage("en-US");
await _flutterTts.setSpeechRate(0.5);
await _flutterTts.awaitSpeakCompletion(true);
```

---

## Quick Debug Commands

```bash
# Check Flutter environment
flutter doctor

# Clean build
flutter clean && flutter pub get

# Build with verbose logs
flutter run --verbose

# Analyze code for errors
flutter analyze
```
