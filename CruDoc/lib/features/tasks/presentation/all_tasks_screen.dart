import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/mobile/tasks/tasks_logic.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/todos/data/todo.dart';
import 'package:doctor_management_app/features/todos/data/todo_repository.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_icons.dart';
import 'package:doctor_management_app/features/todos/presentation/todo_widgets.dart';
import 'package:doctor_management_app/features/todos/presentation/todos_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Show { open, urgent, overdue, done }

bool _isUrgent(TaskItem t) => matchesStatus(t, TaskStatusFilter.urgent);

/// Stages that are waiting on someone else, or on the clinic's next move.
bool _isWaiting(TaskStage s) => switch (s) {
  TaskStage.toRead ||
  TaskStage.toSign ||
  TaskStage.awaitingOk ||
  TaskStage.labToSend ||
  TaskStage.labRemake ||
  TaskStage.readyToFit => true,
  _ => false,
};

String _sourceLabel(TaskSource s) => switch (s) {
  TaskSource.scan => 'Scan',
  TaskSource.report => 'Report',
  TaskSource.plan => 'Plan',
  TaskSource.lab => 'Lab',
};

/// "Overdue 3d", "2h ago".
String _timeText(TaskItem t, DateTime now) {
  if (t.isOverdue(now)) {
    final diff = now.difference(t.dueAt!);
    if (diff.inHours < 24) return 'Overdue ${diff.inHours.clamp(1, 23)}h';
    return 'Overdue ${diff.inDays.clamp(1, 9999)}d';
  }
  final diff = now.difference(t.since);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m ago';
  if (diff.inHours < 24) return '${diff.inHours.clamp(1, 23)}h ago';
  if (diff.inDays < 30) return '${diff.inDays.clamp(1, 29)}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

/// Everything the clinic has to do about patients, in one list: scans to
/// read, reports to sign, treatment plans waiting for a yes, lab cases.
/// The desktop twin of the phone's combined Tasks list.
class AllTasksScreen extends ConsumerStatefulWidget {
  const AllTasksScreen({super.key});

  @override
  ConsumerState<AllTasksScreen> createState() => _AllTasksScreenState();
}

class _AllTasksScreenState extends ConsumerState<AllTasksScreen> {
  _Show _show = _Show.open;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Opens a task the way the phone's Tasks list does.
  void _open(TaskItem t) {
    final lc = t.labCase;
    if (lc != null) {
      showDialog<void>(
        context: context,
        builder: (_) => LabCaseEditDialog(initialCase: lc),
      );
      return;
    }
    if (t.stage.isFinished) {
      if (t.study != null) {
        openRadReport(context, t.study!);
      } else if (t.patient != null) {
        showTreatmentPlanDialog(context, patient: t.patient!);
      }
      return;
    }
    switch (t.stage) {
      case TaskStage.toRead:
      case TaskStage.reading:
        if (t.study != null) openRadStudy(context, ref, t.study!);
      case TaskStage.drafting:
      case TaskStage.toSign:
      case TaskStage.toSend:
        if (t.study != null) openRadReport(context, t.study!);
      case TaskStage.awaitingOk:
      case TaskStage.toTreat:
        if (t.patient != null) {
          showTreatmentPlanDialog(context, patient: t.patient!).then((_) {
            ref.invalidate(clinicTreatmentPlansProvider);
          });
        }
      case TaskStage.delivered:
      case TaskStage.invoiced:
      case TaskStage.declined:
      case TaskStage.labToSend:
      case TaskStage.atLab:
      case TaskStage.labRemake:
      case TaskStage.readyToFit:
      case TaskStage.fitted:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final now = DateTime.now();

    final tabs = {
      for (final t in sidebarTabs(
        dental: ref.watch(dentalFeaturesProvider),
        access: ref.watch(clinicAccessProvider).value,
      ))
        t.tab,
    };
    final radiologyOn =
        tabs.contains(DesktopTab.worklist) || tabs.contains(DesktopTab.reports);
    final plansOn = tabs.contains(DesktopTab.treatmentPlans);
    final labOn = tabs.contains(DesktopTab.labCases);

    final studiesAsync = radiologyOn ? ref.watch(radStudiesProvider) : null;
    final referrers = radiologyOn
        ? ref.watch(radReferrerByIdProvider)
        : const <String, RadReferrer>{};
    final planItemsAsync = plansOn
        ? ref.watch(clinicTreatmentPlansProvider)
        : null;
    final labCases = labOn ? ref.watch(allLabCasesProvider) : null;
    final patientsAsync = (radiologyOn || plansOn || labOn)
        ? ref.watch(patientsStreamProvider)
        : null;

    final loading =
        (radiologyOn && studiesAsync?.value == null) ||
        (plansOn &&
            (planItemsAsync?.value == null || patientsAsync?.value == null));

    final patients = patientsAsync?.value ?? const <Patient>[];
    final board = buildTaskBoard(
      studies: studiesAsync?.value,
      referrers: referrers,
      planItems: planItemsAsync?.value,
      patientsById: {for (final p in patients) p.id: p},
      now: now,
      labCases: labCases,
    );

    final urgent = board.items.where(_isUrgent).toList();
    final overdue = board.items.where((t) => t.isOverdue(now)).toList();

    // Already in urgency order (open) and newest first (done).
    final candidates = switch (_show) {
      _Show.open => board.items,
      _Show.urgent => urgent,
      _Show.overdue => overdue,
      _Show.done => board.finished,
    };
    final shown = [
      for (final t in candidates)
        if (matchesSearch(t, _query)) t,
    ];

    // To-dos made by or given to me, shown under Open and Overdue only.
    final uid = ref.watch(clinicAccessProvider).value?.uid ?? '';
    final myTodos = ref.watch(myTodosProvider).value ?? const <Todo>[];
    final involving = groupTodos(
      myTodos
          .where((t) => !t.done && (t.assignedTo == uid || t.createdBy == uid))
          .toList(),
      uid,
      now,
    );
    final q = _query.trim().toLowerCase();
    final todos = (_show == _Show.open || _show == _Show.overdue)
        ? [
            for (final l in involving.values)
              for (final t in l)
                if ((_show == _Show.open || t.overdue(now)) &&
                    (q.isEmpty ||
                        t.title.toLowerCase().contains(q) ||
                        t.note.toLowerCase().contains(q)))
                  t,
          ]
        : const <Todo>[];
    final openTodoCount = involving.values.fold<int>(0, (n, l) => n + l.length);

    Widget cell(String label, int value, String caption, {Color? tone}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GlanceLabel(label),
            GlanceMetric('$value'),
            GlanceCaption(
              Text(
                caption,
                style: tone == null ? null : CruType.caption.tint(tone),
              ),
            ),
          ],
        );

    final subtitle = loading
        ? ''
        : board.items.isEmpty && openTodoCount == 0
        ? 'Nothing waiting'
        : [
            DashFormat.plural(board.items.length, 'open task'),
            if (urgent.isNotEmpty) '${urgent.length} urgent',
            if (openTodoCount > 0) DashFormat.plural(openTodoCount, 'to-do'),
          ].join(' · ');

    return Padding(
      padding: cruIsPhone(context)
          ? CruSpace.mainPaddingPhone
          : CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(title: 'All tasks', subtitle: subtitle),
          const SizedBox(height: CruSpace.cardGap),
          if (loading)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Tasks at a glance',
              cells: [
                cell(
                  'Open',
                  board.items.length,
                  board.items.isEmpty ? 'Nothing waiting' : 'to do',
                ),
                cell(
                  'Urgent',
                  urgent.length,
                  urgent.isEmpty ? 'None urgent' : 'STAT or urgent',
                ),
                cell(
                  'Overdue',
                  overdue.length,
                  overdue.isEmpty ? 'Nothing late' : 'past their date',
                  tone: overdue.isEmpty ? null : c.amberText,
                ),
                cell(
                  'Done today',
                  board.doneToday,
                  board.doneToday == 0 ? 'Nothing yet' : 'finished today',
                  tone: board.doneToday == 0 ? null : c.greenText,
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final filter = CruSegmentedControl<_Show>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_Show.open, 'Open'),
                  CruSegment(_Show.urgent, 'Urgent'),
                  CruSegment(_Show.overdue, 'Overdue'),
                  CruSegment(_Show.done, 'Done'),
                ],
                selected: _show,
                onChanged: (s) => setState(() => _show = s),
              );
              final field = DentalSearchField(
                controller: _search,
                hint: 'Search patient or task',
                onChanged: (v) => setState(() => _query = v),
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: filter,
                    ),
                    const SizedBox(height: CruSpace.s10),
                    field,
                  ],
                );
              }
              // The search fills the row after the filter, as on every list.
              return Row(
                children: [
                  filter,
                  const SizedBox(width: CruSpace.s12),
                  Expanded(child: field),
                ],
              );
            },
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Tasks',
              padding: const EdgeInsets.all(CruSpace.s12),
              child: loading
                  ? const SizedBox.shrink()
                  : shown.isEmpty && todos.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child:
                            board.items.isEmpty &&
                                openTodoCount == 0 &&
                                _query.trim().isEmpty &&
                                _show != _Show.done
                            ? const DentalEmptyState(
                                icon: TodoIcons.check,
                                title: 'All caught up',
                                body:
                                    'Scans to read, reports to sign, plans '
                                    'waiting for a yes and lab cases show up '
                                    'here.',
                              )
                            : const DentalEmptyState(
                                icon: TodoIcons.check,
                                title: 'No matches',
                                body: 'Try another filter or search.',
                              ),
                      ),
                    )
                  : ListView(
                      children: [
                        if (todos.isNotEmpty) ...[
                          DentalGroupLabel(
                            'To-do',
                            trailing: '${todos.length}',
                          ),
                          for (var i = 0; i < todos.length && i < 5; i++) ...[
                            if (i > 0) const CruSeparator(indent: 12 + 24 + 12),
                            TodoRow(todo: todos[i], uid: uid, now: now),
                          ],
                          if (todos.length > 5)
                            Align(
                              alignment: Alignment.centerRight,
                              child: CruCapsuleButton(
                                label: 'See all',
                                onPressed: () => ref
                                    .read(shellNavigatorProvider)
                                    ?.call(DesktopTab.todos),
                              ),
                            ),
                          if (shown.isNotEmpty)
                            const SizedBox(height: CruSpace.s8),
                        ],
                        if (todos.isNotEmpty && shown.isNotEmpty)
                          const DentalGroupLabel('Tasks'),
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const CruSeparator(indent: 12 + 40 + 12),
                          _TaskRow(
                            task: shown[i],
                            now: now,
                            onOpen: () => _open(shown[i]),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.now, required this.onOpen});

  final TaskItem task;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = task;
    final urgency = t.critical
        ? null
        : switch (t.priority) {
            RadPriority.stat => 'STAT',
            RadPriority.urgent => 'Urgent',
            _ => null,
          };
    final subtitle = [
      ?urgency,
      if (t.title.isNotEmpty) t.title,
      if (t.detail != null && t.detail!.isNotEmpty) t.detail!,
      _timeText(t, now),
    ].join(' · ');

    final CruPill pill;
    if (t.critical) {
      pill = CruPill(
        text: 'Critical',
        background: c.redTint,
        foreground: c.redText,
      );
    } else if (t.stage.isFinished) {
      pill = t.stage == TaskStage.declined
          ? CruPill(
              text: t.stage.label,
              background: c.inset,
              foreground: c.label3,
            )
          : CruPill(
              text: t.stage.label,
              background: c.greenTint,
              foreground: c.greenText,
            );
    } else if (_isWaiting(t.stage)) {
      pill = CruPill(
        text: t.stage.label,
        background: c.amberTint,
        foreground: c.amberText,
      );
    } else {
      pill = CruPill(
        text: t.stage.label,
        background: c.inset,
        foreground: c.label3,
      );
    }

    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.patientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.callout.w600.tint(c.label),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.subhead.tabular.tint(c.label2),
          ),
        ],
      ),
    );
    final semantic = '${t.patientName}, ${t.stage.label}';

    if (cruIsPhone(context)) {
      return DentalListRow(
        semanticLabel: semantic,
        minHeight: 64,
        onTap: onOpen,
        child: Row(
          children: [
            CruMonogram(name: t.patientName, size: 40),
            const SizedBox(width: CruSpace.s12),
            info,
            const SizedBox(width: CruSpace.s10),
            pill,
          ],
        ),
      );
    }
    return DentalListRow(
      semanticLabel: semantic,
      minHeight: 64,
      onTap: onOpen,
      child: Row(
        children: [
          CruMonogram(name: t.patientName, size: 40),
          const SizedBox(width: CruSpace.s12),
          info,
          const SizedBox(width: CruSpace.s16),
          SizedBox(
            width: 56,
            child: Text(
              _sourceLabel(t.source),
              style: CruType.subhead.tint(c.label3),
            ),
          ),
          SizedBox(
            width: 140,
            child: Align(alignment: Alignment.centerLeft, child: pill),
          ),
          SizedBox(
            width: 120,
            child: t.patient == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: CruCapsuleButton(
                      label: 'Open patient',
                      onPressed: () =>
                          DashboardActions.openPatient(context, t.patient!),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
