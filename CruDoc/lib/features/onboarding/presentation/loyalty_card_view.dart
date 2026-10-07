import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Widest the card grows; past this it reads as a banner, not a card.
const double _kMaxWidth = 560;

/// Largest badge in the case; badges shrink to fit a phone.
const double _kBadge = 56;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The loyalty card, drawn as a trainer card: a framed ID with the
/// doctor's name and portrait, and a badge case below. Each month with
/// CruDoc earns that month's badge; five badges and the 6th month is free.
/// The frame turns bronze, silver, then gold as free months are claimed.
class LoyaltyCardView extends StatefulWidget {
  const LoyaltyCardView({
    super.key,
    required this.card,
    this.holderName,
    this.holderId,
    this.photoUrl,
    this.animateLast = false,
    this.onClaim,
  });

  final LoyaltyCard card;

  /// "Dr. Ananya Deshpande"; the NAME row hides when null.
  final String? holderName;

  /// The Auth uid; the card shows a 5-digit ID derived from it.
  final String? holderId;
  final String? photoUrl;

  /// Press the newest badge in with motion when first built (onboarding).
  final bool animateLast;

  /// Shown as "Claim free month" once the card is full.
  final VoidCallback? onClaim;

  @override
  State<LoyaltyCardView> createState() => _LoyaltyCardViewState();
}

class _LoyaltyCardViewState extends State<LoyaltyCardView> {
  /// Index of the badge to animate, or null.
  int? _fresh;

  @override
  void initState() {
    super.initState();
    if (widget.animateLast && widget.card.stamps > 0) {
      _fresh = widget.card.stamps - 1;
    }
  }

  @override
  void didUpdateWidget(LoyaltyCardView old) {
    super.didUpdateWidget(old);
    if (widget.card.stamps > old.card.stamps) _fresh = widget.card.stamps - 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final card = widget.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: Semantics(
            label: 'Loyalty card, ${card.stamps} of $kLoyaltySlots badges',
            child: _TrainerCard(
              card: card,
              holderName: widget.holderName,
              holderId: widget.holderId,
              photoUrl: widget.photoUrl,
              fresh: _fresh,
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        Text(
          card.freeMonthReady
              ? 'Card full. Your next month is on us.'
              : 'Every month with CruDoc earns that month\'s badge. '
                    'Collect $kLoyaltySlots and the 6th month is free.',
          style: CruType.caption.tint(c.label3),
        ),
        if (card.freeMonthReady && widget.onClaim != null) ...[
          const SizedBox(height: CruSpace.s12),
          CruButton(label: 'Claim free month', onPressed: widget.onClaim),
        ],
      ],
    );
  }
}

/// Frame colours by free months claimed: brand ink, then bronze, silver,
/// gold. Metal tiers are artwork, like the badges.
(Color, Color) _frameColors(CruColors c, int claimed) => switch (claimed) {
  0 => (c.accent, c.ink),
  1 => (const Color(0xFFC4824F), const Color(0xFF6E3D1C)),
  2 => (const Color(0xFFA9B4BF), const Color(0xFF55606C)),
  _ => (const Color(0xFFE2B03F), const Color(0xFF8A5C0E)),
};

class _TrainerCard extends StatelessWidget {
  const _TrainerCard({
    required this.card,
    required this.holderName,
    required this.holderId,
    required this.photoUrl,
    required this.fresh,
  });

  final LoyaltyCard card;
  final String? holderName;
  final String? holderId;
  final String? photoUrl;
  final int? fresh;

  /// Stable 5-digit ID from the uid (String.hashCode is not stable).
  static String _idNo(String uid) {
    var h = 0x811C9DC5;
    for (final u in uid.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
    }
    return (h % 100000).toString().padLeft(5, '0');
  }

