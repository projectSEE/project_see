import 'package:flutter/material.dart';

/// Centralized app colors — strict Black & White only.
class AppColors {
  AppColors._();

  // Primary
  static const Color primary = Colors.black;
  static const Color primaryLight = Colors.white;
  static const Color primaryDark = Colors.black;

  // Text
  static const Color textPrimary = Colors.black;
  static const Color textSecondary = Color(0xFF333333);
  static const Color textLight = Colors.white;
  static const Color textMuted = Color(0xFF999999);

  // Background
  static const Color background = Colors.white;
  static const Color backgroundDark = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color surfaceDark = Color(0xFF1A1A1A);

  // Semantic — still B/W
  static const Color success = Colors.black;
  static const Color warning = Colors.black;
  static const Color error = Colors.black;
  static const Color info = Colors.black;

  // Chat Bubble
  static const Color userBubble = Colors.black;
  static const Color userBubbleText = Colors.white;
  static const Color aiBubble = Colors.white;
  static const Color aiBubbleText = Colors.black;
  static const Color systemBubble = Color(0xFFF0F0F0);
  static const Color systemBubbleText = Colors.black;

  // Live Mode
  static const Color recording = Colors.black;
  static const Color aiSpeaking = Colors.black;
  static const Color liveActive = Colors.black;
}

/// App-wide text styles for consistency.
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Roboto';

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle chatMessage = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const TextStyle systemMessage = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    fontStyle: FontStyle.italic,
    height: 1.4,
  );
}

/// App-wide spacing and sizing constants.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusRound = 30.0;
}

/// App-wide decoration presets.
class AppDecorations {
  AppDecorations._();

  static BoxDecoration get userBubble => BoxDecoration(
    color: AppColors.userBubble,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(
      color: const Color(0xFF888888).withValues(alpha: 0.5),
      width: 1.5,
    ),
  );

  static BoxDecoration get aiBubble => BoxDecoration(
    color: AppColors.aiBubble,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(
      color: const Color(0xFF888888).withValues(alpha: 0.5),
      width: 1.5,
    ),
  );

  static BoxDecoration get systemBubble => BoxDecoration(
    color: AppColors.systemBubble,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  );

  static BoxDecoration get inputContainer => BoxDecoration(
    color: AppColors.surface,
    border: Border(top: BorderSide(color: Colors.black, width: 2)),
  );

  static BoxDecoration get card => BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
