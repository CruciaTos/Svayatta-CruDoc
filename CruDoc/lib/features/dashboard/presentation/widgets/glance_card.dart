import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Today at a glance: Seen today, Waiting now, Collected today.
///
/// "Follow-ups due" is not shown: no record holds a follow-up date yet
/// (GAP, see IMPLEMENTATION_REPORT.md).
class GlanceCard extends StatelessWidget {
  const GlanceCard({super.key, required this.glance, required this.collected});

  final GlanceData? glance;
  final CollectedToday? collected;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      glance == null
          ? const GlanceCellSkeleton(ring: true)
          : _SeenCell(glance!),
      glance == null ? const GlanceCellSkeleton() : _WaitingCell(glance!),
      collected == null
          ? const GlanceCellSkeleton()
          : _CollectedCell(collected!),
    ];
    return GlanceStrip(
      semanticLabel: 'Today at a glance',
      separatorColor: const Color(0xFFA1BCFF),
      separatorWidth: 1.0,
      cells: cells,
    );
  }
}

/// The glance layout: one card, equal cells split by separators. Shared
/// with the Patient details facts strip.
class GlanceStrip extends StatelessWidget {
  const GlanceStrip({
    super.key,
    required this.cells,
    this.semanticLabel,
    this.borderColor,
    this.borderWidth,
    this.separatorColor,
    this.separatorWidth,
  });

  final List<Widget> cells;
  final String? semanticLabel;
  final Color? borderColor;
  final double? borderWidth;
  final Color? separatorColor;
  final double? separatorWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (cruIsPhone(context) && cells.length > 2) return _grid(context);
    return CruCard(
      semanticLabel: semanticLabel,
      borderColor: borderColor,
      borderWidth: borderWidth ?? 1,
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s24),
                  decoration: i == 0
                      ? null
                      : BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: separatorColor ?? c.separator,
                              width:
                                  separatorWidth ??
                                  (separatorColor != null ? 1.5 : 1),
                            ),
                          ),
                        ),
                  alignment: Alignment.topLeft,
                  child: cells[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension on GlanceStrip {
  /// Phone: two cells a row, so every number keeps its full label.
  Widget _grid(BuildContext context) {
    final c = context.cru;
    final line = BorderSide(
      color: separatorColor ?? c.separator,
      width: separatorWidth ?? 1,
    );
    Widget cell(int i, {required bool left}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s14,
          CruSpace.s12,
          CruSpace.s14,
        ),
        decoration: left ? null : BoxDecoration(border: Border(left: line)),
        alignment: Alignment.topLeft,
        child: i < cells.length ? cells[i] : const SizedBox.shrink(),
      ),
    );
    return CruCard(
      semanticLabel: semanticLabel,
      borderColor: borderColor,
      borderWidth: borderWidth ?? 1,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < cells.length; r += 2)
            Container(
              decoration: r == 0
                  ? null
                  : BoxDecoration(border: Border(top: line)),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cell(r, left: true), cell(r + 1, left: false)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cell label (13/500 label2).
class GlanceLabel extends StatelessWidget {
  const GlanceLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: CruType.subhead.w500.tint(color ?? context.cru.accentText),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// Cell value (28/600) with an optional quieter suffix ("of 13").
class GlanceMetric extends StatelessWidget {
  const GlanceMetric(this.value, {super.key, this.suffix});
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value, style: CruType.metric.tint(c.label)),
          if (suffix != null)
            TextSpan(
              text: ' $suffix',
              style: CruType.metricSuffix.tint(c.label2),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Cell caption (12.5 tabular label2).
class GlanceCaption extends StatelessWidget {
  const GlanceCaption(this.child, {super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: CruType.caption.tabular.tint(context.cru.label2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    child: child,
  );
}

class _SeenCell extends StatelessWidget {
  const _SeenCell(this.g);
  final GlanceData g;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final percent = g.total > 0 ? ((g.seen / g.total) * 100).toInt() : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CruProgressRing(
          value: g.progress,
          color: c.green,
          semanticLabel: 'Seen ${g.seen} of ${g.total}',
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: GlanceLabel('Seen today', color: c.accentText),
                  ),
                  const SizedBox(width: CruSpace.s6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: ShapeDecoration(
                      color: c.greenTint,
                      shape: cruShape(6),
                    ),
                    child: Text(
                      '$percent%',
                      style: CruType.micro.w700.tabular.tint(c.greenText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              GlanceMetric('${g.seen}', suffix: 'of ${g.total}'),
              const SizedBox(height: 2),
              GlanceCaption(
                Text(
                  g.total == 0
                      ? 'No appointments yet'
                      : g.stillToSee == 0
                      ? '✓ Everyone seen'
                      : '${g.stillToSee} still to see',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaitingCell extends StatelessWidget {
  const _WaitingCell(this.g);
  final GlanceData g;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: GlanceLabel('Waiting now', color: c.accentText)),
          ],
        ),
        const SizedBox(height: 2),
        GlanceMetric('${g.waiting}'),
        const SizedBox(height: 2),
        GlanceCaption(
          g.averageWaitMinutes == null
              ? const Text('Queue is clear')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruStatusDot(CruDotKind.waiting, size: 8),
                    const SizedBox(width: CruSpace.s6),
                    Flexible(
                      child: Text(
                        'Avg wait ${DashFormat.minutes(g.averageWaitMinutes!)}',
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.tabular.tint(c.label2),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CollectedCell extends StatelessWidget {
  const _CollectedCell(this.data);
  final CollectedToday data;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final diff = data.difference;
    final vs = 'vs last ${data.weekdayName}';
    Widget caption;
    if (data.today == 0 && data.sameDayLastWeek == 0) {
      caption = const Text('Nothing recorded yet');
    } else if (diff == 0) {
      caption = Text('Same as last ${data.weekdayName}');
    } else {
      final up = diff > 0;
      final tone = up ? c.greenText : c.label2;
      caption = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: ShapeDecoration(
              color: up ? c.greenTint : c.inset,
              shape: cruShape(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CruIcon(
                  up ? CruIcons.arrowUp : CruIcons.arrowDown,
                  size: 11,
                  strokeWidth: 2.6,
                  color: tone,
                ),
                const SizedBox(width: 2),
                Text(
                  DashFormat.rupees(diff.abs()),
                  style: CruType.micro.w700.tabular.tint(tone),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              vs,
              style: CruType.caption.tabular.tint(c.label2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel('Collected today', color: c.accentText),
        const SizedBox(height: 2),
        GlanceMetric(DashFormat.rupees(data.today)),
        const SizedBox(height: 2),
        GlanceCaption(caption),
      ],
    );
  }
}

/// Loading placeholder for one cell.
class GlanceCellSkeleton extends StatelessWidget {
  const GlanceCellSkeleton({super.key, this.ring = false});
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final column = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonBox(width: 80, height: 12),
        SizedBox(height: 10),
        SkeletonBox(width: 56, height: 26),
        SizedBox(height: 8),
        SkeletonBox(width: 110, height: 10),
      ],
    );
    if (!ring) return column;
    return Row(
      children: [
        const SkeletonBox(
          width: CruSize.progressRing,
          height: CruSize.progressRing,
          circle: true,
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(child: column),
      ],
    );
  }
}