  DateTime? get _started {
    if (card.joinedAt != null) return card.joinedAt;
    if (card.stampedMonths.isEmpty) return null;
    return DateTime.tryParse('${card.stampedMonths.first}-01');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (light, dark) = _frameColors(c, card.freeMonthsClaimed);
    final onFrame = c.onAccent;
    final left = kLoyaltySlots - card.stamps;
    final started = _started;
    final name = holderName?.trim();

    final fields = <(String, String)>[
      if (name != null && name.isNotEmpty) ('NAME', name),
      if (started != null)
        ('STARTED', '${_months[started.month - 1]} ${started.year}'),
      ('BADGES', '${card.stamps}/$kLoyaltySlots'),
      (
        'FREE MONTH',
        card.freeMonthReady
            ? 'Ready'
            : 'In $left ${left == 1 ? 'month' : 'months'}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final portrait = (width * 0.22).clamp(64.0, 104.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CruRadius.card),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, dark],
            ),
            boxShadow: c.cardShadow,
          ),
          child: CustomPaint(
            painter: _StripePainter(onFrame.withValues(alpha: 0.07)),
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: title, a star per free month, ID No.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s8,
                      CruSpace.s4,
                      CruSpace.s8,
                      CruSpace.s12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'LOYALTY CARD',
                          style: CruType.headline.w700
                              .copyWith(letterSpacing: 1.6)
                              .tint(onFrame),
                        ),
                        for (
                          var i = 0;
                          i < math.min(card.freeMonthsClaimed, 5);
                          i++
                        )
                          Padding(
                            padding: const EdgeInsets.only(left: CruSpace.s4),
                            child: CustomPaint(
                              size: const Size.square(14),
                              painter: _StarPainter(),
                            ),
                          ),
                        const Spacer(),
                        if (holderId != null && holderId!.isNotEmpty)
                          Text(
                            'ID No. ${_idNo(holderId!)}',
                            style: CruType.caption.w600.tabular
                                .copyWith(letterSpacing: 0.6)
                                .tint(onFrame.withValues(alpha: 0.9)),
                          ),
                      ],
                    ),
                  ),
                  // Ruled fields and the portrait.
                  Container(
                    padding: const EdgeInsets.all(CruSpace.s16),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(
                        CruRadius.card - CruSpace.s12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < fields.length; i++)
                                _Field(
                                  label: fields[i].$1,
                                  value: fields[i].$2,
                                  last: i == fields.length - 1,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: CruSpace.s16),
                        _Portrait(
                          name: name ?? '',
                          photoUrl: photoUrl,
                          size: portrait,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CruSpace.s12),
                  _BadgeCase(card: card, fresh: fresh, onFrame: onFrame),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.last});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: CruType.micro.w600
                .copyWith(letterSpacing: 0.8)
                .tint(c.label3),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.callout.w600.tabular.tint(c.label),
            ),
          ),
        ],
      ),
    );
  }
}

/// The trainer photo: profile picture, or initials when there is none.
class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final initials = Center(
      child: Text(
        CruMonogram.initialsOf(name),
        style: CruType.monogram(size * 0.34).tint(c.label2),
      ),
    );
    return Container(
      width: size,
      height: size * 1.15,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CruRadius.iconTile),
        border: Border.all(color: c.separator),
      ),
      child: photoUrl == null || photoUrl!.isEmpty
          ? initials
          : Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initials,
            ),
    );
  }
}

class _BadgeCase extends StatelessWidget {
  const _BadgeCase({
    required this.card,
    required this.fresh,
    required this.onFrame,
  });

  final LoyaltyCard card;
  final int? fresh;
  final Color onFrame;

  static int? _monthOf(String key) {
    final m = int.tryParse(key.split('-').last);
    return m == null || m < 1 || m > 12 ? null : m;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(CruRadius.card - CruSpace.s12),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          const slots = kLoyaltySlots + 1;
          final size = ((box.maxWidth - CruSpace.s8 * (slots - 1)) / slots)
              .clamp(0.0, _kBadge);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < kLoyaltySlots; i++)
                _BadgeSlot(
                  index: i,
                  size: size,
                  month: i < card.stamps && i < card.stampedMonths.length
                      ? _monthOf(card.stampedMonths[i])
                      : null,
                  stamped: i < card.stamps,
                  animate: i == fresh,
                  onFrame: onFrame,
                ),
              _FreeSlot(
                ready: card.freeMonthReady,
                size: size,
                onFrame: onFrame,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BadgeSlot extends StatelessWidget {
  const _BadgeSlot({
    required this.index,
    required this.size,
    required this.month,
    required this.stamped,
    required this.animate,
    required this.onFrame,
  });

  final int index;
  final double size;

  /// 1–12, or null for an empty slot.
  final int? month;
  final bool stamped;
  final bool animate;
  final Color onFrame;

  @override
  Widget build(BuildContext context) {
    final art = month == null ? null : _badges[month! - 1];
    Widget face = CustomPaint(
      size: Size.square(size),
      painter: art != null && stamped ? _BadgePainter(art) : _SocketPainter(),
    );
    if (animate && art != null) {
      face = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 1.6 - 0.6 * t, child: child),
        ),
        child: face,
      );
    }
    final label = month != null
        ? _months[month! - 1].toUpperCase()
        : '${index + 1}';
    return Semantics(
      label: month != null
          ? '${_months[month! - 1]} badge, ${art!.stone}'
          : 'Badge ${index + 1}, not yet earned',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          face,
          const SizedBox(height: CruSpace.s4),
          Text(
            label,
            style: CruType.micro.w600.tabular
                .copyWith(letterSpacing: 0.6)
                .tint(onFrame.withValues(alpha: month != null ? 0.9 : 0.45)),
          ),
        ],
      ),
    );
  }
}

