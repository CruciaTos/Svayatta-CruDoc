import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/special_tests.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/special_tests_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: special tests recorded for
/// this patient, with the test library one tap away.
class SpecialTestsCard extends ConsumerWidget {
  const SpecialTestsCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioTestResult,
      )),
    );
    final results = testResults(recs.value ?? const <DentalRecord>[]);
    final latest = results.take(3).toList();

    return CruCard(
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
                  Icons.fact_check_outlined,
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
                      'Special tests',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      results.isEmpty
                          ? 'Orthopaedic test guide and results'
                          : '${results.length} result${results.length == 1 ? '' : 's'} recorded',
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: 'Library',
                icon: CruIcons.search,
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => SpecialTestsScreen(patient: patient),
                      ),
                    ),
              ),
            ],
          ),
          for (final r in latest)
            if (specialTestById(r.testId) case final t?)
              InkWell(
                borderRadius: BorderRadius.circular(CruRadius.control),
                onTap: () => openSpecialTest(context, patient, t),
                child: Padding(
                  padding: const EdgeInsets.only(top: CruSpace.s12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.name} · ${TestResult.resultLabel(r.result)} · ${TestResult.sideLabel(r.side)}',
                          style: CruType.body.w600.tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: CruSpace.s8),
                      Text(
                        DentalFormat.shortDate(r.date),
                        style: CruType.caption.tabular.tint(c.label2),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
