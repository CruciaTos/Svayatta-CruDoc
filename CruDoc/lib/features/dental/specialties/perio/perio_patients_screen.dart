import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/dental/records/perio_staging.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Maintenance recalls count as due this many days ahead (or overdue).
const _maintenanceWindow = Duration(days: 14);

/// One charted patient, from their newest perio exam.
class PerioPatientRow {
  const PerioPatientRow({
    required this.patientId,
    required this.exam,
    required this.summary,
    required this.dx,
    required this.nextRecall,
    required this.maintenanceDue,
  });

  final String patientId;
  final DentalRecord exam;
  final PerioSummary summary;

  /// The stage and grade saved for [exam], if any.
  final DentalRecord? dx;

  /// The patient's earliest open recall, whatever it's for.
  final DentalRecord? nextRecall;

  /// A perio recall due within two weeks, or overdue.
  final bool maintenanceDue;

  /// Stage III/IV periodontitis, or any site 6 mm or deeper.
  bool get activeDisease =>
      summary.deep6 > 0 ||
      (dx != null &&
          dx!.str('diagnosis') == 'periodontitis' &&
          (dx!.integer('stage') ?? 0) >= 3);
}

/// Everything the Perio patients page and the periodontist's dashboard
/// card show, worked out once.
class PerioOverview {
  PerioOverview._(this.rows, this.maintenanceDue, this.examsThisMonth);

  factory PerioOverview.from({
    required List<DentalRecord> exams,
    required List<DentalRecord> dxs,
    required List<DentalRecord> recalls,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final horizon = today.add(_maintenanceWindow + const Duration(days: 1));

    // Records come newest first: the first one seen is the latest.
    final latest = <String, DentalRecord>{};
    for (final e in exams) {
      if (e.patientId.isNotEmpty) latest.putIfAbsent(e.patientId, () => e);
    }
    final dxByExam = <String, DentalRecord>{};
    for (final d in dxs) {
      dxByExam.putIfAbsent(d.str('examId'), () => d);
    }

    final open =
        recalls.where((r) => recallStatusOf(r).isOpen).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final nextRecall = <String, DentalRecord>{};
    for (final r in open) {
      nextRecall.putIfAbsent(r.patientId, () => r);
    }
    final maintenance = open
        .where(
          (r) =>
              r.str('reason').toLowerCase().contains('perio') &&
              r.recordedAt.isBefore(horizon),
        )
        .toList();
    final maintenancePatients = {for (final r in maintenance) r.patientId};

    final rows = [
      for (final e in latest.entries)
        PerioPatientRow(
          patientId: e.key,
          exam: e.value,
          summary: perioSummaryOf(e.value),
          dx: dxByExam[e.value.id],
          nextRecall: nextRecall[e.key],
          maintenanceDue: maintenancePatients.contains(e.key),
        ),
    ]..sort((a, b) => b.exam.recordedAt.compareTo(a.exam.recordedAt));

    final thisMonth = exams
        .where(
          (e) =>
              e.recordedAt.year == now.year && e.recordedAt.month == now.month,
        )
        .length;
    return PerioOverview._(rows, maintenance, thisMonth);
  }

  final List<PerioPatientRow> rows;

  /// Open perio recalls due within two weeks, or overdue.
  final List<DentalRecord> maintenanceDue;
  final int examsThisMonth;

  int get deepPockets => rows.where((r) => r.summary.deep6 > 0).length;
  int get bleeding30 =>
      rows.where((r) => (r.summary.bopPct ?? 0) >= 30).length;
  int get activeDisease => rows.where((r) => r.activeDisease).length;
}

/// The clinic's perio picture; null while the records load.
final perioOverviewProvider = Provider<PerioOverview?>((ref) {
  final exams = ref.watch(clinicRecordsProvider(RecKind.perio)).value;
  final dxs = ref.watch(clinicRecordsProvider(RecKind.perioDx)).value;
  final recalls = ref.watch(clinicRecordsProvider(RecKind.recall)).value;
  if (exams == null || dxs == null || recalls == null) return null;
  return PerioOverview.from(
    exams: exams,
    dxs: dxs,
    recalls: recalls,
    now: DateTime.now(),
  );
});

enum _Show { all, active, maintenance }

/// The periodontist's worklist: who has active disease and who is due
/// for maintenance. One row per charted patient, from their newest exam.
class PerioPatientsScreen extends ConsumerStatefulWidget {
  const PerioPatientsScreen({super.key});

  @override
  ConsumerState<PerioPatientsScreen> createState() =>
      _PerioPatientsScreenState();
}

class _PerioPatientsScreenState extends ConsumerState<PerioPatientsScreen> {
  _Show _show = _Show.all;