class _FreeSlot extends StatelessWidget {
  const _FreeSlot({
    required this.ready,
    required this.size,
    required this.onFrame,
  });

  final bool ready;
  final double size;
  final Color onFrame;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: ready ? 'Free month ready' : 'Free month',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: ready ? 1 : 0.4,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: CustomPaint(
              size: Size.square(size),
              painter: _RosettePainter(ready),
            ),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            'FREE',
            style: CruType.micro.w600
                .copyWith(letterSpacing: 0.6)
                .tint(onFrame.withValues(alpha: ready ? 0.9 : 0.45)),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Badge artwork. Each month is its birthstone, cut to its own shape. These
// colours are illustration, like the tooth renders, not UI tokens.
// -----------------------------------------------------------------------------

class _BadgeArt {
  const _BadgeArt(this.stone, this.color, this.shape, {this.opal = false});

  final String stone;
  final Color color;

  /// Outline in a unit square.
  final Path Function() shape;

  /// Iridescent fill instead of a single colour.
  final bool opal;
}

final _badges = <_BadgeArt>[
  _BadgeArt(
    'garnet',
    const Color(0xFF9E1B34),
    () => _polygon(8, 0.48, math.pi / 8),
  ),
  _BadgeArt('amethyst', const Color(0xFF8E5BD0), _rhombus),
  _BadgeArt('aquamarine', const Color(0xFF4FB8C6), _droplet),
  _BadgeArt('diamond', const Color(0xFFB9CCDD), () => _star(4, 0.49, 0.2)),
  _BadgeArt('emerald', const Color(0xFF1F9A5E), _emeraldCut),
  _BadgeArt(
    'pearl',
    const Color(0xFFD9CFC0),
    () => Path()
      ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.46)),
  ),
  _BadgeArt('ruby', const Color(0xFFD0213F), _flame),
  _BadgeArt('peridot', const Color(0xFF93B52C), _leaf),
  _BadgeArt('sapphire', const Color(0xFF2A55C4), _shield),
  _BadgeArt(
    'opal',
    const Color(0xFFE6C8E8),
    () => _polygon(6, 0.48, -math.pi / 2),
    opal: true,
  ),
  _BadgeArt('topaz', const Color(0xFFEE9A24), () => _star(5, 0.5, 0.23)),
  _BadgeArt('turquoise', const Color(0xFF26B3AC), () => _star(6, 0.49, 0.29)),
];

