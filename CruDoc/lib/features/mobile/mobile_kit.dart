import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The phone's five tabs, in bottom-nav order.
abstract final class MobileTab {
  static const home = 0;
  static const schedule = 1;
  static const patients = 2;
  static const revenue = 3;
  static const more = 4;
  static const count = 5;
}

/// Switches the phone's tab while the mobile shell is on screen; null
/// otherwise (desktop, sign-in).
final mobileTabSwitcherProvider = StateProvider<void Function(int tab)?>(
  (ref) => null,
);

/// The tab the phone is showing.
final mobileCurrentTabProvider = StateProvider<int>((ref) => MobileTab.home);

/// The phone palette (from the reference design): Neon Blue for every
/// action, Penn Blue for the darkest surfaces, Lavender and Periwinkle
/// for soft fills.
abstract final class MobileBlue {
  static const Color neon = Color(0xFF3960FB);
  static const Color deep = Color(0xFF2B4BDB);
  static const Color penn = Color(0xFF142258);
  static const Color lavender = Color(0xFFEBEFFF);
  static const Color periwinkle = Color(0xFFC2CEFE);

  /// Hairline around inner field boxes on white cards.
  static const Color field = Color(0xFFE6EAF4);
}

/// Phone spacing that depends on the device: room for the island at the
/// top, the blue band behind each header and the floating nav at the
/// bottom.
abstract final class MobileMetrics {
  /// Side margin of every phone page.
  static const double gutter = 16;

  /// The floating nav's height.
  static const double navHeight = 56;

  /// Status bar height, or the island's room in a narrow desktop window.
  static double _status(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).top;
    return pad >= 20 ? pad : 44;
  }

  /// Where page content starts.
  static double top(BuildContext context) => _status(context) + CruSpace.s12;

  /// Gap between the nav and the bottom of the screen.
  static double navBottom(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, CruSpace.s10) +
      CruSpace.s6;

  /// Scroll padding so the last row clears the floating nav.
  static double bottom(BuildContext context) =>
      navHeight + navBottom(context) + CruSpace.s24;
}

/// The phone's type scale: Geist, kept light like the reference. Titles
/// are medium or semibold, everything else regular; size and colour do
/// the ranking, not heavy weights.
abstract final class MobileType {
  static const String _f = CruType.family;
  static const List<FontFeature> _tab = CruType.tabular;

