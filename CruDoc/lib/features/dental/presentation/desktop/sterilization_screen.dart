import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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

enum _CycleFilter { all, passed, failed, biPending }

String _indicatorLabel(String v) => switch (v) {
  'pass' => 'Pass',
  'fail' => 'Fail',
  'pending' => 'Pending',
  _ => 'Not used',
};

/// Autoclave cycles for infection-control records: what was run, by
/// whom, and whether it passed. A failed load is marked with a warning
/// icon: it isn't safe to use.
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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _monthStepper(CruColors c) {
    final now = DateTime.now();
    final atNow = _month.year == now.year && _month.month == now.month;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CruIconButton(
          icon: CruIcons.chevronLeft,
          semanticLabel: 'Previous month',
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        SizedBox(
          width: 128,
          child: Text(
            DateFormat('MMMM yyyy').format(_month),
            textAlign: TextAlign.center,
            style: CruType.subhead.w600.tabular.tint(c.label),
          ),
        ),
        CruIconButton(
          icon: CruIcons.chevronRight,
          semanticLabel: 'Next month',
          onPressed: atNow
              ? null
              : () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
        ),
      ],
    );
  }

  /// The month as a table for inspectors, through the same print /
  /// save-as-PDF sheet the perio chart uses.
  Future<void> _exportMonth(List<SterilizationLogModel> month) async {
    final identity = ref.read(doctorIdentityProvider);
    final cycles = [...month]
      ..sort((a, b) => a.cycleDate.compareTo(b.cycleDate));
    final label = DateFormat('MMMM yyyy').format(_month);
    final machines = {
      for (final l in cycles)
        if (l.autoclaveName.trim().isNotEmpty) l.autoclaveName.trim(),
    }.toList()..sort();
    SterilizationResult res(SterilizationLogModel l) =>
        SterilizationResult.fromString(l.result);
    final passes = cycles.where((l) => res(l) == SterilizationResult.pass);
    final fails = cycles.where((l) => res(l) == SterilizationResult.fail);
    final biTests = cycles.where((l) => l.biologicalIndicator != 'not_used');

    pw.Widget line(String text, double width) => pw.Container(
      width: width,
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide()),
      ),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text(
            identity.clinicName ?? identity.fullName ?? 'Clinic',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Sterilisation log - $label'),
          pw.Text(
            machines.isEmpty
                ? 'Autoclave: not named'
                : 'Autoclave${machines.length > 1 ? 's' : ''}: ${machines.join(', ')}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              'No.',
              'Date',
              'Time',
              'Autoclave',
              'Program',
              'Load',
              'Chemical',
              'Biological',
              'Result',
              'Run by',
            ],
            data: [
              for (final l in cycles)
                [
                  l.cycleNumber > 0 ? '${l.cycleNumber}' : '',
                  DateFormat('d MMM').format(l.cycleDate),
                  DentalFormat.time(l.cycleDate),
                  l.autoclaveName,
                  l.program,
                  l.loadDescription,
                  _indicatorLabel(l.chemicalIndicator),
                  _indicatorLabel(l.biologicalIndicator),
                  l.biPending ? 'Pass (BI pending)' : res(l).label,
                  l.operatorName,
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(3),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Cycles: ${cycles.length}   Pass: ${passes.length}   '
            'Fail: ${fails.length}   Biological tests: ${biTests.length}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 36),
          pw.Row(
            children: [
              line('Signature', 220),
              pw.SizedBox(width: 40),
              line('Date', 120),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'Sterilisation log $label',
      onLayout: (_) => doc.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final async = ref.watch(clinicSterilizationProvider);
    final logs = async.value == null
        ? null
        : ([...async.value!]
            ..sort((a, b) => b.cycleDate.compareTo(a.cycleDate)));
    final now = DateTime.now();

    final today =
        logs?.where((l) => DentalFormat.sameDay(l.cycleDate, now)).toList() ??
        const [];
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final week =
        logs?.where((l) => !l.cycleDate.isBefore(weekStart)).toList() ??
        const [];
    final recent =
        logs?.where((l) => now.difference(l.cycleDate).inDays < 30).toList() ??
        const [];
    SterilizationResult r(SterilizationLogModel l) =>
        SterilizationResult.fromString(l.result);
    final failed30 = recent
        .where((l) => r(l) == SterilizationResult.fail)
        .length;
    final passed30 = recent
        .where((l) => r(l) == SterilizationResult.pass)
        .length;

    final q = _query.trim().toLowerCase();
    final inMonth = (logs ?? const <SterilizationLogModel>[])
        .where(
          (l) =>
              l.cycleDate.year == _month.year &&
              l.cycleDate.month == _month.month,
        )
        .toList();
    final shown = inMonth
        .where(
          (l) => switch (_filter) {
            _CycleFilter.all => true,
            _CycleFilter.passed => r(l) == SterilizationResult.pass,
            _CycleFilter.failed => r(l) == SterilizationResult.fail,
            _CycleFilter.biPending => l.biPending,
          },
        )
        .where(
          (l) =>
              q.isEmpty ||
              l.autoclaveName.toLowerCase().contains(q) ||
              l.loadDescription.toLowerCase().contains(q) ||
              l.operatorName.toLowerCase().contains(q) ||
              l.notes.toLowerCase().contains(q),
        )
        .toList();

    // Grouped by day, newest first.
    final groups = <String, List<SterilizationLogModel>>{};
    for (final l in shown) {
      (groups[DentalFormat.day(l.cycleDate, now)] ??= []).add(l);
    }

    Widget cell(String label, String value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );
    final last = logs == null || logs.isEmpty ? null : logs.first;

    return Padding(
      padding: cruIsPhone(context)
          ? CruSpace.mainPaddingPhone
          : CruSpace.mainPadding,
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
                label: 'Monthly report (PDF)',
                icon: CruIcons.fileText,
                kind: CruButtonKind.secondary,
                onPressed: inMonth.isEmpty ? null : () => _exportMonth(inMonth),
              ),
              CruButton(
                label: 'Add cycle',
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
                      ? Text(
                          'No cycle logged yet',
                          style: CruType.caption.tint(c.amberText),
                        )
                      : Text(
                          'Last at ${DentalFormat.time(today.first.cycleDate)}',
                        ),
                ),
                cell(
                  'This week',
                  '${week.length}',
                  Text(
                    DashFormat.plural(
                      week
                          .where((l) => r(l) == SterilizationResult.pass)
                          .length,
                      'passed cycle',
                    ),
                  ),
                ),
                cell(
                  'Failed',
                  '$failed30',
                  failed30 == 0
                      ? const Text('None in 30 days')
                      : Text(
                          'In 30 days · re-run those loads',
                          style: CruType.caption.tint(c.label2),
                        ),
                ),
                cell(
                  'Pass rate',
                  recent.isEmpty
                      ? '—'
                      : '${(passed30 * 100 / recent.length).round()}%',
                  Text(
                    recent.isEmpty
                        ? 'No cycles in 30 days'
                        : 'of ${DashFormat.plural(recent.length, 'cycle')} in 30 days',
                  ),
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          DentalFilterBar(
            filters: [
              CruSegmentedControl<_CycleFilter>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_CycleFilter.all, 'All'),
                  CruSegment(_CycleFilter.passed, 'Pass'),
                  CruSegment(_CycleFilter.failed, 'Fail'),
                  CruSegment(_CycleFilter.biPending, 'BI pending'),
                ],
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ],
            search: DentalSearchField(
              controller: _search,
              hint: 'Search autoclave, load or operator',
              onChanged: (v) => setState(() => _query = v),
            ),
            trailing: [_monthStepper(c)],
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
                          title: logs.isEmpty
                              ? 'No cycles logged yet'
                              : 'No cycles in ${DateFormat('MMMM yyyy').format(_month)}',
                          body: logs.isEmpty
                              ? 'Log each autoclave cycle to keep your '
                                    'infection-control record ready for inspection.'
                              : 'Try another month, filter or search.',
                          actions: [
                            if (logs.isEmpty)
                              CruButton(
                                label: 'Add cycle',
                                icon: CruIcons.plus,
                                onPressed: () =>
                                    showSterilizationDialog(context),
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final e in groups.entries) ...[
                          DentalGroupLabel(
                            e.key,
                            trailing: DashFormat.plural(
                              e.value.length,
                              'cycle',
                            ),
                          ),
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
    final machine = log.autoclaveName.trim();
    final title = [
      if (log.cycleNumber > 0) '#${log.cycleNumber}',
      machine.isEmpty ? 'Autoclave cycle' : machine,
    ].join(' · ');
    return DentalListRow(
      semanticLabel: '$title, ${log.result}',
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  [
                    if (log.program.trim().isNotEmpty) log.program.trim(),
                    if (load.isNotEmpty) load,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          sterilizationPill(c, log.result, biPending: log.biPending),
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

const _programs = ['121 °C', '134 °C', 'Custom'];

class _CycleDialog extends ConsumerStatefulWidget {
  const _CycleDialog({required this.existing});

  final SterilizationLogModel? existing;

  @override
  ConsumerState<_CycleDialog> createState() => _CycleDialogState();
}

class _CycleDialogState extends ConsumerState<_CycleDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _autoclave;
  late final TextEditingController _number;
  late final TextEditingController _operator;
  late final TextEditingController _load;
  late final TextEditingController _notes;
  late final TextEditingController _temp;
  late final TextEditingController _pressure;
  late final TextEditingController _hold;
  late final TextEditingController _reason;
  late final TextEditingController _correction;
  late DateTime _at;
  late String _program;
  late String _chemical;
  late String _biological;
  SterilizationResult? _override;
  bool _numberTouched = false;
  bool _more = false;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  /// Same-day edits only; later changes are a dated correction note.
  late final bool _locked;

  List<SterilizationLogModel> get _all =>
      ref.read(clinicSterilizationProvider).value ?? const [];

  SterilizationResult get _auto =>
      _chemical == 'fail' || _biological == 'fail'
      ? SterilizationResult.fail
      : SterilizationResult.pass;

  SterilizationResult get _result => _override ?? _auto;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final logs = _all;
    final lastMachine = logs
        .map((l) => l.autoclaveName.trim())
        .firstWhere((n) => n.isNotEmpty, orElse: () => '');
    final lastOperator = logs.firstOrNull?.operatorName;
    final me = ref.read(doctorIdentityProvider).fullName;
    _locked =
        e != null && !DentalFormat.sameDay(e.createdAt, DateTime.now());
    _autoclave = TextEditingController(text: e?.autoclaveName ?? lastMachine);
    _number = TextEditingController(
      text: e == null
          ? '${_suggest(_autoclave.text)}'
          : (e.cycleNumber > 0 ? '${e.cycleNumber}' : ''),
    );
    _operator = TextEditingController(
      text:
          e?.operatorName ??
          (lastOperator?.trim().isNotEmpty == true ? lastOperator : me),
    );
    _load = TextEditingController(text: e?.loadDescription ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _program = e == null || e.program.isEmpty ? _programs.first : e.program;
    String num(int? v) => v == null ? '' : '$v';
    _temp = TextEditingController(
      text: e == null ? '121' : num(e.temperatureC),
    );
    _pressure = TextEditingController(text: num(e?.pressureKpa));
    _hold = TextEditingController(text: num(e?.holdMinutes));
    _reason = TextEditingController(text: e?.overrideReason ?? '');
    _correction = TextEditingController();
    _at = e?.cycleDate ?? DateTime.now();
    _chemical = e?.chemicalIndicator ?? 'not_used';
    _biological = e?.biologicalIndicator ?? 'not_used';
    if (e != null && SterilizationResult.fromString(e.result) != _auto) {
      _override = SterilizationResult.fromString(e.result);
    }
  }

  @override
  void dispose() {
    for (final t in [
      _autoclave,
      _number,
      _operator,
      _load,
      _notes,
      _temp,
      _pressure,
      _hold,
      _reason,
      _correction,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  /// Last cycle number for this autoclave, plus one.
  int _suggest(String machine) {
    final key = machine.trim().toLowerCase();
    var top = 0;
    for (final l in _all) {
      if (l.autoclaveName.trim().toLowerCase() == key &&
          l.cycleNumber > top) {
        top = l.cycleNumber;
      }
    }
    return top + 1;
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (t == null) return;
    setState(
      () => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute),
    );
    _edited();
  }

  int? _int(TextEditingController t) => int.tryParse(t.text.trim());

  Future<void> _save() async {
    final e = widget.existing;
    final me = ref.read(doctorIdentityProvider).fullName ?? '';
    if (_locked) {
      final note = _correction.text.trim();
      if (note.isEmpty) {
        setState(() => _notice = 'Write the correction first.');
        return;
      }
      final now = DateTime.now();
      final stamp =
          '${DentalFormat.date(now)} ${DentalFormat.time(now)}'
          '${me.isEmpty ? '' : ' · $me'}: $note';
      await _write(
        _rebuild(
          e!,
          correctionNote: e.correctionNote.isEmpty
              ? stamp
              : '${e.correctionNote}\n$stamp',
        ),
      );
      return;
    }
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final now = DateTime.now();
    await _write(
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
        autoclaveName: _autoclave.text.trim(),
        cycleNumber: _int(_number) ?? 0,
        program: _program,
        temperatureC: _int(_temp),
        pressureKpa: _int(_pressure),
        holdMinutes: _int(_hold),
        chemicalIndicator: _chemical,
        biologicalIndicator: _biological,
        overrideReason: _override == null ? '' : _reason.text.trim(),
        createdBy: e?.createdBy.isNotEmpty == true ? e!.createdBy : me,
        editedAt: e == null ? null : now,
        editedBy: e == null ? '' : me,
        correctionNote: e?.correctionNote ?? '',
        syncStatus: 'pending',
      ),
    );
  }

  SterilizationLogModel _rebuild(
    SterilizationLogModel e, {
    required String correctionNote,
  }) {
    final now = DateTime.now();
    return SterilizationLogModel(
      id: e.id,
      doctorId: e.doctorId,
      cycleDate: e.cycleDate,
      operatorName: e.operatorName,
      loadDescription: e.loadDescription,
      result: e.result,
      notes: e.notes,
      createdAt: e.createdAt,
      updatedAt: now,
      autoclaveName: e.autoclaveName,
      cycleNumber: e.cycleNumber,
      program: e.program,
      temperatureC: e.temperatureC,
      pressureKpa: e.pressureKpa,
      holdMinutes: e.holdMinutes,
      chemicalIndicator: e.chemicalIndicator,
      biologicalIndicator: e.biologicalIndicator,
      overrideReason: e.overrideReason,
      createdBy: e.createdBy,
      editedAt: now,
      editedBy: ref.read(doctorIdentityProvider).fullName ?? '',
      correctionNote: correctionNote,
      syncStatus: 'pending',
    );
  }

  Future<void> _write(SterilizationLogModel log) async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await ref.read(dentalRepositoryProvider).saveSterilizationLog(log);
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
      body:
          'The ${DentalFormat.time(e.cycleDate)} cycle on '
          '${DentalFormat.date(e.cycleDate)} will be removed from the log.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await ref
        .read(dentalRepositoryProvider)
        .saveSterilizationLog(
          e.copyWith(
            isDeleted: true,
            updatedAt: DateTime.now(),
            syncStatus: 'pending',
          ),
        );
    ref.invalidate(clinicSterilizationProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _segmented(
    String label,
    List<(String, String)> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return CruFieldFrame(
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: CruSegmentedControl<String>(
          semanticLabel: label,
          segments: [for (final o in options) CruSegment(o.$1, o.$2)],
          selected: value,
          onChanged: (v) {
            setState(() => onChanged(v));
            _edited();
          },
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller,
    String hint,
  ) {
    return CruTextField(
      label: label,
      optional: true,
      controller: controller,
      hint: hint,
      tabular: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _edited(),
    );
  }

  Widget _readOnly(CruColors c, SterilizationLogModel e) {
    String chemical = _indicatorLabel(e.chemicalIndicator);
    String bio = _indicatorLabel(e.biologicalIndicator);
    final rows = <(String, String)>[
      ('Autoclave', e.autoclaveName),
      ('Cycle no.', e.cycleNumber > 0 ? '${e.cycleNumber}' : ''),
      ('Program', e.program),
      ('Load', e.loadDescription),
      ('Chemical indicator', chemical),
      ('Biological indicator', bio),
      ('Temperature', e.temperatureC == null ? '' : '${e.temperatureC} °C'),
      ('Pressure', e.pressureKpa == null ? '' : '${e.pressureKpa} kPa'),
      ('Hold', e.holdMinutes == null ? '' : '${e.holdMinutes} min'),
      ('Run by', e.operatorName),
      ('Override reason', e.overrideReason),
      ('Notes', e.notes),
      ('Corrections', e.correctionNote),
      if (e.editedAt != null)
        (
          'Last edited',
          '${DentalFormat.date(e.editedAt!)} ${DentalFormat.time(e.editedAt!)}'
              '${e.editedBy.isEmpty ? '' : ' · ${e.editedBy}'}',
        ),
    ].where((r) => r.$2.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruFormSection(
          first: true,
          title: 'Cycle',
          description: 'Entries are locked after the day they were made.',
          children: [
            for (final r in rows)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(r.$1, style: CruType.subhead.tint(c.label2)),
                  ),
                  Expanded(
                    child: Text(r.$2, style: CruType.callout.tint(c.label)),
                  ),
                ],
              ),
          ],
        ),
        CruFormSection(
          title: 'Add a correction',
          description: 'Dated and kept with the entry. The original stays.',
          children: [
            CruTextField(
              label: 'Correction note',
              controller: _correction,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _edited(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final e = widget.existing;
    final failed = _result == SterilizationResult.fail;
    final notes = CruTextField(
      label: 'Notes',
      optional: !failed,
      controller: _notes,
      maxLines: 3,
      hint: failed
          ? 'Load quarantined and re-run at 2:10 PM'
          : 'Indicator batch, anything unusual',
      textCapitalization: TextCapitalization.sentences,
      validator: (v) => failed && (v ?? '').trim().isEmpty
          ? 'Say what was done with the load.'
          : null,
      onChanged: (_) => _edited(),
    );
    return CruFormDialog(
      title: e == null ? 'Add autoclave cycle' : 'Autoclave cycle',
      subtitle: '${DentalFormat.date(_at)} · ${DentalFormat.time(_at)}',
      leading: const CruIconTile(
        icon: DentalIcons.shield,
        tone: CruTileTone.accent,
      ),
      submitLabel: _locked
          ? 'Add correction'
          : e == null
          ? 'Add cycle'
          : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: _locked
          ? _readOnly(c, e!)
          : Form(
              key: _form,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CruFormSection(
                    first: true,
                    title: 'Cycle',
                    description: 'Which autoclave, what program, what went in.',
                    children: [
                      CruFieldRow(
                        children: [
                          CruTextField(
                            label: 'Autoclave',
                            controller: _autoclave,
                            hint: 'Autoclave A',
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Name the autoclave.'
                                : null,
                            onChanged: (v) {
                              if (!_numberTouched && e == null) {
                                _number.text = '${_suggest(v)}';
                              }
                              _edited();
                            },
                          ),
                          CruTextField(
                            label: 'Cycle no.',
                            controller: _number,
                            tabular: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) {
                              _numberTouched = true;
                              _edited();
                            },
                          ),
                        ],
                      ),
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
                              final d = await pickDentalDate(
                                context,
                                initial: _at,
                                last: DateTime.now(),
                              );
                              if (d != null) {
                                setState(
                                  () => _at = DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                    _at.hour,
                                    _at.minute,
                                  ),
                                );
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
                      _segmented(
                        'Program',
                        [for (final p in _programs) (p, p)],
                        _program,
                        (v) {
                          _program = v;
                          if (v != 'Custom') {
                            _temp.text = v.split(' ').first;
                          }
                        },
                      ),
                      CruTextField(
                        label: 'Load',
                        controller: _load,
                        hint: 'Hand pieces, 2 trays',
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Say what went in.'
                            : null,
                        onChanged: (_) => _edited(),
                      ),
                      CruTextField(
                        label: 'Run by',
                        controller: _operator,
                        hint: 'Who loaded and started it',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Add who ran the cycle.'
                            : null,
                        onChanged: (_) => _edited(),
                      ),
                    ],
                  ),
                  CruFormSection(
                    title: 'Indicators and result',
                    description: failed
                        ? "A failed load isn't safe to use. Note what was done with it."
                        : 'The result follows the indicators.',
                    children: [
                      _segmented(
                        'Chemical indicator',
                        const [
                          ('not_used', 'Not used'),
                          ('pass', 'Pass'),
                          ('fail', 'Fail'),
                        ],
                        _chemical,
                        (v) => _chemical = v,
                      ),
                      _segmented(
                        'Biological indicator',
                        const [
                          ('not_used', 'Not used'),
                          ('pass', 'Pass'),
                          ('fail', 'Fail'),
                          ('pending', 'Pending'),
                        ],
                        _biological,
                        (v) => _biological = v,
                      ),
                      Row(
                        children: [
                          Text(
                            'Result',
                            style: CruType.subhead.tint(c.label2),
                          ),
                          const SizedBox(width: CruSpace.s12),
                          sterilizationPill(
                            c,
                            _result.code,
                            biPending:
                                _biological == 'pending' &&
                                _result == SterilizationResult.pass,
                          ),
                          const Spacer(),
                          CruLink(
                            label: _override == null
                                ? 'Override result'
                                : 'Use indicator result',
                            onPressed: () {
                              setState(() {
                                _override = _override == null
                                    ? (_auto == SterilizationResult.pass
                                          ? SterilizationResult.fail
                                          : SterilizationResult.pass)
                                    : null;
                              });
                              _edited();
                            },
                          ),
                        ],
                      ),
                      if (_override != null)
                        CruTextField(
                          label: 'Reason for override',
                          controller: _reason,
                          hint: 'Why the result differs from the indicators',
                          textCapitalization: TextCapitalization.sentences,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Give a reason.'
                              : null,
                          onChanged: (_) => _edited(),
                        ),
                      if (failed) notes,
                    ],
                  ),
                  CruFormSection(
                    title: 'More details',
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CruLink(
                          label: _more
                              ? 'Hide temperature, pressure and hold'
                              : 'Temperature, pressure, hold and notes',
                          onPressed: () => setState(() => _more = !_more),
                        ),
                      ),
                      if (_more) ...[
                        CruFieldRow(
                          children: [
                            _numberField('Temperature (°C)', _temp, '134'),
                            _numberField('Pressure (kPa)', _pressure, '210'),
                            _numberField('Hold (min)', _hold, '4'),
                          ],
                        ),
                        if (!failed) notes,
                      ],
                      if (e != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CruLink(
                            label: 'Delete this cycle',
                            onPressed: _delete,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
