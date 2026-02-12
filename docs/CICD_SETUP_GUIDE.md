# CI/CD Setup Guide

This guide explains how to set up the GitHub Actions CI/CD pipeline for the KitaHack project.

## Quick Setup

### 1. Create the Workflow File

Create the folder structure and file in your local repository:

```
.github/
  workflows/
    android-ci.yml
```

### 2. Add the Workflow Content

Copy this content into `.github/workflows/android-ci.yml`:

```yaml
name: Flutter Android CI/CD

on:
  workflow_dispatch:  # Allow manual triggering
  push:
    branches: [ "development" ]
  pull_request:
    branches: [ "development" ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      # 1. Get the code
      - name: Checkout Code
        uses: actions/checkout@v3

      # 2. Set up Java (Required for Android)
      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'

      # 3. Set up Flutter
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      # 4. Get Flutter dependencies
      - name: Get dependencies
        run: flutter pub get

      # 5. Run Tests (skipped - tests need Firebase mock setup)
      # - name: Run Tests
      #   run: flutter test

      # 6. Build the APK
      - name: Build Release APK
        run: flutter build apk --release

      # 7. Upload APK as artifact (for download)
      - name: Upload APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk

      # 8. Upload to Firebase (Only runs on push to development or manual trigger)
      - name: Upload to Firebase App Distribution
        if: github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && github.ref == 'refs/heads/development')
        uses: wzieba/Firebase-Distribution-Github-Action@v1
        with:
          appId: ${{ secrets.FIREBASE_APP_ID }}
          token: ${{ secrets.FIREBASE_TOKEN }}
          groups: beta_testers
          file: build/app/outputs/flutter-apk/app-release.apk
```

---

## GitHub Secrets Configuration

> **Important**: Only repository admins need to configure secrets.

Go to: **GitHub Repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `FIREBASE_APP_ID` | Your Firebase Android App ID | Firebase Console → Project Settings → Your App |
| `FIREBASE_TOKEN` | Firebase CLI auth token | Run `firebase login:ci` in terminal |

### Getting Firebase Token

```bash
# Install Firebase CLI if needed
npm install -g firebase-tools

# Login and get token
firebase login:ci

# Copy the token that appears
```

---

## How the Pipeline Works

| Trigger | What Happens |
|---------|--------------|
| Push to `development` | Build APK + Upload to Firebase |
| PR to `development` | Build APK only (validation) |
| Manual trigger | Build APK + Upload to Firebase |

### Artifacts

After each run, download the APK from: **Actions → Workflow Run → Artifacts → app-release**

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails on dependencies | Check `pubspec.yaml` for version conflicts |
| Firebase upload fails | Verify secrets are configured correctly |
| Java version error | Ensure JDK 17 is specified in workflow |

---

## Questions?

Contact the project maintainer for help with secrets or configuration.
