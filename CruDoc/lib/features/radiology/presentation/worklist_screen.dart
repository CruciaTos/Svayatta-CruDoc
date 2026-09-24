import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/pacs_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/rad_import_flow.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Show { all, toRead, inReport, signed }

/// The next study to read: STAT first, then urgent, then the one due
/// soonest.
RadStudy? radNextUnread(List<RadStudy> studies) {
  final open = studies
      .where((s) => s.status == RadStudyStatus.newStudy || s.status == RadStudyStatus.reading)
      .toList()
    ..sort(_byUrgency);
  return open.firstOrNull;
}

int _byUrgency(RadStudy a, RadStudy b) {
  if (a.priority != b.priority) return b.priority.index.compareTo(a.priority.index);
  final da = a.dueAt ?? a.receivedAt, db = b.dueAt ?? b.receivedAt;
  return da.compareTo(db);
}

/// Scans sent for reading and where each one is: to read, in report,
/// signed. Drop files or folders anywhere here to import them.
class RadWorklistScreen extends ConsumerStatefulWidget {
  const RadWorklistScreen({super.key});

  @override
  ConsumerState<RadWorklistScreen> createState() => _RadWorklistScreenState();
}

class _RadWorklistScreenState extends ConsumerState<RadWorklistScreen> {
  _Show _show = _Show.all;
  RadModality? _type;
  final _search = TextEditingController();
  String _query = '';
  bool _dragging = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import([List<String>? paths]) => runRadImport(context, ref, paths: paths);

  void _openNext(List<RadStudy> studies) {
    final next = radNextUnread(studies);
    if (next == null) {
      radToast(context, 'Nothing left to read.');
      return;
    }
    openRadStudy(context, ref, next);
  }

