import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Medical history: Condition from the patient record; Allergies,
/// Medications and Past illnesses from the homeopathy case sheet when
/// there is one. Tobacco and Last X-ray have no data (GAP) and are not
/// shown.
class MedicalHistoryCard extends StatelessWidget {
  const MedicalHistoryCard({
    super.key,
    required this.summary,
    required this.caseSheet,
    required this.onEdit,
  });

  final PatientSummary summary;
  final HomeopathyCaseSheet? caseSheet;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final history = caseSheet?.medicalHistory;
    final allergies = KnownAllergies.parse(history?.allergies);
    final rows = <(String, String, bool)>[
      if (summary.condition != null) ('Condition', summary.condition!, true),
      if (allergies != null)
        ('Allergies', allergies.none ? 'None known' : allergies.text, false),
      if (history != null && history.pastMedications.trim().isNotEmpty)
        ('Medications', history.pastMedications.trim(), false),
      if (history != null && history.pastIllnesses.trim().isNotEmpty)
        ('Past illnesses', history.pastIllnesses.trim(), false),
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
              _HistoryRow(
                label: rows[i].$1,
                value: rows[i].$2,
                emphasis: rows[i].$3,
                separator: i < rows.length - 1,
              ),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.value,
    required this.emphasis,
    required this.separator,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool separator;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      decoration: separator
          ? BoxDecoration(border: Border(bottom: BorderSide(color: c.separator)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: CruSize.historyKeyColumn,
            child: Text(label, style: CruType.text.tint(c.label2)),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              value,
              style: (emphasis ? CruType.text.w500 : CruType.text)
                  .tabular
                  .tint(c.label),
            ),
          ),
        ],
      ),
    );
  }
}
