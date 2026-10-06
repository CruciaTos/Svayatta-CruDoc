import 'package:flutter/material.dart';

import 'package:crudoc_shared/theme/app_colors.dart';
import 'package:crudoc_shared/theme/cru_colors.dart';
import 'package:crudoc_shared/theme/cru_input_border.dart';
import 'package:crudoc_shared/theme/cru_tokens.dart';
import 'package:crudoc_shared/theme/cru_type.dart';

export 'package:crudoc_shared/theme/cru_colors.dart';
export 'package:crudoc_shared/theme/cru_input_border.dart';
export 'package:crudoc_shared/theme/cru_tokens.dart';
export 'package:crudoc_shared/theme/cru_type.dart';

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
    final scheme =
        ColorScheme.fromSeed(
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
      inputDecorationTheme: _inputs(c),
      datePickerTheme: _datePicker(c),
      timePickerTheme: _timePicker(c),
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
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(CruRadius.control),
          side: BorderSide(color: c.hairline),
        ),
        textStyle: CruType.text.copyWith(color: c.label),
        labelTextStyle: WidgetStatePropertyAll(
          CruType.text.copyWith(color: c.label),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
          side: BorderSide(color: c.cardBorder),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dialogTheme: const DialogThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(elevation: 0),
      snackBarTheme: const SnackBarThemeData(elevation: 0),
      extensions: [c],
    );
  }

  /// Text fields: inset fill at rest, surface fill with a 1.5 px accent
  /// ring on focus, an amber ring on a validation error (red is kept for
  /// allergies). A field that passes its own `border` keeps it.
  static InputDecorationThemeData _inputs(CruColors c) {
    return InputDecorationThemeData(
      filled: true,
      fillColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.focused) ? c.surface : c.inset,
      ),
      hoverColor: (c.isEvening ? CruBrand.white : const Color(0xFF000000))
          .withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s14,
        vertical: CruSpace.s12,
      ),
      hintStyle: CruType.input.tint(c.label3),
      labelStyle: CruType.subhead.w500.tint(c.label2),
      floatingLabelStyle: CruType.subhead.w500.tint(c.label2),
      helperStyle: CruType.caption.tint(c.label3),
      errorStyle: CruType.caption.w500.tint(c.amberText),
      errorMaxLines: 2,
      prefixStyle: CruType.input.w500.tint(c.label2),
      suffixStyle: CruType.input.tint(c.label3),
      prefixIconColor: c.label3,
      suffixIconColor: c.label3,
      border: CruStateInputBorder(
        rest: BorderSide(color: c.inset.withValues(alpha: 0), width: 1.5),
        focused: BorderSide(color: c.accent, width: 1.5),
        error: BorderSide(color: c.amber, width: 1.5),
      ),
    );
  }

  /// Text buttons in pickers: Cancel quiet, OK in the accent.
  static ButtonStyle _pickerButton(Color color) => TextButton.styleFrom(
    foregroundColor: color,
    textStyle: CruType.text.w600,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
    ),
  );

  static ShapeBorder _pickerShape(CruColors c) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(CruRadius.card),
    side: BorderSide(color: c.cardBorder),
  );

  /// [color] when selected, [rest] otherwise.
  static WidgetStateColor _selected(Color color, Color rest) =>
      WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected) ? color : rest,
      );

  static DatePickerThemeData _datePicker(CruColors c) {
    final day = WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return c.onAccent;
      if (states.contains(WidgetState.disabled)) {
        return c.label3.withValues(alpha: 0.5);
      }
      return c.label;
    });
    return DatePickerThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: _pickerShape(c),
      headerBackgroundColor: c.surface,
      headerForegroundColor: c.label,
      headerHeadlineStyle: CruType.title2.tabular,
      headerHelpStyle: CruType.subhead.w500,
      subHeaderForegroundColor: c.label2,
      weekdayStyle: CruType.caption.w500.tint(c.label3),
      dayStyle: CruType.body.tabular,
      dayForegroundColor: day,
      dayBackgroundColor: _selected(c.accent, Colors.transparent),
      dayOverlayColor: WidgetStatePropertyAll(c.accent.withValues(alpha: 0.08)),
      todayForegroundColor: _selected(c.onAccent, c.accent),
      todayBackgroundColor: _selected(c.accent, Colors.transparent),
      todayBorder: BorderSide(color: c.accent),
      yearStyle: CruType.body.tabular,
      yearForegroundColor: day,
      yearBackgroundColor: _selected(c.accent, Colors.transparent),
      yearOverlayColor: WidgetStatePropertyAll(
        c.accent.withValues(alpha: 0.08),
      ),
      rangePickerBackgroundColor: c.surface,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerShadowColor: Colors.transparent,
      rangePickerElevation: 0,
      rangePickerShape: _pickerShape(c),
      rangePickerHeaderBackgroundColor: c.surface,
      rangePickerHeaderForegroundColor: c.label,
      rangePickerHeaderHeadlineStyle: CruType.title2.tabular,
      rangePickerHeaderHelpStyle: CruType.subhead.w500,
      rangeSelectionBackgroundColor: c.accentTint,
      dividerColor: c.separator,
      cancelButtonStyle: _pickerButton(c.label2),
      confirmButtonStyle: _pickerButton(c.accent),
    );
  }

  static TimePickerThemeData _timePicker(CruColors c) {
    final segment = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
    );
    return TimePickerThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      shape: _pickerShape(c),
      helpTextStyle: CruType.subhead.w500.tint(c.label2),
      hourMinuteShape: segment,
      hourMinuteColor: _selected(c.accent, c.inset),
      hourMinuteTextColor: _selected(c.onAccent, c.label),
      hourMinuteTextStyle: CruType.largeTitle.copyWith(
        fontSize: 44,
        height: 52 / 44,
        fontWeight: FontWeight.w500,
        fontFeatures: CruType.tabular,
      ),
      timeSelectorSeparatorColor: WidgetStatePropertyAll(c.label),
      dayPeriodShape: segment,
      dayPeriodBorderSide: BorderSide(color: c.separator),
      dayPeriodColor: _selected(c.accent, Colors.transparent),
      dayPeriodTextColor: _selected(c.onAccent, c.label2),
      dayPeriodTextStyle: CruType.subhead.w600,
      dialBackgroundColor: c.inset,
      dialHandColor: c.accent,
      dialTextColor: _selected(c.onAccent, c.label),
      dialTextStyle: CruType.body.tabular,
      entryModeIconColor: c.label2,
      cancelButtonStyle: _pickerButton(c.label2),
      confirmButtonStyle: _pickerButton(c.accent),
    );
  }
}
