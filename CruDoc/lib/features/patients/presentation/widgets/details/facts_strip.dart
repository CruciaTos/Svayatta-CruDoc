import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Plan steps done out of the total (dentists with a treatment plan).
class PlanProgress {
  const PlanProgress({required this.done, required this.total});
  final int done;
  final int total;
}

/// Key facts, on the dashboard's glance strip: Treatment (or Visits),
/// Next visit, Last visit, Balance due.
class PatientFactsStrip extends StatelessWidget {
  const PatientFactsStrip({
    super.key,
    required this.summary,
    required this.now,
    this.plan,
    this.planLoading = false,
  });

  final PatientSummary summary;
  final DateTime now;

  /// Null when the patient has no treatment plan: the first cell shows
  /// completed visits without a ring.
  final PlanProgress? plan;

  /// The dental plan is still loading.
  final bool planLoading;

  @override
  Widget build(BuildContext context) {
    return GlanceStrip(
      semanticLabel: 'Key facts',
      cells: [
        planLoading
            ? const GlanceCellSkeleton(ring: true)
            : (plan != null ? _PlanCell(plan!) : _VisitsCell(summary)),
        _NextCell(summary: summary, now: now),
        _LastCell(summary: summary, now: now),
        _BalanceCell(summary),
      ],
    );
  }
}

/// "10:00 AM · Bracket bonding", or just the time.
String _timeAndTreatment(Visit v) {
  final t = v.treatmentType?.trim();
  final time = DashFormat.time(v.scheduledStart);
  return t == null || t.isEmpty ? time : '$time · $t';
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.caption});
  final String label;
  final Widget value;
  final Widget caption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [GlanceLabel(label), value, GlanceCaption(caption)],
      );
}

class _PlanCell extends StatelessWidget {
  const _PlanCell(this.plan);
  final PlanProgress plan;

  @override
  Widget build(BuildContext context) {
    final value = plan.total == 0 ? 0.0 : plan.done / plan.total;
    return Row(
      children: [
        CruProgressRing(
          value: value,
          semanticLabel: '${plan.done} of ${plan.total} steps done',
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(
          child: _Cell(
            label: 'Treatment',
            value: GlanceMetric('${plan.done}', suffix: 'of ${plan.total}'),
            caption: const Text('steps done'),
          ),
        ),
      ],
    );
  }
}

class _VisitsCell extends StatelessWidget {
  const _VisitsCell(this.s);
  final PatientSummary s;

  @override
  Widget build(BuildContext context) {
    final n = s.completedCount;
    return _Cell(
      label: 'Visits',
      value: GlanceMetric('$n'),
      caption: Text(n == 1 ? 'visit done' : 'visits done'),
    );
  }
}

class _NextCell extends StatelessWidget {
  const _NextCell({required this.summary, required this.now});
  final PatientSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final next = summary.nextVisit;
    final overdue = summary.overdueSince;
    if (next != null) {
      return _Cell(
        label: 'Next visit',
        value: GlanceMetric(PatientFormat.day(next.scheduledStart, now)),
        caption: Text(_timeAndTreatment(next)),
      );
    }
    if (overdue != null) {
      return _Cell(
        label: 'Next visit',
        value: Text(
          'Overdue',
          style: CruType.metric.tint(c.amberText),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        caption: Text('since ${PatientFormat.weekdayDate(overdue)}'),
      );
    }
    return const _Cell(
      label: 'Next visit',
      value: GlanceMetric('—'),
      caption: Text('Nothing booked'),
    );
  }
}

class _LastCell extends StatelessWidget {
  const _LastCell({required this.summary, required this.now});
  final PatientSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final last = summary.lastVisit;
    if (last == null) {
      return const _Cell(
        label: 'Last visit',
        value: GlanceMetric('—'),
        caption: Text('No visits yet'),
      );
    }
    return _Cell(
      label: 'Last visit',
      value: GlanceMetric(PatientFormat.day(last.scheduledStart, now)),
      caption: Text(_timeAndTreatment(last)),
    );
  }
}

class _BalanceCell extends StatelessWidget {
  const _BalanceCell(this.s);
  final PatientSummary s;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return _Cell(
      label: 'Balance due',
      value: GlanceMetric(PatientFormat.rupees(s.balance)),
      caption: s.hasBalance
          ? Row(children: [
              const CruStatusDot(CruDotKind.waiting, size: CruSize.smallDot),
              const SizedBox(width: CruSpace.s6),
              Flexible(
                child: Text(
                  'Package balance',
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ),
            ])
          : const Text('No balance due'),
    );
  }
}
