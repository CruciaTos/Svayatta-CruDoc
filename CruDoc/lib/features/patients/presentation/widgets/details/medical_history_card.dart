import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Medical history, the one place for it: Condition and Notes from the
/// patient record; Allergies as the header shows them; Medications and
/// Past illnesses from the homeopathy case sheet when there is one; for
/// dentists, a Dental history row that opens the oral medicine history.
/// Tobacco and Last X-ray have no data (GAP) and are not shown.
class MedicalHistoryCard extends StatelessWidget {
  const MedicalHistoryCard({
    super.key,
    required this.summary,
    required this.caseSheet,
    required this.allergies,
    required this.onEdit,
    this.dental,
  });

  final PatientSummary summary;
  final HomeopathyCaseSheet? caseSheet;

  /// Null when nothing is recorded (the row is hidden).
  final KnownAllergies? allergies;
  final VoidCallback onEdit;

  /// Dentists: the oral medicine history in a line, and the way into it.
  final ({String line, VoidCallback onOpen})? dental;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final history = caseSheet?.medicalHistory;
    final a = allergies;
    final d = dental;
    final rows = <_Row>[
      if (summary.condition != null)
        _Row('Condition', summary.condition!, emphasis: true),
      if (a != null) _Row('Allergies', a.none ? 'None known' : a.text),
      if (history != null && history.pastMedications.trim().isNotEmpty)
        _Row('Medications', history.pastMedications.trim()),
      if (history != null && history.pastIllnesses.trim().isNotEmpty)
        _Row('Past illnesses', history.pastIllnesses.trim()),
      if (d != null) _Row('Dental history', d.line, onTap: d.onOpen),
      // Visit notes live on their visits; this is the note on the record.
      if (summary.patient.notes.trim().isNotEmpty)
        _Row('Notes', summary.patient.notes.trim()),
    ];
    final updated = caseSheet?.updatedAt ?? summary.patient.updatedAt;

    return CruCard(
      semanticLabel: 'Medical history',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsCardHeader(
            title: 'Medical history',
            trailing: CruLink(label: 'Edit', onPressed: onEdit),
          ),
          const SizedBox(height: CruSpace.s6),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
              child: Text(
                'Nothing recorded yet',
                style: CruType.text.tint(c.label2),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++)
              _HistoryRow(row: rows[i], separator: i < rows.length - 1),
          const SizedBox(height: CruSpace.s6),
          Text(
            'Updated ${PatientFormat.weekdayDate(updated)}',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value, {this.emphasis = false, this.onTap});
  final String label;
  final String value;
  final bool emphasis;

  /// Opens the record the row sums up (a chevron shows it).
  final VoidCallback? onTap;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row, required this.separator});

  final _Row row;
  final bool separator;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final tap = row.onTap;
    Widget body(bool hovered) => Container(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      decoration: separator
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.separator)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: CruSize.historyKeyColumn,
            child: Text(row.label, style: CruType.text.tint(c.label2)),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              row.value,
              style: (row.emphasis ? CruType.text.w500 : CruType.text).tabular
                  .tint(hovered ? c.accentText : c.label),
            ),
          ),
          if (tap != null) ...[
            const SizedBox(width: CruSpace.s8),
            CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
          ],
        ],
      ),
    );
    if (tap == null) return body(false);
    return CruPressable(
      onTap: tap,
      scaleOnPress: false,
      semanticLabel: '${row.label}: ${row.value}',
      builder: (context, hovered) => body(hovered),
    );
  }
}
