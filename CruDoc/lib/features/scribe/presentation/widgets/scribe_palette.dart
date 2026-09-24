import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';

/// Colour and shape tokens for the scribe UI.
///
/// The scribe widgets are shared between mobile and desktop, but each shell
/// has its own visual language: mobile uses the [AppColors] tokens from the
/// visit/session screens, desktop uses the slate palette of the other
/// desktop tabs (Queue, Inventory…). Pick [mobile] or [desktop] so the scribe
/// matches the screen it's opened from.
@immutable
class ScribePalette {
  const ScribePalette({
    required this.textPrimary,
    required this.textSecondary,
    required this.hint,
    required this.border,
    required this.card,
    required this.cardBorder,
    required this.field,
    required this.fieldBorder,
    required this.primary,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.success,
    required this.symptom,
    required this.diagnosis,
    required this.existing,
    required this.cardRadius,
    required this.fieldRadius,
    required this.labelsOutsideCards,
  });

  final Color textPrimary;
  final Color textSecondary;
  final Color hint;
  final Color border;

  /// Background of a section card.
  final Color card;
  final Color cardBorder;

  /// Fill of text inputs.
  final Color field;

  /// Outline of text inputs, or null for borderless filled inputs.
  final Color? fieldBorder;

  /// Main call-to-action colour (start, confirm, save).
  final Color primary;

  /// Informational highlights (AI notices, links, focus rings).
  final Color accent;
  final Color accentSoft;

  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final Color success;

  /// Chip colours for the editable lists.
  final Color symptom;
  final Color diagnosis;
  final Color existing;

  final double cardRadius;
  final double fieldRadius;

  /// Mobile screens put the uppercase section label above the card (as in
  /// Visit Details); desktop puts it inside the card.
  final bool labelsOutsideCards;

  static const mobile = ScribePalette(
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    hint: Color(0xFF9CA3AF),
    border: AppColors.divider,
    card: AppColors.cardSurface,
    cardBorder: Color(0x0FFFFFFF),
    field: AppColors.inputBackground,
    fieldBorder: null,
    primary: AppColors.slateBlue,
    accent: AppColors.accentBlue,
    accentSoft: Color(0xFFEAF5FC),
    // Matches the accents of Visit Details / Session Details.
    danger: Color(0xFFE57373),
    dangerSoft: Color(0xFFFDEDED),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFEF6E7),
    success: Color(0xFF48C9B0),
    symptom: AppColors.accentBlue,
    diagnosis: Color(0xFF8B5CF6),
    existing: Color(0xFF0D9488),
    cardRadius: 16,
    fieldRadius: 12,
    labelsOutsideCards: true,
  );

  static const desktop = ScribePalette(
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    hint: Color(0xFF94A3B8),
    border: Color(0xFFE2E8F0),
    card: Colors.white,
    cardBorder: Color(0xFFE2E8F0),
    field: Color(0xFFF8FAFC),
    fieldBorder: Color(0xFFE2E8F0),
    primary: Color(0xFF0284C7),
    accent: Color(0xFF0284C7),
    accentSoft: Color(0xFFF0F9FF),
    danger: Color(0xFFF43F5E),
    dangerSoft: Color(0xFFFFF1F2),
    warning: Color(0xFFF59E0B),
    warningSoft: Color(0xFFFFFBEB),
    success: Color(0xFF10B981),
    symptom: Color(0xFF0EA5E9),
    diagnosis: Color(0xFF7C3AED),
    existing: Color(0xFF10B981),
    cardRadius: 14,
    fieldRadius: 10,
    labelsOutsideCards: false,
  );

  /// Mobile tokens for content on the light bottom-sheet surface, where the
  /// default card colour would be invisible against the sheet.
  static final mobileSheet = mobile.copyWith(
    card: Colors.white,
    cardBorder: AppColors.divider,
  );

  ScribePalette copyWith({Color? card, Color? cardBorder}) => ScribePalette(
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    hint: hint,
    border: border,
    card: card ?? this.card,
    cardBorder: cardBorder ?? this.cardBorder,
    field: field,
    fieldBorder: fieldBorder,
    primary: primary,
    accent: accent,
    accentSoft: accentSoft,
    danger: danger,
    dangerSoft: dangerSoft,
    warning: warning,
    warningSoft: warningSoft,
    success: success,
    symptom: symptom,
    diagnosis: diagnosis,
    existing: existing,
    cardRadius: cardRadius,
    fieldRadius: fieldRadius,
    labelsOutsideCards: labelsOutsideCards,
  );

  TextStyle get sectionLabel => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: textSecondary.withValues(alpha: 0.85),
  );

  InputDecoration fieldDecoration(String hint, {bool dense = false}) {
    OutlineInputBorder outline(Color? color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: this.hint, fontSize: dense ? 12.5 : 13.5),
      filled: true,
      fillColor: field,
      isDense: dense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: dense ? 10 : 12,
      ),
      border: outline(fieldBorder),
      enabledBorder: outline(fieldBorder),
      focusedBorder: outline(accent, 1.5),
    );
  }
}
