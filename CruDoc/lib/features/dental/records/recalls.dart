import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _defaultMessage =
    'Hello {name}, this is a reminder from {clinic} that your {reason} is due on {date}. '
    'Reply to confirm, or call us to pick another time.';

/// Recall rules a new clinic starts with (all editable).
const _defaultRules = <(String, int, List<String>)>[
  (
    'Check-up and cleaning',
    6,
    [
      'scaling',
      'cleaning',
      'prophylaxis',
      'polish',
      'check',
      'exam',
      'consult',
    ],
  ),
  (
    'Perio maintenance',
    3,
    ['root planing', 'srp', 'curettage', 'flap', 'perio', 'gingivectomy'],
  ),
  ('Ortho adjustment', 1, ['ortho', 'bracket', 'wire', 'aligner', 'adjust']),
  (
    'Fluoride and sealant review',
    6,
    ['fluoride', 'sealant', 'pit and fissure'],
  ),
  ('Root canal review', 6, ['root canal', 'rct', 'endodont', 'pulpectomy']),
  ('Implant review', 12, ['implant']),
];

enum RecallStatus {
  pending('To send'),
  sent('Sent'),
  confirmed('Confirmed'),
  rescheduled('Rescheduled'),
  noResponse('No response'),
  done('Booked'),
  cancelled('Cancelled');

  const RecallStatus(this.label);
  final String label;

  bool get isOpen => this != done && this != cancelled;

  static RecallStatus fromName(String n) =>
      values.firstWhere((s) => s.name == n, orElse: () => pending);
}

RecallStatus recallStatusOf(DentalRecord r) =>
    RecallStatus.fromName(r.str('status'));

/// A recall rule: which treatments it follows and after how long.
class RecallRule {
  RecallRule(this.record);
  final DentalRecord record;

  String get name => record.str('name');
  int get months => record.integer('months') ?? 6;
  List<String> get keywords => record.data['keywords'] is List
      ? [for (final k in record.data['keywords'] as List) '$k']
      : [];
  String get message =>
      record.str('message').isEmpty ? _defaultMessage : record.str('message');

  bool matches(String procedure) {
    final p = procedure.toLowerCase();
    return keywords.any(
      (k) => k.trim().isNotEmpty && p.contains(k.trim().toLowerCase()),
    );
  }
}

DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, d.day);

/// The clinic's recall rules, created from the defaults the first time.
final recallRulesProvider = FutureProvider<List<RecallRule>>((ref) async {
  final repo = ref.watch(dentalRecordsRepoProvider);
  final doctorId = ref.watch(dentalDoctorIdProvider);
  var rules = await repo.all(doctorId, RecKind.recallRule);
  final seeded = (await repo.all(
    doctorId,
    RecKind.meta,
  )).any((r) => r.str('what') == 'recallRules');
  if (rules.isEmpty && !seeded) {
    for (final (name, months, keywords) in _defaultRules) {
      await repo.save(
        doctorId,
        DentalRecord.create('', RecKind.recallRule, {
          'name': name,
          'months': months,
          'keywords': keywords,
          'message': _defaultMessage,
        }),
      );
    }
    await repo.save(
      doctorId,
      DentalRecord.create('', RecKind.meta, {'what': 'recallRules'}),
    );
    rules = await repo.all(doctorId, RecKind.recallRule);
  }
  return [for (final r in rules) RecallRule(r)]
    ..sort((a, b) => a.months.compareTo(b.months));
});

