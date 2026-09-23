import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _CycleFilter { all, passed, failed, incomplete }

/// Autoclave cycles for infection-control records: what was run, by
/// whom, and whether it passed. A failed load stands out in red: it isn't
/// safe to use.
class SterilizationScreen extends ConsumerStatefulWidget {
  const SterilizationScreen({super.key});

  @override
  ConsumerState<SterilizationScreen> createState() =>
      _SterilizationScreenState();
}

class _SterilizationScreenState extends ConsumerState<SterilizationScreen> {
  _CycleFilter _filter = _CycleFilter.all;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final async = ref.watch(clinicSterilizationProvider);
    final logs = async.value == null
        ? null
        : ([...async.value!]..sort((a, b) => b.cycleDate.compareTo(a.cycleDate)));
    final now = DateTime.now();

    final today = logs?.where((l) => DentalFormat.sameDay(l.cycleDate, now)).toList() ?? const [];
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final week = logs?.where((l) => !l.cycleDate.isBefore(weekStart)).toList() ?? const [];
    final month = logs
            ?.where((l) => now.difference(l.cycleDate).inDays < 30)
            .toList() ??
        const [];
    SterilizationResult r(SterilizationLogModel l) =>
        SterilizationResult.fromString(l.result);
    final failed30 = month.where((l) => r(l) == SterilizationResult.fail).length;
    final passed30 = month.where((l) => r(l) == SterilizationResult.pass).length;

    final q = _query.trim().toLowerCase();
    final shown = (logs ?? const <SterilizationLogModel>[])
        .where((l) => switch (_filter) {
              _CycleFilter.all => true,
              _CycleFilter.passed => r(l) == SterilizationResult.pass,
              _CycleFilter.failed => r(l) == SterilizationResult.fail,
              _CycleFilter.incomplete => r(l) == SterilizationResult.incomplete,
            })
        .where((l) =>
            q.isEmpty ||
            l.loadDescription.toLowerCase().contains(q) ||
            l.operatorName.toLowerCase().contains(q) ||
            l.notes.toLowerCase().contains(q))
        .toList();

    // Grouped by day, newest first.
    final groups = <String, List<SterilizationLogModel>>{};
    for (final l in shown) {
      (groups[DentalFormat.day(l.cycleDate, now)] ??= []).add(l);
    }

