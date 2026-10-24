import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/worklist_screen.dart';

/// Where a task originated.
enum TaskSource { scan, report, plan, lab }

/// The stage a task is in. Decides its label, verb, step number and source.
enum TaskStage {
  toRead('To read', 'Read', TaskSource.scan, 1, 4),
  reading('Reading', 'Continue', TaskSource.scan, 1, 4),
  drafting('Writing report', 'Write', TaskSource.report, 2, 4),
  toSign('To sign', 'Sign', TaskSource.report, 3, 4),
  toSend('Signed · to send', 'Send', TaskSource.report, 4, 4),
  awaitingOk('Waiting for OK', 'Follow up', TaskSource.plan, 1, 2),
  toTreat('To treat', 'Treat', TaskSource.plan, 2, 2),
  delivered('Sent', 'View', TaskSource.report, 4, 4),
  invoiced('Invoiced', 'View', TaskSource.plan, 2, 2),
  declined('Declined', 'View', TaskSource.plan, 1, 2),

  // Lab cases (crowns, bridges, dentures made by a lab).
  labToSend('To send to lab', 'Send', TaskSource.lab, 1, 3),
  atLab('At the lab', 'Track', TaskSource.lab, 2, 3),
  labRemake('Remake', 'Follow up', TaskSource.lab, 2, 3),
  readyToFit('Ready to fit', 'Fit', TaskSource.lab, 3, 3),
  fitted('Fitted', 'View', TaskSource.lab, 3, 3);

  const TaskStage(this.label, this.verb, this.source, this.step, this.steps);

  final String label;
  final String verb;
  final TaskSource source;
  final int step;
  final int steps;

  bool get isFinished =>
      this == delivered ||
      this == invoiced ||
      this == declined ||
      this == fitted;
}

/// A single patient's job on the unified mobile Tasks board.
class TaskItem {
  final String id; // 'scan_<studyId>' / 'plan_<patientId>_<stage.name>'
  final TaskStage stage;
  TaskSource get source => stage.source;
  final String patientName;
  final String? patientId; // null/empty when not matched to a CruDoc patient
  final String title;
  final String? detail;
  final RadPriority? priority; // scans/reports only
  final bool critical; // study.critical
  final DateTime since; // when this stage started
  final DateTime? dueAt;
  final double? amount; // plans: sum of estimatedPrice of its items
  final RadStudy? study; // set for scan/report tasks
  final Patient? patient; // set for plan tasks
  final List<TreatmentPlanLineItemModel> planItems; // empty for radiology
  final LabCase? labCase; // set for lab case tasks
  final String searchText; // lower-cased haystack

  const TaskItem({
    required this.id,
    required this.stage,
    required this.patientName,
    this.patientId,
    required this.title,
    this.detail,
    this.priority,
    this.critical = false,
    required this.since,
    this.dueAt,
    this.amount,
    this.study,
    this.patient,
    this.planItems = const [],
    this.labCase,
    required this.searchText,
  });

  bool isOverdue(DateTime now) => dueAt != null && now.isAfter(dueAt!);
}

/// Source filter pills across the top.
enum TaskSourceFilter {
  all('All'),
  worklist('Worklist'),
  reports('Reports'),
  plans('Treatment plans'),
  labCases('Lab cases');

  const TaskSourceFilter(this.label);
  final String label;
}

/// Time filter options.
enum TaskTimeFilter {
  any('Any time'),
  overdue('Overdue'),
  today('Due today'),
  week('This week'),
  noDeadline('No deadline');

  const TaskTimeFilter(this.label);
  final String label;
}

/// Status filter options.
enum TaskStatusFilter {
  any('Any'),
  open('Open'),
  urgent('Urgent'),
  toRead('To read'),
  reading('Reading'),
  drafting('Drafting'),
  toSign('To sign'),
  toSend('To send'),
  sent('Sent'),
  awaiting('Awaiting'),
  accepted('Accepted'),
  invoiced('Invoiced'),
  declined('Declined'),
  atLab('At the lab'),
  readyToFit('Ready to fit'),
  fitted('Fitted');

  const TaskStatusFilter(this.label);
  final String label;
}

