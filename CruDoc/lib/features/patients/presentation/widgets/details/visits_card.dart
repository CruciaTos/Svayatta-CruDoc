import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';

/// Past visits shown before "See all".
const int kVisitsCardPastLimit = 4;

/// Visits: Upcoming and Past, from the patient's summary. A past booking
/// that was never recorded reads "not recorded" in amber with Update —
/// never "Pending".
class VisitsCard extends StatefulWidget {
  const VisitsCard({
    super.key,
    required this.summary,
    required this.now,
    required this.onUpdate,
  });

  final PatientSummary summary;
  final DateTime now;
  final ValueChanged<Visit> onUpdate;

  @override
  State<VisitsCard> createState() => _VisitsCardState();
}

class _VisitsCardState extends State<VisitsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final upcoming = widget.summary.upcoming(widget.now);
    final past = widget.summary.past(widget.now);
    final more = past.length > kVisitsCardPastLimit;
    final shownPast =
        _all || !more ? past : past.take(kVisitsCardPastLimit).toList();

    return CruCard(
      semanticLabel: 'Visits',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: 'Visits',
              trailing: more
                  ? CruLink(
                      label: _all ? 'Show less' : 'See all',
                      onPressed: () => setState(() => _all = !_all),
                    )
                  : null,
            ),
          ),
          if (upcoming.isEmpty && past.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Text('No visits yet', style: CruType.text.tint(c.label2)),
            ),
          if (upcoming.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: DetailsSectionLabel('Upcoming'),
            ),
            ..._rows(upcoming, upcomingSection: true),
          ],
          if (shownPast.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(12, upcoming.isEmpty ? 12 : 14, 12, 6),
              child: const DetailsSectionLabel('Past'),
            ),
            ..._rows(shownPast, upcomingSection: false),
          ],
        ],
      ),
    );
  }

  List<Widget> _rows(List<Visit> visits, {required bool upcomingSection}) => [
        for (var i = 0; i < visits.length; i++) ...[
          if (i > 0)
            const CruSeparator(
              indent: CruSize.visitTextInset,
              endIndent: CruSpace.s12,
            ),
          VisitRow(
            visit: visits[i],
            now: widget.now,
            upcoming: upcomingSection,
            onUpdate: () => widget.onUpdate(visits[i]),
          ),
        ],
      ];
}

/// Date tile, title, "Wed · 10:00 AM" and the status on the right.
class VisitRow extends StatelessWidget {
  const VisitRow({
    super.key,
    required this.visit,
    required this.now,
    required this.upcoming,
    required this.onUpdate,
  });

  final Visit visit;
  final DateTime now;
  final bool upcoming;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = visit.scheduledStart;
    final status = PatientsBuilder.visitStatus(visit, now);
    final treatment = visit.treatmentType?.trim();
    final title = treatment != null && treatment.isNotEmpty
        ? treatment
        : (visit.visitType == VisitType.home ? 'Home visit' : 'Clinic visit');
    final day = PatientFormat.day(t, now);
    final relative = day == 'Today' || day == 'Tomorrow' || day == 'Yesterday';
    var sub = '${relative ? day : PatientFormat.weekdayShort(t)} · '
        '${DashFormat.time(t)}';
    final notRecorded = status == VisitRowStatus.notRecorded;
    if (notRecorded) sub = '$sub · not recorded';

    final Widget trailing = switch (status) {
      VisitRowStatus.booked =>
        Text('Booked', style: CruType.subhead.w500.tint(c.label3)),
      VisitRowStatus.done =>
        Text('Done', style: CruType.subhead.w600.tint(c.greenText)),
      VisitRowStatus.notRecorded => CruCapsuleButton(
          label: 'Update',
          height: CruSize.rowCapsule,
          semanticLabel: 'Update the visit on ${PatientFormat.weekdayDate(t)}',
          onPressed: onUpdate,
        ),
      VisitRowStatus.cancelled =>
        Text('Cancelled', style: CruType.subhead.w500.tint(c.label3)),
      VisitRowStatus.missed =>
        Text('Missed', style: CruType.subhead.w500.tint(c.label2)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s8,
      ),
      child: Row(
        children: [
          CruDateTile(
            month: PatientFormat.month(t),
            day: PatientFormat.dayOfMonth(t),
            upcoming: upcoming,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: CruType.callout.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sub,
                  style: CruType.subhead.tabular
                      .tint(notRecorded ? c.amberText : c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Booked together with someone: their own visit here, and
                // who else was seen.
                if (visit.groupId != null && visit.groupId!.isNotEmpty)
                  Consumer(
                    builder: (context, ref, _) {
                      final names = ref.watch(
                        visitGroupNamesProvider(
                          (groupId: visit.groupId!, visitId: visit.id),
                        ),
                      );
                      if (names.isEmpty) return const SizedBox.shrink();
                      return Row(
                        children: [
                          CruIcon(
                            CruIcons.patients,
                            size: 13,
                            strokeWidth: 2,
                            color: c.label3,
                          ),
                          const SizedBox(width: CruSpace.s4),
                          Flexible(
                            child: Text(
                              'Seen with ${names.join(', ')}',
                              style: CruType.caption.tint(c.label2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          trailing,
        ],
      ),
    );
  }
}
