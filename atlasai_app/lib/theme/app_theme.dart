import 'package:flutter/material.dart';

/// Shared design tokens. Extracted out of main.dart's old inline
/// ThemeData so every screen (Day 4 auth, Day 5 chat/timeline/capture)
/// can reference the same palette/spacing instead of hardcoding values.
///
/// Colors are built around the same seed main.dart used before this
/// file existed (0xFF1F4E5F — a dark industrial teal), so switching to
/// AppTheme.light() doesn't visually change anything already shipped.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1F4E5F);
  static const Color background = Color(0xFFF5F7F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDF1F2);
  static const Color border = Color(0xFFDCE3E5);

  static const Color textPrimary = Color(0xFF1A2327);
  static const Color textSecondary = Color(0xFF5B6B70);
  static const Color textFaint = Color(0xFF8C9A9E);

  static const Color success = Color(0xFF2E7D32);
  static const Color successBg = Color(0xFFE6F4E8);

  static const Color warning = Color(0xFFB8720A);
  static const Color warningBg = Color(0xFFFCF0DC);

  static const Color danger = Color(0xFFC62828);
  static const Color dangerBg = Color(0xFFFBE7E7);
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  AppRadius._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    );
  }
}