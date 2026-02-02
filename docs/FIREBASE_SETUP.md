# KitaHack Firebase Setup Guide

Complete setup guide for Firebase Realtime Database integration with the Visual Assistant App.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Firebase Console Setup](#firebase-console-setup)
3. [Flutter Dependencies](#flutter-dependencies)
4. [Android Configuration](#android-configuration)
5. [iOS Configuration](#ios-configuration)
6. [Security Rules](#security-rules)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Flutter SDK | ^3.7.2 | `flutter --version` |
| Dart SDK | ^3.7.2 | `dart --version` |
| Android Studio | Latest | - |
| Xcode (macOS) | 15+ | `xcodebuild -version` |
| Node.js | 18+ | `node --version` |
| Firebase CLI | Latest | `firebase --version` |

### Install Firebase CLI
```bash
npm install -g firebase-tools
firebase login
```

---

## Firebase Console Setup

### Step 1: Create/Select Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add Project** or select existing project
3. Enable **Google Analytics** (optional but recommended)

### Step 2: Register Android App

1. Click **Add app** → Select **Android**
2. Enter package name: `com.example.visual_assistant_app`
3. Enter App nickname: `Visual Assistant App`
4. Download `google-services.json`
5. Place file at:
   ```
   android/app/google-services.json
   ```

### Step 3: Register iOS App (if applicable)

1. Click **Add app** → Select **iOS**
2. Enter Bundle ID: `com.example.visualAssistantApp`
3. Download `GoogleService-Info.plist`
4. Place file at:
   ```
   ios/Runner/GoogleService-Info.plist
   ```

### Step 4: Enable Realtime Database

1. In Firebase Console, go to **Build** → **Realtime Database**
2. Click **Create Database**
3. Select location closest to your users:
   - `us-central1` (Iowa) - Recommended for Vertex AI
   - `asia-southeast1` (Singapore) - For SEA users
4. Start in **Test Mode** (we'll secure it later)
5. Note your database URL:
   ```
   https://your-project-id-default-rtdb.firebaseio.com/
   ```

### Step 5: Enable Vertex AI API (for Gemini)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your Firebase project
3. Navigate to **APIs & Services** → **Enabled APIs**
4. Enable **Vertex AI API**
5. Enable **Firebase AI API**

---

## Flutter Dependencies

### pubspec.yaml

Add these dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase Core (required)
  firebase_core: ^4.4.0
  
  # Firebase AI / Vertex AI for Gemini
  firebase_ai: ^3.7.0
  
  # Firebase Realtime Database (NEW)
  firebase_database: ^11.4.1
  
  # Location services (optional, for POI features)
  geolocator: ^13.0.2
  
  # Existing dependencies
  cupertino_icons: ^1.0.8
  image_picker: ^1.2.1
  flutter_tts: ^4.2.5
  permission_handler: ^12.0.1
  path_provider: ^2.1.5
  record: ^6.1.2
  flutter_pcm_sound: ^3.3.3
```

### Install Dependencies
```bash
flutter pub get
```

---

## Android Configuration

### File: `android/settings.gradle.kts`

Ensure Google Services plugin is declared:

```kotlin
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    // Google Services plugin for Firebase
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
```

### File: `android/build.gradle.kts`

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
```

### File: `android/app/build.gradle.kts`

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    // Apply Google Services plugin
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.visual_assistant_app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.visual_assistant_app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BOM (Bill of Materials) - manages versions
    implementation(platform("com.google.firebase:firebase-bom:34.8.0"))
    implementation("com.google.firebase:firebase-analytics")
    // Realtime Database is auto-included via Flutter plugin
}
```

### File: `android/app/src/main/AndroidManifest.xml`

Ensure these permissions are present:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    
    <!-- Location permissions (for POI features) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    
    <application
        android:label="visual_assistant_app"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <!-- ... rest of application config ... -->
    </application>
</manifest>
```

### File: `android/app/google-services.json`

> ⚠️ **Download from Firebase Console** (see Step 2 above)

Place at: `android/app/google-services.json`

---

## iOS Configuration

### File: `ios/Runner/GoogleService-Info.plist`

> ⚠️ **Download from Firebase Console** (see Step 3 above)

Place at: `ios/Runner/GoogleService-Info.plist`

### File: `ios/Runner/Info.plist`

Add location permissions (for POI features):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find accessible points of interest near you.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>We need your location to provide navigation assistance.</string>
```

### File: `ios/Podfile`

Ensure minimum iOS version is 13.0 or higher:

```ruby
platform :ios, '13.0'
```

After modifying, run:
```bash
cd ios && pod install && cd ..
```

---

## Security Rules

### Realtime Database Rules

Go to **Firebase Console** → **Realtime Database** → **Rules** tab.

#### Development Rules (Test Mode)
```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

#### Production Rules (Recommended)
```json
{
  "rules": {
    "users": {
      "$userId": {
        ".read": "auth != null && auth.uid == $userId",
        ".write": "auth != null && auth.uid == $userId",
        "conversations": {
          ".indexOn": ["timestamp"]
        }
      }
    },
    "pois": {
      ".read": "auth != null",
      ".write": "auth != null && root.child('admins').child(auth.uid).exists()",
      ".indexOn": ["type", "lastUpdated"]
    }
  }
}
```

---

## Verification

### Step 1: Clean Build
```bash
flutter clean
flutter pub get
```

### Step 2: Build for Android
```bash
flutter build apk --debug
```

### Step 3: Run on Device/Emulator
```bash
flutter run
```

### Step 4: Check Firebase Connection

Add temporary debug code to `main.dart`:

```dart
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Test database connection
  final ref = FirebaseDatabase.instance.ref('test');
  await ref.set({'timestamp': ServerValue.timestamp});
  print('✅ Firebase Realtime Database connected!');
  
  runApp(const VisualAssistantApp());
}
```

Check the Firebase Console → Realtime Database to see if `test` node was created.

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `google-services.json` not found | Download from Firebase Console and place in `android/app/` |
| `No Firebase App` error | Ensure `await Firebase.initializeApp()` is called in `main()` |
| Gradle build fails | Run `cd android && ./gradlew clean && cd ..` |
| iOS pod install fails | Run `cd ios && pod deintegrate && pod install && cd ..` |
| Permission denied errors | Check Firebase Security Rules |

### Useful Commands

```bash
# Check Flutter doctor
flutter doctor -v

# Clear all caches
flutter clean && flutter pub get

# Rebuild Android
cd android && ./gradlew clean && cd .. && flutter build apk

# Rebuild iOS
cd ios && pod deintegrate && pod install && cd .. && flutter build ios
```

---

## Project Structure After Setup

```
KitaHack/
├── android/
│   ├── app/
│   │   ├── build.gradle.kts          ✓ Google Services plugin applied
│   │   ├── google-services.json      ✓ Download from Firebase
│   │   └── src/main/AndroidManifest.xml  ✓ Permissions added
│   ├── build.gradle.kts              ✓ Repositories configured
│   └── settings.gradle.kts           ✓ Plugins declared
├── ios/
│   ├── Runner/
│   │   ├── GoogleService-Info.plist  ✓ Download from Firebase
│   │   └── Info.plist                ✓ Permissions added
│   └── Podfile                       ✓ iOS 13.0+ minimum
├── lib/
│   ├── main.dart                     ✓ Firebase initialized
│   └── services/
│       ├── gemini_service.dart       ✓ AI service
│       └── database_service.dart     ✓ NEW: Database service
├── docs/
│   ├── DATABASE_SCHEMA.md            ✓ Schema documentation
│   └── FIREBASE_SETUP.md             ✓ This file
└── pubspec.yaml                      ✓ Dependencies added
```

---

## Next Steps

1. ✅ Complete Firebase Console setup
2. ✅ Add configuration files
3. ✅ Run verification steps
4. 🔲 Implement `DatabaseService` class
5. 🔲 Integrate with `GeminiService`
6. 🔲 Test on physical device

---

**Last Updated:** February 2026  
**Maintainers:** KitaHack Development Team
