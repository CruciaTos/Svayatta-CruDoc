import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Arrow beside the comparison percentage, sized to the 12.5 px caption
/// (same size as the dashboard's Collected today caption).
const double _arrowSize = 13;
const double _arrowStroke = 2.4;

/// Gap between the arrow and the percentage (as the dashboard).
const double _arrowGap = 3;

/// Collected, Expenses, Net and Pending for the selected period.
class RevenueGlance extends StatelessWidget {
  const RevenueGlance({super.key, required this.overview, required this.pending});

  /// Null while revenue entries load.
  final RevenueOverview? overview;

  /// Null while pending payments load.
  final List<PendingGroup>? pending;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    return GlanceStrip(
      semanticLabel: 'At a glance',
      cells: [
        o == null ? const GlanceCellSkeleton() : _CollectedCell(o),
        o == null ? const GlanceCellSkeleton() : _ExpensesCell(o),
        o == null ? const GlanceCellSkeleton() : _NetCell(o),
        pending == null ? const GlanceCellSkeleton() : _PendingCell(pending!),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.caption});

  final String label;
  final String value;
  final Widget caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );
  }
}

class _CollectedCell extends StatelessWidget {
  const _CollectedCell(this.o);
  final RevenueOverview o;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final cmp = o.comparison;
    final pct = cmp.percent;
    final vs = o.comparisonLabel;
    Widget caption;
    if (cmp.current <= 0 && cmp.previous <= 0) {
      caption = const Text('Nothing collected yet');
    } else if (pct == null) {
      caption = Text('Nothing to compare with $vs');
    } else if (pct == 0) {
      caption = Text('Same as $vs');
    } else {
      // Up is green; down is amber (needs attention), never red.
      final up = pct > 0;
      final tone = up ? c.greenText : c.amberText;
      caption = Row(children: [
        CruIcon(
          up ? CruIcons.arrowUp : CruIcons.arrowDown,
          size: _arrowSize,
          strokeWidth: _arrowStroke,
          color: tone,
        ),
        const SizedBox(width: _arrowGap),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${pct.abs()}%',
                style: CruType.caption.w600.tabular.tint(tone),
              ),
              TextSpan(text: ' vs $vs'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);
    }
    return _Cell(
      label: 'Collected',
      value: DashFormat.rupees(o.collected),
      caption: caption,
    );
  }
}

class _ExpensesCell extends StatelessWidget {
  const _ExpensesCell(this.o);
  final RevenueOverview o;

  @override
  Widget build(BuildContext context) => _Cell(
        label: 'Expenses',
        value: DashFormat.rupees(o.expenses),
        caption: Text(o.expenseCaption),
      );
}

class _NetCell extends StatelessWidget {
  const _NetCell(this.o);
  final RevenueOverview o;

  @override
  Widget build(BuildContext context) {
    final pct = o.netPercent;
    final net = o.net;
    final value = net < 0
        ? '−${DashFormat.rupees(net.abs())}'
        : DashFormat.rupees(net);
    return _Cell(
      label: 'Net',
      value: value,
      caption: Text(pct == null ? 'Nothing collected yet' : '$pct% of collections'),
    );
  }
}

class _PendingCell extends StatelessWidget {
  const _PendingCell(this.groups);
  final List<PendingGroup> groups;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final total = groups.fold<double>(0, (s, g) => s + g.total);
    final Widget caption;
    if (groups.isEmpty) {
      caption = const Text('All settled');
    } else {
      final oldest = groups.first.ageDays;
      caption = Row(children: [
        const CruStatusDot(CruDotKind.waiting, size: CruSize.smallDot),
        const SizedBox(width: CruSpace.s6),
        Flexible(
          child: Text(
            '${DashFormat.plural(groups.length, 'patient')}'
            ' · oldest ${RevenueBuilder.age(oldest)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.caption.tabular.tint(c.label2),
          ),
        ),
      ]);
    }
    return _Cell(
      label: 'Pending',
      value: DashFormat.rupees(total),
      caption: caption,
    );
  }
}
