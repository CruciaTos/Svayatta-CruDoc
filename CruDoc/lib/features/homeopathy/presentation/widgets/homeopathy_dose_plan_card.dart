import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_potency_chips.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_field.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How a remedy is to be taken. [needsDays] patterns ask for a duration.
enum HomeoDosePattern {
  single('Single dose', false),
  onceDaily('Once daily', true),
  twiceDaily('Twice daily', true),
  thriceDaily('Thrice daily', true),
  weekly('Weekly', true),
  inWaterDaily('In water, daily', true),
  waitAndWatch('Wait and watch', false);

  const HomeoDosePattern(this.label, this.needsDays);
  final String label;
  final bool needsDays;

  static HomeoDosePattern fromName(String n) => values.firstWhere(
    (p) => p.name == n,
    orElse: () => HomeoDosePattern.single,
  );

  int get defaultDays => switch (this) {
    HomeoDosePattern.weekly => 28,
    _ => 7,
  };
}

/// One saved dose plan (record kind `homeoDosePlan`).
class HomeoDosePlan {
  const HomeoDosePlan(this.record);

  final DentalRecord record;

  String get id => record.id;
  DateTime get date => record.recordedAt;
  String get remedy => record.str('remedy');
  String get potency => record.str('potency');
  HomeoDosePattern get pattern =>
      HomeoDosePattern.fromName(record.str('pattern'));
  int? get days => record.integer('days');
  DateTime? get reviewOn => record.date('reviewOn');
  String get note => record.str('note');
  String get recallId => record.str('recallId');

  /// "Nux vomica 200C · Twice daily, 7 days".
  String get summary {
    final rx = [remedy, potency].where((s) => s.isNotEmpty).join(' ');
    final d = days;
    final how = pattern.needsDays && d != null
        ? '${pattern.label}, $d day${d == 1 ? '' : 's'}'
        : pattern.label;
    return rx.isEmpty ? how : '$rx · $how';
  }
}

