import 'package:flutter/material.dart';

/// Centralized app colors based on SDG-inspired palette.
/// Use these constants throughout the app for consistency.
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // Primary Colors
  static const Color primary = Color(0xFF4285F4);       // Base Theme - Blue
  static const Color primaryLight = Color(0xFF80B4FF);
  static const Color primaryDark = Color(0xFF0D47A1);

  // SDG Accent Colors
  static const Color sdg9Orange = Color(0xFFF4845F);    // SDG 9 - Orange/Coral
  static const Color sdg10Pink = Color(0xFFE84A8A);     // SDG 10 - Pink/Magenta
  static const Color sdg11Yellow = Color(0xFFFCC419);   // SDG 11 - Yellow

  // Neutral Colors
  static const Color textPrimary = Color(0xFF3D4550);   // Charcoal
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFADB5BD);

  // Background Colors
  static const Color background = Color(0xFFFFFFFF);    // 2nd Base - White
  static const Color backgroundDark = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color surfaceDark = Color(0xFF2D2D2D);

  // Semantic Colors
  static const Color success = Color(0xFF28A745);
  static const Color warning = sdg11Yellow;
  static const Color error = Color(0xFFDC3545);
  static const Color info = primary;

  // Chat Bubble Colors
  static const Color userBubble = primary;
  static const Color userBubbleText = textLight;
  static const Color aiBubble = surface;
  static const Color aiBubbleText = textPrimary;
  static const Color systemBubble = Color(0xFFE3F2FD);
  static const Color systemBubbleText = textPrimary;

  // Live Mode Colors
  static const Color recording = error;
  static const Color aiSpeaking = sdg9Orange;
  static const Color liveActive = success;
}

/// App-wide text styles for consistency.
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Roboto';

  // Headers
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

  // Body
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

  // Chat specific
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

  // Border radius
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
  );

  static BoxDecoration get aiBubble => BoxDecoration(
    color: AppColors.aiBubble,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
  );

  static BoxDecoration get systemBubble => BoxDecoration(
    color: AppColors.systemBubble,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  );

  static BoxDecoration get inputContainer => BoxDecoration(
    color: AppColors.surface,
    border: Border(top: BorderSide(color: AppColors.primary, width: 2)),
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
