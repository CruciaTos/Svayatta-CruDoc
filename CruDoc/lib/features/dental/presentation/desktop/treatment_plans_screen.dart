import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _PlanFilter { open, awaiting, accepted, invoiced, declined, all }

/// One patient's plan on the clinic-wide list.
class _PatientPlan {
  _PatientPlan(this.patient, this.items);

  final Patient patient;
  final List<TreatmentPlanLineItemModel> items;

  List<TreatmentPlanLineItemModel> _with(TreatmentPlanItemStatus s) =>
      items.where((i) => TreatmentPlanItemStatus.fromString(i.status) == s).toList();

  List<TreatmentPlanLineItemModel> get proposed => _with(TreatmentPlanItemStatus.proposed);
  List<TreatmentPlanLineItemModel> get accepted => _with(TreatmentPlanItemStatus.accepted);
  List<TreatmentPlanLineItemModel> get invoiced => _with(TreatmentPlanItemStatus.invoiced);
  List<TreatmentPlanLineItemModel> get declined => _with(TreatmentPlanItemStatus.declined);

  static double sum(List<TreatmentPlanLineItemModel> l) =>
      l.fold(0.0, (t, i) => t + i.estimatedPrice);

  DateTime get updated =>
      items.map((i) => i.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  bool matches(_PlanFilter f) => switch (f) {
        _PlanFilter.open => proposed.isNotEmpty || accepted.isNotEmpty,
        _PlanFilter.awaiting => proposed.isNotEmpty,
        _PlanFilter.accepted => accepted.isNotEmpty,
        _PlanFilter.invoiced => invoiced.isNotEmpty,
        _PlanFilter.declined => declined.isNotEmpty,
        _PlanFilter.all => true,
      };
}

/// Every patient's treatment plan: what's waiting for a yes, what's
/// accepted and still to do, what's been invoiced.
class TreatmentPlansScreen extends ConsumerStatefulWidget {
  const TreatmentPlansScreen({super.key});