  static const largeTitle = TextStyle(
    fontFamily: _f,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );
  static const title = TextStyle(
    fontFamily: _f,
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const title2 = TextStyle(
    fontFamily: _f,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const metric = TextStyle(
    fontFamily: _f,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    fontFeatures: _tab,
  );
  static const metricSuffix = TextStyle(
    fontFamily: _f,
    fontSize: 15,
    height: 30 / 15,
    fontWeight: FontWeight.w400,
    fontFeatures: _tab,
  );

  /// Sheet titles.
  static const headline = TextStyle(
    fontFamily: _f,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Names and row titles.
  static const row = TextStyle(
    fontFamily: _f,
    fontSize: 15.5,
    height: 21 / 15.5,
    fontWeight: FontWeight.w500,
  );
  static const callout = TextStyle(
    fontFamily: _f,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
  );
  static const text = TextStyle(
    fontFamily: _f,
    fontSize: 15,
    height: 21 / 15,
    fontWeight: FontWeight.w400,
  );

  /// Second lines under a title.
  static const subhead = TextStyle(
    fontFamily: _f,
    fontSize: 13.5,
    height: 19 / 13.5,
    fontWeight: FontWeight.w400,
  );
  static const caption = TextStyle(
    fontFamily: _f,
    fontSize: 12.5,
    height: 17 / 12.5,
    fontWeight: FontWeight.w400,
  );

  /// Pills, tiny labels.
  static const micro = TextStyle(
    fontFamily: _f,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );
  static const chip = TextStyle(
    fontFamily: _f,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w400,
  );
  static const dateLine = TextStyle(
    fontFamily: _f,
    fontSize: 14,
    height: 19 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Card headings ("Quick actions").
  static const groupLabel = TextStyle(
    fontFamily: _f,
    fontSize: 15.5,
    height: 21 / 15.5,
    fontWeight: FontWeight.w500,
  );
  static const input = TextStyle(
    fontFamily: _f,
    fontSize: 15,
    height: 21 / 15,
    fontWeight: FontWeight.w400,
  );

  /// The blue capsule's label, in capitals like the reference.
  static const button = TextStyle(
    fontFamily: _f,
    fontSize: 14.5,
    height: 20 / 14.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}

/// Soft tints for icon tiles. The phone uses a few more colours than the
/// desktop to tell tasks apart at a glance; each is one quiet tint with a
/// strong glyph, so a grid reads calm rather than loud.
enum MobileTone { blue, sky, indigo, teal, green, amber, violet, slate }

/// (fill, glyph) for [tone] in the current appearance.
(Color, Color) mobileTone(CruColors c, MobileTone tone) {
  final eve = c.isEvening;
  return switch (tone) {
    MobileTone.blue =>
      eve
          ? (const Color(0x383960FB), CruBrand.ink300)
          : (MobileBlue.lavender, MobileBlue.neon),
    MobileTone.sky =>
      eve
          ? (const Color(0x2E38BDF8), const Color(0xFF7DD3FC))
          : (const Color(0xFFE2F2FD), const Color(0xFF0369A1)),
    MobileTone.indigo =>
      eve
          ? (const Color(0x336366F1), const Color(0xFFA5B4FC))
          : (const Color(0xFFECEBFD), const Color(0xFF4338CA)),
    MobileTone.teal =>
      eve
          ? (const Color(0x2914B8A6), const Color(0xFF5EEAD4))
          : (const Color(0xFFDDF4F1), const Color(0xFF0F766E)),
    MobileTone.green =>
      eve
          ? (const Color(0x2930D158), const Color(0xFF4ADE80))
          : (const Color(0xFFE2F5E7), const Color(0xFF15803D)),
    MobileTone.amber =>
      eve
          ? (const Color(0x29FF9F0A), const Color(0xFFFFB340))
          : (const Color(0xFFFFF0DB), const Color(0xFFB45309)),
    MobileTone.violet =>
      eve
          ? (const Color(0x2EB98CEA), const Color(0xFFCDB0F2))
          : (const Color(0xFFF2EAFB), const Color(0xFF7E3FC2)),
    MobileTone.slate => (c.inset, c.label2),
  };
}

/// Quick-action tile gradients (top-left, bottom-right) by position:
/// the first row of four in shades of blue, the second in shades of pink.
/// The glyph on them is white. Same in Day and Evening.
const List<(Color, Color)> _quickActionBlues = [
  (Color(0xFF7DD3FC), Color(0xFF0EA5E9)),
  (Color(0xFF60A5FA), Color(0xFF2563EB)),
  (Color(0xFF3B82F6), Color(0xFF1D4ED8)),
  (Color(0xFF2563EB), Color(0xFF1E3A8A)),
];
const List<(Color, Color)> _quickActionPinks = [
  (Color(0xFFFBCFE8), Color(0xFFF472B6)),
  (Color(0xFFF9A8D4), Color(0xFFEC4899)),
  (Color(0xFFF472B6), Color(0xFFDB2777)),
  (Color(0xFFEC4899), Color(0xFF9D174D)),
];

(Color, Color) mobileQuickActionGradient(int index) {
  final row = index < 4 ? _quickActionBlues : _quickActionPinks;
  return row[index % 4];
}

/// Icon fills: one blue family everywhere (lavender circle, blue glyph),
/// like the reference; only quiet utility icons stay grey. Colour is kept
/// for status pills (waiting, done), not for icons.
(Color, Color) mobileGlyphTone(CruColors c, MobileTone tone) =>
    tone == MobileTone.slate
    ? mobileTone(c, tone)
    : mobileTone(c, MobileTone.blue);

/// Marks the tabs (not pushed pages) as sitting on the tab background,
/// so their headers can follow the Day look's ink.
class MobileTabSurface extends InheritedWidget {
  const MobileTabSurface({super.key, required super.child});

  static bool on(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileTabSurface>() != null;

  @override
  bool updateShouldNotify(MobileTabSurface oldWidget) => false;
}

/// True when text and glyphs straight on the background need to be
/// light: always in Evening; in Day on the tabs when the Day look is dark
/// at the top (pushed pages stay light, with dark text).
bool mobileOnDark(BuildContext context) =>
    context.cru.isEvening ||
    (kMobileDayLook.darkHeader && MobileTabSurface.on(context));

/// Text and glyphs at the top of every tab: white on a dark background,
/// dark on a light one.
Color mobileInk(BuildContext context) =>
    mobileOnDark(context) ? Colors.white : context.cru.label;

/// The edge on cards, fields and chips: a darker, slightly thicker grey in
/// light mode, the quiet hairline in dark mode.
BorderSide mobileBorder(CruColors c) => c.isEvening
    ? BorderSide(color: c.cardBorder)
    : const BorderSide(color: Color(0xFFB4BFCE), width: 1.5);

/// Light taps that confirm what a gesture did.
abstract final class MobileHaptics {
  static void select() => HapticFeedback.selectionClick();
  static void tap() => HapticFeedback.lightImpact();
  static void commit() => HapticFeedback.mediumImpact();
}

/// Pushes [page] over the whole phone screen. Cupertino routes slide in
/// and can be swiped back from the left edge on every phone.
Future<T?> pushMobile<T>(BuildContext context, Widget page) => Navigator.of(
  context,
  rootNavigator: true,
).push<T>(CupertinoPageRoute<T>(builder: (_) => page));

/// The root navigator's context: dialogs and sheets open from there.
BuildContext mobileRoot(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).context;

void mobileSay(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

/// The top of every tab, on the blue: an optional quiet line, a white
/// title and an optional action on the right.
class MobileHeader extends StatelessWidget {
  const MobileHeader({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.trailing,
    this.pushed = false,
  });

  final String title;
  final String? overline;
  final String? subtitle;
  final Widget? trailing;

  /// On a pushed page, under its back link: no status bar room.
  final bool pushed;

  @override
  Widget build(BuildContext context) {
    final ink = mobileInk(context);
    final soft = ink.withValues(alpha: 0.62);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MobileMetrics.gutter + CruSpace.s2,
        pushed ? CruSpace.s4 : MobileMetrics.top(context),
        MobileMetrics.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) ...[
                  Text(overline!, style: MobileType.dateLine.tint(soft)),
                  const SizedBox(height: CruSpace.s2),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MobileType.largeTitle.tint(ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(subtitle!, style: MobileType.subhead.tint(soft)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CruSpace.s12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A 44 px round button on the canvas: Neon Blue with a white glyph
/// for the tab's one "add", or white with a blue glyph.
class MobileCircleButton extends StatelessWidget {
  const MobileCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.filled = true,
    this.size = 44,
  });

  final CruIconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// A little stronger: the tab's one "add".
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onPressed == null
          ? null
          : () {
              MobileHaptics.tap();
              onPressed!();
            },
      semanticLabel: semanticLabel,
      builder: (context, hovered) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? Colors.white
              : (mobileOnDark(context) ? Colors.white : MobileBlue.neon)
                    .withValues(alpha: 0.18),
          boxShadow: [
            BoxShadow(
              color: MobileBlue.neon.withValues(alpha: filled ? 0.25 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CruIcon(
          icon,
          size: 20,
          strokeWidth: 2,
          color: filled ? MobileBlue.neon : mobileInk(context),
        ),
      ),
    );
  }
}

/// The phone's filled action: a solid Neon Blue capsule with a label in
/// capitals, like the reference's "SEARCH FLIGHT".
class MobilePrimaryButton extends StatelessWidget {
  const MobilePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final CruIconData? icon;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onPressed == null
          ? null
          : () {
              MobileHaptics.commit();
              onPressed!();
            },
      semanticLabel: label,
      builder: (context, _) => Container(
        height: 50,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: MobileBlue.neon,
          shadows: [
            BoxShadow(
              color: MobileBlue.neon.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              CruIcon(icon!, size: 15, strokeWidth: 2.2, color: Colors.white),
              const SizedBox(width: CruSpace.s8),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MobileType.button.tint(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded box inside a white card holding one fact: a small grey
/// label over its value (the reference's From / Departure fields).
class MobileField extends StatelessWidget {
  const MobileField({super.key, this.label, required this.child});

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(label!, style: MobileType.caption.tint(c.label3)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: ShapeDecoration(
            color: c.surface,
            shape: cruShape(CruRadius.control + 2, side: mobileBorder(c)),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// A white card: no outline in Day, just a soft blue-tinted lift off the
/// canvas; Evening keeps the hairline and no shadow.
class MobileCard extends StatelessWidget {
  const MobileCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        shape: cruShape(radius),
        shadows: c.isEvening
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF1D3591).withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      // The border is painted over the content: full-width rows paint
      // their own surface and would otherwise hide it along the sides.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: cruShape(radius, side: mobileBorder(c)),
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: c.surface,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
    if (onTap == null) return card;
    return CruPressable(
      onTap: () {
        MobileHaptics.tap();
        onTap!();
      },
      builder: (context, hovered) => card,
    );
  }
}

/// A person's monogram in a double ring: a thin gap in the page colour,
/// then a ring in the person's own colour that sweeps into a lighter
/// tint of it. [size] is the monogram's own size; the rings add 9 px.
class MobileAvatar extends StatelessWidget {
  const MobileAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (base, _) = CruMonogram.vibrantColorsOf(name, c.isEvening);
    final hsl = HSLColor.fromColor(base);
    final vivid = hsl
        .withSaturation((hsl.saturation + 0.2).clamp(0.0, 1.0))
        .withLightness(0.55)
        .toColor();
    final light = Color.lerp(vivid, Colors.white, 0.5)!;
    final ring = size >= 48 ? 3.0 : 2.5;
    final gap = size >= 48 ? 2.5 : 2.0;
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          startAngle: 0,
          endAngle: 6.2832,
          transform: const GradientRotation(-1.2),
          colors: [vivid, light, vivid, vivid],
          stops: const [0, 0.22, 0.5, 1],
        ),
      ),
      child: Container(
        padding: EdgeInsets.all(gap),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface),
        child: CruMonogram(name: name, size: size, showRing: false),
      ),
    );
  }
}

/// A round icon: lavender circle, blue glyph (grey for utility icons).
class MobileIconTile extends StatelessWidget {
  const MobileIconTile({
    super.key,
    required this.icon,
    required this.tone,
    this.size = 38,
    this.iconSize = 18,
    this.radius,
  });

  final CruIconData icon;
  final MobileTone tone;
  final double size;
  final double iconSize;

  /// Unused: tiles are circles. Kept so callers needn't change.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = mobileGlyphTone(context.cru, tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: CruIcon(icon, size: iconSize, strokeWidth: 1.8, color: fg),
    );
  }
}

/// A small status pill in a [MobileTone].
class MobilePill extends StatelessWidget {
  const MobilePill(this.text, {super.key, required this.tone, this.icon});

  final String text;
  final MobileTone tone;
  final CruIconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = mobileTone(context.cru, tone);
    return Container(
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 13, strokeWidth: 2.4, color: fg),
            const SizedBox(width: CruSpace.s4),
          ],
          Text(text, style: MobileType.micro.w600.tabular.tint(fg)),
        ],
      ),
    );
  }
}

/// One tappable row in a card. A long press opens [onLongPress] (an
/// actions sheet) with a firm tap so it is felt, not just seen.
class MobileRow extends StatelessWidget {
  const MobileRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.titleStyle,
    this.padding = const EdgeInsets.symmetric(
      horizontal: CruSpace.s16,
      vertical: CruSpace.s14,
    ),
    this.chevron = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry padding;

  /// Opens another page (iOS-style ›).
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                MobileHaptics.commit();
                onLongPress!();
              },
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hoverFill,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: CruSpace.s12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle ?? MobileType.row.tint(c.label),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.caption.tint(c.label2),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s10),
                trailing!,
              ],
              if (chevron) ...[
                const SizedBox(width: CruSpace.s8),
                CruIcon(
                  CruIcons.chevronRight,
                  size: 16,
                  strokeWidth: 2,
                  color: c.label3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A card's heading ("Quick actions") with an optional quiet link on the
/// right ("See all"), like the reference's "Flight Coupons!  See more".
class MobileGroupTitle extends StatelessWidget {
  const MobileGroupTitle(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.onBackground = false,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Straight on the page background rather than inside a card: takes the
  /// background's ink.
  final bool onBackground;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: MobileType.groupLabel.tint(
                onBackground ? mobileInk(context) : c.label,
              ),
            ),
          ),
          if (action != null)
            CruLink(
              label: action!,
              onPressed: onAction,
              style: MobileType.caption.copyWith(
                fontWeight: FontWeight.w500,
                color: MobileBlue.neon,
              ),
            ),
        ],
      ),
    );
  }
}

