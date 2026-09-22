import 'package:flutter/material.dart';

/// Ink Blue brand scale (OKLCH hue 267). The only blue in the product.
///
/// Widgets should read semantic colours from [CruColors] instead; the
/// scale exists so the semantic tokens below have one source.
abstract final class CruBrand {
  static const Color ink50 = Color(0xFFF4F7FE);
  static const Color ink100 = Color(0xFFE5EDFF);
  static const Color ink200 = Color(0xFFC9D9FE);
  static const Color ink300 = Color(0xFFA1BCFF);
  static const Color ink400 = Color(0xFF7399FF);
  static const Color ink500 = Color(0xFF4973F8);
  static const Color ink600 = Color(0xFF3155E0);
  static const Color ink700 = Color(0xFF2542BD);
  static const Color ink800 = Color(0xFF1D3591);
  static const Color ink900 = Color(0xFF152764);

  static const Color white = Color(0xFFFFFFFF);
}

/// Which colour set is active. Day is for opening hours; Evening runs
/// from the evening session until close (see the appearance provider).
enum CruAppearance { day, evening }

/// Semantic colour tokens for the Calm Clinical design.
///
/// Every colour means something (see DESIGN_SPEC.md §1): accent is brand
/// and "now", amber is waiting, green is done, red is allergies/safety
/// only, violet ([ai]) is AI-generated content only, teal is labs.
@immutable
class CruColors extends ThemeExtension<CruColors> {
  const CruColors({
    required this.appearance,
    required this.canvas,
    required this.surface,
    required this.inset,
    required this.track,
    required this.label,
    required this.label2,
    required this.label3,
    required this.separator,
    required this.hairline,
    required this.ink,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentTint,
    required this.accentWash,
    required this.amber,
    required this.amberText,
    required this.amberTint,
    required this.green,
    required this.greenText,
    required this.greenTint,
    required this.redText,
    required this.redTint,
    required this.ai,
    required this.aiTint,
    required this.tealText,
    required this.tealTint,
    required this.sidebarSelected,
    required this.segmentSelected,
    required this.hoverFill,
    required this.cardShadow,
    required this.segmentShadow,
    required this.inkShadow,
    required this.paneShadow,
    required this.inkBorder,
    required this.primaryButtonFill,
    required this.primaryButtonText,
    required this.allergyChipFill,
    required this.allergyChipText,
  });

  final CruAppearance appearance;

  final Color canvas;
  final Color surface;
  final Color inset;

  /// Rings, bars and monograms.
  final Color track;

  final Color label;
  final Color label2;

  /// Timestamps and quiet metadata only.
  final Color label3;

  final Color separator;

  /// Card borders.
  final Color hairline;

  /// Up next card surface.
  final Color ink;

  /// Fills: primary button, app mark, "now" dot, progress.
  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color accentTint;

  /// The current ("now") schedule row.
  final Color accentWash;

  final Color amber;
  final Color amberText;
  final Color amberTint;

  final Color green;
  final Color greenText;
  final Color greenTint;

  final Color redText;
  final Color redTint;

  final Color ai;
  final Color aiTint;

  final Color tealText;
  final Color tealTint;

  final Color sidebarSelected;
  final Color segmentSelected;

  /// Inset fill that rows and buttons take on hover.
  final Color hoverFill;

  /// Elevation for cards, search, selected sidebar item. Empty in Evening.
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> segmentShadow;

  /// Up next card elevation (Day only).
  final List<BoxShadow> inkShadow;

  /// Raised panels that float beside a list (the Patients preview pane).
  final List<BoxShadow> paneShadow;

  /// Up next card border (Evening only).
  final Color inkBorder;

  /// The single filled action. On the Up next card it inverts to white
  /// with ink text; everywhere else it is the accent.
  final Color primaryButtonFill;
  final Color primaryButtonText;

  final Color allergyChipFill;
  final Color allergyChipText;

  bool get isEvening => appearance == CruAppearance.evening;

