import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Largest stamp slot; slots shrink to fit a phone.
const double _kSlot = 52;

/// The loyalty card: five month slots and the free sixth. A slot stamped
/// while the card is on screen (or [animateLast] on first show) presses in.
class LoyaltyCardView extends StatefulWidget {
  const LoyaltyCardView({
    super.key,
    required this.card,
    this.animateLast = false,
    this.onClaim,
  });

  final LoyaltyCard card;

  /// Stamp the newest slot in with motion when first built (onboarding).
  final bool animateLast;

  /// Shown as "Claim free month" once the card is full.
  final VoidCallback? onClaim;

  @override
  State<LoyaltyCardView> createState() => _LoyaltyCardViewState();
}

class _LoyaltyCardViewState extends State<LoyaltyCardView> {
  /// Index of the slot to animate, or null.
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
    final left = kLoyaltySlots - card.stamps;
    return CruCard(
      semanticLabel: 'Loyalty card',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Loyalty card', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            card.freeMonthReady
                ? 'Card full. Your next month is on us.'
                : 'Every month with CruDoc earns a stamp. '
                      'Collect $kLoyaltySlots and the 6th month is free.',
            style: CruType.text.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s20),
          // Six slots on one line; they shrink to fit a phone.
          LayoutBuilder(
            builder: (context, box) {
              final size = ((box.maxWidth - CruSpace.s8 * kLoyaltySlots) /
                      (kLoyaltySlots + 1))
                  .clamp(0.0, _kSlot);
              return Row(
                children: [
                  for (var i = 0; i < kLoyaltySlots; i++) ...[
                    _Slot(
                      index: i,
                      size: size,
                      stamped: i < card.stamps,
                      month: i < card.stampedMonths.length
                          ? card.stampedMonths[i]
                          : null,
                      animate: i == _fresh,
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  _FreeSlot(ready: card.freeMonthReady, size: size),
                ],
              );
            },
          ),
          const SizedBox(height: CruSpace.s16),
          if (card.freeMonthReady && widget.onClaim != null)
            CruButton(label: 'Claim free month', onPressed: widget.onClaim)
          else
            Text(
              card.freeMonthReady
                  ? ''
                  : '$left more ${left == 1 ? 'month' : 'months'} to a free one.',
              style: CruType.caption.tabular.tint(c.label3),
            ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.index,
    required this.size,
    required this.stamped,
    required this.month,
    required this.animate,
  });

  final int index;
  final double size;
  final bool stamped;
  final String? month;
  final bool animate;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? get _monthLabel {
    final m = int.tryParse(month?.split('-').last ?? '');
    return m == null || m < 1 || m > 12 ? null : _months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stamped ? c.accent : c.inset,
      ),
      child: stamped
          ? CruIcon(CruIcons.check, size: size * 0.42, color: c.onAccent, strokeWidth: 2.4)
          : Text(
              '${index + 1}',
              style: CruType.row.tabular.tint(c.label3),
            ),
    );
    return Semantics(
      label: stamped ? 'Month ${index + 1} stamped' : 'Month ${index + 1}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          animate
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 1.6 - 0.6 * t, child: child),
                  ),
                  child: face,
                )
              : face,
          const SizedBox(height: CruSpace.s6),
          Text(
            stamped ? (_monthLabel ?? '') : '',
            style: CruType.micro.tint(c.label3),
          ),
        ],
      ),
    );
  }
}

class _FreeSlot extends StatelessWidget {
  const _FreeSlot({required this.ready, required this.size});

  final bool ready;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: ready ? 'Free month ready' : 'Free month',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ready ? c.green : c.greenTint,
            ),
            child: Text(
              'FREE',
              maxLines: 1,
              style: CruType.micro.w600.tint(
                ready ? c.onAccent : c.greenText,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s6),
          Text('6th', style: CruType.micro.tint(c.label3)),
        ],
      ),
    );
  }
}
