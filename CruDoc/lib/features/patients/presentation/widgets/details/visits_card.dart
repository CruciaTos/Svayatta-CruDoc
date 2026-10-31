import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_files_provider.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The visit's name: its treatment, else where it happened.
String visitTitle(Visit visit) {
  final treatment = visit.treatmentType?.trim();
  if (treatment != null && treatment.isNotEmpty) return treatment;
  return visit.visitType == VisitType.home ? 'Home visit' : 'Clinic visit';
}

/// Visits on the Overview: the next one ("Today" when it is today) and
/// the last one. Each visit is its session and opens it ([onOpen]);
/// "See all N visits" goes to the Visits tab ([onSeeAll]).
class VisitsCard extends ConsumerWidget {
  const VisitsCard({
    super.key,
    required this.summary,
    required this.now,
    required this.onOpen,
    required this.onSeeAll,
    this.showClinical = true,
  });

  final PatientSummary summary;
  final DateTime now;
  final ValueChanged<Visit> onOpen;
  final VoidCallback onSeeAll;

  /// Note previews, Scribe marks and file counts (clinical roles only).
  final bool showClinical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final upcoming = summary.upcoming(now);
    final past = summary.past(now);
    final next = upcoming.firstOrNull;
    final last = past.firstOrNull;
    final total = upcoming.length + past.length;
    final shown = (next == null ? 0 : 1) + (last == null ? 0 : 1);
    final files = showClinical
        ? ref.watch(sessionFilesProvider(summary.id))
        : SessionFiles.empty;
    final today = next != null && DateUtils.isSameDay(next.scheduledStart, now);

