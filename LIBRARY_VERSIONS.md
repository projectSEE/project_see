# 📦 Library Versions Reference

本文档列出所有依赖库的版本，供将来参考和排错使用。

---

## Flutter SDK

| 组件 | 版本 |
|------|------|
| Flutter | 3.29.2 |
| Dart | 3.7.2 |
| DevTools | 2.42.3 |

---

## pubspec.yaml 依赖

### 主要依赖 (dependencies)

| 库名 | 版本 | 用途 |
|------|------|------|
| `flutter` | SDK | 核心框架 |
| `cupertino_icons` | ^1.0.8 | iOS 风格图标 |
| `google_mlkit_object_detection` | ^0.13.0 | ML Kit 物体检测 |
| `camera` | ^0.11.0+2 | 相机访问 |
| `flutter_tts` | ^4.2.0 | 文字转语音 |
| `vibration` | ^2.0.0 | 震动反馈 |
| `permission_handler` | ^11.3.1 | 权限管理 |

### 开发依赖 (dev_dependencies)

| 库名 | 版本 | 用途 |
|------|------|------|
| `flutter_test` | SDK | 测试框架 |
| `flutter_lints` | ^5.0.0 | 代码规范检查 |

---

## Android 配置

### settings.gradle.kts

| 插件 | 版本 |
|------|------|
| `dev.flutter.flutter-plugin-loader` | 1.0.0 |
| `com.android.application` | 8.7.0 |
| `org.jetbrains.kotlin.android` | **2.1.0** ⚠️ |

> ⚠️ **重要**: Kotlin 必须使用 2.1.0 才能兼容 flutter_tts 4.2.0

### build.gradle.kts

| 配置 | 值 |
|------|------|
| `namespace` | com.kitahack.blind_assist |
| `compileSdk` | flutter.compileSdkVersion |
| `minSdk` | **24** ⚠️ |
| `targetSdk` | flutter.targetSdkVersion |
| `sourceCompatibility` | Java 17 |
| `targetCompatibility` | Java 17 |
| `jvmTarget` | 17 |

> ⚠️ **重要**: minSdk 必须为 24 才能支持 ML Kit 和 flutter_tts

---

## Android 权限 (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

---

## 兼容性矩阵

| 库 | 最低 minSdk | 需要 Kotlin |
|----|-------------|-------------|
| flutter_tts 4.2.0 | 24 | 2.x |
| google_mlkit_object_detection | 21 | 1.8+ |
| camera | 21 | 1.8+ |
| vibration | 16 | 1.8+ |
| permission_handler | 21 | 1.8+ |

---

## 如何更新依赖

```bash
# 查看过时的包
flutter pub outdated

# 更新所有包
flutter pub upgrade

# 强制更新主版本
flutter pub upgrade --major-versions
```

---

## 版本冲突排查

如果遇到版本冲突，运行：
```bash
flutter pub deps --style=compact
```

查看完整依赖树，找出冲突的包。
