import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/charting_records.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The exams in one row on Charting's Chart tab: Perio, Endo, Pain/TMD,
/// Ortho (and Eruption for a child). Each one is its own card with a round
/// icon over its name and status. Fixed order, one tap to each exam.
class ExamDock extends StatelessWidget {
  const ExamDock({super.key, required this.records, this.perioKey});

  final List<ChartRecord> records;

  /// On the Perio cell, so Charting can grow the perio chart from it.
  final GlobalKey? perioKey;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    return Semantics(
      explicitChildNodes: true,
      label: 'Exams',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const SizedBox(width: CruSpace.s8),
            Expanded(
              child: KeyedSubtree(
                key: records[i].id == 'perio' ? perioKey : null,
                child: RecordIconCell(record: records[i], dock: true),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