/// Usual classical advice, shown as a general reminder only.
const _antidotes = [
  'coffee',
  'camphor',
  'strong mint or menthol',
  'strong aromatics',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Patient screen card: the active dose plan with its review date, earlier
/// plans below. "Plan dose" opens the planner sheet.
class HomeopathyDosePlanCard extends ConsumerWidget {
  const HomeopathyDosePlanCard({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  Future<void> _plan(BuildContext context, WidgetRef ref) async {
    final sheet = ref.read(homeopathyCaseSheetProvider(patientId)).value;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.cru.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      builder: (_) => _DosePlanSheet(
        patientId: patientId,
        patientName: patientName,
        initialRemedy: sheet?.prescriptionNotes.prescribedRemedy ?? '',
        initialPotency: sheet?.prescriptionNotes.potency ?? '',
      ),
    );
  }

  Future<void> _removeRecall(WidgetRef ref, HomeoDosePlan plan) async {
    final id = plan.recallId;
    if (id.isEmpty) return;
    await ref.read(dentalRecordsRepoProvider).delete(id);
    ref.invalidate(
      patientRecordsProvider((patientId: patientId, kind: RecKind.recall)),
    );
    ref.invalidate(clinicRecordsProvider(RecKind.recall));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    HomeoDosePlan plan,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete this dose plan?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            'The ${DentalFormat.date(plan.date)} plan and its review '
            'reminder are removed.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (confirm != true) return;
    await _removeRecall(ref, plan);
    await deleteDentalRecord(ref, plan.record);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final plans = [
      for (final r
          in ref
                  .watch(
                    patientRecordsProvider((
                      patientId: patientId,
                      kind: RecKind.homeoDosePlan,
                    )),
                  )
                  .value ??
              const <DentalRecord>[])
        HomeoDosePlan(r),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final active = plans.firstOrNull;
    final review = active?.reviewOn;
    final due =
        review != null && !_dateOnly(review).isAfter(_dateOnly(DateTime.now()));

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Dose plan', style: CruType.headline.tint(c.label)),
              ),
              CruPressable(
                onTap: () => _plan(context, ref),
                semanticLabel: 'Plan dose',
                builder: (context, hovered) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(CruIcons.plus, size: CruSpace.s16, color: c.accent),
                    const SizedBox(width: CruSpace.s4),
                    Text(
                      'Plan dose',
                      style: CruType.subhead.w600.tint(c.accentText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          if (active == null)
            Text('No dose plan yet.', style: CruType.text.tint(c.label2))
          else ...[
            Text(active.summary, style: CruType.text.tabular.tint(c.label)),
            if (active.note.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s2),
              Text(active.note, style: CruType.caption.tint(c.label2)),
            ],
            if (review != null) ...[
              const SizedBox(height: CruSpace.s8),
              Row(
                children: [
                  Text(
                    'Review on ${DentalFormat.date(review)}',
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                  if (due) ...[
                    const SizedBox(width: CruSpace.s8),
                    CruPill(
                      text: 'Review due',
                      background: c.amberTint,
                      foreground: c.amberText,
                    ),
                  ],
                ],
              ),
            ],
            if (plans.length > 1) ...[
              const SizedBox(height: CruSpace.s16),
              Text('Earlier plans', style: CruType.subhead.w600.tint(c.label2)),
              const SizedBox(height: CruSpace.s4),
              for (final p in plans.skip(1))
                _HistoryRow(plan: p, onDelete: () => _delete(context, ref, p)),
            ],
          ],
          if (active != null) ...[
            const SizedBox(height: CruSpace.s4),
            Align(
              alignment: Alignment.centerRight,
              child: CruIconButton(
                icon: FileIcons.trash,
                iconSize: 16,
                onPressed: () => _delete(context, ref, active),
                semanticLabel: 'Delete dose plan',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.plan, required this.onDelete});

  final HomeoDosePlan plan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${DentalFormat.date(plan.date)} · ${plan.summary}',
            style: CruType.caption.tabular.tint(c.label2),
          ),
        ),
        CruIconButton(
          icon: FileIcons.trash,
          iconSize: 16,
          onPressed: onDelete,
          semanticLabel: 'Delete earlier dose plan',
        ),
      ],
    );
  }
}

class _DosePlanSheet extends ConsumerStatefulWidget {
  const _DosePlanSheet({
    required this.patientId,
    required this.patientName,
    required this.initialRemedy,
    required this.initialPotency,
  });

  final String patientId;
  final String patientName;
  final String initialRemedy;
  final String initialPotency;

  @override
  ConsumerState<_DosePlanSheet> createState() => _DosePlanSheetState();
}

class _DosePlanSheetState extends ConsumerState<_DosePlanSheet> {
  late final _remedy = TextEditingController(text: widget.initialRemedy);
  late final _potency = TextEditingController(text: widget.initialPotency);
  final _note = TextEditingController();
  HomeoDosePattern _pattern = HomeoDosePattern.single;
  int _days = 7;
  late DateTime _review = _suggested();
  // Once the physician picks a date themselves, patterns stop moving it.
  bool _reviewPicked = false;
  bool _saving = false;

  @override
  void dispose() {
    _remedy.dispose();
    _potency.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime _suggested() {
    final today = _dateOnly(DateTime.now());
    return today.add(
      _pattern.needsDays ? Duration(days: _days) : const Duration(days: 28),
    );
  }

  void _refreshReview() {
    if (!_reviewPicked) _review = _suggested();
  }

  Future<void> _pickReview() async {
    final d = await pickDentalDate(
      context,
      initial: _review,
      helpText: 'Review on',
      last: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d != null) {
      setState(() {
        _review = d;
        _reviewPicked = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_remedy.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);

    // Replace the earlier plan's review reminder with this one.
    final existing =
        ref
            .read(
              patientRecordsProvider((
                patientId: widget.patientId,
                kind: RecKind.homeoDosePlan,
              )),
            )
            .value ??
        const <DentalRecord>[];
    final latest = ([
      ...existing,
    ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt))).firstOrNull;
    if (latest != null) {
      final oldRecall = HomeoDosePlan(latest).recallId;
      if (oldRecall.isNotEmpty) {
        await ref.read(dentalRecordsRepoProvider).delete(oldRecall);
      }
    }

    final recall = DentalRecord.create(widget.patientId, RecKind.recall, {
      'patientName': widget.patientName,
      'reason': 'Homeopathy dose review',
      'ruleId': '',
      'notes': _remedy.text.trim(),
      'status': 'pending',
    }, at: _review);
    await saveDentalRecord(ref, recall);

    await saveDentalRecord(
      ref,
      DentalRecord.create(widget.patientId, RecKind.homeoDosePlan, {
        'patientId': widget.patientId,
        'remedy': _remedy.text.trim(),
        'potency': _potency.text.trim(),
        'pattern': _pattern.name,
        if (_pattern.needsDays) 'days': _days,
        'reviewOn': _review.millisecondsSinceEpoch,
        'note': _note.text.trim(),
        'recallId': recall.id,
      }),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: EdgeInsets.only(
        left: CruSpace.s20,
        right: CruSpace.s20,
        top: CruSpace.s14,
        bottom: MediaQuery.of(context).viewInsets.bottom + CruSpace.s20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: CruSpace.s32 + CruSpace.s12,
                height: CruSpace.s4,
                margin: const EdgeInsets.only(bottom: CruSpace.s16),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Text('Plan dose', style: CruType.title2.tint(c.label)),
            const SizedBox(height: CruSpace.s16),
            HomeopathyRemedyField(
              controller: _remedy,
              label: 'Remedy',
              hint: 'Search remedies',
            ),
            const SizedBox(height: CruSpace.s12),
            HomeopathyPotencyChips(controller: _potency),
            const SizedBox(height: CruSpace.s14),
            const HomeopathyGroupLabel('Dosing pattern'),
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final p in HomeoDosePattern.values)
                  HomeopathyChoiceChip(
                    label: p.label,
                    selected: _pattern == p,
                    onSelected: (_) => setState(() {
                      _pattern = p;
                      if (p.needsDays) _days = p.defaultDays;
                      _refreshReview();
                    }),
                  ),
              ],
            ),
            if (_pattern.needsDays) ...[
              const SizedBox(height: CruSpace.s14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Duration',
                      style: CruType.subhead.w500.tint(c.label2),
                    ),
                  ),
                  CruCapsuleButton(
                    label: '-',
                    semanticLabel: 'Fewer days',
                    onPressed: _days > 1
                        ? () => setState(() {
                            _days--;
                            _refreshReview();
                          })
                        : null,
                  ),
                  SizedBox(
                    width: CruSpace.s32 + CruSpace.s24,
                    child: Text(
                      '$_days ${_days == 1 ? 'day' : 'days'}',
                      textAlign: TextAlign.center,
                      style: CruType.callout.w600.tabular.tint(c.label),
                    ),
                  ),
                  CruCapsuleButton(
                    label: '+',
                    semanticLabel: 'More days',
                    onPressed: () => setState(() {
                      _days++;
                      _refreshReview();
                    }),
                  ),
                ],
              ),
            ],
            const SizedBox(height: CruSpace.s14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Review on',
                    style: CruType.subhead.w500.tint(c.label2),
                  ),
                ),
                CruCapsuleButton(
                  label: DentalFormat.date(_review),
                  icon: CruIcons.calendar,
                  onPressed: _pickReview,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            HomeopathyFormField(
              controller: _note,
              label: 'Note',
              hint: 'Instructions for the patient',
              maxLines: 3,
            ),
            const SizedBox(height: CruSpace.s12),
            Text(
              'General reminder: avoid ${_antidotes.join(', ')} while on a '
              'remedy, as per the usual classical advice.',
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(label: 'Save plan', expand: true, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