/// Rows in one card with hairlines between them, with an optional small
/// heading (and link) or a custom header at the top of the card.
class MobileRowGroup extends StatelessWidget {
  const MobileRowGroup({
    super.key,
    required this.children,
    this.indent = 64,
    this.title,
    this.action,
    this.onAction,
    this.header,
  });

  final List<Widget> children;

  /// Where separators start (past the leading tile).
  final double indent;

  /// A quiet label above the rows ("Seen today").
  final String? title;

  /// A link beside [title] ("Schedule").
  final String? action;
  final VoidCallback? onAction;

  /// Anything else above the rows (a day and its counts).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: MobileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              MobileGroupTitle(title!, action: action, onAction: onAction),
            ?header,
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) CruSeparator(indent: indent),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// What a right swipe on a row does.
class MobileSwipeAction {
  const MobileSwipeAction({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onCommit,
  });

  final String label;
  final CruIconData icon;
  final MobileTone tone;
  final Future<void> Function() onCommit;
}

/// A row that can be swiped right to run [action]: the action shows
/// underneath as the row slides, a firm tap marks the point of no return
/// and letting go past it runs the action. Swipes the other way pass
/// through, so the tabs still change on a left swipe.
class MobileSwipeRow extends StatefulWidget {
  const MobileSwipeRow({super.key, required this.child, this.action});

