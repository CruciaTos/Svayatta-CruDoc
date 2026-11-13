import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/charting_records.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The exams in one row on Charting's Chart tab: Perio, Endo, Pain/TMD,
/// Ortho (and Eruption for a child), round icons with their status under
/// them. Fixed order, one tap to each exam.
class ExamDock extends StatelessWidget {
  const ExamDock({super.key, required this.records, this.perioKey});

  final List<ChartRecord> records;

  /// On the Perio cell, so Charting can grow the perio chart from it.
  final GlobalKey? perioKey;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    return CruCard(
      semanticLabel: 'Exams',
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in records)
            Expanded(
              child: KeyedSubtree(
                key: r.id == 'perio' ? perioKey : null,
                child: RecordIconCell(record: r, dock: true),
              ),
            ),
        ],
      ),
    );
  }
}