/// Returns the status filter options available for each source pill.
List<TaskStatusFilter> statusFiltersFor(TaskSourceFilter source) =>
    switch (source) {
      TaskSourceFilter.all => const [
        TaskStatusFilter.any,
        TaskStatusFilter.open,
        TaskStatusFilter.urgent,
      ],
      TaskSourceFilter.worklist => const [
        TaskStatusFilter.any,
        TaskStatusFilter.toRead,
        TaskStatusFilter.reading,
        TaskStatusFilter.urgent,
      ],
      TaskSourceFilter.reports => const [
        TaskStatusFilter.any,
        TaskStatusFilter.drafting,
        TaskStatusFilter.toSign,
        TaskStatusFilter.toSend,
        TaskStatusFilter.sent,
      ],
      TaskSourceFilter.plans => const [
        TaskStatusFilter.any,
        TaskStatusFilter.open,
        TaskStatusFilter.awaiting,
        TaskStatusFilter.accepted,
        TaskStatusFilter.invoiced,
        TaskStatusFilter.declined,
      ],
      TaskSourceFilter.labCases => const [
        TaskStatusFilter.any,
        TaskStatusFilter.open,
        TaskStatusFilter.atLab,
        TaskStatusFilter.readyToFit,
        TaskStatusFilter.fitted,
      ],
    };

/// Whether a task matches a source filter.
bool matchesSource(TaskItem t, TaskSourceFilter f) {
  return switch (f) {
    TaskSourceFilter.all => true,
    TaskSourceFilter.worklist =>
      t.stage == TaskStage.toRead || t.stage == TaskStage.reading,
    TaskSourceFilter.reports =>
      t.stage == TaskStage.drafting ||
          t.stage == TaskStage.toSign ||
          t.stage == TaskStage.toSend ||
          t.stage == TaskStage.delivered,
    TaskSourceFilter.plans =>
      t.stage == TaskStage.awaitingOk ||
          t.stage == TaskStage.toTreat ||
          t.stage == TaskStage.invoiced ||
          t.stage == TaskStage.declined,
    TaskSourceFilter.labCases => t.source == TaskSource.lab,
  };
}

/// Whether a task matches a time filter.
bool matchesTime(TaskItem t, TaskTimeFilter f, DateTime now) {
  switch (f) {
    case TaskTimeFilter.any:
      return true;
    case TaskTimeFilter.overdue:
      return t.isOverdue(now);
    case TaskTimeFilter.today:
      if (t.dueAt == null) return false;
      return t.dueAt!.year == now.year &&
          t.dueAt!.month == now.month &&
          t.dueAt!.day == now.day;
    case TaskTimeFilter.week:
      if (t.dueAt == null) return false;
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 7));
      return !t.dueAt!.isBefore(start) && t.dueAt!.isBefore(end);
    case TaskTimeFilter.noDeadline:
      return t.dueAt == null;
  }
}

/// Whether a task matches a status filter.
bool matchesStatus(TaskItem t, TaskStatusFilter f) {
  return switch (f) {
    TaskStatusFilter.any => true,
    TaskStatusFilter.open => !t.stage.isFinished,
    TaskStatusFilter.urgent =>
      t.critical ||
          t.priority == RadPriority.stat ||
          t.priority == RadPriority.urgent,
    TaskStatusFilter.toRead => t.stage == TaskStage.toRead,
    TaskStatusFilter.reading => t.stage == TaskStage.reading,
    TaskStatusFilter.drafting => t.stage == TaskStage.drafting,
    TaskStatusFilter.toSign => t.stage == TaskStage.toSign,
    TaskStatusFilter.toSend => t.stage == TaskStage.toSend,
    TaskStatusFilter.sent => t.stage == TaskStage.delivered,
    TaskStatusFilter.awaiting => t.stage == TaskStage.awaitingOk,
    TaskStatusFilter.accepted => t.stage == TaskStage.toTreat,
    TaskStatusFilter.invoiced => t.stage == TaskStage.invoiced,
    TaskStatusFilter.declined => t.stage == TaskStage.declined,
    TaskStatusFilter.atLab =>
      t.stage == TaskStage.atLab || t.stage == TaskStage.labRemake,
    TaskStatusFilter.readyToFit => t.stage == TaskStage.readyToFit,
    TaskStatusFilter.fitted => t.stage == TaskStage.fitted,
  };
}

/// Whether a task matches a search query (all whitespace-separated terms must match).
bool matchesSearch(TaskItem t, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return true;
  final terms = trimmed.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  return terms.every((term) => t.searchText.contains(term));
}