/// Recalls worth adding: completed treatments whose rule makes them due
/// within 30 days (or overdue) and that have no open recall for that rule.
final recallSuggestionsProvider =
    FutureProvider<
      List<
        ({String patientId, RecallRule rule, DateTime due, String procedure})
      >
    >((ref) async {
      final rules = await ref.watch(recallRulesProvider.future);
      final recalls = await ref.watch(
        clinicRecordsProvider(RecKind.recall).future,
      );
      final doctorId = ref.watch(dentalDoctorIdProvider);
      final now = DateTime.now();
      final procedures = await ref
          .watch(dentalRecordsRepoProvider)
          .completedProcedures(
            doctorId,
            now.subtract(const Duration(days: 730)),
          );
      final latest =
          <
            String,
            ({
              String patientId,
              RecallRule rule,
              DateTime due,
              String procedure,
            })
          >{};
      for (final p in procedures) {
        for (final rule in rules) {
          if (!rule.matches(p.name)) continue;
          final key = '${p.patientId}|${rule.record.id}';
          if (latest.containsKey(key)) continue; // newest first
          latest[key] = (
            patientId: p.patientId,
            rule: rule,
            due: _addMonths(p.at, rule.months),
            procedure: p.name,
          );
        }
      }
      return latest.values.where((s) {
        if (s.due.isAfter(now.add(const Duration(days: 30)))) return false;
        return !recalls.any(
          (r) =>
              r.patientId == s.patientId &&
              r.str('ruleId') == s.rule.record.id &&
              (recallStatusOf(r).isOpen ||
                  !r.recordedAt.isBefore(
                    s.due.subtract(const Duration(days: 45)),
                  )),
        );
      }).toList()..sort((a, b) => a.due.compareTo(b.due));
    });

String _fill(
  String template, {
  required String name,
  required String clinic,
  required String reason,
  required DateTime date,
}) => template
    .replaceAll('{name}', name.split(' ').first)
    .replaceAll('{clinic}', clinic)
    .replaceAll('{reason}', reason.toLowerCase())
    .replaceAll('{date}', DentalFormat.date(date));