  @override
  ConsumerState<TreatmentPlansScreen> createState() =>
      _TreatmentPlansScreenState();
}

class _TreatmentPlansScreenState extends ConsumerState<TreatmentPlansScreen> {
  _PlanFilter _filter = _PlanFilter.open;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newPlan() async {
    final patient = await showPatientPickerDialog(
      context,
      title: 'Plan treatment for',
    );
    if (patient == null || !mounted) return;
    await showTreatmentPlanDialog(context, patient: patient);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final itemsAsync = ref.watch(clinicTreatmentPlansProvider);
    final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final byId = {for (final p in patients) p.id: p};
    final items = itemsAsync.value;

    final plans = <_PatientPlan>[];
    if (items != null) {
      final grouped = <String, List<TreatmentPlanLineItemModel>>{};
      for (final i in items) {
        if (i.isDeleted) continue;
        (grouped[i.patientId] ??= []).add(i);
      }
      for (final e in grouped.entries) {
        final p = byId[e.key];
        if (p == null) continue;
        plans.add(_PatientPlan(p, e.value..sort((a, b) => a.sequence.compareTo(b.sequence))));
      }
      plans.sort((a, b) => b.updated.compareTo(a.updated));
    }

    final all = plans.expand((p) => p.items).toList();
    final proposed = all.where((i) => TreatmentPlanItemStatus.fromString(i.status) == TreatmentPlanItemStatus.proposed).toList();
    final accepted = all.where((i) => TreatmentPlanItemStatus.fromString(i.status) == TreatmentPlanItemStatus.accepted).toList();
    final invoiced = all.where((i) => TreatmentPlanItemStatus.fromString(i.status) == TreatmentPlanItemStatus.invoiced).toList();
    final declined = all.where((i) => TreatmentPlanItemStatus.fromString(i.status) == TreatmentPlanItemStatus.declined).toList();
    final decided = accepted.length + invoiced.length + declined.length;
    final openPatients = plans.where((p) => p.matches(_PlanFilter.open)).length;

    final q = _query.trim().toLowerCase();
    final shown = plans
        .where((p) => p.matches(_filter))
        .where((p) =>
            q.isEmpty ||
            p.patient.fullName.toLowerCase().contains(q) ||
            p.items.any((i) => i.procedureName.toLowerCase().contains(q)))
        .toList();

    Widget cell(String label, String value, String caption, {Color? tone}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GlanceLabel(label),
            GlanceMetric(value),
            GlanceCaption(Text(caption,
                style: tone == null ? null : CruType.caption.tint(tone))),
          ],
        );

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Treatment plans',
            subtitle: items == null
                ? ''
                : openPatients == 0
                    ? 'No open plans'
                    : '${DashFormat.plural(openPatients, 'patient')} with open plans · '
                        '${DashFormat.rupees(_PatientPlan.sum(proposed) + _PatientPlan.sum(accepted))} to do',
            actions: [
              CruButton(label: 'New plan', icon: CruIcons.plus, onPressed: _newPlan),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (items == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Plans at a glance',
              cells: [
                cell(
                  'Awaiting a yes',
                  DashFormat.rupees(_PatientPlan.sum(proposed)),
                  proposed.isEmpty
                      ? 'Nothing waiting'
                      : '${DashFormat.plural(proposed.length, 'procedure')} proposed',
                  tone: proposed.isEmpty ? null : c.amberText,
                ),
                cell(
                  'Accepted',
                  DashFormat.rupees(_PatientPlan.sum(accepted)),
                  accepted.isEmpty
                      ? 'Nothing to do yet'
                      : '${DashFormat.plural(accepted.length, 'procedure')} to do',
                ),
                cell(
                  'Invoiced',
                  DashFormat.rupees(_PatientPlan.sum(invoiced)),
                  '${DashFormat.plural(invoiced.length, 'procedure')} done',
                ),
                cell(
                  'Acceptance',
                  decided == 0
                      ? '—'
                      : '${((accepted.length + invoiced.length) * 100 / decided).round()}%',
                  decided == 0
                      ? 'No decisions yet'
                      : 'of ${DashFormat.plural(decided, 'decided procedure')}',
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final filter = CruSegmentedControl<_PlanFilter>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_PlanFilter.open, 'Open'),
                  CruSegment(_PlanFilter.awaiting, 'Awaiting yes'),
                  CruSegment(_PlanFilter.accepted, 'Accepted'),
                  CruSegment(_PlanFilter.invoiced, 'Invoiced'),
                  CruSegment(_PlanFilter.declined, 'Declined'),
                  CruSegment(_PlanFilter.all, 'All'),
                ],
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              );
              final search = SizedBox(
                width: 280,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search patient or procedure',
                  onChanged: (v) => setState(() => _query = v),
                ),
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal, child: filter),
                    const SizedBox(height: CruSpace.s10),
                    search,
                  ],
                );
              }
              return Row(children: [filter, const Spacer(), search]);
            },
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Plans',
              padding: const EdgeInsets.all(CruSpace.s12),
              child: items == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: DentalIcons.plan,
                              title: plans.isEmpty
                                  ? 'No treatment plans yet'
                                  : 'No plans here',
                              body: plans.isEmpty
                                  ? 'Plan work from a patient\'s tooth chart, or '
                                      'start one here. Each procedure can be '
                                      'accepted, done and invoiced on its own.'
                                  : 'Try another filter or search.',
                              actions: [
                                if (plans.isEmpty)
                                  CruButton(
                                    label: 'New plan',
                                    icon: CruIcons.plus,
                                    onPressed: _newPlan,
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: shown.length,
                          separatorBuilder: (_, _) =>
                              const CruSeparator(indent: 12 + 40 + 12),
                          itemBuilder: (context, i) => _PlanRow(plan: shown[i]),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});

  final _PatientPlan plan;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = plan.items
        .where((i) => TreatmentPlanItemStatus.fromString(i.status) != TreatmentPlanItemStatus.declined)
        .toList();
    final summary = active
        .map((i) {
          final t = i.toothNumbers.isEmpty ? '' : ' (${i.toothNumbers.join(', ')})';
          return '${i.procedureName}$t';
        })
        .join(' · ');
    final done = plan.invoiced.length;
    final openSum = _PatientPlan.sum(plan.proposed) + _PatientPlan.sum(plan.accepted);
    final Widget pill = plan.proposed.isNotEmpty
        ? CruPill(text: 'Awaiting yes', background: c.amberTint, foreground: c.amberText)
        : plan.accepted.isNotEmpty
            ? CruPill(text: 'Accepted', background: c.accentTint, foreground: c.accentText)
            : plan.invoiced.isNotEmpty
                ? CruPill(text: 'Done', background: c.greenTint, foreground: c.greenText)
                : CruPill(text: 'Declined', background: c.inset, foreground: c.label3);
    return DentalListRow(
      semanticLabel: '${plan.patient.fullName}, treatment plan',
      minHeight: 64,
      onTap: () => showTreatmentPlanDialog(context, patient: plan.patient),
      child: Row(
        children: [
          CruMonogram(name: plan.patient.fullName, size: 40),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.patient.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.w600.tint(c.label),
                ),
                Text(
                  summary.isEmpty ? 'Every item declined' : summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          SizedBox(
            width: 90,
            child: Text(
              '$done of ${active.length} done',
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              openSum > 0 ? DashFormat.rupees(openSum) : '—',
              textAlign: TextAlign.right,
              style: CruType.row.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: pill)),
          CruCapsuleButton(
            label: 'Open patient',
            onPressed: () => DashboardActions.openPatient(context, plan.patient),
          ),
        ],
      ),
    );
  }
}
