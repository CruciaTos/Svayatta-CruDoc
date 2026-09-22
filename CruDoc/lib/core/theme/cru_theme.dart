import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/core/theme/cru_tokens.dart';
import 'package:doctor_management_app/core/theme/cru_type.dart';

export 'package:doctor_management_app/core/theme/cru_colors.dart';
export 'package:doctor_management_app/core/theme/cru_tokens.dart';
export 'package:doctor_management_app/core/theme/cru_type.dart';

/// Builds [ThemeData] for the Calm Clinical design.
///
/// [CruTheme.day] is the app-wide theme. [CruTheme.evening] is applied
/// only around the desktop shell chrome and the dashboard: the other
/// screens paint their own light panels and rely on default dark text,
/// so they always stay on Day.
abstract final class CruTheme {
  static ThemeData day() => _build(CruColors.day);

  static ThemeData evening() => _build(CruColors.evening);

  static ThemeData of(CruAppearance appearance) =>
      appearance == CruAppearance.evening ? evening() : day();

  static ThemeData _build(CruColors c) {
    final brightness = c.isEvening ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.surface,
      onSurface: c.label,
      onSurfaceVariant: c.label2,
      outlineVariant: c.separator,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // Default family for text that doesn't name one. Existing screens
      // that set PlusJakartaSans explicitly keep it.
      fontFamily: CruType.family,
      colorScheme: scheme,
      primaryColor: c.accent,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      dividerColor: c.separator,
      // Same sizes the app used before the redesign so other screens
      // keep their layout; only their colours come from the new palette.
      textTheme: TextTheme(
        displayLarge: AppColors.pageHeading.copyWith(color: c.label),
        headlineSmall: AppColors.sectionHeading.copyWith(color: c.label),
        bodyLarge: AppColors.bodyLarge.copyWith(color: c.label),
        bodyMedium: AppColors.bodyMedium.copyWith(color: c.label),
        bodySmall: AppColors.bodySmall.copyWith(color: c.label2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accentTint,
        selectionHandleColor: c.accent,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: CruType.caption.copyWith(color: c.surface),
        decoration: BoxDecoration(
          color: c.label,
          borderRadius: BorderRadius.circular(CruRadius.keycap),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: c.isEvening ? 0 : 8,
        shadowColor: c.label.withValues(alpha: 0.18),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(CruRadius.control),
          side: BorderSide(color: c.hairline),
        ),
        textStyle: CruType.text.copyWith(color: c.label),
        labelTextStyle: WidgetStatePropertyAll(
          CruType.text.copyWith(color: c.label),
        ),
      ),
      extensions: [c],
    );
  }
}
