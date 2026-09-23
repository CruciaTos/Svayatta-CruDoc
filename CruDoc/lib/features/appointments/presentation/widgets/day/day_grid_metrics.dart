import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Geometry of the Day grid (html/ApptsDay.dc.html). Sizes with no
/// shared token are private to the grid; see NEEDS.md (Builder 1).
abstract final class DayGridMetrics {
  /// 1.6 px per minute: an hour is 96 px.
  static const double pxPerMinute = 1.6;

  /// The time gutter left of the blocks.
  static const double gutter = CruSize.timeColumn;

  /// Hour labels are right-aligned in this width, 12 px before the line.
  static const double hourLabelWidth = gutter - CruSpace.s12;

  /// Blocks start 8 px after the gutter and stop 8 px before the edge.
  static const double blockLeft = gutter + CruSpace.s8;
  static const double blockRight = CruSpace.s8;

  /// Gap between side-by-side blocks in an overlap group.
  static const double blockGap = CruSpace.s4;

  /// Block corner radius (no token: NEEDS.md "CruRadius.block").
  static const double blockRadius = 8;

  /// Selection ring width.
  static const double ring = 2;

  /// Visits this long or shorter draw on one line.
  static const int oneLineMaxMinutes = 20;

  /// Now line: 2 px line, 10 px dot, 18 px time pill.
  static const double nowLine = 2;
  static const double nowDot = 10;
  static const double gutterPill = 18;

  /// Overlap marker bar in the gutter.
  static const double markerBar = 4;

  /// The collapsed break band between sessions (not to scale).
  static const double breakBand = 44;

  /// Room above the first hour line for its label.
  static const double topInset = CruSpace.s8;

  static double minutes(int m) => m * pxPerMinute;
}
