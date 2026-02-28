# SEE — System Data Flow Overview

## Executive Summary

**Key System Stats:**
- **5** Core Screens
- **2** On-Device Models
- **2** Gemini AI Modes
- **3** Cloud Services
- **35** Dart Source Files

### Camera & Sensor Pipeline
Camera frames (YUV420) are consumed by two parallel pipelines: **ML Kit** processes every frame for object detection via NV21 conversion, while **Depth Anything V2** runs ONNX inference on RGB frames resized to 252×252 at ~3 FPS. A third branch samples 1 frame/sec as JPEG (via native Kotlin MethodChannel at quality 40) for the Gemini Live API video stream.

### Gemini AI Integration
**Chat mode** uses Gemini 2.5 Flash for text/image queries with Firestore context injection and automatic POI extraction via brace-counting JSON parsing. **Live mode** streams bidirectional audio (16 kHz up / 24 kHz down) and video over WebSocket with custom VAD configuration, barge-in support (AudioTrack flush), and non-verbal earcon cues for blind users.

### Fall Detection & Emergency
Accelerometer data is continuously monitored for a two-phase pattern: free-fall (magnitude <1.5g) followed by impact (>20g) within 500 ms. Detection triggers a siren, vibration pattern, and a 10-second countdown dialog. If not cancelled, the app auto-dials the emergency contact and uploads feedback to Firestore.

### Navigation & Location
Google Directions API provides walking routes parsed into step-by-step instructions. Live position tracking (5 m filter) auto-advances steps when within 10 m of each waypoint. Explore mode queries the Places API (New) within 100 m to announce nearby POIs via TTS, with a 50-entry deduplication set and 5-second cooldown.

### Output & Accessibility
Obstacle proximity drives a 3-tier haptic feedback system (light/medium/heavy impact) with a 300 ms throttle and 0.2 intensity boost for approaching objects. TTS announces the closest obstacle every 3 seconds with 2-second duplicate suppression. Audio output routes through the loudspeaker with echo cancellation for simultaneous AI speech and microphone input.

### Resilience & Error Handling
The system implements multi-layer fallbacks: Places API (New) → legacy endpoint; custom VAD → SDK fallback; stream-mode detection → file-based after 100 failures; location → last known position after 15 s timeout. TTS initialisation retries 5 times with progressive delays. Lifecycle observers pause all streams on `inactive` and reinitialise on `resumed`.