Path _polygon(int n, double r, double start) {
  final p = Path();
  for (var i = 0; i < n; i++) {
    final a = start + i * 2 * math.pi / n;
    final o = Offset(0.5 + r * math.cos(a), 0.5 + r * math.sin(a));
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

Path _star(int points, double outer, double inner) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final o = Offset(0.5 + r * math.cos(a), 0.52 + r * math.sin(a));
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

Path _rhombus() => Path()
  ..moveTo(0.5, 0.02)
  ..lineTo(0.92, 0.5)
  ..lineTo(0.5, 0.98)
  ..lineTo(0.08, 0.5)
  ..close();

Path _droplet() => Path()
  ..moveTo(0.5, 0.02)
  ..cubicTo(0.62, 0.22, 0.86, 0.4, 0.86, 0.62)
  ..arcToPoint(
    const Offset(0.14, 0.62),
    radius: const Radius.circular(0.361),
    clockwise: true,
  )
  ..cubicTo(0.14, 0.4, 0.38, 0.22, 0.5, 0.02)
  ..close();

Path _emeraldCut() => Path()
  ..moveTo(0.3, 0.04)
  ..lineTo(0.7, 0.04)
  ..lineTo(0.86, 0.2)
  ..lineTo(0.86, 0.8)
  ..lineTo(0.7, 0.96)
  ..lineTo(0.3, 0.96)
  ..lineTo(0.14, 0.8)
  ..lineTo(0.14, 0.2)
  ..close();

Path _flame() => Path()
  ..moveTo(0.5, 0.02)
  ..cubicTo(0.62, 0.2, 0.88, 0.38, 0.86, 0.64)
  ..cubicTo(0.84, 0.86, 0.68, 0.98, 0.5, 0.98)
  ..cubicTo(0.32, 0.98, 0.16, 0.86, 0.14, 0.64)
  ..cubicTo(0.13, 0.48, 0.24, 0.36, 0.32, 0.3)
  ..cubicTo(0.34, 0.42, 0.4, 0.48, 0.44, 0.5)
  ..cubicTo(0.4, 0.3, 0.44, 0.14, 0.5, 0.02)
  ..close();

Path _leaf() => Path()
  ..moveTo(0.1, 0.9)
  ..quadraticBezierTo(0.04, 0.04, 0.9, 0.1)
  ..quadraticBezierTo(0.96, 0.96, 0.1, 0.9)
  ..close();

Path _shield() => Path()
  ..moveTo(0.5, 0.03)
  ..lineTo(0.9, 0.16)
  ..lineTo(0.88, 0.5)
  ..quadraticBezierTo(0.84, 0.82, 0.5, 0.98)
  ..quadraticBezierTo(0.16, 0.82, 0.12, 0.5)
  ..lineTo(0.1, 0.16)
  ..close();

Path _scaled(Path unit, double size) =>
    unit.transform(Matrix4.diagonal3Values(size, size, 1).storage);

/// A metal-rimmed gem: shadow, faceted fill, inner table, glint.
class _BadgePainter extends CustomPainter {
  _BadgePainter(this.art);

  final _BadgeArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final outline = _scaled(art.shape(), s);
    final bounds = Offset.zero & size;
    final light = Color.lerp(art.color, Colors.white, 0.45)!;
    final dark = Color.lerp(art.color, Colors.black, 0.35)!;

    canvas.drawShadow(outline, Colors.black, 2, false);
    canvas.drawPath(
      outline,
      Paint()
        ..shader =
            (art.opal
                    ? SweepGradient(
                        colors: const [
                          Color(0xFFF7C6E0),
                          Color(0xFFC6E7F7),
                          Color(0xFFD4F5D0),
                          Color(0xFFFFF1C2),
                          Color(0xFFE2CCF7),
                          Color(0xFFF7C6E0),
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [light, art.color, dark],
                      ))
                .createShader(bounds),
    );

    // Inner table facet: the outline shrunk toward the centre.
    final table = outline.transform(
      (Matrix4.identity()
            ..translateByDouble(s * 0.5, s * 0.5, 0, 1)
            ..scaleByDouble(0.55, 0.55, 1, 1)
            ..translateByDouble(-s * 0.5, -s * 0.5, 0, 1))
          .storage,
    );
    canvas.drawPath(
      table,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.4),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      table,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Metal rim.
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4D6), Color(0xFFC9A55A), Color(0xFF7D6230)],
        ).createShader(bounds),
    );

    // Glint, clipped to the gem.
    canvas.save();
    canvas.clipPath(outline);
    canvas.translate(s * 0.36, s * 0.3);
    canvas.rotate(-math.pi / 5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.2, height: s * 0.09),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.art != art;
}

/// An empty, recessed slot in the badge case.
class _SocketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.4;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      0.15 * math.pi,
      0.7 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.2),
    );
  }

  @override
  bool shouldRepaint(_SocketPainter old) => false;
}

/// The gold rosette in the 6th slot: the free month.
class _RosettePainter extends CustomPainter {
  _RosettePainter(this.ready);

  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final centre = size.center(Offset.zero);
    final bounds = Offset.zero & size;
    final petals = Path();
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      petals.addOval(
        Rect.fromCircle(
          center: centre + Offset(math.cos(a), math.sin(a)) * s * 0.36,
          radius: s * 0.11,
        ),
      );
    }
    petals.addOval(Rect.fromCircle(center: centre, radius: s * 0.38));
    const gold = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFE9A8), Color(0xFFE2B03F), Color(0xFF9A6A12)],
    );
    if (ready) canvas.drawShadow(petals, Colors.black, 2, false);
    canvas.drawPath(petals, Paint()..shader = gold.createShader(bounds));
    canvas.drawCircle(
      centre,
      s * 0.26,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [Color(0xFFC98A1B), Color(0xFFFFF4D6)],
        ).createShader(bounds),
    );
    // A five-point star stamped in the centre.
    canvas.save();
    canvas.translate(centre.dx - s * 0.16, centre.dy - s * 0.165);
    canvas.drawPath(
      _scaled(_star(5, 0.5, 0.22), s * 0.32),
      Paint()..color = const Color(0xFF9A6A12),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RosettePainter old) => old.ready != ready;
}

/// One gold star in the header per free month claimed.
class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _scaled(_star(5, 0.5, 0.22), size.width),
      Paint()..color = const Color(0xFFFFD45C),
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

/// Faint diagonal stripes across the frame.
class _StripePainter extends CustomPainter {
  _StripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(CruRadius.card),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4;
    for (var x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.color != color;
}