  void _open(Patient? p) {
    if (p == null) {
      recToast(context, "This patient's record isn't loaded yet.");
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: Theme.of(context),
          child: PerioChartScreen(patient: p),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final overview = ref.watch(perioOverviewProvider);
    final patients = {
      for (final p
          in ref.watch(patientsStreamProvider).value ?? const <Patient>[])
        p.id: p,
    };
    final rows = overview?.rows ?? const <PerioPatientRow>[];
    final shown = rows
        .where(
          (r) => switch (_show) {
            _Show.all => true,
            _Show.active => r.activeDisease,
            _Show.maintenance => r.maintenanceDue,
          },
        )
        .toList();
    final today = DateUtils.dateOnly(DateTime.now());

    Widget cell(String label, int value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric('$value'),
        GlanceCaption(caption),
      ],
    );

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Perio patients',
            subtitle: overview == null || rows.isEmpty
                ? 'Who has active disease, and who is due for maintenance'
                : '${overview.activeDisease} with active disease · '
                      '${overview.maintenanceDue.length} due for maintenance',
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (overview == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Perio patients at a glance',
              cells: [
                cell(
                  'Charted',
                  rows.length,
                  const Text('Patients with an exam'),
                ),
                cell(
                  'Deep pockets',
                  overview.deepPockets,
                  const Text('Sites 6 mm or deeper'),
                ),
                cell(
                  'Bleeding ≥ 30%',
                  overview.bleeding30,
                  const Text('On the latest exam'),
                ),
                cell(
                  'Maintenance due',
                  overview.maintenanceDue.length,
                  overview.maintenanceDue.isEmpty
                      ? const Text('None in the next 14 days')
                      : Text(
                          'Next 14 days or overdue',
                          style: CruType.caption.tint(c.amberText),
                        ),
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              CruSegmentedControl<_Show>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_Show.all, 'All'),
                  CruSegment(_Show.active, 'Active disease'),
                  CruSegment(_Show.maintenance, 'Maintenance due'),
                ],
                selected: _show,
                onChanged: (s) => setState(() => _show = s),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Perio patients',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: overview == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: DentalEmptyState(
                          icon: RecIcons.perio,
                          title: rows.isEmpty
                              ? 'No perio exams yet'
                              : 'Nothing here',
                          body: rows.isEmpty
                              ? 'Chart a patient from their record: Clinical '
                                    'records, then Perio chart. They show up '
                                    'here with their pockets, bleeding and recall.'
                              : 'No patients match this filter.',
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        const SizedBox(height: CruSpace.s8),
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const CruSeparator(indent: 12 + 36 + 12),
                          _PatientRow(
                            row: shown[i],
                            patient: patients[shown[i].patientId],
                            today: today,
                            onTap: () => _open(patients[shown[i].patientId]),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.row,
    required this.patient,
    required this.today,
    required this.onTap,
  });

  final PerioPatientRow row;
  final Patient? patient;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = row.summary;
    final name = patient?.fullName ?? 'Patient not found';
    final stage = row.dx == null ? '' : perioStageGrade(row.dx!);
    final recall = row.nextRecall;
    final late = recall != null && recall.recordedAt.isBefore(today);
    final detail = [
      'Last exam ${DentalFormat.date(row.exam.recordedAt)}',
      if (s.meanPd != null) 'PD ${s.meanPd!.toStringAsFixed(1)} mm',
      if (s.bopPct != null) 'bleeding ${s.bopPct!.toStringAsFixed(0)}%',
      '${DashFormat.plural(s.deep6, 'site')} ≥ 6 mm',
    ].join(' · ');

    return DentalListRow(
      semanticLabel: '$name. $detail${stage.isEmpty ? '' : '. $stage'}',
      onTap: onTap,
      minHeight: 64,
      child: Row(
        children: [
          CruMonogram(name: patient?.fullName ?? '', size: 36),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(
                    s.deep6 > 0 ? c.amberText : c.label2,
                  ),
                ),
              ],
            ),
          ),
          if (stage.isNotEmpty) ...[
            const SizedBox(width: CruSpace.s12),
            CruPill(text: stage, background: c.inset, foreground: c.label2),
          ],
          const SizedBox(width: CruSpace.s12),
          SizedBox(
            width: 104,
            child: Text(
              recall == null
                  ? 'No recall'
                  : 'Recall ${DentalFormat.shortDate(recall.recordedAt)}',
              textAlign: TextAlign.right,
              style: CruType.subhead.tabular.tint(
                recall == null
                    ? c.label3
                    : late || row.maintenanceDue
                    ? c.amberText
                    : c.label2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
