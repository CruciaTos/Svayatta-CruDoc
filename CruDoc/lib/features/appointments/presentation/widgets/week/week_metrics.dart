import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Week grid sizes from design/clinic-redesign/html/ApptsWeek.dc.html.
/// Sizes with no design token are private to the Week view and listed in
/// NEEDS.md (Builder 2) for the lead to promote or map.
abstract final class WeekMetrics {
  /// 1.2 px per minute (PROMPT.md, Week).
  static const double pxPerMinute = 1.2;

  /// Hour-label gutter, 60 px. No token.
  static const double gutter = 60;

  /// Every block is 22 px tall whatever its duration. No token.
  static const double blockHeight = 22;

  /// Blocks sit 3 px in from each side of their column. No token.
  static const double blockInset = 3;

  /// Gap between blocks of one overlap group.
  static const double overlapGap = CruSpace.s4;

  /// Filled circle behind today's date in the column header. No token.
  static const double dateCircle = 34;

  /// Now-line dot. No token.
  static const double nowDot = 10;

  /// Now-line thickness.
  static const double nowLine = CruSpace.s2;

  /// Time pill in the gutter. No token.
  static const double nowPill = 18;

  /// Collapsed break band between sessions. No token.
  static const double breakBand = 30;

  /// Hour labels sit 8 px above their line (half the micro line height).
  static const double hourLabelLift = CruSpace.s8;

  /// Hour labels end 10 px before the first column.
  static const double hourLabelEnd = CruSpace.s10;

  /// Space above and below the scrolling grid so the first and last hour
  /// labels aren't clipped.
  static const double gridTop = CruSpace.s14;
  static const double gridBottom = CruSpace.s8;

  /// Minutes of [t] since the midnight of [day] (handles a range that ends
  /// at midnight, which is the next calendar day).
  static int minuteOf(DateTime t, DateTime day) =>
      t.difference(DateTime(day.year, day.month, day.day)).inMinutes;
}
