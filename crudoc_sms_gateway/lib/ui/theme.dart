import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide design tokens for the CruDoc SMS Gateway.
class AppTheme {
  AppTheme._();

  // ── Colors ─────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0D1117);
  static const Color bgCard = Color(0xFF161B22);
  static const Color bgCardLight = Color(0xFF1C2333);
  static const Color border = Color(0xFF30363D);
  static const Color accentGreen = Color(0xFF39D353);
  static const Color accentBlue = Color(0xFF58A6FF);
  static const Color accentOrange = Color(0xFFF0883E);
  static const Color accentRed = Color(0xFFF85149);
  static const Color accentYellow = Color(0xFFD29922);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);

  // ── Status Colors ──────────────────────────────────────
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ready':
      case 'online':
      case 'sent':
        return accentGreen;
      case 'busy':
      case 'sending':
        return accentBlue;
      case 'no_sim':
      case 'permission_denied':
      case 'failed':
        return accentRed;
      case 'offline':
        return textMuted;
      case 'duplicate':
        return accentYellow;
      default:
        return accentOrange;
    }
  }

  // ── Typography ─────────────────────────────────────────
  static TextStyle get heading => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static TextStyle get subheading => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textMuted,
      );

  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  // ── Decorations ────────────────────────────────────────
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      );

  static BoxDecoration glowCard(Color glowColor) => BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glowColor.withValues(alpha: 0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.1),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      );

  // ── ThemeData ──────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        fontFamily: GoogleFonts.inter().fontFamily,
        appBarTheme: AppBarTheme(
          backgroundColor: bgDark,
          elevation: 0,
          titleTextStyle: heading,
          iconTheme: const IconThemeData(color: textPrimary),
        ),
        colorScheme: ColorScheme.dark(
          primary: accentBlue,
          secondary: accentGreen,
          surface: bgCard,
          error: accentRed,
        ),
      );
}
