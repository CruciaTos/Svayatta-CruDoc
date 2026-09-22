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
      glance == null ? const GlanceCellSkeleton(ring: true) : _SeenCell(glance!),
      glance == null ? const GlanceCellSkeleton() : _WaitingCell(glance!),
      collected == null ? const GlanceCellSkeleton() : _CollectedCell(collected!),
    ];
    return GlanceStrip(semanticLabel: 'Today at a glance', cells: cells);
  }
}

/// The glance layout: one card, equal cells split by separators. Shared
/// with the Patient details facts strip.
class GlanceStrip extends StatelessWidget {
  const GlanceStrip({super.key, required this.cells, this.semanticLabel});

  final List<Widget> cells;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: semanticLabel,
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
                          border: Border(left: BorderSide(color: c.separator)),
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

/// Cell label (13/500 label2).
class GlanceLabel extends StatelessWidget {
  const GlanceLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CruType.subhead.w500.tint(context.cru.label2),
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
      TextSpan(children: [
        TextSpan(text: value, style: CruType.metric.tint(c.label)),
        if (suffix != null)
          TextSpan(text: ' $suffix', style: CruType.metricSuffix.tint(c.label2)),
      ]),
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
    return Row(
      children: [
        CruProgressRing(
          value: g.progress,
          semanticLabel: 'Seen ${g.seen} of ${g.total}',
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const GlanceLabel('Seen today'),
              GlanceMetric('${g.seen}', suffix: 'of ${g.total}'),
              GlanceCaption(Text(
                g.total == 0
                    ? 'No appointments yet'
                    : g.stillToSee == 0
                        ? 'Everyone seen'
                        : '${g.stillToSee} still to see',
              )),
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
        const GlanceLabel('Waiting now'),
        GlanceMetric('${g.waiting}'),
        GlanceCaption(g.averageWaitMinutes == null
            ? const Text('Queue is clear')
            : Row(children: [
                CruStatusDot(CruDotKind.waiting, size: CruSize.smallDot),
                const SizedBox(width: CruSpace.s6),
                Flexible(
                  child: Text(
                    'Average wait ${DashFormat.minutes(g.averageWaitMinutes!)}',
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                ),
              ])),
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
      // Up is green ("money up"). Down stays neutral: red is reserved
      // for allergies and patient safety.
      final up = diff > 0;
      final tone = up ? c.greenText : c.label2;
      caption = Row(children: [
        CruIcon(up ? CruIcons.arrowUp : CruIcons.arrowDown,
            size: 13, strokeWidth: 2.4, color: tone),
        const SizedBox(width: 3),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: DashFormat.rupees(diff.abs()),
                style: CruType.caption.w600.tabular.tint(tone),
              ),
              TextSpan(text: ' $vs'),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const GlanceLabel('Collected today'),
        GlanceMetric(DashFormat.rupees(data.today)),
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
    return Row(children: [
      const SkeletonBox(
        width: CruSize.progressRing,
        height: CruSize.progressRing,
        circle: true,
      ),
      const SizedBox(width: CruSpace.s16),
      Expanded(child: column),
    ]);
  }
}
