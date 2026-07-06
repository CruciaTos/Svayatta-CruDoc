import 'package:flutter/material.dart';

/// ============================================================
/// APP COLORS — "Moody Blues" palette
/// Single source of truth for every color used across CruDoc.
/// Matches the CruSam / DZEN visual identity so the doctor's app
/// feels like part of the same product family.
/// ============================================================
class AppColors {
  AppColors._();

  // Core palette
  static const midnightBlue = Color(0xFF1B2430);
  static const charcoalGray = Color(0xFF2A313C);
  static const slateBlue = Color(0xFF4A5A75);
  static const silver = Color(0xFFB9C2CF);
  static const beige = Color(0xFFE9E4D8);

  // Background gradient
  static const bgTop = Color(0xFF232A35);
  static const bgBottom = Color(0xFF171D26);

  // Surfaces
  static const cardSurface = Color(0xFF2E3644);
  static const cardSurfaceAlt = Color(0xFF333C4B);
  static const cardSurfaceRaised = Color(0xFF39424F);

  // Chart / data accents
  static const chartBarLight = Color(0xFFA9C3D8);
  static const chartBarDim = Color(0xFF5A6779);

  // Status colors
  static const positiveGreen = Color(0xFF7FBF8F);
  static const warningAmber = Color(0xFFD9B36C);
  static const dangerRed = Color(0xFFD98080);
  static const infoBlue = Color(0xFF7FA6D9);

  // Priority tags (from the Board screen reference)
  static const priorityHigh = Color(0xFFD98080);
  static const priorityMedium = Color(0xFFD9B36C);
  static const priorityLow = Color(0xFF7FBF8F);

  // Structural
  static const divider = Color(0x1FFFFFFF);
  static const dividerStrong = Color(0x33FFFFFF);
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF9AA4B2);
  static const textMuted = Color(0xFF6E7887);
}

/// ============================================================
/// APP SPACING / RADIUS TOKENS
/// ============================================================
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const pill = 100.0;
}

/// ============================================================
/// APP THEME — wires tokens into a ThemeData for MaterialApp
/// ============================================================
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.midnightBlue,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: AppColors.slateBlue,
        secondary: AppColors.beige,
        surface: AppColors.cardSurface,
        error: AppColors.dangerRed,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        labelSmall: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
        ),
      ),
      dividerColor: AppColors.divider,
      iconTheme: const IconThemeData(color: AppColors.silver),
    );
  }

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.bgTop, AppColors.bgBottom],
  );
}