  final Widget child;

  /// Null: a plain row.
  final MobileSwipeAction? action;

  @override
  State<MobileSwipeRow> createState() => _MobileSwipeRowState();
}

class _MobileSwipeRowState extends State<MobileSwipeRow>
    with SingleTickerProviderStateMixin {
  static const double _commitAt = 96;

  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
        )..addListener(
          () => setState(() => _dx = _settleFrom * (1 - _settle.value)),
        );
  }

  double _dx = 0;
  double _settleFrom = 0;
  bool _armed = false;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _settle.stop();
    final width = context.size?.width ?? 360;
    var next = math.max(0.0, _dx + d.delta.dx);
    // Past the commit point the row follows less, like a rubber band.
    final limit = width * 0.62;
    if (next > limit) next = limit + (next - limit) * 0.25;
    final armed = next >= _commitAt;
    if (armed != _armed) {
      armed ? MobileHaptics.commit() : MobileHaptics.select();
    }
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? _]) {
    final commit = _armed;
    _settleFrom = _dx;
    _armed = false;
    _settle.forward(from: 0);
    if (commit) widget.action?.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    if (action == null) return widget.child;
    final c = context.cru;
    final (bg, fg) = mobileTone(c, action.tone);
    return RawGestureDetector(
      gestures: {
        _RightSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_RightSwipeRecognizer>(
              () => _RightSwipeRecognizer(debugOwner: this),
              (r) => r
                ..onUpdate = _update
                ..onEnd = _end
                ..onCancel = _end,
            ),
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: _armed ? fg : bg,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: CruSpace.s20),
                  child: Opacity(
                    opacity: (_dx / 48).clamp(0.0, 1.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: _armed ? 1.15 : 1,
                          duration: CruMotion.fast,
                          curve: CruMotion.curve,
                          child: CruIcon(
                            action.icon,
                            size: 20,
                            strokeWidth: 2.2,
                            color: _armed ? c.surface : fg,
                          ),
                        ),
                        const SizedBox(width: CruSpace.s8),
                        Text(
                          action.label,
                          style: MobileType.callout.tint(
                            _armed ? c.surface : fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// A horizontal drag that only claims right swipes. Left swipes never
/// win the gesture arena, so the tab pager behind takes them.
class _RightSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _RightSwipeRecognizer({super.debugOwner});

  Offset? _down;
  double _dx = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    _dx = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _down != null) {
      _dx = event.position.dx - _down!.dx;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      _dx > 0 &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}

/// One choice in an actions sheet.
class MobileSheetAction {
  const MobileSheetAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone = MobileTone.slate,
    this.destructive = false,
    this.detail,
  });

  final String label;
  final String? detail;
  final CruIconData icon;
  final MobileTone tone;

  /// Cancels or removes something: set apart below a separator.
  final bool destructive;
  final VoidCallback onTap;
}

/// The long-press sheet: who or what it is about, then what can be done.
Future<void> showMobileActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  required List<MobileSheetAction> actions,
}) {
  final root = mobileRoot(context);
  return showModalBottomSheet<void>(
    context: root,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) {
      final c = sheetContext.cru;
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            CruSpace.s8,
            0,
            CruSpace.s8,
            CruSpace.s8,
          ),
          decoration: ShapeDecoration(color: c.surface, shape: cruShape(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: CruSpace.s8),
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                    color: c.track,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(width: CruSpace.s12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MobileType.headline.tint(c.label),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: CruSpace.s2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: MobileType.subhead.tint(c.label2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s6),
              for (final a in actions) ...[
                // Cancelling sits apart from the everyday actions.
                if (a.destructive) const CruSeparator(indent: 70),
                InkWell(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: c.hoverFill,
                  onTap: () {
                    MobileHaptics.tap();
                    Navigator.of(sheetContext).pop();
                    a.onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: CruSpace.s10,
                    ),
                    child: Row(
                      children: [
                        MobileIconTile(icon: a.icon, tone: a.tone),
                        const SizedBox(width: CruSpace.s14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.label,
                                style: MobileType.row
                                    .copyWith(fontWeight: FontWeight.w500)
                                    .tint(c.label),
                              ),
                              if (a.detail != null)
                                Text(
                                  a.detail!,
                                  style: MobileType.caption.tint(c.label3),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: CruSpace.s10),
            ],
          ),
        ),
      );
    },
  );
}

