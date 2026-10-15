import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Sessions shown before "See all".
const int kSessionHistoryLimit = 4;

/// The patient's session notes: one row per consultation the AI scribe
/// wrote up, newest first. Opening a row shows the full note, which
/// clinicians can edit. Only built when there is at least one session.
class SessionHistoryCard extends StatefulWidget {
  const SessionHistoryCard({
    super.key,
    required this.patient,
    required this.sessions,
  });

  final Patient patient;

  /// Session notes, newest first (see `sessionHistoryProvider`).
  final List<ConsultationNote> sessions;

  @override
  State<SessionHistoryCard> createState() => _SessionHistoryCardState();
}

class _SessionHistoryCardState extends State<SessionHistoryCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final more = sessions.length > kSessionHistoryLimit;
    final shown = _all || !more
        ? sessions
        : sessions.take(kSessionHistoryLimit).toList();

    return CruCard(
      semanticLabel: 'Session notes',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DetailsCardHeader(
              title: 'Session notes',
              trailing: more
                  ? CruLink(
                      label: _all ? 'Show less' : 'See all',
                      onPressed: () => setState(() => _all = !_all),
                    )
                  : null,
            ),
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              const CruSeparator(
                indent: CruSize.visitTextInset,
                endIndent: CruSpace.s12,
              ),
            SessionRow(
              note: shown[i],
              onOpen: () => openSessionNote(
                context,
                note: shown[i],
                patient: widget.patient,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Date tile, what the session was about, and "10:30 AM · Token 4 ·
/// Edited".
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.note, required this.onOpen});

  final ConsultationNote note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = note.createdAt;
    final sub = [
      DashFormat.time(t),
      if (note.isEdited) 'Edited',
    ].join(' · ');
    return CruPressable(
      onTap: onOpen,
      semanticLabel: 'Open the session on ${PatientFormat.weekdayDate(t)}',
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: BoxDecoration(
          color: hovered ? c.hoverFill : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CruDateTile(
              month: PatientFormat.month(t),
              day: PatientFormat.dayOfMonth(t),
              upcoming: false,
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sessionTitle(note),
                    style: CruType.callout.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub,
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
          ],
        ),
      ),
    );
  }
}
