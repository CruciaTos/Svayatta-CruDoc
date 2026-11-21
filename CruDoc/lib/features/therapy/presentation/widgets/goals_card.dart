import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the patient is working towards, and whether they got there.
///
/// Goals are written in the patient's own words, so the card shows the text
/// as typed and never summarises it. A goal whose date has gone by is the
/// only thing on this card that asks for anything: it goes amber and the
/// card's action becomes Review, because the point of putting a date on a
/// goal is that somebody is asked about it when the date arrives. Amber and
/// not red — a goal running late changes the plan, it is not a safety matter.

/// Patient Details card: the goals, still-open ones first.
class GoalsCard extends ConsumerWidget {
  const GoalsCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((patientId: patient.id, kind: RecKind.physioGoal)),
    );
    final goals = physioGoals(recs.value ?? const <DentalRecord>[]);
    final now = DateTime.now();
    final overdue = goalsDueForReview(goals, now);
    final open = [
      for (final g in goals)
        if (g.isOpen) g,
    ];
    final reached = [
      for (final g in goals)
        if (g.status == GoalStatus.reached) g,
    ];

    final String subtitle;
    if (goals.isEmpty) {
      subtitle = 'What the patient is working towards';
    } else if (overdue.isNotEmpty) {
      final rest = open.length - overdue.length;
      subtitle =
          '${overdue.length} past ${overdue.length == 1 ? 'its' : 'their'} '
          'date${rest > 0 ? ' · $rest still open' : ''}';
    } else {
      subtitle = [
        '${open.length} open',
        if (reached.isNotEmpty) '${reached.length} reached',
      ].join(' · ');
    }

    return CruCard(
      semanticLabel: 'Goals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIconTile(
                icon: CruIcons.check,
                tone: overdue.isNotEmpty
                    ? CruTileTone.amber
                    : (goals.isNotEmpty && open.isEmpty && reached.isNotEmpty
                          ? CruTileTone.green
                          : CruTileTone.neutral),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Goals', style: CruType.headline.w600.tint(c.label)),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      subtitle,
                      style: CruType.caption.tabular.tint(
                        overdue.isNotEmpty ? c.amberText : c.label2,
                      ),
                    ),
                  ],
                ),
              ),
              // One action. Reviewing what has run late comes before adding
              // more, so that is what the button opens.
              CruCapsuleButton(
                label: overdue.isNotEmpty
                    ? 'Review'
                    : (goals.isEmpty ? 'Add goal' : '+ Add'),
                icon: goals.isEmpty ? CruIcons.plus : null,
                onPressed: () => showGoalSheet(
                  context,
                  ref,
                  patient,
                  existing: overdue.firstOrNull,
                ),
              ),
            ],
          ),
          for (final g in goals)
            _GoalRow(
              goal: g,
              now: now,
              onTap: () => showGoalSheet(context, ref, patient, existing: g),
            ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.now, required this.onTap});

  final PhysioGoal goal;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final overdue = goal.overdue(now);
    final days = goal.daysLeft(now);
    final target = goal.target;

    final (String status, Color tint) = switch (goal.status) {
      GoalStatus.reached => ('Reached', c.greenText),
      GoalStatus.missed => ('Not reached', c.label3),
      GoalStatus.open when target == null => ('No date', c.label3),
      GoalStatus.open when overdue => (
        'Past ${DentalFormat.date(target!)}',
        c.amberText,
      ),
      GoalStatus.open when days == 0 => ('Due today', c.label2),
      GoalStatus.open => ('Due ${DentalFormat.date(target!)}', c.label2),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(CruRadius.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: CruSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.body.w600.tint(
                      goal.isOpen ? c.label : c.label2,
                    ),
                  ),
                  if (goal.note.trim().isNotEmpty)
                    Text(
                      goal.note.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.tint(c.label3),
                    ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Text(status, style: CruType.caption.tabular.tint(tint)),
          ],
        ),
      ),
    );
  }
}

/// Add a goal, or open one to change it or settle it.
Future<void> showGoalSheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient, {
  PhysioGoal? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _GoalSheet(patient: patient, existing: existing),
);

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.patient, required this.existing});

  final Patient patient;
  final PhysioGoal? existing;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  late DateTime? _target = widget.existing?.target;
  late GoalStatus _status = widget.existing?.status ?? GoalStatus.open;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTarget() async {
    final picked = await pickDentalDate(
      context,
      initial: _target ?? DateTime.now().add(const Duration(days: 28)),
      helpText: 'Reach it by',
      // A goal is reached in the future, so the picker has to allow one.
      last: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _target = picked);
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    final data = PhysioGoal.toData(
      text: text,
      target: _target,
      status: _status,
      note: _note.text.trim(),
    );
    final old = widget.existing;
    await saveDentalRecord(
      ref,
      old != null
          ? old.record.copyWith(data: data)
          : DentalRecord.create(widget.patient.id, RecKind.physioGoal, data),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final goal = widget.existing;
    if (goal == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this goal?',
      body:
          '"${goal.text}" and how it ended will be removed from the record. '
          'To keep the history, mark it not reached instead.',
      action: 'Delete goal',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    await deleteDentalRecord(ref, goal.record);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final goal = widget.existing;
    final overdue = goal != null && goal.overdue(DateTime.now());

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNew ? 'Add a goal' : 'Goal',
                style: CruType.headline.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                overdue
                    ? 'The date on this goal has gone by. Decide where it '
                          'stands, or move the date.'
                    : "In the patient's own words — what they want to be "
                          'able to do again.',
                style: CruType.caption.tint(overdue ? c.amberText : c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Goal',
                controller: _text,
                hint: 'Climb the stairs at home without the rail',
                maxLines: 2,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: CruSpace.s16),
              Row(
                children: [
                  CruCapsuleButton(
                    label: _target == null
                        ? 'Set a target date'
                        : 'By ${DentalFormat.date(_target!)}',
                    icon: CruIcons.calendar,
                    onPressed: _pickTarget,
                  ),
                  if (_target != null) ...[
                    const SizedBox(width: CruSpace.s8),
                    CruCapsuleButton(
                      label: 'Clear',
                      onPressed: () => setState(() => _target = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Without a date the goal still stands, it just never comes '
                'up for review.',
                style: CruType.caption.tint(c.label3),
              ),
              // A goal starts open. Where it ended up is a decision taken
              // later, so the choice only appears once there is a goal to
              // decide about.
              if (!_isNew) ...[
                const SizedBox(height: CruSpace.s16),
                Text(
                  'WHERE IT STANDS',
                  style: CruType.groupLabel.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s8),
                Row(
                  children: [
                    for (final s in GoalStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(right: CruSpace.s8),
                        child: DentalChoiceChip(
                          label: s.label,
                          selected: _status == s,
                          onTap: () => setState(() => _status = s),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Note',
                controller: _note,
                hint: 'How it is going, or what got in the way',
                maxLines: 2,
                optional: true,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: CruSpace.s20),
              CruButton(
                label: _saving
                    ? 'Saving…'
                    : (_isNew ? 'Add goal' : 'Save goal'),
                expand: true,
                onPressed: _saving || _text.text.trim().isEmpty ? null : _save,
              ),
              if (!_isNew) ...[
                const SizedBox(height: CruSpace.s8),
                CruCapsuleButton(
                  label: 'Delete goal',
                  onPressed: _saving ? null : _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