    Widget row(Visit v, {required bool upcoming}) => MorphTag(
      id: 'visit:${v.id}',
      child: VisitRow(
        visit: v,
        now: now,
        upcoming: upcoming,
        showClinical: showClinical,
        fileCount: files.forVisit(v).length,
        onOpen: () => onOpen(v),
      ),
    );

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
              onTap: onSeeAll,
              morphId: 'title',
            ),
          ),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Text(
                'No visits yet. Book one with New visit; its notes and '
                'files go here.',
                style: CruType.text.tint(c.label2),
              ),
            ),
          if (next != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: DetailsSectionLabel(today ? 'Today' : 'Next'),
            ),
            row(next, upcoming: true),
          ],
          if (last != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(12, next == null ? 12 : 14, 12, 6),
              child: const DetailsSectionLabel('Last'),
            ),
            row(last, upcoming: false),
          ],
          if (total > shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CruLink(
                  label: 'See all $total visits',
                  onPressed: onSeeAll,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the Visits tab lists.
enum _VisitFilter { all, notes, missed }

/// The Visits tab: every visit, upcoming first, then the past by month.
/// A filter (all, with notes, missed or never recorded) shows once there
/// are enough visits to need it. Each visit opens its session
/// ([onOpen]).
class VisitsList extends ConsumerStatefulWidget {
  const VisitsList({
    super.key,
    required this.summary,
    required this.now,
    required this.onOpen,
    this.showClinical = true,
  });

  final PatientSummary summary;
  final DateTime now;
  final ValueChanged<Visit> onOpen;
  final bool showClinical;

  /// Visits before the filter shows.
  static const int filterFrom = 6;

  @override
  ConsumerState<VisitsList> createState() => _VisitsListState();
}

class _VisitsListState extends ConsumerState<VisitsList> {
  _VisitFilter _filter = _VisitFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final now = widget.now;
    final clinical = widget.showClinical;
    final upcoming = widget.summary.upcoming(now);
    final past = widget.summary.past(now);
    final total = upcoming.length + past.length;
    final files = clinical
        ? ref.watch(sessionFilesProvider(widget.summary.id))
        : SessionFiles.empty;
    // Visits Scribe wrote a confirmed note for.
    final scribed = clinical
        ? {
            for (final n
                in ref.watch(sessionHistoryProvider(widget.summary.id)).value ??
                    const <ConsultationNote>[])
              if (n.status == ConsultationNoteStatus.confirmed) n.visitId,
          }
        : const <String>{};
    final showFilter = total >= VisitsList.filterFrom;
    final filter = showFilter ? _filter : _VisitFilter.all;
    bool keep(Visit v) => switch (filter) {
      _VisitFilter.all => true,
      _VisitFilter.notes =>
        (v.therapistNotes?.trim().isNotEmpty ?? false) ||
            scribed.contains(v.id),
      _VisitFilter.missed =>
        v.status == VisitStatus.missed ||
            PatientsBuilder.visitStatus(v, now) == VisitRowStatus.notRecorded,
    };
    final shownUpcoming = upcoming.where(keep).toList();
    // Past visits by month, newest first.
    final months = <(String, List<Visit>)>[];
    for (final v in past.where(keep)) {
      final t = v.scheduledStart;
      final label = DateFormat(
        t.year == now.year ? 'MMMM' : 'MMMM y',
      ).format(t);
      if (months.isEmpty || months.last.$1 != label) {
        months.add((label, [v]));
      } else {
        months.last.$2.add(v);
      }
    }

    List<Widget> rows(List<Visit> visits, {required bool upcomingSection}) => [
      for (var i = 0; i < visits.length; i++) ...[
        if (i > 0)
          const CruSeparator(
            indent: CruSize.visitTextInset,
            endIndent: CruSpace.s12,
          ),
        MorphTag(
          id: 'visit:${visits[i].id}',
          child: VisitRow(
            visit: visits[i],
            now: now,
            upcoming: upcomingSection,
            showClinical: clinical,
            fileCount: files.forVisit(visits[i]).length,
            onOpen: () => widget.onOpen(visits[i]),
          ),
        ),
      ],
    ];

    final sections = <(String, List<Visit>, bool)>[
      if (shownUpcoming.isNotEmpty) ('Upcoming', shownUpcoming, true),
      for (final (label, visits) in months) (label, visits, false),
    ];
    final String empty;
    if (total == 0) {
      empty =
          'No visits yet. Book one with New visit; its notes and files go '
          'here.';
    } else {
      empty = switch (filter) {
        _VisitFilter.notes => 'No visits with notes yet.',
        _VisitFilter.missed => 'No missed visits.',
        _VisitFilter.all => 'No visits yet.',
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFilter) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: CruSegmentedControl<_VisitFilter>(
              semanticLabel: 'Show',
              segments: [
                const CruSegment(_VisitFilter.all, 'All'),
                if (clinical)
                  const CruSegment(_VisitFilter.notes, 'With notes'),
                const CruSegment(_VisitFilter.missed, 'Missed'),
              ],
              selected: filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          const SizedBox(height: CruSpace.s12),
        ],
        CruCard(
          semanticLabel: 'Visits',
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sections.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Text(empty, style: CruType.text.tint(c.label2)),
                ),
              for (var i = 0; i < sections.length; i++) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(12, i == 0 ? 12 : 18, 12, 6),
                  child: DetailsSectionLabel(sections[i].$1),
                ),
                ...rows(sections[i].$2, upcomingSection: sections[i].$3),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Booked", "Done", "Cancelled", "Missed" or "Not recorded", quiet except
/// done (green) and not recorded (amber).
class VisitStatusText extends StatelessWidget {
  const VisitStatusText({super.key, required this.status});
  final VisitRowStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (String text, TextStyle style) = switch (status) {
      VisitRowStatus.booked => ('Booked', CruType.subhead.w500.tint(c.label3)),
      VisitRowStatus.done => ('Done', CruType.subhead.w600.tint(c.greenText)),
      VisitRowStatus.notRecorded => (
        'Not recorded',
        CruType.subhead.w500.tint(c.amberText),
      ),
      VisitRowStatus.cancelled => (
        'Cancelled',
        CruType.subhead.w500.tint(c.label3),
      ),
      VisitRowStatus.missed => ('Missed', CruType.subhead.w500.tint(c.label2)),
    };
    return Text(text, style: style);
  }
}

/// Date tile, title, "Wed · 10:00 AM · 2 files", the start of the session
/// note, and the status on the right. Opens the visit.
class VisitRow extends StatelessWidget {
  const VisitRow({
    super.key,
    required this.visit,
    required this.now,
    required this.upcoming,
    required this.onOpen,
    this.showClinical = true,
    this.fileCount = 0,
  });

  final Visit visit;
  final DateTime now;
  final bool upcoming;
  final VoidCallback onOpen;
  final bool showClinical;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = visit.scheduledStart;
    final status = PatientsBuilder.visitStatus(visit, now);
    final day = PatientFormat.day(t, now);
    final relative = day == 'Today' || day == 'Tomorrow' || day == 'Yesterday';
    final notRecorded = status == VisitRowStatus.notRecorded;
    final sub = [
      '${relative ? day : PatientFormat.weekdayShort(t)} · '
          '${DashFormat.time(t)}',
      if (notRecorded) 'not recorded',
      if (showClinical && fileCount > 0) DashFormat.plural(fileCount, 'file'),
    ].join(' · ');
    final note = showClinical ? _firstLine(visit.therapistNotes) : null;

    final Widget trailing = notRecorded
        ? CruCapsuleButton(
            label: 'Update',
            height: CruSize.rowCapsule,
            semanticLabel:
                'Update the visit on ${PatientFormat.weekdayDate(t)}',
            onPressed: onOpen,
          )
        : VisitStatusText(status: status);

    return CruPressable(
      onTap: onOpen,
      scaleOnPress: false,
      semanticLabel:
          'Open the visit on ${PatientFormat.weekdayDate(t)}: '
          '${visitTitle(visit)}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
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
                    visitTitle(visit),
                    style: CruType.callout.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CruTimeText(
                    sub,
                    style: CruType.subhead.tabular.tint(
                      notRecorded ? c.amberText : c.label2,
                    ),
                    timeColor: c.accentText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showClinical) _NotePreview(visitId: visit.id, note: note),
                  // Booked together with someone: their own visit here,
                  // and who else was seen.
                  if (visit.groupId != null && visit.groupId!.isNotEmpty)
                    _SeenWith(visit: visit),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            trailing,
          ],
        ),
      ),
    );
  }

  static String? _firstLine(String? text) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return null;
    final nl = t.indexOf('\n');
    return nl < 0 ? t : t.substring(0, nl).trim();
  }
}

/// The session note's first line; a violet ✦ in front when Scribe wrote
/// a note for the visit ("Scribe note" alone when there is no typed one).
class _NotePreview extends ConsumerWidget {
  const _NotePreview({required this.visitId, required this.note});

  final String visitId;
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final scribe =
        ref
            .watch(notesForVisitProvider(visitId))
            .value
            ?.any((n) => n.status == ConsultationNoteStatus.confirmed) ??
        false;
    if (note == null && !scribe) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s2),
      child: Row(
        children: [
          if (scribe) ...[
            CruIcon(
              CruIcons.sparkleSingle,
              size: 12,
              strokeWidth: 2,
              color: c.ai,
            ),
            const SizedBox(width: CruSpace.s4),
          ],
          Flexible(
            child: Text(
              note ?? 'Scribe note',
              style: CruType.caption.tint(note == null ? c.ai : c.label2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeenWith extends ConsumerWidget {
  const _SeenWith({required this.visit});
  final Visit visit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final names = ref.watch(
      visitGroupNamesProvider((groupId: visit.groupId!, visitId: visit.id)),
    );
    if (names.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        CruIcon(CruIcons.patients, size: 13, strokeWidth: 2, color: c.label3),
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
  }
}