/// Urgency comparator for sorting tasks (highest urgency first).
int compareUrgency(TaskItem a, TaskItem b, DateTime now) {
  // 1. Critical before non-critical
  if (a.critical != b.critical) {
    return a.critical ? -1 : 1;
  }

  // 2. Overdue before not overdue
  final aOverdue = a.isOverdue(now);
  final bOverdue = b.isOverdue(now);
  if (aOverdue != bOverdue) {
    return aOverdue ? -1 : 1;
  }

  // 3. Priority: stat > urgent > routine > no priority (plans)
  int priorityRank(RadPriority? p) => switch (p) {
    RadPriority.stat => 3,
    RadPriority.urgent => 2,
    RadPriority.routine => 1,
    null => 0,
  };
  final aRank = priorityRank(a.priority);
  final bRank = priorityRank(b.priority);
  if (aRank != bRank) {
    return bRank.compareTo(aRank); // higher rank first
  }

  // 4. Earlier dueAt first; a null dueAt goes last
  if (a.dueAt != null && b.dueAt != null) {
    final c = a.dueAt!.compareTo(b.dueAt!);
    if (c != 0) return c;
  } else if (a.dueAt != null && b.dueAt == null) {
    return -1;
  } else if (a.dueAt == null && b.dueAt != null) {
    return 1;
  }

  // 5. Older since first
  final sinceComp = a.since.compareTo(b.since);
  if (sinceComp != 0) return sinceComp;

  return a.id.compareTo(b.id);
}

/// The state of the unified tasks board.
class TaskBoard {
  final List<TaskItem> items; // open tasks, sorted by urgency
  final List<TaskItem>
  finished; // delivered studies + invoiced/declined plan items
  final int doneToday; // delivered studies + invoiced plan items updated today
  final RadStudy? nextToRead; // radNextUnread(studies), null if none

  const TaskBoard({
    required this.items,
    required this.finished,
    required this.doneToday,
    this.nextToRead,
  });
}