/// Add or change a patient's recall. Returns true when saved.
Future<bool> showSetRecallDialog(
  BuildContext context, {
  Patient? patient,
  DentalRecord? existing,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _SetRecallDialog(patient: patient, existing: existing),
    ) ==
    true;

class _SetRecallDialog extends ConsumerStatefulWidget {
  const _SetRecallDialog({this.patient, this.existing});

  final Patient? patient;
  final DentalRecord? existing;

  @override
  ConsumerState<_SetRecallDialog> createState() => _SetRecallDialogState();
}

class _SetRecallDialogState extends ConsumerState<_SetRecallDialog> {
  Patient? _patient;
  RecallRule? _rule;
  late DateTime _due;
  late final _reason = TextEditingController(
    text: widget.existing?.str('reason') ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.existing?.str('notes') ?? '',
  );

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _due = widget.existing?.recordedAt ?? _addMonths(DateTime.now(), 6);
    if (_patient == null && widget.existing != null) {
      final all = ref.read(patientsStreamProvider).value ?? const <Patient>[];
      for (final p in all) {
        if (p.id == widget.existing!.patientId) _patient = p;
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _patient;
    if (p == null || _reason.text.trim().isEmpty) {
      recToast(context, 'Pick a patient and a reason.');
      return;
    }
    final e = widget.existing;
    final data = {
      ...?e?.data,
      'patientName': p.fullName,
      'reason': _reason.text.trim(),
      'ruleId': _rule?.record.id ?? e?.str('ruleId') ?? '',
      'notes': _notes.text.trim(),
      'status': e?.str('status').isNotEmpty == true
          ? e!.str('status')
          : RecallStatus.pending.name,
    };
    await saveDentalRecord(
      ref,
      e == null
          ? DentalRecord.create(p.id, RecKind.recall, data, at: _due)
          : e.copyWith(data: data, recordedAt: _due),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(recallRulesProvider).value ?? const <RecallRule>[];
    return CruFormDialog(
      title: widget.existing == null ? 'Set recall' : 'Edit recall',
      subtitle: _patient?.fullName ?? 'Remind a patient to come back',
      leading: const CruIconTile(
        icon: RecIcons.recall,
        tone: CruTileTone.accent,
      ),
      submitLabel: 'Save recall',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Recall',
            description:
                'A rule sets the date from today; change it if you like.',
            children: [
              if (widget.patient == null)
                CruPickerField(
                  label: 'Patient',
                  icon: CruIcons.user,
                  value: _patient?.fullName,
                  placeholder: 'Pick a patient',
                  onTap: () async {
                    final p = await pickRadPatient(
                      context,
                      title: 'Pick a patient',
                      subtitle: 'Who should come back',
                    );
                    if (p != null) setState(() => _patient = p);
                  },
                ),
              CruFieldFrame(
                label: 'Reason',
                child: DentalChipWrap<RecallRule>(
                  options: rules,
                  label: (r) => '${r.name} · ${r.months} mo',
                  isSelected: (r) => r.record.id == _rule?.record.id,
                  onTap: (r) => setState(() {
                    _rule = r;
                    _reason.text = r.name;
                    _due = _addMonths(DateTime.now(), r.months);
                  }),
                ),
              ),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Reason text',
                    controller: _reason,
                    hint: 'Check-up and cleaning',
                  ),
                  CruPickerField(
                    label: 'Due',
                    icon: CruIcons.calendar,
                    value: DentalFormat.date(_due),
                    placeholder: 'Pick a date',
                    onTap: () async {
                      final d = await pickDentalDate(
                        context,
                        initial: _due,
                        last: DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                  ),
                ],
              ),
              CruTextField(label: 'Notes', optional: true, controller: _notes),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit the recall rules: name, interval, the treatments that trigger it
/// and the message sent.
Future<void> showRecallRulesDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _RulesDialog());

class _RulesDialog extends ConsumerWidget {
  const _RulesDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final rules = ref.watch(recallRulesProvider).value ?? const <RecallRule>[];
    return DentalPanelDialog(
      title: 'Recall rules',
      subtitle: 'Completed treatments matching a rule suggest a recall',
      leading: const CruIconTile(
        icon: RecIcons.recall,
        tone: CruTileTone.neutral,
      ),
      width: CruSize.formDialog,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rules)
            DentalListRow(
              semanticLabel: r.name,
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _RuleEditor(rule: r),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${r.months} mo',
                      style: CruType.subhead.w600.tabular.tint(c.label),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: CruType.callout.tint(c.label)),
                        Text(
                          'After: ${r.keywords.join(', ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
                ],
              ),
            ),
        ],
      ),
      footer: Row(
        children: [
          CruButton(
            label: 'Add rule',
            icon: CruIcons.plus,
            kind: CruButtonKind.secondary,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _RuleEditor(),
            ),
          ),
          const Spacer(),
          CruButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _RuleEditor extends ConsumerStatefulWidget {
  const _RuleEditor({this.rule});

  final RecallRule? rule;

  @override
  ConsumerState<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<_RuleEditor> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _months = TextEditingController(
    text: '${widget.rule?.months ?? 6}',
  );
  late final _keywords = TextEditingController(
    text: widget.rule?.keywords.join(', ') ?? '',
  );
  late final _message = TextEditingController(
    text: widget.rule?.message ?? _defaultMessage,
  );

  @override
  void dispose() {
    for (final c in [_name, _months, _keywords, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final data = {
      'name': _name.text.trim(),
      'months': (int.tryParse(_months.text.trim()) ?? 6).clamp(1, 60),
      'keywords': [
        for (final k in _keywords.text.split(','))
          if (k.trim().isNotEmpty) k.trim().toLowerCase(),
      ],
      'message': _message.text.trim().isEmpty
          ? _defaultMessage
          : _message.text.trim(),
    };
    final r = widget.rule?.record;
    await saveDentalRecord(
      ref,
      r == null
          ? DentalRecord.create('', RecKind.recallRule, data)
          : r.copyWith(data: data),
    );
    ref.invalidate(recallRulesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final r = widget.rule?.record;
    if (r == null) return;
    await deleteDentalRecord(ref, r);
    ref.invalidate(recallRulesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.rule == null ? 'New recall rule' : 'Edit recall rule',
      leading: const CruIconTile(
        icon: RecIcons.recall,
        tone: CruTileTone.accent,
      ),
      submitLabel: 'Save rule',
      onSubmit: _save,
      body: CruFormSection(
        first: true,
        title: 'Rule',
        description:
            'Use {name}, {clinic}, {reason} and {date} in the message.',
        children: [
          CruFieldRow(
            children: [
              CruTextField(
                label: 'Name',
                controller: _name,
                hint: 'Check-up and cleaning',
              ),
              CruTextField(
                label: 'Every',
                controller: _months,
                tabular: true,
                trailing: Text(
                  'months',
                  style: CruType.subhead.tint(context.cru.label3),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          CruTextField(
            label: 'After treatments containing',
            controller: _keywords,
            hint: 'scaling, cleaning, prophylaxis',
            help: 'Words separated by commas, matched in procedure names.',
          ),
          CruTextField(label: 'Message', controller: _message, maxLines: 3),
          if (widget.rule != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CruLink(label: 'Delete this rule', onPressed: _delete),
            ),
        ],
      ),
    );
  }
}

// ================================================================ screen

enum _Show { due, confirmed, closed }

/// Recalls: who should come back, reminders by WhatsApp or SMS, and what
/// each patient replied.
class RecallsScreen extends ConsumerStatefulWidget {
  const RecallsScreen({super.key});

  @override
  ConsumerState<RecallsScreen> createState() => _RecallsScreenState();
}

class _RecallsScreenState extends ConsumerState<RecallsScreen> {
  _Show _show = _Show.due;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addSuggestions(
    List<({String patientId, RecallRule rule, DateTime due, String procedure})>
    list,
    Map<String, Patient> patients,
  ) async {
    for (final s in list) {
      await saveDentalRecord(
        ref,
        DentalRecord.create(s.patientId, RecKind.recall, {
          'patientName': patients[s.patientId]?.fullName ?? '',
          'reason': s.rule.name,
          'ruleId': s.rule.record.id,
          'procedure': s.procedure,
          'status': RecallStatus.pending.name,
          'source': 'procedure',
        }, at: s.due),
      );
    }
    ref.invalidate(recallSuggestionsProvider);
    if (mounted) {
      recToast(
        context,
        list.length == 1 ? 'Recall added' : '${list.length} recalls added',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recalls = ref.watch(clinicRecordsProvider(RecKind.recall)).value;
    final suggestions = ref.watch(recallSuggestionsProvider).value ?? const [];
    final patients = {
      for (final p
          in ref.watch(patientsStreamProvider).value ?? const <Patient>[])
        p.id: p,
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final open =
        recalls?.where((r) => recallStatusOf(r).isOpen).toList() ??
        const <DentalRecord>[];
    final overdue = open.where((r) => r.recordedAt.isBefore(today)).length;
    final week = open
        .where(
          (r) =>
              !r.recordedAt.isBefore(today) &&
              r.recordedAt.isBefore(today.add(const Duration(days: 7))),
        )
        .length;
    final waiting = open
        .where((r) => recallStatusOf(r) == RecallStatus.sent)
        .length;
    final confirmed = open
        .where((r) => recallStatusOf(r) == RecallStatus.confirmed)
        .length;

    final q = _query.trim().toLowerCase();
    final shown =
        (recalls ?? const <DentalRecord>[])
            .where(
              (r) => switch (_show) {
                _Show.due =>
                  recallStatusOf(r).isOpen &&
                      recallStatusOf(r) != RecallStatus.confirmed,
                _Show.confirmed => recallStatusOf(r) == RecallStatus.confirmed,
                _Show.closed => !recallStatusOf(r).isOpen,
              },
            )
            .where(
              (r) =>
                  q.isEmpty ||
                  (patients[r.patientId]?.fullName ?? r.str('patientName'))
                      .toLowerCase()
                      .contains(q) ||
                  r.str('reason').toLowerCase().contains(q),
            )
            .toList()
          ..sort(
            (a, b) => _show == _Show.closed
                ? b.updatedAt.compareTo(a.updatedAt)
                : a.recordedAt.compareTo(b.recordedAt),
          );

    Widget cell(String label, String value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Recalls',
            subtitle: recalls == null || recalls.isEmpty
                ? 'Bring patients back for check-ups and reviews'
                : '$overdue overdue · $week due this week',
            actions: [
              CruButton(
                label: 'Rules',
                icon: CruIcons.settings,
                kind: CruButtonKind.secondary,
                onPressed: () => showRecallRulesDialog(context),
              ),
              CruButton(
                label: 'Set recall',
                icon: CruIcons.plus,
                onPressed: () => showSetRecallDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (recalls == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Recalls at a glance',
              cells: [
                cell(
                  'Overdue',
                  '$overdue',
                  overdue == 0
                      ? const Text('None')
                      : Text(
                          'Past their due date',
                          style: CruType.caption.tint(c.amberText),
                        ),
                ),
                cell('Due this week', '$week', const Text('Next 7 days')),
                cell(
                  'Waiting for a reply',
                  '$waiting',
                  const Text('Reminder sent'),
                ),
                cell('Confirmed', '$confirmed', const Text('Book them in')),
              ],
            ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: CruSpace.cardGap),
            CruCard(
              semanticLabel: 'Suggested recalls',
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const CruIconTile(
                    icon: RecIcons.recall,
                    tone: CruTileTone.amber,
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DashFormat.plural(suggestions.length, 'patient')} due from past treatment',
                          style: CruType.callout.w600.tint(c.label),
                        ),
                        Text(
                          suggestions
                              .take(3)
                              .map(
                                (s) =>
                                    '${patients[s.patientId]?.fullName ?? 'Patient'} · ${s.rule.name} ${DentalFormat.shortDate(s.due)}',
                              )
                              .join('   '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.subhead.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  CruButton(
                    label: suggestions.length == 1 ? 'Add recall' : 'Add all',
                    kind: CruButtonKind.tinted,
                    onPressed: () => _addSuggestions(suggestions, patients),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              CruSegmentedControl<_Show>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_Show.due, 'Due'),
                  CruSegment(_Show.confirmed, 'Confirmed'),
                  CruSegment(_Show.closed, 'Booked or cancelled'),
                ],
                selected: _show,
                onChanged: (s) => setState(() => _show = s),
              ),
              const Spacer(),
              SizedBox(
                width: 280,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search patient or reason',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Recalls',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: recalls == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: DentalEmptyState(
                          icon: RecIcons.recall,
                          title: recalls.isEmpty
                              ? 'No recalls yet'
                              : 'Nothing here',
                          body: recalls.isEmpty
                              ? 'Set a recall from a patient\'s record or here. Completed '
                                    'treatments that match a rule show up above as suggestions.'
                              : 'Try another filter or search.',
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        const SizedBox(height: CruSpace.s8),
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const CruSeparator(indent: 12 + 76 + 12),
                          _RecallRow(
                            recall: shown[i],
                            patient: patients[shown[i].patientId],
                            today: today,
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

class _RecallRow extends ConsumerWidget {
  const _RecallRow({
    required this.recall,
    required this.patient,
    required this.today,
  });

  final DentalRecord recall;
  final Patient? patient;
  final DateTime today;

  String _message(WidgetRef ref) {
    final rules = ref.read(recallRulesProvider).value ?? const <RecallRule>[];
    final rule = rules
        .where((r) => r.record.id == recall.str('ruleId'))
        .firstOrNull;
    return _fill(
      rule?.message ?? _defaultMessage,
      name: patient?.fullName ?? recall.str('patientName'),
      clinic: ref.read(doctorIdentityProvider).clinicName ?? 'our clinic',
      reason: recall.str('reason'),
      date: recall.recordedAt,
    );
  }

  Future<void> _mark(
    WidgetRef ref,
    RecallStatus s, {
    String? channel,
    DateTime? due,
  }) => saveDentalRecord(
    ref,
    recall.copyWith(
      recordedAt: due,
      data: {
        ...recall.data,
        'status': s.name,
        'channel': ?channel,
        if (channel != null)
          'lastSentAt': DateTime.now().millisecondsSinceEpoch,
      },
    ),
  );

  Future<void> _whatsApp(BuildContext context, WidgetRef ref) async {
    final p = patient;
    if (p == null) return;
    await PatientActions.whatsApp(context, p, message: _message(ref));
    await _mark(ref, RecallStatus.sent, channel: 'WhatsApp');
  }

  Future<void> _sms(BuildContext context, WidgetRef ref) async {
    final phone = (patient?.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) {
      recToast(context, 'No phone number on record.');
      return;
    }
    final ok = await launchUrl(
      Uri(scheme: 'sms', path: phone, queryParameters: {'body': _message(ref)}),
    );
    if (!ok) {
      if (context.mounted) {
        recToast(context, 'No SMS app on this computer. Use WhatsApp instead.');
      }
      return;
    }
    await _mark(ref, RecallStatus.sent, channel: 'SMS');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final status = recallStatusOf(recall);
    final late = status.isOpen && recall.recordedAt.isBefore(today);
    final sent = recall.date('lastSentAt');
    return DentalListRow(
      semanticLabel:
          '${patient?.fullName ?? recall.str('patientName')}, ${recall.str('reason')}',
      onTap: () =>
          showSetRecallDialog(context, patient: patient, existing: recall),
      minHeight: 60,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              DentalFormat.shortDate(recall.recordedAt),
              style: CruType.subhead.w600.tabular.tint(
                late ? c.amberText : c.label,
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient?.fullName ?? recall.str('patientName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  [
                    recall.str('reason'),
                    if (sent != null)
                      '${recall.str('channel')} ${DentalFormat.day(sent, DateTime.now()).toLowerCase()}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          CruPill(
            text: status.label,
            background: switch (status) {
              RecallStatus.confirmed || RecallStatus.done => c.greenTint,
              RecallStatus.sent || RecallStatus.rescheduled => c.amberTint,
              _ => c.inset,
            },
            foreground: switch (status) {
              RecallStatus.confirmed || RecallStatus.done => c.greenText,
              RecallStatus.sent || RecallStatus.rescheduled => c.amberText,
              _ => c.label2,
            },
          ),
          const SizedBox(width: CruSpace.s10),
          if (status.isOpen && patient != null) ...[
            CruCapsuleButton(
              label: 'WhatsApp',
              icon: CruIcons.whatsapp,
              onPressed: () => _whatsApp(context, ref),
            ),
            const SizedBox(width: CruSpace.s6),
            CruCapsuleButton(label: 'SMS', onPressed: () => _sms(context, ref)),
          ],
          PopupMenuButton<String>(
            tooltip: 'Reply and booking',
            icon: CruIcon(CruIcons.more, size: 18, color: c.label2),
            onSelected: (v) async {
              switch (v) {
                case 'confirmed':
                  await _mark(ref, RecallStatus.confirmed);
                case 'noResponse':
                  await _mark(ref, RecallStatus.noResponse);
                case 'rescheduled':
                  final d = await pickDentalDate(
                    context,
                    initial: recall.recordedAt.isBefore(today)
                        ? today
                        : recall.recordedAt,
                    last: DateTime.now().add(const Duration(days: 365 * 2)),
                    helpText: 'New recall date',
                  );
                  if (d != null) {
                    await _mark(ref, RecallStatus.rescheduled, due: d);
                  }
                case 'book':
                  final p = patient;
                  if (p == null) return;
                  await PatientActions.newVisit(context, ref, p);
                  await _mark(ref, RecallStatus.done);
                case 'cancel':
                  await _mark(ref, RecallStatus.cancelled);
                case 'delete':
                  await deleteDentalRecord(ref, recall);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'confirmed',
                child: Text('Replied: confirmed'),
              ),
              const PopupMenuItem(
                value: 'rescheduled',
                child: Text('Replied: another date…'),
              ),
              const PopupMenuItem(
                value: 'noResponse',
                child: Text('No response'),
              ),
              const PopupMenuDivider(),
              if (patient != null)
                const PopupMenuItem(value: 'book', child: Text('Book visit')),
              const PopupMenuItem(
                value: 'cancel',
                child: Text('Cancel recall'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
