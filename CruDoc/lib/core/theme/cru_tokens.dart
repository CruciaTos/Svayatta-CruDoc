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

  /// Summary strips above a list ("₹78,400 outstanding").
  static const double strip = 16;

  /// Inset panels inside the preview pane (balance block).
  static const double panel = 14;

  /// The 52 px import tile on the first-week panel.
  static const double largeTile = 15;

  /// 6 px linear progress bars.
  static const double thinBar = 3;

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

  /// Main padding below [CruBreakpoint.compact] (as the dashboard).
  static const EdgeInsets mainPaddingCompact =
      EdgeInsets.fromLTRB(12, 24, 24, 24);

  /// The "Bring your existing patients" panel.
  static const EdgeInsets firstWeekPanel = EdgeInsets.fromLTRB(32, 40, 32, 36);
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

  /// Patients list (design/patients-redesign).
  static const double searchBar = 44;
  static const double filterChip = 36;
  static const double tableRow = 64;
  static const double compactRow = 62;
  static const double groupHeader = 38;
  static const double tableHeader = 44;
  static const double monogramList = 36;
  static const double previewPane = 420;
  static const double monogramPreview = 56;
  static const double squareButton = 36;
  static const double infoPill = 28;
  static const double actionTile = 60;
  static const double progressBar = 6;
  static const double largeTile = 52;

  /// Patients table fixed columns (the flexible Patient and Condition
  /// columns share the rest 2.1 : 2.3).
  static const double tableAgeColumn = 64;
  static const double tableLastVisitColumn = 124;
  static const double tableNextVisitColumn = 148;
  static const double tableBalanceColumn = 92;
  static const double tableChevronColumn = 16;

  /// Below this card width the table drops the Age and Next visit
  /// columns so names stay readable.
  static const double tableNarrow = 720;

  /// "Send reminders" / "Message all" on a summary strip.
  static const double stripButton = 36;

  /// First-week panel: lead paragraph and hint-card grid widths.
  static const double leadMaxWidth = 520;
  static const double hintGridMaxWidth = 760;

  /// Below this width the hint cards stack.
  static const double hintGridColumns = 560;

  /// The "Send reminders" dialog.
  static const double remindersDialog = 480;

  /// Patient details.
  static const double monogramProfile = 76;
  static const double stepperNode = 24;
  static const double dateTileWidth = 44;
  static const double dateTileHeight = 48;
  static const double historyKeyColumn = 104;
  static const double composer = 48;

  /// Stepper: current-step dot, connector line, "Next" pill.
  static const double stepperDot = 8;
  static const double stepperConnector = 2;
  static const double nextPill = 24;

  /// Capsules: row actions ("Book", "Update"), the "Record payment"
  /// capsule on an inset panel, and Call / WhatsApp beside the profile.
  static const double rowCapsule = 28;
  static const double panelCapsule = 32;
  static const double profileCapsule = 36;

  /// On-token dialogs (Record payment, Delete patient).
  static const double dialog = 420;

  /// Desktop form dialogs (Add patient, …): section label column, the
  /// minimum width of a tag input and a tag's remove button.
  static const double formDialog = 760;
  static const double formSectionLabel = 184;
  static const double formTagInput = 140;
  static const double formTagClose = 20;

  /// Patients table separators: row padding 16 + monogram 36 + gap 12.
  static const double patientTextInset = 64;

  /// Visit row separators: padding 12 + date tile 44 + gap 12.
  static const double visitTextInset = 68;

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

  /// Patients: below this the preview pane slides over the list as a
  /// sheet instead of splitting it.
  static const double splitPane = 1200;

  /// Patients: below this a row opens Patient details directly.
  static const double phone = 800;

  /// Patient details: available content width for the two-column
  /// layout (left flexible + 384 px right column).
  static const double detailsTwoColumn = 900;

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

  /// Patients preview pane sliding in (opacity + 16 px from the right).
  static const Duration pane = Duration(milliseconds: 240);

  /// Summary strips fading in above a list.
  static const Duration strip = Duration(milliseconds: 220);

  /// [standard], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, [Duration d = standard]) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : d;
}
