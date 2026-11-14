import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/patient_export.dart';
import 'package:doctor_management_app/features/patients/data/patient_import.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Step { start, match, preview, importing, done }

/// Settings → Import & export: bring patients in from Excel or CSV, or take
/// them out as a file.
class ImportExportSection extends ConsumerStatefulWidget {
  const ImportExportSection({super.key});

  @override
  ConsumerState<ImportExportSection> createState() =>
      _ImportExportSectionState();
}

class _ImportExportSectionState extends ConsumerState<ImportExportSection> {
  static final _count = NumberFormat.decimalPattern('en_IN');

  _Step _step = _Step.start;
  String? _notice;
  bool _busy = false;

  // Import state.
  String _fileName = '';
  Uint8List? _bytes;
  ParsedTable? _table;
  ImportMapping _mapping = {};
  bool _otherColumns = false;
  ImportPlan? _plan;
  bool _importAnyway = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  int _imported = 0;
  final List<(ImportRow, String)> _skipped = [];

  // Export state.
  ExportFormat _format = ExportFormat.excel;

  void _say(String text) => setState(() => _notice = text);

  // ------------------------------------------------------------- import

  Future<void> _pickFile() async {
    setState(() {
      _notice = null;
      _busy = true;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) {
          setState(() => _busy = false);
          _say("Couldn't open that file. Try again.");
        }
        return;
      }
      _fileName = file.name;
      _bytes = bytes;
      await _parse(0);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _say("Couldn't open that file. Try again.");
      }
    }
  }

  Future<void> _parse(int sheet) async {
    final table = await compute(
      parseTableFile,
      TableRequest(_bytes!, _fileName, sheet),
    );
    if (!mounted) return;
    if (table.error != null) {
      setState(() {
        _busy = false;
        _notice = table.error;
      });
      return;
    }
    final mapping = await loadMapping(table.headers);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _table = table;
      _mapping = mapping;
      _step = _Step.match;
    });
  }

  bool get _hasName =>
      _mapping[ImportField.firstName] != null ||
      _mapping[ImportField.lastName] != null ||
      _mapping[ImportField.fullName] != null;

  void _toPreview() {
    final existing = ref.read(patientsStreamProvider).value;
    if (existing == null) {
      _say('Still loading your patients. Try again in a moment.');
      return;
    }
    final table = _table!;
    unawaited(saveMapping(table.headers, _mapping));
    setState(() {
      _notice = null;
      _plan = buildImportPlan(
        table: table,
        mapping: _mapping,
        existing: existing,
        addOtherColumns: _otherColumns,
        now: DateTime.now(),
      );
      _importAnyway = false;
      _step = _Step.preview;
    });
  }

  Future<void> _runImport() async {
    final plan = _plan!;
    final repo = ref.read(patientRepositoryProvider);
    final now = DateTime.now();
    final todo = [
      for (final r in plan.rows)
        if (r.status == RowStatus.ready ||
            (_importAnyway && r.status == RowStatus.duplicate))
          r,
    ];
    _skipped.clear();
    for (final r in plan.rows) {
      if (r.status == RowStatus.error) {
        _skipped.add((r, r.reason ?? 'Could not be read'));
      } else if (r.status == RowStatus.duplicate && !_importAnyway) {
        _skipped.add((r, r.reason ?? 'Possible duplicate'));
      }
    }
    setState(() {
      _cancel = false;
      _done = 0;
      _imported = 0;
      _total = todo.length;
      _notice = null;
      _step = _Step.importing;
    });
    for (final r in todo) {
      if (_cancel || !mounted) {
        _skipped.add((r, 'Import cancelled'));
        continue;
      }
      try {
        await repo.createPatient(
          patientForRow(r, fileName: _fileName, now: now),
        );
        _imported++;
      } catch (_) {
        _skipped.add((r, "Couldn't be saved"));
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _step = _Step.done);
  }

  Future<void> _downloadSkipped() async {
    final table = _table!;
    final rows = <List<String>>[
      [...table.headers, 'Reason'],
      for (final (r, why) in _skipped) [...r.raw, why],
    ];
    await _deliver(
      'Skipped rows ${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
      csvBytes(rows),
    );
  }

  Future<void> _downloadSample() => _deliver(
    'CruDoc patient import sample.csv',
    csvBytes([sampleHeaders]),
  );

  Future<void> _deliver(String name, Uint8List bytes) async {
    try {
      final ok = await deliverFile(name, bytes);
      if (ok && mounted && !_isPhoneWidth) _say('Saved $name.');
    } catch (_) {
      if (mounted) _say("Couldn't save the file. Try another folder.");
    }
  }

  bool get _isPhoneWidth => cruIsPhone(context);

  void _reset() => setState(() {
    _step = _Step.start;
    _table = null;
    _bytes = null;
    _plan = null;
    _notice = null;
    _skipped.clear();
  });

  // ------------------------------------------------------------- export

  Future<void> _export(List<Patient> patients) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final now = DateTime.now();
      final bytes = encodeRows(patientExportRows(patients), _format);
      final ok = await deliverFile(exportFileName(now, _format), bytes);
      if (mounted && ok && !_isPhoneWidth) {
        _say('Saved ${exportFileName(now, _format)}.');
      }
    } catch (_) {
      if (mounted) _say("Couldn't create the file. Try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          CruCard(
            padding: const EdgeInsets.all(CruSpace.s16),
            semanticLabel: 'Notice',
            child: Row(
              children: [
                CruIcon(CruIcons.warning, size: 18, color: c.amberText),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Text(_notice!, style: CruType.text.tint(c.label)),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),
        ],
        switch (_step) {
          _Step.start => _start(context),
          _Step.match => _match(context),
          _Step.preview => _preview(context),
          _Step.importing => _importing(context),
          _Step.done => _finished(context),
        },
      ],
    );
  }

  Widget _heading(BuildContext context, String title, String? body) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: CruType.headline.tint(c.label)),
        if (body != null) ...[
          const SizedBox(height: CruSpace.s4),
          Text(body, style: CruType.text.tint(c.label2)),
        ],
      ],
    );
  }

  Widget _start(BuildContext context) {
    final c = context.cru;
    final patients = ref.watch(patientsStreamProvider).value ?? const [];
    final loaded = ref.watch(patientsStreamProvider).hasValue;
    final empty = loaded && patients.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruCard(
          semanticLabel: 'Import patients',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Import patients',
                'Bring patients from another app or an Excel sheet. Choose an '
                    '.xlsx or .csv file, match its columns, check the preview, '
                    'then import.',
              ),
              const SizedBox(height: CruSpace.s20),
              Wrap(
                spacing: CruSpace.s12,
                runSpacing: CruSpace.s12,
                children: [
                  CruButton(
                    label: _busy ? 'Reading file…' : 'Choose file',
                    icon: CruIcons.importExport,
                    onPressed: _busy ? null : _pickFile,
                  ),
                  CruButton(
                    label: 'Download sample file',
                    kind: CruButtonKind.secondary,
                    icon: CruIcons.download,
                    onPressed: _downloadSample,
                  ),
                  CruButton(
                    label: 'Copy AI prompt',
                    kind: CruButtonKind.secondary,
                    icon: CruIcons.sparkle,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: aiFormatPrompt),
                      );
                      _say(
                        'Prompt copied. Paste it into Gemini, ChatGPT or '
                        'Claude with your sheet, save the reply as a .csv '
                        'file, then choose that file here.',
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              Text(
                'Sheet not in order? Copy the AI prompt, paste it into any AI '
                'chat with your rows, and it returns a file in the format '
                'CruDoc reads. This sends patient details to that AI company: '
                'use an account with training on your data switched off.',
                style: CruType.text.tint(context.cru.label2),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        CruCard(
          semanticLabel: 'Export patients',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Export patients',
                'A file of your patients: names, phones, dates of birth, '
                    'diagnoses and notes.',
              ),
              const SizedBox(height: CruSpace.s16),
              Align(
                alignment: Alignment.centerLeft,
                child: CruSegmentedControl<ExportFormat>(
                  semanticLabel: 'File format',
                  segments: [
                    for (final f in ExportFormat.values)
                      CruSegment(f, f.label),
                  ],
                  selected: _format,
                  onChanged: (f) => setState(() => _format = f),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              Wrap(
                spacing: CruSpace.s12,
                runSpacing: CruSpace.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CruButton(
                    label: 'Export patients',
                    kind: CruButtonKind.secondary,
                    icon: CruIcons.download,
                    onPressed: _busy || !loaded || empty
                        ? null
                        : () => _export(patients),
                  ),
                  if (empty)
                    Text(
                      'No patients to export',
                      style: CruType.text.tint(c.label3),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _match(BuildContext context) {
    final c = context.cru;
    final table = _table!;
    final columns = [-1, for (var i = 0; i < table.headers.length; i++) i];
    String sample(int? i) {
      if (i == null) return '';
      final values = [
        for (final r in table.rows)
          if (r[i].isNotEmpty) r[i],
      ].take(3);
      return values.join('  ·  ');
    }

    return CruCard(
      semanticLabel: 'Match columns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'Match columns',
            '$_fileName · ${_count.format(table.rows.length)} rows. Pick the '
                "column for each CruDoc field. Fields you don't match stay "
                'blank.',
          ),
          if (table.sheetNames.length > 1) ...[
            const SizedBox(height: CruSpace.s16),
            CruDropdownField<int>(
              label: 'Sheet',
              value: table.sheet,
              items: [for (var i = 0; i < table.sheetNames.length; i++) i],
              itemLabel: (i) => table.sheetNames[i],
              onChanged: _busy
                  ? null
                  : (i) async {
                      setState(() => _busy = true);
                      await _parse(i);
                    },
            ),
          ],
          for (final f in ImportField.values) ...[
            const SizedBox(height: CruSpace.s16),
            CruDropdownField<int>(
              label: f.label,
              value: _mapping[f] ?? -1,
              items: columns,
              itemLabel: (i) => i < 0 ? 'Not in file' : table.headers[i],
              help: sample(_mapping[f]).isEmpty ? null : sample(_mapping[f]),
              onChanged: (i) => setState(() {
                final next = Map<ImportField, int?>.of(_mapping);
                if (i >= 0) {
                  // A column feeds one field.
                  for (final e in next.entries) {
                    if (e.value == i) next[e.key] = null;
                  }
                }
                next[f] = i < 0 ? null : i;
                _mapping = next;
              }),
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          Text(
            'Age, address and old patient ID have no field in CruDoc: they go '
            'into the patient\'s notes.',
            style: CruType.caption.tint(c.label3),
          ),
          const SizedBox(height: CruSpace.s8),
          CruSwitchRow(
            title: 'Add other columns to notes',
            value: _otherColumns,
            onChanged: (v) => setState(() => _otherColumns = v),
          ),
          const SizedBox(height: CruSpace.s20),
          Wrap(
            spacing: CruSpace.s12,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CruButton(
                label: 'Back',
                kind: CruButtonKind.inset,
                onPressed: _reset,
              ),
              CruButton(
                label: 'Preview',
                onPressed: _hasName ? _toPreview : null,
              ),
              if (!_hasName)
                Text(
                  'Match a name column to continue',
                  style: CruType.text.tint(c.label3),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ImportRow r) {
    final c = context.cru;
    return switch (r.status) {
      RowStatus.ready => CruChip(
        value: 'Ready',
        background: c.greenTint,
        foreground: c.greenText,
      ),
      RowStatus.duplicate => CruChip(
        value: 'Duplicate',
        background: c.amberTint,
        foreground: c.amberText,
      ),
      RowStatus.error => CruChip(
        value: 'Error',
        icon: CruIcons.warning,
        background: c.inset,
        foreground: c.label2,
      ),
    };
  }

  Widget _preview(BuildContext context) {
    final c = context.cru;
    final plan = _plan!;
    final toImport = plan.ready + (_importAnyway ? plan.duplicates : 0);
    return CruCard(
      semanticLabel: 'Preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context, 'Preview', null),
          const SizedBox(height: CruSpace.s12),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              CruChip(
                value: '${_count.format(plan.ready)} ready',
                background: c.greenTint,
                foreground: c.greenText,
              ),
              CruChip(
                value: '${_count.format(plan.duplicates)} possible duplicates',
                background: c.amberTint,
                foreground: c.amberText,
              ),
              if (plan.noDob > 0)
                CruChip(
                  value:
                      'No date of birth or age: ${_count.format(plan.noDob)} '
                      "— saved with today's date; fill in later",
                  background: c.amberTint,
                  foreground: c.amberText,
                ),
              CruChip(
                value: '${_count.format(plan.errors)} errors',
                icon: CruIcons.warning,
                background: c.inset,
                foreground: c.label2,
              ),
            ],
          ),
          if (plan.duplicates > 0) ...[
            const SizedBox(height: CruSpace.s12),
            CruSwitchRow(
              title: 'Import possible duplicates anyway',
              subtitle:
                  'Off: rows with a phone number you already have, or that '
                  'repeats in the file, are skipped.',
              value: _importAnyway,
              onChanged: (v) => setState(() => _importAnyway = v),
            ),
          ],
          if (plan.errors > 0) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              'Rows with no name are skipped.',
              style: CruType.caption.tint(c.label3),
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          Text(
            plan.rows.length > 50
                ? 'FIRST 50 OF ${_count.format(plan.rows.length)} ROWS'
                : 'ROWS',
            style: CruType.groupLabel.tint(c.label3),
          ),
          const SizedBox(height: CruSpace.s8),
          for (final r in plan.rows.take(50)) _previewRow(context, r),
          const SizedBox(height: CruSpace.s20),
          Wrap(
            spacing: CruSpace.s12,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CruButton(
                label: 'Back',
                kind: CruButtonKind.inset,
                onPressed: () => setState(() => _step = _Step.match),
              ),
              CruButton(
                label: toImport == 0
                    ? 'Import'
                    : 'Import ${_count.format(toImport)} '
                          '${toImport == 1 ? 'patient' : 'patients'}',
                onPressed: toImport == 0 ? null : _runImport,
              ),
              if (toImport == 0)
                Text(
                  'Nothing to import',
                  style: CruType.text.tint(c.label3),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewRow(BuildContext context, ImportRow r) {
    final c = context.cru;
    final detail = [
      if (r.phone.isNotEmpty) r.phone,
      if (r.reason != null) r.reason!,
      ...r.warnings,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.cardBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${r.number}',
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.displayName.isEmpty ? 'No name' : r.displayName,
                  style: CruType.row.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: CruType.caption.tabular.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          if (r.lacksDobAndAge) ...[
            CruChip(
              value: 'No DOB',
              background: c.amberTint,
              foreground: c.amberText,
            ),
            const SizedBox(width: CruSpace.s4),
          ],
          _statusChip(context, r),
        ],
      ),
    );
  }

  Widget _importing(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Importing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'Importing ${_count.format(_done)} / ${_count.format(_total)}',
            'Keep this page open until it finishes.',
          ),
          const SizedBox(height: CruSpace.s16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _total == 0 ? 0 : _done / _total,
              minHeight: 6,
              backgroundColor: c.inset,
              color: c.accent,
            ),
          ),
          const SizedBox(height: CruSpace.s20),
          Align(
            alignment: Alignment.centerLeft,
            child: CruButton(
              label: _cancel ? 'Stopping…' : 'Cancel',
              kind: CruButtonKind.inset,
              onPressed: _cancel ? null : () => setState(() => _cancel = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finished(BuildContext context) {
    final c = context.cru;
    final failed = _skipped
        .where((s) => s.$2 == "Couldn't be saved" || s.$2 == 'Import cancelled')
        .length;
    final skipped = _skipped.length - failed;
    Widget stat(String label, int n) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _count.format(n),
            style: CruType.title.tabular.tint(c.label),
          ),
          Text(label, style: CruType.text.tint(c.label2)),
        ],
      ),
    );
    return CruCard(
      semanticLabel: 'Import finished',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            _cancel ? 'Import stopped' : 'Import finished',
            _cancel ? 'Patients already imported stay in CruDoc.' : null,
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            children: [
              stat('Imported', _imported),
              stat('Skipped', skipped),
              stat('Not imported', failed),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          Wrap(
            spacing: CruSpace.s12,
            runSpacing: CruSpace.s8,
            children: [
              CruButton(label: 'Done', onPressed: _reset),
              if (_skipped.isNotEmpty)
                CruButton(
                  label: 'Download skipped rows',
                  kind: CruButtonKind.secondary,
                  icon: CruIcons.download,
                  onPressed: _downloadSkipped,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
