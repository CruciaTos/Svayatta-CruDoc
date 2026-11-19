import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/exercise_library_screen.dart';
import 'package:doctor_management_app/features/therapy/presentation/hep_builder_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: the latest home exercise
/// program, with the exercise library one tap away.
class HepCard extends ConsumerWidget {
  const HepCard({super.key, required this.patient});

  final Patient patient;

  void _push(BuildContext context, Widget screen) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((patientId: patient.id, kind: RecKind.physioHep)),
    );
    final programs = [
      for (final r in recs.value ?? const <DentalRecord>[])
        HepProgram.fromRecord(r),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final latest = programs.firstOrNull;

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
                  Icons.fitness_center_rounded,
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
                      'Home exercises',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      latest == null
                          ? 'Build a program from the exercise library'
                          : '${latest.items.length} exercise${latest.items.length == 1 ? '' : 's'} · ${DentalFormat.date(latest.date)}',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: 'Library',
                icon: CruIcons.search,
                onPressed: () => _push(context, const ExerciseLibraryScreen()),
              ),
              const SizedBox(width: CruSpace.s8),
              CruCapsuleButton(
                label: latest == null ? '+ Program' : 'Open',
                icon: latest == null ? CruIcons.plus : null,
                onPressed: () => _push(
                  context,
                  HepBuilderScreen(patient: patient, program: latest),
                ),
              ),
            ],
          ),
          if (latest != null && latest.items.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s12),
            Text(
              latest.items.take(3).map((i) => i.name).join(' · ') +
                  (latest.items.length > 3
                      ? ' · +${latest.items.length - 3} more'
                      : ''),
              style: CruType.caption.tint(c.label2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
