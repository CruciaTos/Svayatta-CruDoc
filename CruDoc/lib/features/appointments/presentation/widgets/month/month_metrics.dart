import 'package:flutter/painting.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Month sizes from design/clinic-redesign/html/ApptsMonth.dc.html.
/// Sizes with no design token are private to the Month view and listed in
/// NEEDS.md (Builder 2).
abstract final class MonthMetrics {
  /// Tiles are 112 px tall. No token.
  static const double tileHeight = 112;

  /// Tile radius (16, the strip radius).
  static const double tileRadius = CruRadius.strip;

  /// Gap between tiles and between weekday labels.
  static const double gap = CruSpace.s8;

  /// Tile padding: 8 top, 10 sides, 10 bottom.
  static const EdgeInsets tilePadding = EdgeInsets.fromLTRB(
    CruSpace.s10,
    CruSpace.s8,
    CruSpace.s10,
    CruSpace.s10,
  );

  /// Date row height and today's filled circle (26). No token (CruSize.pill
  /// is the same number but a different element).
  static const double dateRow = 26;

  /// Selected tile ring.
  static const double ringWidth = CruSpace.s2;

  /// Day panel rows are 50 px tall. No token.
  static const double panelRow = 50;

  /// Time column in day panel and Agenda rows ("10:30 AM"). No token.
  static const double timeColumn = 76;

  /// Opacity of past tiles ("55% white").
  static const double pastTileAlpha = 0.55;
}