/// A pushed page that hosts a screen with its own header: a back link to
/// where it came from, then the screen.
class MobileHostPage extends StatelessWidget {
  const MobileHostPage({
    super.key,
    required this.child,
    this.backLabel = 'Back',
  });

  final Widget child;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MobileBackdropPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: (top >= 20 ? top : 44) + CruSpace.s4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 40,
                  child: CruLink(
                    label: backLabel,
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: MobileType.row.copyWith(fontWeight: FontWeight.w500),
                    leading: const CruIcon(
                      CruIcons.chevronLeft,
                      size: 22,
                      strokeWidth: 2.2,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable filter chip: white with dark text; the selected one Neon
/// Blue with white text.
class MobileChip extends StatelessWidget {
  const MobileChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.attention = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  /// Amber dot before the label: needs attention.
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? Colors.white
        : (context.cru.isEvening ? context.cru.label : MobileBlue.penn);
    final edge = mobileBorder(context.cru);
    return CruPressable(
      onTap: () {
        MobileHaptics.select();
        onTap();
      },
      semanticLabel: label,
      builder: (context, _) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        decoration: ShapeDecoration(
          color: selected ? MobileBlue.neon : context.cru.surface,
          shape: StadiumBorder(
            side: selected ? const BorderSide(color: Colors.white) : edge,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attention) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFB340),
                ),
              ),
              const SizedBox(width: CruSpace.s6),
            ],
            Text(
              label,
              style: MobileType.chip.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: CruSpace.s6),
              Text(
                '$count',
                style: MobileType.chip.tabular.tint(fg.withValues(alpha: 0.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The search box on the blue band: a white field with a soft lift.
class MobileSearchField extends StatelessWidget {
  const MobileSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: CruSpace.s16, right: CruSpace.s4),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control + 2),
        shadows: [
          BoxShadow(
            color: const Color(0xFF0B1B4D).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.search, size: 19, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: MobileType.input.tint(c.label),
              cursorColor: MobileBlue.neon,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: MobileType.input.tint(c.label3),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: CruSpace.s10)
                : CruIconButton(
                    icon: CruIcons.close,
                    size: 40,
                    iconSize: 16,
                    semanticLabel: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Centered message for an empty list, in a white card, with one way
/// forward.
class MobileEmpty extends StatelessWidget {
  const MobileEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final CruIconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: MobileCard(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MobileIconTile(
              icon: icon,
              tone: MobileTone.blue,
              size: 52,
              iconSize: 24,
              radius: 16,
            ),
            const SizedBox(height: CruSpace.s14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: MobileType.headline.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: MobileType.subhead.tint(c.label2),
            ),
            if (action != null) ...[
              const SizedBox(height: CruSpace.s20),
              MobilePrimaryButton(
                label: action!,
                icon: CruIcons.plus,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Keeps a tab's scroll position and state while the user is on another
/// tab.
class MobileKeepAlive extends StatefulWidget {
  const MobileKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<MobileKeepAlive> createState() => _MobileKeepAliveState();
}

class _MobileKeepAliveState extends State<MobileKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A full-width segmented control: every option is a thumb-sized target.
/// [onBand] gives the reference's One Way / Round Trip look: a white
/// capsule, the selected option a blue pill with white text.
class MobileSegmented<T> extends StatelessWidget {
  const MobileSegmented({
    super.key,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.onBand = false,
  });

  final List<T> values;
  final String Function(T value) label;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool onBand;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final track = onBand ? c.surface : c.inset;
    final pick = onBand ? MobileBlue.neon : c.segmentSelected;
    final on = onBand ? Colors.white : c.label;
    final off = onBand ? c.label2 : c.label2;
    return Container(
      height: onBand ? 46 : 42,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: track,
        shape: onBand
            ? StadiumBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
              )
            : cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: CruPressable(
                onTap: () {
                  MobileHaptics.select();
                  onChanged(v);
                },
                semanticLabel: label(v),
                scaleOnPress: false,
                builder: (context, _) => AnimatedContainer(
                  duration: CruMotion.of(context, CruMotion.fast),
                  curve: CruMotion.curve,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: v == selected ? pick : pick.withValues(alpha: 0),
                    shape: onBand
                        ? const StadiumBorder()
                        : cruShape(CruRadius.segmentOuter - 2),
                  ),
                  child: Text(
                    label(v),
                    style: MobileType.chip.copyWith(
                      fontWeight: v == selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: v == selected ? on : off,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What a card shows while its data loads: a small spinner and a line
/// saying what is coming, never an empty white box.
class MobileLoading extends StatelessWidget {
  const MobileLoading(this.label, {super.key, this.height = 96});

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MobileBlue.neon,
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          Text(label, style: MobileType.subhead.tint(c.label2)),
        ],
      ),
    );
  }
}
