import 'package:flutter/painting.dart';

/// Calm Clinical type scale (DESIGN_SPEC.md §2.3). Geist is bundled as an
/// asset. Styles carry no colour: widgets apply one from `CruColors`.
///
/// Letter spacing is already converted to logical pixels.
abstract final class CruType {
  static const String family = 'Geist';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle largeTitle = TextStyle(
    fontFamily: family,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.66,
  );

  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );

  /// Glance numbers and totals. Always tabular.
  static const TextStyle metric = TextStyle(
    fontFamily: family,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.56,
    fontFeatures: tabular,
  );

  /// The quieter "of 13" beside a metric.
  static const TextStyle metricSuffix = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 34 / 17,
    fontWeight: FontWeight.w500,
    fontFeatures: tabular,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.17,
  );

  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// Patient names in lists and 44 px buttons.
  static const TextStyle row = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle nav = TextStyle(
    fontFamily: family,
    fontSize: 14.5,
    height: 20 / 14.5,
    fontWeight: FontWeight.w500,
  );

  /// List item titles.
  static const TextStyle callout = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 19 / 14,
    fontWeight: FontWeight.w600,
  );

  /// 14 px running text (search input, insights, secondary buttons).
  static const TextStyle text = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Header date line.
  static const TextStyle dateLine = TextStyle(
    fontFamily: family,
    fontSize: 13.5,
    height: 18 / 13.5,
    fontWeight: FontWeight.w500,
  );

  /// Profile row name.
  static const TextStyle profileName = TextStyle(
    fontFamily: family,
    fontSize: 13.5,
    height: 18 / 13.5,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle subhead = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 12.5,
    height: 16 / 12.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: family,
    fontSize: 11.5,
    height: 14 / 11.5,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle groupLabel = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
  );

  /// Wordmark beside the app mark.
  static const TextStyle wordmark = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.17,
  );

  /// Monogram initials; the size scales with the avatar.
  static TextStyle monogram(double size) => TextStyle(
        fontFamily: family,
        fontSize: size,
        height: 1,
        fontWeight: FontWeight.w600,
      );
}

extension CruTextStyleX on TextStyle {
  /// Tabular figures for times, counts, rupees and vitals.
  TextStyle get tabular => copyWith(fontFeatures: CruType.tabular);

  TextStyle get w500 => copyWith(fontWeight: FontWeight.w500);
  TextStyle get w600 => copyWith(fontWeight: FontWeight.w600);
  TextStyle tint(Color color) => copyWith(color: color);
}
