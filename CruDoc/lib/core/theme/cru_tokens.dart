import 'package:flutter/widgets.dart';

/// Corner radii (DESIGN_SPEC.md §2.4). Inner radius = outer − inset.
abstract final class CruRadius {
  static const double card = 24;

  /// Rows, inner panels, full-width buttons, buttons and inputs.
  static const double control = 12;

  /// The clinic switcher button.
  static const double switcher = 14;

  static const double iconTile = 10;
  static const double appMark = 9;
  static const double segmentOuter = 11;
  static const double segmentInner = 8;

  /// Shortcut hint ("Ctrl K").
  static const double keycap = 6;

  /// Collections bars and the closed-day stub.
  static const double bar = 6;
  static const double barStub = 2;

  /// Chips, pills, capsule buttons and avatars.
  static const double full = 999;
}

/// 4-pt spacing grid (DESIGN_SPEC.md §2.5) plus the few named layout
/// values the reference uses.
abstract final class CruSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double s24 = 24;
  static const double s32 = 32;

  /// Gap between cards.
  static const double cardGap = 20;

  /// Vertical rhythm of the main column.
  static const double stackGap = 22;

  static const EdgeInsets sidebarPadding =
      EdgeInsets.fromLTRB(20, 24, 12, 20);
  static const EdgeInsets mainPadding = EdgeInsets.fromLTRB(12, 28, 32, 32);
}

/// Fixed sizes used by the layout and components.
abstract final class CruSize {
  static const double sidebar = 248;
  static const double sidebarCollapsed = 72;
  static const double rightColumn = 384;

  static const double appMark = 30;
  static const double navItem = 40;
  static const double navIcon = 20;
  static const double clinicTile = 32;

  static const double searchWidth = 300;
  static const double control = 40;
  static const double actionButton = 44;
  static const double capsule = 30;
  static const double chip = 30;
  static const double pill = 26;
  static const double segmentHeight = 36;
  static const double segmentItem = 30;

  static const double scheduleRow = 60;
  static const double collapsedRow = 48;
  static const double timeColumn = 64;
  static const double statusDot = 8;
  static const double smallDot = 6;

  static const double monogramRow = 34;
  static const double monogramUpNext = 56;
  static const double iconTile = 36;
  static const double progressRing = 52;
  static const double progressStroke = 6;

  static const double barWidth = 24;
  static const double barMaxHeight = 80;
  static const double barStub = 4;
  static const double barSlot = 34;
  static const double chartHeight = 124;

  /// Where schedule separators start: row padding 12 + time 64 + gap 14
  /// + dot 8 + gap 14 + monogram 34 + gap 14.
  static const double scheduleTextInset = 160;

  /// Needs attention separators: padding 12 + tile 36 + gap 12.
  static const double attentionTextInset = 60;
}

/// Window-width breakpoints (DESIGN_SPEC.md §3).
abstract final class CruBreakpoint {
  /// Two columns: main + 384 px right column.
  static const double wide = 1280;

  /// Below this the sidebar collapses to icons and everything is one
  /// column.
  static const double compact = 960;
}

/// Motion (DESIGN_SPEC.md §5): 200–250 ms, easeOutCubic, no bounce.
abstract final class CruMotion {
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOutCubic;
  static const double pressScale = 0.98;

  /// [standard], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, [Duration d = standard]) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : d;
}