/// Builds the task board from radiology and dental data.
TaskBoard buildTaskBoard({
  required List<RadStudy>? studies,
  required Map<String, RadReferrer> referrers,
  required List<TreatmentPlanLineItemModel>? planItems,
  required Map<String, Patient> patientsById,
  required DateTime now,
  List<LabCase>? labCases,
}) {
  final items = <TaskItem>[];
  final finished = <TaskItem>[];
  var doneToday = 0;

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // 1. Radiology
  if (studies != null) {
    for (final study in studies) {
      // No modality label (IOPA, OPG…): the patient and the question say
      // enough. Empty when neither was recorded.
      final title = study.clinicalQuestion.isNotEmpty
          ? study.clinicalQuestion
          : study.description;
      final referrer = referrers[study.referrerId];
      final detail = (referrer != null && referrer.name.isNotEmpty)
          ? referrer.name
          : null;

      final patient = study.patientId.isNotEmpty
          ? patientsById[study.patientId]
          : null;

      final searchParts = [
        study.patientName,
        title,
        ?detail,
        if (referrer != null) referrer.name,
        if (referrer != null) referrer.clinic,
        study.description,
        study.accession,
        study.modality.label,
      ];
      final searchText = searchParts.join(' ').toLowerCase();

      if (study.status == RadStudyStatus.delivered) {
        if (isSameDay(study.updatedAt, now)) {
          doneToday++;
        }
        finished.add(
          TaskItem(
            id: 'scan_${study.id}',
            stage: TaskStage.delivered,
            patientName: study.patientName,
            patientId: study.patientId.isNotEmpty ? study.patientId : null,
            title: title,
            detail: detail,
            priority: study.priority,
            critical: study.critical,
            since: study.updatedAt,
            dueAt: study.dueAt,
            amount: null,
            study: study,
            patient: patient,
            planItems: const [],
            searchText: searchText,
          ),
        );
        continue;
      }

      final TaskStage? stage = switch (study.status) {
        RadStudyStatus.newStudy => TaskStage.toRead,
        RadStudyStatus.reading => TaskStage.reading,
        RadStudyStatus.draft => TaskStage.drafting,
        RadStudyStatus.preliminary => TaskStage.toSign,
        RadStudyStatus.finalised => TaskStage.toSend,
        RadStudyStatus.delivered => null,
      };

      if (stage == null) continue;

      items.add(
        TaskItem(
          id: 'scan_${study.id}',
          stage: stage,
          patientName: study.patientName,
          patientId: study.patientId.isNotEmpty ? study.patientId : null,
          title: title,
          detail: detail,
          priority: study.priority,
          critical: study.critical,
          since: study.updatedAt,
          dueAt: study.dueAt,
          amount: null,
          study: study,
          patient: patient,
          planItems: const [],
          searchText: searchText,
        ),
      );
    }
  }

  // 2. Dental treatment plans
  if (planItems != null) {
    final proposedByPatient = <Patient, List<TreatmentPlanLineItemModel>>{};
    final acceptedByPatient = <Patient, List<TreatmentPlanLineItemModel>>{};
    final invoicedByPatient = <Patient, List<TreatmentPlanLineItemModel>>{};
    final declinedByPatient = <Patient, List<TreatmentPlanLineItemModel>>{};

    for (final item in planItems) {
      if (item.isDeleted) continue;

      final patient = patientsById[item.patientId];
      if (patient == null) continue;

      final status = TreatmentPlanItemStatus.fromString(item.status);
      switch (status) {
        case TreatmentPlanItemStatus.proposed:
          (proposedByPatient[patient] ??= []).add(item);
        case TreatmentPlanItemStatus.accepted:
          (acceptedByPatient[patient] ??= []).add(item);
        case TreatmentPlanItemStatus.invoiced:
          if (isSameDay(item.updatedAt, now)) {
            doneToday++;
          }
          (invoicedByPatient[patient] ??= []).add(item);
        case TreatmentPlanItemStatus.declined:
          (declinedByPatient[patient] ??= []).add(item);
      }
    }

    // Proposed items -> awaitingOk (open task)
    for (final entry in proposedByPatient.entries) {
      final patient = entry.key;
      final list = entry.value
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      final first = list.first;
      final teeth = first.toothNumbers.isNotEmpty
          ? ' · ${first.toothNumbers.join(', ')}'
          : '';
      final more = list.length > 1 ? ' (+${list.length - 1} more)' : '';
      final title = '${first.procedureName}$teeth$more';

      final total = list.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
      final detail =
          '${DashFormat.plural(list.length, 'procedure')} proposed · ${DashFormat.rupees(total)}';

      final newestUpdated = list
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final since = newestUpdated;
      final dueAt = since.add(const Duration(days: 7));

      final searchParts = [
        patient.fullName,
        title,
        detail,
        for (final item in list) item.procedureName,
        for (final item in list) ...item.toothNumbers,
      ];
      final searchText = searchParts.join(' ').toLowerCase();

      items.add(
        TaskItem(
          id: 'plan_${patient.id}_${TaskStage.awaitingOk.name}',
          stage: TaskStage.awaitingOk,
          patientName: patient.fullName,
          patientId: patient.id,
          title: title,
          detail: detail,
          priority: null,
          critical: false,
          since: since,
          dueAt: dueAt,
          amount: total,
          study: null,
          patient: patient,
          planItems: list,
          searchText: searchText,
        ),
      );
    }

    // Accepted items -> toTreat (open task)
    for (final entry in acceptedByPatient.entries) {
      final patient = entry.key;
      final list = entry.value
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      final first = list.first;
      final teeth = first.toothNumbers.isNotEmpty
          ? ' · ${first.toothNumbers.join(', ')}'
          : '';
      final more = list.length > 1 ? ' (+${list.length - 1} more)' : '';
      final title = '${first.procedureName}$teeth$more';

      final total = list.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
      final detail = '${list.length} to do · ${DashFormat.rupees(total)}';

      final newestUpdated = list
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final since = newestUpdated;
      final dueAt = since.add(const Duration(days: 14));

      final searchParts = [
        patient.fullName,
        title,
        detail,
        for (final item in list) item.procedureName,
        for (final item in list) ...item.toothNumbers,
      ];
      final searchText = searchParts.join(' ').toLowerCase();

      items.add(
        TaskItem(
          id: 'plan_${patient.id}_${TaskStage.toTreat.name}',
          stage: TaskStage.toTreat,
          patientName: patient.fullName,
          patientId: patient.id,
          title: title,
          detail: detail,
          priority: null,
          critical: false,
          since: since,
          dueAt: dueAt,
          amount: total,
          study: null,
          patient: patient,
          planItems: list,
          searchText: searchText,
        ),
      );
    }

    // Invoiced items -> finished
    for (final entry in invoicedByPatient.entries) {
      final patient = entry.key;
      final list = entry.value
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      final first = list.first;
      final teeth = first.toothNumbers.isNotEmpty
          ? ' · ${first.toothNumbers.join(', ')}'
          : '';
      final more = list.length > 1 ? ' (+${list.length - 1} more)' : '';
      final title = '${first.procedureName}$teeth$more';

      final total = list.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
      final detail = '${list.length} invoiced · ${DashFormat.rupees(total)}';

      final newestUpdated = list
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final searchParts = [
        patient.fullName,
        title,
        detail,
        for (final item in list) item.procedureName,
        for (final item in list) ...item.toothNumbers,
      ];
      final searchText = searchParts.join(' ').toLowerCase();

      finished.add(
        TaskItem(
          id: 'plan_${patient.id}_${TaskStage.invoiced.name}',
          stage: TaskStage.invoiced,
          patientName: patient.fullName,
          patientId: patient.id,
          title: title,
          detail: detail,
          priority: null,
          critical: false,
          since: newestUpdated,
          dueAt: null,
          amount: total,
          study: null,
          patient: patient,
          planItems: list,
          searchText: searchText,
        ),
      );
    }

    // Declined items -> finished
    for (final entry in declinedByPatient.entries) {
      final patient = entry.key;
      final list = entry.value
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      final first = list.first;
      final teeth = first.toothNumbers.isNotEmpty
          ? ' · ${first.toothNumbers.join(', ')}'
          : '';
      final more = list.length > 1 ? ' (+${list.length - 1} more)' : '';
      final title = '${first.procedureName}$teeth$more';

      final total = list.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
      final detail = '${list.length} declined · ${DashFormat.rupees(total)}';

      final newestUpdated = list
          .map((i) => i.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      final searchParts = [
        patient.fullName,
        title,
        detail,
        for (final item in list) item.procedureName,
        for (final item in list) ...item.toothNumbers,
      ];
      final searchText = searchParts.join(' ').toLowerCase();

      finished.add(
        TaskItem(
          id: 'plan_${patient.id}_${TaskStage.declined.name}',
          stage: TaskStage.declined,
          patientName: patient.fullName,
          patientId: patient.id,
          title: title,
          detail: detail,
          priority: null,
          critical: false,
          since: newestUpdated,
          dueAt: null,
          amount: total,
          study: null,
          patient: patient,
          planItems: list,
          searchText: searchText,
        ),
      );
    }
  }

  // 3. Lab cases
  for (final lc in labCases ?? const <LabCase>[]) {
    final patient = patientsById[lc.patientId];
    final name = patient?.fullName.trim() ?? '';
    final stage = switch (lc.stage) {
      LabCaseStage.scanned => TaskStage.labToSend,
      LabCaseStage.remake => TaskStage.labRemake,
      LabCaseStage.received => TaskStage.readyToFit,
      LabCaseStage.fitted => TaskStage.fitted,
      _ => TaskStage.atLab,
    };
    final teeth = lc.teeth.where((t) => t.trim().isNotEmpty).join(', ');
    final title = [
      if (lc.type.trim().isNotEmpty) lc.type.trim(),
      if (teeth.isNotEmpty) teeth,
    ].join(' · ');
    final lab = lc.labName.trim();
    final since = lc.history.isEmpty
        ? lc.recordedAt
        : lc.history.map((h) => h.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final item = TaskItem(
      id: 'lab_${lc.id}',
      stage: stage,
      patientName: name.isEmpty ? 'Patient' : name,
      patientId: lc.patientId.isNotEmpty ? lc.patientId : null,
      title: title,
      detail: lab.isEmpty ? null : lab,
      since: since,
      dueAt: stage.isFinished ? null : lc.due,
      patient: patient,
      labCase: lc,
      searchText: [
        name,
        lc.type,
        teeth,
        lab,
        lc.material,
        lc.stage.label,
      ].join(' ').toLowerCase(),
    );
    if (stage.isFinished) {
      if (isSameDay(since, now)) doneToday++;
      finished.add(item);
    } else {
      items.add(item);
    }
  }

  items.sort((a, b) => compareUrgency(a, b, now));
  finished.sort((a, b) => b.since.compareTo(a.since));

  final nextToRead = studies != null ? radNextUnread(studies) : null;

  return TaskBoard(
    items: items,
    finished: finished,
    doneToday: doneToday,
    nextToRead: nextToRead,
  );
}