  static const CruColors day = CruColors(
    appearance: CruAppearance.day,
    canvas: Color(0xFFF1F4F9),
    surface: Color(0xFFFFFFFF),
    inset: Color(0xFFF2F4F7),
    track: Color(0xFFE6EAF0),
    label: Color(0xFF1D1D1F),
    label2: Color(0xFF6E6E73),
    label3: Color(0xFF86868B),
    separator: Color(0x14101828),
    hairline: Color(0x0F101828),
    ink: CruBrand.ink700,
    accent: CruBrand.ink600,
    onAccent: CruBrand.white,
    accentText: CruBrand.ink600,
    accentTint: CruBrand.ink100,
    accentWash: CruBrand.ink50,
    amber: Color(0xFFFF9F0A),
    amberText: Color(0xFFB25000),
    amberTint: Color(0xFFFFF4E5),
    green: Color(0xFF34C759),
    greenText: Color(0xFF248A3D),
    greenTint: Color(0xFFEAF8EE),
    redText: Color(0xFFD70015),
    redTint: Color(0xFFFDECEC),
    ai: Color(0xFF8031C0),
    aiTint: Color(0xFFF8F3FF),
    tealText: Color(0xFF0E7490),
    tealTint: Color(0xFFE6F4F6),
    sidebarSelected: Color(0xFFFFFFFF),
    segmentSelected: Color(0xFFFFFFFF),
    hoverFill: Color(0xFFF2F4F7),
    cardShadow: [
      BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
    ],
    segmentShadow: [
      BoxShadow(color: Color(0x1F101828), blurRadius: 3, offset: Offset(0, 1)),
    ],
    inkShadow: [
      BoxShadow(color: Color(0x332542BD), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x992542BD),
        blurRadius: 40,
        spreadRadius: -24,
        offset: Offset(0, 24),
      ),
    ],
    paneShadow: [
      BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x24101828),
        blurRadius: 32,
        spreadRadius: -16,
        offset: Offset(0, 16),
      ),
    ],
    inkBorder: Color(0x00000000),
    primaryButtonFill: CruBrand.ink600,
    primaryButtonText: CruBrand.white,
    allergyChipFill: CruBrand.white,
    allergyChipText: Color(0xFFD70015),
  );

  static const CruColors evening = CruColors(
    appearance: CruAppearance.evening,
    canvas: Color(0xFF111214),
    surface: Color(0xFF1C1D20),
    inset: Color(0xFF26272B),
    track: Color(0xFF313237),
    label: Color(0xFFF5F5F7),
    label2: Color(0xFFA1A1A6),
    label3: Color(0xFF8E8E93),
    separator: Color(0x14FFFFFF),
    hairline: Color(0x0FFFFFFF),
    ink: CruBrand.ink800,
    accent: CruBrand.ink600,
    onAccent: CruBrand.white,
    accentText: CruBrand.ink400,
    accentTint: Color(0x384973F8),
    accentWash: Color(0x1A4973F8),
    amber: Color(0xFFFF9F0A),
    amberText: Color(0xFFFFB340),
    amberTint: Color(0x24FF9F0A),
    green: Color(0xFF30D158),
    greenText: Color(0xFF30D158),
    greenTint: Color(0x2430D158),
    redText: Color(0xFFFF7A70),
    redTint: Color(0x29FF453A),
    ai: Color(0xFFB98CEA),
    aiTint: Color(0x24B98CEA),
    tealText: Color(0xFF5EC8D0),
    tealTint: Color(0x245EC8D0),
    sidebarSelected: Color(0xFF26272B),
    segmentSelected: Color(0xFF3A3B40),
    hoverFill: Color(0xFF26272B),
    cardShadow: [],
    segmentShadow: [
      BoxShadow(color: Color(0x59000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
    inkShadow: [],
    paneShadow: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 32,
        spreadRadius: -16,
        offset: Offset(0, 16),
      ),
    ],
    inkBorder: Color(0x0FFFFFFF),
    primaryButtonFill: CruBrand.ink600,
    primaryButtonText: CruBrand.white,
    allergyChipFill: CruBrand.white,
    allergyChipText: Color(0xFFD70015),
  );

  /// Scoped overrides for content sitting on the Up next ink surface.
  CruColors onInk() {
    final isEve = isEvening;
    return copyWith(
      label: CruBrand.white,
      label2: const Color(0xFFD3E0FF),
      label3: const Color(0xFFB4C8FF),
      inset: isEve ? const Color(0x1AFFFFFF) : const Color(0x1FFFFFFF),
      hoverFill: isEve ? const Color(0x24FFFFFF) : const Color(0x29FFFFFF),
      track: isEve ? const Color(0x24FFFFFF) : const Color(0x29FFFFFF),
      accentText: CruBrand.white,
      amberTint: isEve ? const Color(0x1AFFFFFF) : const Color(0x1FFFFFFF),
      amberText: const Color(0xFFFFD08A),
      primaryButtonFill: CruBrand.white,
      primaryButtonText: ink,
    );
  }

  /// The colours for [appearance].
  static CruColors of(CruAppearance appearance) =>
      appearance == CruAppearance.evening ? evening : day;

  @override
  CruColors copyWith({
    Color? label,
    Color? label2,
    Color? label3,
    Color? inset,
    Color? hoverFill,
    Color? track,
    Color? accentText,
    Color? amberTint,
    Color? amberText,
    Color? primaryButtonFill,
    Color? primaryButtonText,
  }) {
    return CruColors(
      appearance: appearance,
      canvas: canvas,
      surface: surface,
      inset: inset ?? this.inset,
      track: track ?? this.track,
      label: label ?? this.label,
      label2: label2 ?? this.label2,
      label3: label3 ?? this.label3,
      separator: separator,
      hairline: hairline,
      ink: ink,
      accent: accent,
      onAccent: onAccent,
      accentText: accentText ?? this.accentText,
      accentTint: accentTint,
      accentWash: accentWash,
      amber: amber,
      amberText: amberText ?? this.amberText,
      amberTint: amberTint ?? this.amberTint,
      green: green,
      greenText: greenText,
      greenTint: greenTint,
      redText: redText,
      redTint: redTint,
      ai: ai,
      aiTint: aiTint,
      tealText: tealText,
      tealTint: tealTint,
      sidebarSelected: sidebarSelected,
      segmentSelected: segmentSelected,
      hoverFill: hoverFill ?? this.hoverFill,
      cardShadow: cardShadow,
      segmentShadow: segmentShadow,
      inkShadow: inkShadow,
      paneShadow: paneShadow,
      inkBorder: inkBorder,
      primaryButtonFill: primaryButtonFill ?? this.primaryButtonFill,
      primaryButtonText: primaryButtonText ?? this.primaryButtonText,
      allergyChipFill: allergyChipFill,
      allergyChipText: allergyChipText,
    );
  }

  @override
  CruColors lerp(covariant CruColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return CruColors(
      appearance: t < 0.5 ? appearance : other.appearance,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      inset: c(inset, other.inset),
      track: c(track, other.track),
      label: c(label, other.label),
      label2: c(label2, other.label2),
      label3: c(label3, other.label3),
      separator: c(separator, other.separator),
      hairline: c(hairline, other.hairline),
      ink: c(ink, other.ink),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentText: c(accentText, other.accentText),
      accentTint: c(accentTint, other.accentTint),
      accentWash: c(accentWash, other.accentWash),
      amber: c(amber, other.amber),
      amberText: c(amberText, other.amberText),
      amberTint: c(amberTint, other.amberTint),
      green: c(green, other.green),
      greenText: c(greenText, other.greenText),
      greenTint: c(greenTint, other.greenTint),
      redText: c(redText, other.redText),
      redTint: c(redTint, other.redTint),
      ai: c(ai, other.ai),
      aiTint: c(aiTint, other.aiTint),
      tealText: c(tealText, other.tealText),
      tealTint: c(tealTint, other.tealTint),
      sidebarSelected: c(sidebarSelected, other.sidebarSelected),
      segmentSelected: c(segmentSelected, other.segmentSelected),
      hoverFill: c(hoverFill, other.hoverFill),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ??
          other.cardShadow,
      segmentShadow:
          BoxShadow.lerpList(segmentShadow, other.segmentShadow, t) ??
              other.segmentShadow,
      inkShadow:
          BoxShadow.lerpList(inkShadow, other.inkShadow, t) ?? other.inkShadow,
      paneShadow: BoxShadow.lerpList(paneShadow, other.paneShadow, t) ??
          other.paneShadow,
      inkBorder: c(inkBorder, other.inkBorder),
      primaryButtonFill: c(primaryButtonFill, other.primaryButtonFill),
      primaryButtonText: c(primaryButtonText, other.primaryButtonText),
      allergyChipFill: c(allergyChipFill, other.allergyChipFill),
      allergyChipText: c(allergyChipText, other.allergyChipText),
    );
  }
}

extension CruColorsContext on BuildContext {
  /// The Calm Clinical colours in scope. Falls back to Day when a widget
  /// is built under a theme that doesn't carry the extension.
  CruColors get cru => Theme.of(this).extension<CruColors>() ?? CruColors.day;
}