    Widget cell(String label, String value, Widget caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [GlanceLabel(label), GlanceMetric(value), GlanceCaption(caption)],
        );
    final last = logs == null || logs.isEmpty ? null : logs.first;

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Sterilization',
            subtitle: last == null
                ? 'Autoclave cycles for your infection-control records'
                : 'Last cycle ${DentalFormat.day(last.cycleDate, now).toLowerCase()} '
                    'at ${DentalFormat.time(last.cycleDate)} · '
                    '${sterilizationWord(last.result)}',
            actions: [
              CruButton(
                label: 'Log cycle',
                icon: CruIcons.plus,
                onPressed: () => showSterilizationDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (logs == null)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Sterilization at a glance',
              cells: [
                cell(
                  'Today',
                  '${today.length}',
                  today.isEmpty
                      ? Text('No cycle logged yet',
                          style: CruType.caption.tint(c.amberText))
                      : Text('Last at ${DentalFormat.time(today.first.cycleDate)}'),
                ),
                cell('This week', '${week.length}',
                    Text(DashFormat.plural(week.where((l) => r(l) == SterilizationResult.pass).length, 'passed cycle'))),
                cell(
                  'Failed',
                  '$failed30',
                  failed30 == 0
                      ? const Text('None in 30 days')
                      : Text('In 30 days · re-run those loads',
                          style: CruType.caption.tint(c.redText)),
                ),
                cell(
                  'Pass rate',
                  month.isEmpty ? '—' : '${(passed30 * 100 / month.length).round()}%',
                  Text(month.isEmpty
                      ? 'No cycles in 30 days'
                      : 'of ${DashFormat.plural(month.length, 'cycle')} in 30 days'),
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              CruSegmentedControl<_CycleFilter>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_CycleFilter.all, 'All'),
                  CruSegment(_CycleFilter.passed, 'Passed'),
                  CruSegment(_CycleFilter.failed, 'Failed'),
                  CruSegment(_CycleFilter.incomplete, 'Incomplete'),
                ],
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const Spacer(),
              SizedBox(
                width: 280,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search load, operator or notes',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Cycles',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: logs == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: DentalIcons.shield,
                              title: logs.isEmpty ? 'No cycles logged yet' : 'No cycles here',
                              body: logs.isEmpty
                                  ? 'Log each autoclave run: what went in, who ran '
                                      'it and whether it passed. It keeps your '
                                      'infection-control record ready for inspection.'
                                  : 'Try another filter or search.',
                              actions: [
                                if (logs.isEmpty)
                                  CruButton(
                                    label: 'Log cycle',
                                    icon: CruIcons.plus,
                                    onPressed: () => showSterilizationDialog(context),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final e in groups.entries) ...[
                              DentalGroupLabel(e.key,
                                  trailing: DashFormat.plural(e.value.length, 'cycle')),
                              for (var i = 0; i < e.value.length; i++) ...[
                                if (i > 0) const CruSeparator(indent: 12 + 76 + 12),
                                _CycleRow(log: e.value[i]),
                              ],
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

class _CycleRow extends StatelessWidget {
  const _CycleRow({required this.log});

  final SterilizationLogModel log;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final load = log.loadDescription.trim();
    final notes = log.notes.trim();
    return DentalListRow(
      semanticLabel: '${load.isEmpty ? 'Cycle' : load}, ${log.result}',
      onTap: () => showSterilizationDialog(context, existing: log),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              DentalFormat.time(log.cycleDate),
              style: CruType.subhead.w600.tabular.tint(c.label),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  load.isEmpty ? 'Autoclave cycle' : load,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  [
                    if (log.operatorName.trim().isNotEmpty) 'By ${log.operatorName.trim()}',
                    if (notes.isNotEmpty) notes,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          sterilizationPill(c, log.result),
        ],
      ),
    );
  }
}

// ================================================================ dialog

Future<bool> showSterilizationDialog(
  BuildContext context, {
  SterilizationLogModel? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CycleDialog(existing: existing),
  );
  return saved == true;
}

class _CycleDialog extends ConsumerStatefulWidget {
  const _CycleDialog({required this.existing});

  final SterilizationLogModel? existing;

  @override
  ConsumerState<_CycleDialog> createState() => _CycleDialogState();
}

class _CycleDialogState extends ConsumerState<_CycleDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _operator;
  late final TextEditingController _load;
  late final TextEditingController _notes;
  late DateTime _at;
  late SterilizationResult _result;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // The last operator is usually the same person.
    final lastOperator = ref.read(clinicSterilizationProvider).value?.firstOrNull?.operatorName;
    final me = ref.read(doctorIdentityProvider).fullName;
    _operator = TextEditingController(
        text: e?.operatorName ?? (lastOperator?.trim().isNotEmpty == true ? lastOperator : me));
    _load = TextEditingController(text: e?.loadDescription ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _at = e?.cycleDate ?? DateTime.now();
    _result = e == null ? SterilizationResult.pass : SterilizationResult.fromString(e.result);
  }

  @override
  void dispose() {
    _operator.dispose();
    _load.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickTime() async {
    final c = context.cru;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: c.accent,
                onPrimary: c.onAccent,
                surface: c.surface,
                onSurface: c.label,
              ),
        ),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
    _edited();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final now = DateTime.now();
      final e = widget.existing;
      await ref.read(dentalRepositoryProvider).saveSterilizationLog(
            SterilizationLogModel(
              id: e?.id ?? const Uuid().v4(),
              doctorId: ref.read(dentalDoctorIdProvider),
              cycleDate: _at,
              operatorName: _operator.text.trim(),
              loadDescription: _load.text.trim(),
              result: _result.code,
              notes: _notes.text.trim(),
              createdAt: e?.createdAt ?? now,
              updatedAt: now,
              syncStatus: 'pending',
            ),
          );
      ref.invalidate(clinicSterilizationProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the cycle. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this cycle?',
      body: 'The ${DentalFormat.time(e.cycleDate)} cycle on '
          '${DentalFormat.date(e.cycleDate)} will be removed from the log.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await ref.read(dentalRepositoryProvider).saveSterilizationLog(
          e.copyWith(isDeleted: true, updatedAt: DateTime.now(), syncStatus: 'pending'),
        );
    ref.invalidate(clinicSterilizationProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final failed = _result == SterilizationResult.fail;
    return CruFormDialog(
      title: widget.existing == null ? 'Log autoclave cycle' : 'Autoclave cycle',
      subtitle: '${DentalFormat.date(_at)} · ${DentalFormat.time(_at)}',
      leading: const CruIconTile(icon: DentalIcons.shield, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Log cycle' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Cycle',
              description: 'When it ran, who ran it and what went in.',
              children: [
                CruFieldRow(
                  children: [
                    CruPickerField(
                      label: 'Date',
                      icon: CruIcons.calendar,
                      value: DentalFormat.date(_at),
                      placeholder: 'Pick a date',
                      trailing: DentalFormat.sameDay(_at, DateTime.now())
                          ? const CruInfoPill(text: 'Today')
                          : null,
                      onTap: () async {
                        final d = await pickDentalDate(context,
                            initial: _at, last: DateTime.now());
                        if (d != null) {
                          setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
                          _edited();
                        }
                      },
                    ),
                    CruPickerField(
                      label: 'Time',
                      icon: CruIcons.clock,
                      value: DentalFormat.time(_at),
                      placeholder: 'Pick a time',
                      onTap: _pickTime,
                    ),
                  ],
                ),
                CruTextField(
                  label: 'Run by',
                  controller: _operator,
                  hint: 'Who loaded and started it',
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Add who ran the cycle.' : null,
                  onChanged: (_) => _edited(),
                ),
                CruTextField(
                  label: 'Load',
                  controller: _load,
                  hint: 'Kit 3, 4 handpieces, 12 pouches',
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Say what went in.' : null,
                  onChanged: (_) => _edited(),
                ),
              ],
            ),
            CruFormSection(
              title: 'Result',
              description: failed
                  ? "A failed load isn't safe to use. Note what was done with it."
                  : 'From the indicator strip or the machine read-out.',
              children: [
                CruFieldFrame(
                  label: 'Result',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<SterilizationResult>(
                      semanticLabel: 'Result',
                      segments: const [
                        CruSegment(SterilizationResult.pass, 'Passed'),
                        CruSegment(SterilizationResult.fail, 'Failed'),
                        CruSegment(SterilizationResult.incomplete, 'Incomplete'),
                      ],
                      selected: _result,
                      onChanged: (r) {
                        setState(() => _result = r);
                        _edited();
                      },
                    ),
                  ),
                ),
                CruTextField(
                  label: 'Notes',
                  optional: !failed,
                  controller: _notes,
                  maxLines: 3,
                  hint: failed
                      ? 'Load quarantined and re-run at 2:10 PM'
                      : 'Temperature, pressure, indicator batch',
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => failed && (v ?? '').trim().isEmpty
                      ? 'Say what was done with the load.'
                      : null,
                  onChanged: (_) => _edited(),
                ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(label: 'Delete this cycle', onPressed: _delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