  bool _matches(RadStudy s, Map<String, RadReferrer> referrers) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final r = referrers[s.referrerId];
    return s.patientName.toLowerCase().contains(q) ||
        s.clinicalQuestion.toLowerCase().contains(q) ||
        s.description.toLowerCase().contains(q) ||
        (r?.name.toLowerCase().contains(q) ?? false) ||
        (r?.clinic.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final async = ref.watch(radStudiesProvider);
    final studies = async.value;
    final referrers = ref.watch(radReferrerByIdProvider);
    final now = DateTime.now();

    final open = studies?.where((s) => s.status.isOpen).toList() ?? const <RadStudy>[];
    final toRead = open
        .where((s) => s.status == RadStudyStatus.newStudy || s.status == RadStudyStatus.reading)
        .toList();
    final urgent = open.where((s) => s.priority != RadPriority.routine).length;
    final overdue = open.where((s) => s.isOverdue(now)).length;
    final signedToday = studies
            ?.where((s) => !s.status.isOpen && DentalFormat.sameDay(s.updatedAt, now))
            .length ??
        0;

    final shown = (studies ?? const <RadStudy>[])
        .where((s) => switch (_show) {
              _Show.all => true,
              _Show.toRead =>
                s.status == RadStudyStatus.newStudy || s.status == RadStudyStatus.reading,
              _Show.inReport =>
                s.status == RadStudyStatus.draft || s.status == RadStudyStatus.preliminary,
              _Show.signed => !s.status.isOpen,
            })
        .where((s) => _type == null || s.modality == _type)
        .where((s) => _matches(s, referrers))
        .toList();

    // To read (most urgent first), in report, then signed (newest first).
    final groups = <(String, List<RadStudy>)>[
      ('To read', shown.where((s) => toRead.contains(s)).toList()..sort(_byUrgency)),
      (
        'In report',
        shown
            .where((s) =>
                s.status == RadStudyStatus.draft || s.status == RadStudyStatus.preliminary)
            .toList()
          ..sort(_byUrgency)
      ),
      (
        'Signed',
        shown.where((s) => !s.status.isOpen).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))
      ),
    ].where((g) => g.$2.isNotEmpty).toList();

    Widget cell(String label, String value, Widget caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [GlanceLabel(label), GlanceMetric(value), GlanceCaption(caption)],
        );

    final page = Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Worklist',
            subtitle: studies == null || studies.isEmpty
                ? 'Scans sent to you for reading'
                : '${DashFormat.plural(toRead.length, 'study', 'studies')} to read'
                    '${overdue > 0 ? ' · $overdue overdue' : ''}',
            actions: [
              CruButton(
                label: 'PACS',
                icon: RadIcons.server,
                kind: CruButtonKind.secondary,
                onPressed: () => showRadPacsQueryDialog(context),
              ),
              CruButton(
                label: 'Open next',
                icon: RadIcons.next,
                kind: CruButtonKind.secondary,
                onPressed: studies == null ? null : () => _openNext(studies),
              ),
              CruButton(
                label: 'Import scans',
                icon: RadIcons.import,
                onPressed: () => _import(),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (studies == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Worklist at a glance',
              cells: [
                cell(
                  'To read',
                  '${toRead.length}',
                  Text(toRead.isEmpty ? 'All caught up' : 'Oldest ${RadFormat.ago(toRead.map((s) => s.receivedAt).reduce((a, b) => a.isBefore(b) ? a : b), now).toLowerCase()}'),
                ),
                cell(
                  'Urgent and STAT',
                  '$urgent',
                  Text(urgent == 0 ? 'None waiting' : 'Waiting for a report'),
                ),
                cell(
                  'Overdue',
                  '$overdue',
                  overdue == 0
                      ? const Text('Everything on time')
                      : Text('Past their turnaround time',
                          style: CruType.caption.tint(c.amberText)),
                ),
                cell('Signed today', '$signedToday',
                    Text(signedToday == 0 ? 'None yet' : 'Reports finalised')),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              CruSegmentedControl<_Show>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_Show.all, 'All'),
                  CruSegment(_Show.toRead, 'To read'),
                  CruSegment(_Show.inReport, 'In report'),
                  CruSegment(_Show.signed, 'Signed'),
                ],
                selected: _show,
                onChanged: (s) => setState(() => _show = s),
              ),
              const SizedBox(width: CruSpace.s12),
              PopupMenuButton<RadModality?>(
                tooltip: 'Study type',
                onSelected: (m) => setState(() => _type = m),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('All types')),
                  for (final m in RadModality.values)
                    PopupMenuItem(value: m, child: Text(m.label)),
                ],
                child: IgnorePointer(
                  child: CruButton(
                    label: _type?.short ?? 'All types',
                    icon: CruIcons.chevronDown,
                    kind: CruButtonKind.inset,
                    onPressed: () {},
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 300,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search patient, referrer or question',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Studies',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: studies == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: RadIcons.worklist,
                              title: studies.isEmpty ? 'No scans yet' : 'No studies here',
                              body: studies.isEmpty
                                  ? 'Import CBCT, OPG, ceph or intraoral scans from a CD, '
                                      'folder or ZIP, or drop them anywhere on this page. '
                                      'Each study waits here until its report is signed.'
                                  : 'Try another filter or search.',
                              actions: [
                                if (studies.isEmpty)
                                  CruButton(
                                    label: 'Import scans',
                                    icon: RadIcons.import,
                                    onPressed: () => _import(),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final g in groups) ...[
                              DentalGroupLabel(g.$1,
                                  trailing: DashFormat.plural(g.$2.length, 'study', 'studies')),
                              for (var i = 0; i < g.$2.length; i++) ...[
                                if (i > 0) const CruSeparator(indent: 12 + 58 + 14),
                                _StudyRow(
                                  study: g.$2[i],
                                  referrer: referrers[g.$2[i].referrerId],
                                  now: now,
                                ),
                              ],
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (studies != null) _openNext(studies);
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _import(),
      },
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          final paths = [for (final f in detail.files) f.path];
          if (paths.isNotEmpty) _import(paths);
        },
        child: Stack(
          children: [
            Positioned.fill(child: page),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(CruSpace.s16),
                    decoration: ShapeDecoration(
                      color: c.surface.withValues(alpha: 0.92),
                      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline, width: 2)),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CruIconTile(icon: RadIcons.import, tone: CruTileTone.accent),
                        const SizedBox(height: CruSpace.s12),
                        Text('Drop to import scans', style: CruType.headline.tint(c.label)),
                        const SizedBox(height: CruSpace.s4),
                        Text('DICOM, pictures, folders, patient CDs and ZIP files',
                            style: CruType.subhead.tint(c.label2)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _RowAction { report, view3d, edit, routine, urgent, stat, invoice, delete }

class _StudyRow extends ConsumerWidget {
  const _StudyRow({required this.study, required this.referrer, required this.now});

  final RadStudy study;
  final RadReferrer? referrer;
  final DateTime now;

  Future<void> _act(BuildContext context, WidgetRef ref, _RowAction a) async {
    final ctrl = ref.read(radiologyProvider);
    switch (a) {
      case _RowAction.report:
        await openRadReport(context, study);
      case _RowAction.view3d:
        await openRadCbct3d(context, study);
      case _RowAction.edit:
        await showDialog<bool>(
          context: context,
          builder: (_) => RadStudyFormDialog(existing: study),
        );
      case _RowAction.routine:
      case _RowAction.urgent:
      case _RowAction.stat:
        final p = switch (a) {
          _RowAction.urgent => RadPriority.urgent,
          _RowAction.stat => RadPriority.stat,
          _ => RadPriority.routine,
        };
        await ctrl.saveStudy(
          study.copyWith(priority: p, dueAt: await ctrl.dueFor(p, study.receivedAt)),
          auditAction: 'Priority ${p.label}',
          detail: study.patientName,
        );
      case _RowAction.invoice:
        await invoiceRadStudy(context, ref, study);
      case _RowAction.delete:
        final ok = await confirmDental(
          context,
          title: 'Delete this study?',
          body: '${study.patientName}\'s ${study.modality.label} from '
              '${RadFormat.date(study.studyDate)}, its ${RadFormat.images(study.imageCount)} '
              'and any report will be removed from this computer.',
          action: 'Delete',
        );
        if (ok) await ctrl.deleteStudy(study);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final due = RadFormat.due(study, now);
    final line = [
      RadFormat.patientLine(study, now),
      if (study.clinicalQuestion.isNotEmpty) study.clinicalQuestion
      else if (study.description.isNotEmpty) study.description,
    ].where((s) => s.isNotEmpty).join(' · ');
    final priority = radPriorityPill(c, study.priority);

    return DentalListRow(
      semanticLabel: '${study.patientName}, ${study.modality.label}, ${study.status.label}',
      onTap: () => openRadStudy(context, ref, study),
      minHeight: 64,
      child: Row(
        children: [
          RadModalityBadge(study.modality),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        study.patientName.isEmpty ? 'Unnamed patient' : study.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.callout.tint(c.label),
                      ),
                    ),
                    if (study.critical) ...[
                      const SizedBox(width: CruSpace.s8),
                      Tooltip(
                        message: 'Critical finding',
                        child: CruIcon(RadIcons.flag, size: 14, strokeWidth: 2, color: c.redText),
                      ),
                    ],
                  ],
                ),
                if (line.isNotEmpty)
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.subhead.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referrer?.name ?? 'No referrer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(referrer == null ? c.label3 : c.label),
                ),
                Text(
                  '${RadFormat.ago(study.receivedAt, now)} · ${RadFormat.images(study.imageCount)}',
                  maxLines: 1,
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          SizedBox(
            width: 104,
            child: Text(
              due.text,
              maxLines: 1,
              style: CruType.subhead.tabular.tint(
                  due.late || due.soon ? c.amberText : c.label2),
            ),
          ),
          SizedBox(
            width: 72,
            child: Align(alignment: Alignment.centerLeft, child: priority ?? const SizedBox.shrink()),
          ),
          SizedBox(
            width: 96,
            child: Align(alignment: Alignment.centerLeft, child: radStatusPill(c, study.status)),
          ),
          PopupMenuButton<_RowAction>(
            tooltip: 'More',
            icon: CruIcon(CruIcons.more, size: 18, color: c.label2),
            onSelected: (a) => _act(context, ref, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _RowAction.report, child: Text('Open report')),
              if (radIsVolume(study))
                const PopupMenuItem(value: _RowAction.view3d, child: Text('Open in 3D')),
              const PopupMenuItem(value: _RowAction.edit, child: Text('Edit referral')),
              const PopupMenuDivider(),
              for (final (a, p) in const [
                (_RowAction.routine, RadPriority.routine),
                (_RowAction.urgent, RadPriority.urgent),
                (_RowAction.stat, RadPriority.stat),
              ])
                CheckedPopupMenuItem(
                  value: a,
                  checked: study.priority == p,
                  child: Text(p.label),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _RowAction.invoice,
                child: Text(study.invoiced ? 'Invoice again' : 'Create invoice'),
              ),
              const PopupMenuItem(value: _RowAction.delete, child: Text('Delete study')),
            ],
          ),
        ],
      ),
    );
  }
}
