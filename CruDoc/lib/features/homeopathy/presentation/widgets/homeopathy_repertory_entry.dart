import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertorization.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/repertory_screen.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The one way into the repertory from a patient's page: a card with a
/// "Repertorize" capsule and a line about the last saved repertorization.
class HomeopathyRepertoryEntry extends ConsumerWidget {
  const HomeopathyRepertoryEntry({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final records =
        ref
            .watch(
              patientRecordsProvider((
                patientId: patientId,
                kind: RecKind.homeoRepertorization,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final saved = [for (final r in records) Repertorization.fromRecord(r)]
      ..sort((a, b) => b.date.compareTo(a.date));

    String summary =
        'Pick rubrics from the case and see which remedies '
        'cover them.';
    if (saved.isNotEmpty) {
      final last = saved.first;
      final top = last.result.remedies.take(3).map((r) => r.abbr).join(', ');
      summary =
          '${saved.length} saved · last '
          '${DateFormat('d MMM yyyy').format(last.date)}'
          '${top.isEmpty ? '' : ': $top'}';
    }

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Repertory', style: CruType.headline.tint(c.label)),
              ),
              CruCapsuleButton(
                label: 'Repertorize',
                icon: HomeopathyIcons.flask,
                onPressed: () => RepertoryScreen.open(
                  context,
                  patientId: patientId,
                  patientName: patientName,
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          Text(summary, style: CruType.caption.tabular.tint(c.label2)),
        ],
      ),
    );
  }
}
