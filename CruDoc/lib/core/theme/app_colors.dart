import 'package:flutter/material.dart';

class AppColors {
  static const midnightBlue = Color(0xFF1B2430);
  static const charcoalGray = Color(0xFF2A313C);
  static const slateBlue = Color(0xFF4A5A75);
  static const silver = Color(0xFFB9C2CF);
  // Accent/beige color used for selected chips and highlights.
  // Previously set to black which made dark text invisible on selection.
  static const beige = Color(0xFFE1F6FF);
  static const bgTop = Color(0xFF232A35);
  static const bgBottom = Color(0xFF171D26);
  static const cardSurface = Color.fromARGB(255, 220, 250, 255);
  static const cardSurfaceAlt = Color(0xFF333C4B);
  static const chartBarLight = Color.fromARGB(255, 30, 120, 255);
  static const chartBarDim = Color.fromARGB(255, 140, 188, 255);
  static const accentBlue = Color(0xFF2D9CDB);
  static const positiveGreen = Color(0xFF7FBF8F);
  /// Muted red companion for expenses / negative amounts.
  /// Used on amount text, filter chips, and avatar backgrounds.
  static const negativeRed = Color(0xFFEF5350);
  static const divider = Color(0x1FFFFFFF);
  static const textPrimary = Color.fromARGB(255, 0, 0, 0);
  static const textSecondary = Color(0xFF6B7280);

  // ============================================================
  // TYPOGRAPHY
  // ============================================================

  static const String headingFontFamily = 'PlusJakartaSans';

  static const TextStyle pageHeading = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w300,
    color: textPrimary,
  );

  static const TextStyle sectionHeading = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w300,
    color: textPrimary,
  );

  static const String bodyFontFamily = 'PlusJakartaSans';

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  /// Additional body style for metadata / secondary info that needs
  /// a slightly larger size than [bodySmall].  e.g. visit date/time/address.
  /// 13 / w400 / [textSecondary]
  static const TextStyle bodyMeta = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );
}

extension ColorValueExtensions on Color {
  /// Returns this color with the provided alpha (0.0 - 1.0).
  /// Implemented with `Color.fromRGBO` to avoid precision loss and
  /// to provide a safe replacement for the incorrect recursive stub.
  Color withValues({required double alpha}) {
    final double a = alpha.clamp(0.0, 1.0);
    final int r = (this.r * 255.0).round();
    final int g = (this.g * 255.0).round();
    final int b = (this.b * 255.0).round();
    return Color.fromRGBO(r, g, b, a);
  }
}