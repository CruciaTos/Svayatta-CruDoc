import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_totality.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_totality_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient screen card: the dominant miasm and the number of characteristic
/// symptoms from the saved totality. The action opens the full screen.
class HomeopathyTotalityCard extends ConsumerWidget {
  const HomeopathyTotalityCard({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HomeopathyTotalityScreen(
        patientId: patientId,
        patientName: patientName,
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs =
        ref
            .watch(
              patientRecordsProvider((
                patientId: patientId,
                kind: RecKind.homeoTotality,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final totality = recs.isEmpty ? null : HomeoTotality.fromRecord(recs.first);
    final dom = totality?.dominant;
    final chars = totality?.characteristicCount ?? 0;
    final hasMarks = totality != null && (dom != null || chars > 0);
    final actionLabel = hasMarks ? 'Open' : 'Build totality';

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Totality', style: CruType.headline.tint(c.label)),
              ),
              CruPressable(
                onTap: () => _open(context),
                semanticLabel: actionLabel,
                builder: (context, hovered) => Text(
                  actionLabel,
                  style: CruType.subhead.w600.tint(c.accentText),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          if (!hasMarks)
            Text(
              'Rank the case sheet symptoms and tag their miasm.',
              style: CruType.text.tint(c.label2),
            )
          else ...[
            if (dom != null)
              Text(
                dominantLine(dom),
                style: CruType.text.tabular.tint(c.label),
              ),
            const SizedBox(height: CruSpace.s2),
            Text(
              '$chars characteristic symptom${chars == 1 ? '' : 's'}',
              style: CruType.caption.tabular.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}
