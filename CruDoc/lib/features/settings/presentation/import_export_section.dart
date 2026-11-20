import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/patient_export.dart';
import 'package:doctor_management_app/features/patients/data/patient_import.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/data/visit_import.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Step { start, match, preview, importing, done }

/// What the wizard is importing. The file step, the column step and the
/// preview are the same either way; what differs is which fields a column
/// can feed and what each ready row becomes.
enum _ImportKind {
  patients('patient', 'patients'),
  visits('visit', 'visits');

  const _ImportKind(this.one, this.many);
  final String one;
  final String many;

  String count(int n) => n == 1 ? one : many;
}

/// A row as the preview shows it, whichever kind is being imported.
class _PreviewLine {
  const _PreviewLine({
    required this.number,
    required this.raw,
    required this.status,
    required this.title,
    required this.detail,
    required this.flag,
    this.reason,
  });

  final int number;
  final List<String> raw;
  final RowStatus status;
  final String title;

  /// The line under the title in the preview.
  final String detail;

  /// Why the row is a duplicate or an error, on its own: this is what the
  /// skipped-rows file carries, so it is not mixed with the row's own values.
  final String? reason;

  /// A short amber chip for something the row is missing, or null.
  final String? flag;
}

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
  static final _visitDate = DateFormat('d MMM yyyy');

  _Step _step = _Step.start;
  String? _notice;
  bool _busy = false;

  // Import state.
  String _fileName = '';
  Uint8List? _bytes;
  ParsedTable? _table;
  _ImportKind _kind = _ImportKind.patients;
  _ImportKind _startKind = _ImportKind.patients;
  ImportMapping _mapping = {};
  VisitImportMapping _visitMapping = {};
  bool _otherColumns = false;
  ImportPlan? _plan;
  VisitImportPlan? _visitPlan;
  bool _importAnyway = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  int _imported = 0;
  final List<({int number, List<String> raw, String why})> _skipped = [];

  // Export state.
  ExportFormat _format = ExportFormat.excel;

  void _say(String text) => setState(() => _notice = text);

  // ------------------------------------------------------------- import

  Future<void> _pickFile(_ImportKind kind) async {
    setState(() {
      _kind = kind;
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
      await _parse(-1);
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
    final mapping = _kind == _ImportKind.patients
        ? await loadMapping(table.headers)
        : null;
    final visitMapping = _kind == _ImportKind.visits
        ? await loadVisitMapping(table.headers)
        : null;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _table = table;
      if (mapping != null) _mapping = mapping;
      if (visitMapping != null) _visitMapping = visitMapping;
      _step = _Step.match;
    });
  }

  bool get _hasName =>
      _mapping[ImportField.firstName] != null ||
      _mapping[ImportField.lastName] != null ||
      _mapping[ImportField.fullName] != null;

  /// A visit row needs a date, and some column that says whose visit it is.
  bool get _hasVisitKeys =>
      _visitMapping[VisitImportField.date] != null &&
      VisitImportField.patientKeys.any((f) => _visitMapping[f] != null);

  bool get _canPreview =>
      _kind == _ImportKind.patients ? _hasName : _hasVisitKeys;

  /// What the match step says is still missing, or null when it can go on.
  String? get _missingForPreview {
    if (_canPreview) return null;
    if (_kind == _ImportKind.patients) return 'Match a name column to continue';
    if (_visitMapping[VisitImportField.date] == null) {
      return 'Match the visit date column to continue';
    }
    return 'Match a patient ID, phone or name column to continue';
  }

  void _toPreview() {
    final existing = ref.read(patientsStreamProvider).value;
    if (existing == null) {
      _say('Still loading your patients. Try again in a moment.');
      return;
    }
    final table = _table!;
    if (_kind == _ImportKind.patients) {
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
      return;
    }

    if (existing.isEmpty) {
      _say(
        'Import your patients first: a visit can only be added to a patient '
        'who is already in CruDoc.',
      );
      return;
    }
    final visits = ref.read(allVisitsProvider).value;
    if (visits == null) {
      _say('Still loading your visits. Try again in a moment.');
      return;
    }
    unawaited(saveVisitMapping(table.headers, _visitMapping));
    setState(() {
      _notice = null;
      _visitPlan = buildVisitPlan(
        table: table,
        mapping: _visitMapping,
        existingPatients: existing,
        existingVisitDays: {
          for (final v in visits)
            if (!v.isDeleted) visitDayKey(v.patientId, v.scheduledStart),
        },
        now: DateTime.now(),
      );
      _importAnyway = false;
      _step = _Step.preview;
    });
  }

  /// The rows of whichever plan is in hand, as the preview shows them.
  List<_PreviewLine> get _lines {
    if (_kind == _ImportKind.patients) {
      return [
        for (final r in _plan!.rows)
          _PreviewLine(
            number: r.number,
            raw: r.raw,
            status: r.status,
            title: r.displayName.isEmpty ? 'No name' : r.displayName,
            detail: [
              if (r.phone.isNotEmpty) r.phone,
              if (r.reason != null) r.reason!,
              ...r.warnings,
            ].join(' · '),
            flag: r.lacksDobAndAge ? 'No DOB' : null,
            reason: r.reason,
          ),
      ];
    }
    return [
      for (final r in _visitPlan!.rows)
        _PreviewLine(
          number: r.number,
          raw: r.raw,
          status: r.status,
          title: r.displayName.isEmpty ? 'No patient' : r.displayName,
          detail: [
            if (r.start != null) _visitDate.format(r.start!),
            if (r.start != null) r.visitStatus.name,
            if (r.treatment.isNotEmpty) r.treatment,
            if (r.reason != null) r.reason!,
            ...r.warnings,
          ].join(' · '),
          flag: r.status != RowStatus.error && !r.hadTime ? 'No time' : null,
          reason: r.reason,
        ),
    ];
  }

  int get _readyCount =>
      _kind == _ImportKind.patients ? _plan!.ready : _visitPlan!.ready;

  int get _duplicateCount => _kind == _ImportKind.patients
      ? _plan!.duplicates
      : _visitPlan!.duplicates;

  int get _errorCount =>
      _kind == _ImportKind.patients ? _plan!.errors : _visitPlan!.errors;

  Future<void> _runImport() async {
    final now = DateTime.now();
    // Driven by row number rather than by row, so one loop saves either
    // kind and the skipped-rows file reads the same way for both.
    final lines = _lines;
    final byNumber = {for (final l in lines) l.number: l};
    final todo = [
      for (final l in lines)
        if (l.status == RowStatus.ready ||
            (_importAnyway && l.status == RowStatus.duplicate))
          l.number,
    ];
    _skipped.clear();
    for (final l in lines) {
      if (l.status == RowStatus.error) {
        _skipped.add((
          number: l.number,
          raw: l.raw,
          why: l.reason ?? 'Could not be read',
        ));
      } else if (l.status == RowStatus.duplicate && !_importAnyway) {
        _skipped.add((
          number: l.number,
          raw: l.raw,
          why: l.reason ?? 'Possible duplicate',
        ));
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

    final patientRows = _kind == _ImportKind.patients
        ? {for (final r in _plan!.rows) r.number: r}
        : const <int, ImportRow>{};
    final visitRows = _kind == _ImportKind.visits
        ? {for (final r in _visitPlan!.rows) r.number: r}
        : const <int, VisitImportRow>{};
    final patientRepo = ref.read(patientRepositoryProvider);
    final visitRepo = ref.read(visitRepositoryProvider);

    for (final number in todo) {
      final line = byNumber[number]!;
      if (_cancel || !mounted) {
        _skipped.add((number: number, raw: line.raw, why: 'Import cancelled'));
        continue;
      }
      try {
        if (_kind == _ImportKind.patients) {
          await patientRepo.createPatient(
            patientForRow(patientRows[number]!, fileName: _fileName, now: now),
          );
        } else {
          await visitRepo.importVisit(
            visitForRow(visitRows[number]!, fileName: _fileName, now: now),
          );
        }
        _imported++;
      } catch (_) {
        _skipped.add((number: number, raw: line.raw, why: "Couldn't be saved"));
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
      for (final s in _skipped) [...s.raw, s.why],
    ];
    await _deliver(
      'Skipped rows ${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
      csvBytes(rows),
    );
  }

  Future<void> _downloadSample() =>
      _deliver('CruDoc patient import sample.csv', csvBytes([sampleHeaders]));

  Future<void> _downloadVisitSample() => _deliver(
    'CruDoc visit history sample.csv',
    csvBytes([visitSampleHeaders]),
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
    _visitPlan = null;
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
    final isVisits = _startKind == _ImportKind.visits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruCard(
          semanticLabel: 'Import',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(
                context,
                'Import',
                isVisits
                    ? 'Bring past visits in from your old software. Each row '
                          'is matched to a patient already here, so import your '
                          'patients first.'
                    : 'Bring patients from another app or an Excel sheet. '
                          'Choose an .xlsx or .csv file, match its columns, '
                          'check the preview, then import.',
              ),
              const SizedBox(height: CruSpace.s16),
              Align(
                alignment: Alignment.centerLeft,
                child: CruSegmentedControl<_ImportKind>(
                  semanticLabel: 'What to import',
                  segments: const [
                    CruSegment(_ImportKind.patients, 'Patients'),
                    CruSegment(_ImportKind.visits, 'Visit history'),
                  ],
                  selected: _startKind,
                  onChanged: (k) => setState(() => _startKind = k),
                ),
              ),
              const SizedBox(height: CruSpace.s20),
              Wrap(
                spacing: CruSpace.s12,
                runSpacing: CruSpace.s12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CruButton(
                    label: _busy ? 'Reading file…' : 'Choose file',
                    icon: CruIcons.importExport,
                    onPressed: _busy || (isVisits && empty)
                        ? null
                        : () => _pickFile(_startKind),
                  ),
                  CruButton(
                    label: 'Download sample file',
                    kind: CruButtonKind.secondary,
                    icon: CruIcons.download,
                    onPressed: isVisits
                        ? _downloadVisitSample
                        : _downloadSample,
                  ),
                  if (!isVisits)
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
                  if (isVisits && empty)
                    Text(
                      'Import your patients first',
                      style: CruType.text.tint(c.label3),
                    ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              Text(
                isVisits
                    ? 'A visit needs a date and some way to say whose it is: '
                          'the patient ID from your old software, a phone '
                          'number or a name. Visits in the past are saved as '
                          'completed unless the file says otherwise. Nobody is '
                          'messaged about an imported visit.'
                    : 'Sheet not in order? Copy the AI prompt, paste it into '
                          'any AI chat with your rows, and it returns a file in '
                          'the format CruDoc reads. This sends patient details '
                          'to that AI company: use an account with training on '
                          'your data switched off.',
                style: CruType.text.tint(c.label2),
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
                    for (final f in ExportFormat.values) CruSegment(f, f.label),
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
          ..._columnPickers(context, table, columns, sample),
          const SizedBox(height: CruSpace.s16),
          if (_kind == _ImportKind.patients) ...[
            Text(
              'Age and address have no field of their own in CruDoc: they go '
              'into the patient\'s notes.',
              style: CruType.caption.tint(c.label3),
            ),
            const SizedBox(height: CruSpace.s8),
            CruSwitchRow(
              title: 'Add other columns to notes',
              value: _otherColumns,
              onChanged: (v) => setState(() => _otherColumns = v),
            ),
          ] else
            Text(
              'Each visit is matched to a patient already in CruDoc, by the ID '
              'from your old software first, then phone, then name. A row '
              'that matches nobody is listed in the preview and skipped.',
              style: CruType.caption.tint(c.label3),
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
                onPressed: _canPreview ? _toPreview : null,
              ),
              if (_missingForPreview != null)
                Text(_missingForPreview!, style: CruType.text.tint(c.label3)),
            ],
          ),
        ],
      ),
    );
  }

  /// One dropdown per field of whichever kind is being imported. A column
  /// feeds one field, so picking it clears it from wherever it was before.
  List<Widget> _columnPickers(
    BuildContext context,
    ParsedTable table,
    List<int> columns,
    String Function(int?) sample,
  ) {
    Widget picker({
      required String label,
      required int? value,
      required void Function(int?) onPicked,
    }) => Padding(
      padding: const EdgeInsets.only(top: CruSpace.s16),
      child: CruDropdownField<int>(
        label: label,
        value: value ?? -1,
        items: columns,
        itemLabel: (i) => i < 0 ? 'Not in file' : table.headers[i],
        help: sample(value).isEmpty ? null : sample(value),
        onChanged: (i) => onPicked(i < 0 ? null : i),
      ),
    );

    if (_kind == _ImportKind.patients) {
      return [
        for (final f in ImportField.values)
          picker(
            label: f.label,
            value: _mapping[f],
            onPicked: (col) => setState(() {
              final next = Map<ImportField, int?>.of(_mapping);
              if (col != null) {
                for (final e in next.entries) {
                  if (e.value == col) next[e.key] = null;
                }
              }
              next[f] = col;
              _mapping = next;
            }),
          ),
      ];
    }
    return [
      for (final f in VisitImportField.values)
        picker(
          label: f.label,
          value: _visitMapping[f],
          onPicked: (col) => setState(() {
            final next = Map<VisitImportField, int?>.of(_visitMapping);
            if (col != null) {
              for (final e in next.entries) {
                if (e.value == col) next[e.key] = null;
              }
            }
            next[f] = col;
            _visitMapping = next;
          }),
        ),
    ];
  }

  Widget _statusChip(BuildContext context, RowStatus status) {
    final c = context.cru;
    return switch (status) {
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
    final lines = _lines;
    final toImport = _readyCount + (_importAnyway ? _duplicateCount : 0);
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
                value: '${_count.format(_readyCount)} ready',
                background: c.greenTint,
                foreground: c.greenText,
              ),
              CruChip(
                value: '${_count.format(_duplicateCount)} possible duplicates',
                background: c.amberTint,
                foreground: c.amberText,
              ),
              if (_kind == _ImportKind.patients && _plan!.noDob > 0)
                CruChip(
                  value:
                      'No date of birth or age: '
                      '${_count.format(_plan!.noDob)} '
                      "— saved with today's date; fill in later",
                  background: c.amberTint,
                  foreground: c.amberText,
                ),
              if (_kind == _ImportKind.visits && _visitPlan!.patients > 0)
                CruChip(
                  value:
                      '${_count.format(_visitPlan!.patients)} '
                      '${_visitPlan!.patients == 1 ? 'patient' : 'patients'}',
                  background: c.inset,
                  foreground: c.label2,
                ),
              if (_kind == _ImportKind.visits && _visitPlan!.noTime > 0)
                CruChip(
                  value:
                      'No time: ${_count.format(_visitPlan!.noTime)} '
                      '— saved at $kVisitImportDefaultHour:00',
                  background: c.amberTint,
                  foreground: c.amberText,
                ),
              CruChip(
                value: '${_count.format(_errorCount)} errors',
                icon: CruIcons.warning,
                background: c.inset,
                foreground: c.label2,
              ),
            ],
          ),
          if (_duplicateCount > 0) ...[
            const SizedBox(height: CruSpace.s12),
            CruSwitchRow(
              title: 'Import possible duplicates anyway',
              value: _importAnyway,
              onChanged: (v) => setState(() => _importAnyway = v),
            ),
          ],
          if (_errorCount > 0) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              _kind == _ImportKind.patients
                  ? 'Rows with no name are skipped.'
                  : 'Rows with no date, or that match no patient here, are '
                        'skipped. Download them at the end to fix and run '
                        'again.',
              style: CruType.caption.tint(c.label3),
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          Text(
            lines.length > 50
                ? 'FIRST 50 OF ${_count.format(lines.length)} ROWS'
                : 'ROWS',
            style: CruType.groupLabel.tint(c.label3),
          ),
          const SizedBox(height: CruSpace.s8),
          for (final l in lines.take(50)) _previewRow(context, l),
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
                          '${_kind.count(toImport)}',
                onPressed: toImport == 0 ? null : _runImport,
              ),
              if (toImport == 0)
                Text('Nothing to import', style: CruType.text.tint(c.label3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewRow(BuildContext context, _PreviewLine line) {
    final c = context.cru;
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
              '${line.number}',
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  style: CruType.row.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (line.detail.isNotEmpty)
                  Text(
                    line.detail,
                    style: CruType.caption.tabular.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          if (line.flag != null) ...[
            CruChip(
              value: line.flag!,
              background: c.amberTint,
              foreground: c.amberText,
            ),
            const SizedBox(width: CruSpace.s4),
          ],
          _statusChip(context, line.status),
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
            'Importing ${_kind.many} '
                '${_count.format(_done)} / ${_count.format(_total)}',
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
        .where(
          (s) => s.why == "Couldn't be saved" || s.why == 'Import cancelled',
        )
        .length;
    final skipped = _skipped.length - failed;
    Widget stat(String label, int n) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_count.format(n), style: CruType.title.tabular.tint(c.label)),
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
            _cancel
                ? 'The ${_kind.many} already imported stay in CruDoc.'
                : null,
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
