import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One row in Needs attention / Wrap up the day: tinted tile, title,
/// detail, capsule action.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final CruIconData icon;
  final CruTileTone tone;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s10,
      ),
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: tone),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CruTimeText(
                  title,
                  style: CruType.callout.tabular.tint(c.label),
                  timeColor: c.accentText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CruTimeText(
                  subtitle,
                  style: CruType.subhead.tabular.tint(c.label2),
                  timeColor: c.accentText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: actionLabel,
            semanticLabel: '$actionLabel: $title',
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// Rows separated by separators that start at the text column.
List<Widget> withSeparators(List<Widget> rows) => [
  for (var i = 0; i < rows.length; i++) ...[
    if (i > 0)
      const CruSeparator(
        indent: CruSize.attentionTextInset,
        endIndent: CruSpace.s12,
      ),
    rows[i],
  ],
];

/// Needs attention (Day). Only stock is backed by data today; lab
/// results and overdue follow-ups are GAPs. Hidden when empty.
class NeedsAttentionCard extends StatelessWidget {
  const NeedsAttentionCard({
    super.key,
    required this.items,
    required this.onOpenInventory,
  });

  final List<AttentionItem> items;
  final VoidCallback onOpenInventory;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Needs attention',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Needs attention',
                      style: CruType.headline.tint(c.label),
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          ...withSeparators([
            for (final item in items)
              ActionRow(
                icon: CruIcons.box,
                tone: CruTileTone.neutral,
                title: item.title,
                subtitle: item.subtitle,
                actionLabel: item.actionLabel,
                onAction: onOpenInventory,
              ),
          ]),
        ],
      ),
    );
  }
}

/// Collections over the last seven days. The UPI / Cash split is a GAP
/// (revenue entries don't record a payment method), so it isn't shown.
class CollectionsCard extends StatelessWidget {
  const CollectionsCard({super.key, required this.data});

  final CollectionsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final max = data.max;
    return CruCard(
      semanticLabel: 'Collections',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.control),
                ),
                child: CruIcon(CruIcons.rupee, size: 16, color: c.accentText),
              ),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Collections',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: c.isEvening ? c.inset : const Color(0xFFF1F5F9),
                  shape: cruShape(CruRadius.full),
                ),
                child: Text(
                  'Last 7 days',
                  style: CruType.caption.tint(c.label2),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                DashFormat.rupees(data.total),
                style: CruType.metric.tint(c.label),
              ),
              const SizedBox(width: CruSpace.s10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: ShapeDecoration(
                  color: c.greenTint,
                  shape: cruShape(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(
                      CruIcons.arrowUp,
                      size: 11,
                      strokeWidth: 2.6,
                      color: c.greenText,
                    ),
                    const SizedBox(width: 2),
                    Text('TOTAL', style: CruType.micro.w700.tint(c.greenText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          SizedBox(
            height: CruSize.chartHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final d in data.days) _Bar(day: d, max: max)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day, required this.max});

  final CollectionDay day;
  final double max;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final safeMax = (max.isNaN || max.isInfinite || max <= 0) ? 1.0 : max;
    final safeAmount =
        (day.amount.isNaN || day.amount.isInfinite || day.amount <= 0)
        ? 0.0
        : day.amount;
    final closed = safeAmount <= 0;
    final rawHeight = closed
        ? CruSize.barStub
        : ((safeAmount / safeMax) * CruSize.barMaxHeight);
    final height = (rawHeight.isNaN || rawHeight.isInfinite)
        ? CruSize.barStub
        : rawHeight.clamp(CruSize.barStub, CruSize.barMaxHeight);

    return Semantics(
      label:
          '${DashFormat.weekday(day.date)}: ${DashFormat.rupees(day.amount)}',
      child: SizedBox(
        width: CruSize.barSlot,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (day.isToday) ...[
              Text(
                DashFormat.rupeesCompact(day.amount),
                style: CruType.micro.w700.tabular.tint(c.accentText),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
              const SizedBox(height: CruSpace.s6),
            ],
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: height, end: height),
              duration: CruMotion.of(context),
              curve: CruMotion.curve,
              builder: (context, h, _) {
                final barH = (h.isNaN || h.isInfinite)
                    ? CruSize.barStub
                    : h.clamp(CruSize.barStub, CruSize.barMaxHeight);
                final Gradient? barGradient = closed
                    ? null
                    : (day.isToday
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [c.accent, c.accentText],
                            )
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: c.isEvening
                                  ? const [Color(0xFF334155), Color(0xFF1E293B)]
                                  : [
                                      c.accentTint,
                                      c.accentTint.withValues(alpha: 0.5),
                                    ],
                            ));
                final Color? barColor = closed ? c.track : null;

                return Container(
                  width: CruSize.barWidth,
                  height: barH,
                  decoration: ShapeDecoration(
                    gradient: barGradient,
                    color: barColor,
                    shape: cruShape(closed ? CruRadius.barStub : CruRadius.bar),
                  ),
                );
              },
            ),
            const SizedBox(height: CruSpace.s8),
            Container(
              padding: day.isToday
                  ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1)
                  : EdgeInsets.zero,
              decoration: day.isToday
                  ? ShapeDecoration(color: c.accentTint, shape: cruShape(4))
                  : null,
              child: Text(
                DashFormat.dayInitials(day.date),
                style: (day.isToday ? CruType.micro.w700 : CruType.micro).tint(
                  day.isToday ? c.accentText : c.label3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
