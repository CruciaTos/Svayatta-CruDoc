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
    final c = context.cru;
    final cells = <Widget>[
      glance == null ? const _CellSkeleton(ring: true) : _SeenCell(glance!),
      glance == null ? const _CellSkeleton() : _WaitingCell(glance!),
      collected == null ? const _CellSkeleton() : _CollectedCell(collected!),
    ];
    return CruCard(
      semanticLabel: 'Today at a glance',
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
                  alignment: Alignment.centerLeft,
                  child: cells[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CruType.subhead.w500.tint(context.cru.label2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, {this.suffix});
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

class _Caption extends StatelessWidget {
  const _Caption(this.child);
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
              const _Label('Seen today'),
              _Metric('${g.seen}', suffix: 'of ${g.total}'),
              _Caption(Text(
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
        const _Label('Waiting now'),
        _Metric('${g.waiting}'),
        _Caption(g.averageWaitMinutes == null
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
        const _Label('Collected today'),
        _Metric(DashFormat.rupees(data.today)),
        _Caption(caption),
      ],
    );
  }
}

class _CellSkeleton extends StatelessWidget {
  const _CellSkeleton({this.ring = false});
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
