<p align="center">
  <h1 align="center">👁️ SEE — Smart Eye Enhancement</h1>
  <p align="center">
    An AI-powered visual assistant app empowering visually impaired users through real-time object detection, intelligent navigation, and multimodal AI interaction.
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.29.0-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.7.0-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Firebase-Enabled-FFCA28?logo=firebase" alt="Firebase">
  <img src="https://img.shields.io/badge/Gemini_AI-Integrated-4285F4?logo=google" alt="Gemini AI">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android" alt="Android">
</p>

# 🌐 Project Hub

### 1. Project S.E.E. — KitaHack 2026

* ▶️ **[View the Live Demo](https://youtu.be/5rptn0NpdhI)**
* 📽️ **[View the Pitch Deck (Canva)](https://www.canva.com/design/DAHCMHdSt18/uquqnk9WNl0ns18z7EnL4Q/edit?utm_content=DAHCMHdSt18&utm_campaign=designshare&utm_medium=link2&utm_source=sharebutton)**
* 📄 **[Read the Full Technical Report](https://drive.google.com/file/d/1cTIu7ANkeM7fOKjEOiLgMboD2CiTFra3/view?usp=drive_link)**
* 📊 **[View the Live Impact Dashboard (Looker Studio)](https://lookerstudio.google.com/reporting/e055b2bb-3efc-4761-9813-8795a3b28159)**
* 🗺️ **[Explore the Technical Roadmap](https://drive.google.com/file/d/10490V8lv0zvaDaJPZsIqbIzrwhghuKBI/view?usp=sharing)**

---

### 2. Core Implementation Details

* ⚙️ **[System Flow & Architecture](https://drive.google.com/file/d/1ysF8-CKwYKD24pHtgkB5aJB0yfzqPbMm/view?usp=drive_link)**
* 💡 **[Solution Overview](https://drive.google.com/open?id=1uc5ivouNl7wbFZQgpQiuPXsvJLWOzfKU)**
* 🗄️ **[Live Telemetry Feed (Raw Data)](https://docs.google.com/spreadsheets/d/1Yg6T8fkQgGcDeqxveZ3kyruuIDqWo67havrZHNhl_k0/edit?usp=sharing)**


## 📑 Table of Contents

- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Firebase Setup](#-firebase-setup)
- [Environment Variables](#-environment-variables)
- [Running the App](#-running-the-app)
- [Project Structure](#-project-structure)
- [Permissions](#-permissions)
- [Troubleshooting](#-troubleshooting)
- [Tech Stack](#-tech-stack)
- [Contributing](#-contributing)

---

## ✨ Features

### 🔍 Obstacle Detection Hub
| Feature | Description |
|---------|-------------|
| **Object Detection** | Real-time on-device object detection using Google ML Kit with voice announcements |
| **Live AI Assistant** | Camera + microphone streaming to Gemini Live API for real-time scene description and guidance |
| **Navigation** | Accessible turn-by-turn navigation with Google Maps, voice-guided directions, and POI exploration |

### 💬 AI Chatbot
- **Text Chat** — Powered by Firebase AI (Gemini) with context-aware responses
- **Image Analysis** — Send photos for AI-powered visual description
- **Voice Input/Output** — Speech-to-text input and text-to-speech responses
- **Live Streaming Mode** — Real-time audio/video conversation with Gemini Live API
- **Chat History** — Persistent conversations stored in Cloud Firestore
- **Export** — Share conversations as PDF

### 🛡️ Safety & Awareness
| Feature | Description |
|---------|-------------|
| **Fall Detection** | Background accelerometer monitoring with emergency auto-calling |
| **Vision Simulator** | Camera-based simulation of eye conditions (glaucoma, cataracts, retinopathy) |
| **Sight Facts** | Educational content about visual impairments with links to national support (NCBM) |

### 🔐 Authentication
- Email/password registration with email verification
- Google Sign-In
- User profiles with emergency contact information stored in Firestore

---

## 🏗️ Architecture

```
lib/
├── main.dart                     # App entry point, auth flow, fall detection
├── firebase_options.dart         # Firebase configuration
├── core/                         # Core configs like localization
├── screens/
│   ├── login_screen.dart         # Auth (email + Google Sign-In)
│   ├── awareness_screen.dart     # Awareness feature menu
│   ├── chat_screen.dart          # AI chatbot (text/image/voice/live)
│   ├── live_screen.dart          # Gemini Live API assistant
│   ├── navigation_screen.dart    # Google Maps navigation
│   ├── object_detection_screen.dart  # ML Kit object detection & Detection hub
│   ├── profile_screen.dart       # User profile & emergency contacts
│   ├── settings_screen.dart      # App settings
│   ├── sight_facts_screen.dart   # Educational content
│   └── vision_simulator_screen.dart  # Eye condition simulator
├── services/
│   ├── firestore_service.dart             # Firestore CRUD operations
│   ├── gemini_service.dart                # Gemini AI integration
│   ├── location_awareness_service.dart    # Location context
│   ├── ml_kit_service.dart                # ML Kit object detection
│   ├── depth_estimation_service.dart      # Visual depth estimation
│   ├── navigation_service.dart            # Navigation logic
│   ├── tts_service.dart                   # Text-to-speech
│   ├── vibration_service.dart             # Haptic feedback
│   └── accessible_live_connector.dart     # Live API connector
├── theme/                        # App theming (light/dark)
├── utils/                        # Audio I/O, accessibility, export
└── widgets/                      # Reusable UI components
```

---

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

| Tool | Version | Notes |
|------|---------|-------|
| **Flutter SDK** | `3.29.0` | Managed via [FVM](https://fvm.app) (recommended) |
| **Dart SDK** | `3.7.0` | Bundled with Flutter |
| **Android Studio** | Latest | With Android SDK, NDK `28.2.13676358` |
| **Java JDK** | `17` | Required for Gradle |
| **Git** | Latest | For cloning the repository |

> **Minimum Android Version:** API 24 (Android 7.0) — Required for ML Kit and TTS.

---

## 🚀 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/projectSEE/project_see.git
cd project_see
```

### 2. Install Flutter (via FVM — Recommended)

```bash
# Install FVM
dart pub global activate fvm

# Install the required Flutter version
fvm install 3.29.0
fvm use 3.29.0

# Verify
fvm flutter --version
```

Or, if using Flutter directly:

```bash
flutter --version
# Ensure output shows Flutter 3.29.x
```

### 3. Install Dependencies

```bash
flutter pub get
```

### 4. Verify Setup

```bash
flutter doctor
```

Ensure there are no critical issues (✓ for Flutter, Android toolchain, and connected devices).

---

## 🔥 Firebase Setup

This project uses Firebase for authentication, Firestore, storage, and AI. You must set up your own Firebase project.

### Step 1: Create a Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Click **Add project** and follow the setup wizard
3. Enable **Google Analytics** (optional)

### Step 2: Register Your Android App

1. In Firebase Console → **Project Settings** → **Add app** → **Android**
2. Set the package name to: `com.kitahack.see`
3. Download `google-services.json`
4. Place it in: `android/app/google-services.json`

### Step 3: Enable Firebase Services

Enable the following in the Firebase Console:

| Service | Path in Console |
|---------|----------------|
| **Authentication** | Build → Authentication → Enable Email/Password and Google |
| **Cloud Firestore** | Build → Firestore Database → Create database |
| **Cloud Storage** | Build → Storage → Get started |
| **Firebase AI (Vertex AI)** | Build → AI → Enable Gemini API |

### Step 4: Install FlutterFire CLI (Optional)

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id>
```

This auto-generates `lib/firebase_options.dart`.

---

## 🔑 Environment Variables

The Google Maps API key is passed at **build time** via `--dart-define`. No `.env` file is needed at runtime.

### Getting a Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the following APIs:
   - **Maps SDK for Android**
   - **Directions API**
   - **Places API**
   - **Geocoding API**
3. Create an API key under **Credentials**
4. Update `android/app/src/main/AndroidManifest.xml` with your key:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE" />
```

> ⚠️ **Important:** Never commit API keys to version control. Consider restricting your key in the Google Cloud Console.

---

## ▶️ Running the App

The app uses **FVM** to manage the Flutter version. All commands below use `fvm flutter` — if you installed Flutter globally at the correct version, you can omit `fvm`.

### Development Build

```bash
# Connect an Android device or start an emulator
fvm flutter run --dart-define=GOOGLE_MAPS_API_KEY=<your-api-key>
```

### Release Build

```bash
fvm flutter run --release --dart-define=GOOGLE_MAPS_API_KEY=<your-api-key>
```

Or to build an APK:

```bash
fvm flutter build apk --release --dart-define=GOOGLE_MAPS_API_KEY=<your-api-key>
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

### Clean Build (if you encounter issues)

```bash
fvm flutter clean
fvm flutter pub get
fvm flutter run --dart-define=GOOGLE_MAPS_API_KEY=<your-api-key>
```

---

## 📂 Project Structure

```
see/
├── android/                  # Android platform files
│   └── app/
│       ├── build.gradle.kts  # Android build config (minSdk 24)
│       └── src/main/
│           └── AndroidManifest.xml  # Permissions & API keys
├── assets/
│   ├── audio/                # Sound assets (siren for fall detection)
│   └── google_fonts/         # Custom fonts
├── lib/                      # Dart source code (see Architecture above)
├── .env                      # Environment variables (git-ignored)
├── .fvmrc                    # FVM Flutter version config
├── pubspec.yaml              # Dependencies
├── firebase.json             # Firebase project config
└── analysis_options.yaml     # Dart linting rules
```

---

## 🔒 Permissions

The app requires the following Android permissions (declared in `AndroidManifest.xml`):

| Permission | Purpose |
|------------|---------|
| `INTERNET` | Firebase, AI API calls, maps |
| `CAMERA` | Object detection, live assistant, vision simulator |
| `RECORD_AUDIO` | Voice input, live streaming |
| `ACCESS_FINE_LOCATION` | Navigation, location awareness |
| `ACCESS_COARSE_LOCATION` | Approximate location |
| `CALL_PHONE` | Emergency auto-calling (fall detection) |
| `VIBRATE` | Haptic feedback for obstacle alerts |
| `WAKE_LOCK` | Keep screen active during navigation |
| `FOREGROUND_SERVICE` | Background fall detection |
| `MODIFY_AUDIO_SETTINGS` | Audio echo cancellation for live mode |

> Users will be prompted to grant permissions at runtime.

---

## 🛠️ Troubleshooting

### Build Fails with Kotlin Version Error

Update Kotlin in `android/settings.gradle.kts`:

```kotlin
id("org.jetbrains.kotlin.android") version "2.1.0" apply false
```

### ML Kit Detects 0 Objects

On Android 15+, stream-based detection may fail. The app uses file-based detection as a workaround. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for details.

### Vibration Not Working

Some devices (e.g., Xiaomi with Android 15) don't respond to the `vibration` plugin. The app falls back to Flutter's `HapticFeedback` API.

### Firebase Connection Issues

```bash
# Ensure google-services.json is in android/app/
# Re-run FlutterFire configuration:
flutterfire configure
```

### General Debug Commands

```bash
flutter doctor          # Check environment
flutter clean           # Clean build artifacts
flutter pub get         # Re-fetch dependencies
flutter run --verbose   # Verbose build logs
flutter analyze         # Static code analysis
```

For the full troubleshooting guide, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## 🧰 Tech Stack

| Category | Technology |
|----------|------------|
| **Framework** | Flutter 3.29.0 / Dart 3.7.0 |
| **AI / ML** | Google Gemini (Firebase AI), Google ML Kit |
| **Backend** | Firebase (Auth, Firestore, Storage, Vertex AI) |
| **Maps** | Google Maps Flutter, Geolocator, Geocoding |
| **Voice** | Speech-to-Text, Flutter TTS, Audio Recording |
| **Safety** | Accelerometer-based fall detection, direct phone calling |
| **Auth** | Firebase Auth (Email/Password, Google Sign-In) |

---

## 🤝 Contributing

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/your-feature`
3. **Commit** your changes: `git commit -m 'Add your feature'`
4. **Push** to the branch: `git push origin feature/your-feature`
5. **Open** a Pull Request

### Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production-ready code |
| `development` | Integration branch |
| `feature/*` | Individual feature branches |

---

## 📄 License

This project was built for **KitaHack 2026**.

---

<p align="center">
  Built with ❤️ using Flutter & Google AI
</p>
