import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/note_composer.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/note_item.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Clinical notes: the composer, then every visit note newest first
/// (from `Visit.therapistNotes`), then the patient's note on file.
class ClinicalNotesCard extends StatelessWidget {
  const ClinicalNotesCard({super.key, required this.summary, required this.now});

  final PatientSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final items = <Widget>[
      for (final v in summary.visits)
        if (v.therapistNotes?.trim().isNotEmpty ?? false)
          NoteItem(
            heading: '${PatientFormat.day(v.scheduledStart, now)} · '
                '${_treatment(v.treatmentType)}',
            trailing: DashFormat.time(v.scheduledStart),
            body: v.therapistNotes!.trim(),
            visitId: v.id,
          ),
      if (summary.patient.notes.trim().isNotEmpty)
        NoteItem(
          heading: 'Patient note',
          trailing: 'On file',
          body: summary.patient.notes.trim(),
        ),
    ];

    return CruCard(
      semanticLabel: 'Clinical notes',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsCardHeader(
            title: 'Clinical notes',
            trailing: items.isEmpty
                ? null
                : Text(
                    DashFormat.plural(items.length, 'note'),
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
          ),
          const SizedBox(height: CruSpace.s16),
          NoteComposer(summary: summary, now: now),
          const SizedBox(height: CruSpace.s16),
          if (items.isEmpty)
            Text('No notes yet', style: CruType.text.tint(c.label2))
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: CruSpace.s16),
                  child: CruSeparator(),
                ),
              items[i],
            ],
        ],
      ),
    );
  }

  static String _treatment(String? t) {
    final v = t?.trim();
    return v == null || v.isEmpty ? 'Visit' : v;
  }
}
