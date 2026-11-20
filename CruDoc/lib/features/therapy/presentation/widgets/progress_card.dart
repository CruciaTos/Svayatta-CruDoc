import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/discharge_summary.dart';
import 'package:doctor_management_app/features/therapy/presentation/progress_report.dart';
import 'package:doctor_management_app/features/therapy/presentation/progress_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: pain and function over time.
class ProgressCard extends ConsumerWidget {
  const ProgressCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioProgress,
      )),
    );
    final entries = progressEntries(recs.value ?? const <DentalRecord>[]);
    final first = entries.firstOrNull;
    final last = entries.lastOrNull;

    String change(String label, int a, int b) =>
        entries.length > 1 && a != b ? '$label $a → $b' : '$label $b';

    return CruCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(CruRadius.control),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => ProgressScreen(patient: patient),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.inset,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                  ),
                  child: Icon(
                    Icons.show_chart_rounded,
                    size: 18,
                    color: c.label2,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progress',
                        style: CruType.headline.w600.tint(c.label),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        last == null
                            ? 'Track pain and daily function'
                            : '${entries.length} score${entries.length == 1 ? '' : 's'} · ${DentalFormat.date(last.date)}',
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                if (last != null) ...[
                  CruCapsuleButton(
                    label: 'Report',
                    icon: CruIcons.fileText,
                    onPressed: () async {
                      try {
                        await shareProgressReport(context, ref, patient);
                      } catch (e) {
                        debugPrint('progress report failed: $e');
                        if (context.mounted) {
                          recToast(context, "Couldn't build the report.");
                        }
                      }
                    },
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruCapsuleButton(
                    label: 'Discharge',
                    icon: CruIcons.fileText,
                    onPressed: () async {
                      try {
                        await shareDischargeSummary(context, ref, patient);
                      } catch (e) {
                        debugPrint('discharge summary failed: $e');
                        if (context.mounted) {
                          recToast(context, "Couldn't build the summary.");
                        }
                      }
                    },
                  ),
                  const SizedBox(width: CruSpace.s8),
                ],
                CruCapsuleButton(
                  label: last == null ? 'Log first score' : 'Log',
                  icon: CruIcons.plus,
                  onPressed: () =>
                      showProgressEntrySheet(context, ref, patient),
                ),
              ],
            ),
            if (first != null && last != null) ...[
              const SizedBox(height: CruSpace.s12),
              Text(
                '${change('Pain', first.pain, last.pain)}  ·  ${change('Function', first.function, last.function)}',
                style: CruType.body.w600.tint(c.label),
              ),
              if (entries.length > 1) ...[
                const SizedBox(height: CruSpace.s12),
                ProgressTrend(entries: entries),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
