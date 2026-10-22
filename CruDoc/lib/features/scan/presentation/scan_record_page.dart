import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scan/data/record_pdf.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/data/scan_reader.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A paper report, prescription or letter made digital: the AI says what it
/// is, names it, pulls out the results and writes it up. Saved to the
/// patient's files as one PDF — the typed record, then the scanned pages.
class ScanRecordPage extends StatefulWidget {
  const ScanRecordPage({super.key, required this.pages, required this.patient});

  final List<ScannedPage> pages;
  final Patient patient;

  @override
  State<ScanRecordPage> createState() => _ScanRecordPageState();
}

class _ScanRecordPageState extends State<ScanRecordPage> {
  final _reader = ScanReader();
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _summary = TextEditingController();

  ScannedRecord? _record;
  String? _error;
  String _kind = 'Other';
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _error = null;
      _record = null;
    });
    try {
      final record = await _reader.readRecord(widget.pages);
      if (!mounted) return;
      _title.text = record.title.isEmpty ? record.kind : record.title;
      _source.text = record.source;
      _summary.text = record.summary;
      setState(() {
        _record = record;
        _kind = record.kind;
        _date = record.date;
      });
    } on ScanReadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickKind() => showMobileActionSheet(
    context,
    title: 'What is it?',
    actions: [
      for (final k in ScanReader.recordKinds)
        MobileSheetAction(
          label: k,
          icon: k == _kind ? CruIcons.check : CruIcons.fileText,
          tone: k == _kind ? MobileTone.blue : MobileTone.slate,
          onTap: () => setState(() => _kind = k),
        ),
    ],
  );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null || _saving) return;
    final title = _title.text.trim().isEmpty ? _kind : _title.text.trim();
    setState(() => _saving = true);
    final root = mobileRoot(context);
    try {
      final pdf = await RecordPdf.build(
        title: title,
        kind: _kind,
        date: _date,
        source: _source.text.trim(),
        summary: _summary.text.trim(),
        findings: record.findings,
        patientName: widget.patient.fullName,
        pages: widget.pages,
      );
      final name = '${FilesRepository.cleanName(title)}.pdf';
      final ids = await FilesRepository.instance.addFilesWithIds([
        FileSource(name: name, sizeBytes: pdf.lengthInBytes, bytes: pdf),
      ], patientId: widget.patient.id);
      if (ids.isEmpty) throw StateError('the file was not added');
      final file = await FilesRepository.instance.file(ids.first);
      if (!mounted || !root.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(root)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text("Saved to ${widget.patient.firstName}'s files."),
            action: file == null
                ? null
                : SnackBarAction(
                    label: 'Open',
                    onPressed: () => FilesActions.open(
                      root,
                      file,
                      patientName: widget.patient.fullName,
                    ),
                  ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      mobileSay(context, "Couldn't save the record: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final error = _error;
    final c = context.cru;
    return ScanScaffold(
      title: 'Patient record',
      subtitle: widget.patient.fullName,
      bottom: record == null
          ? null
          : MobilePrimaryButton(
              label: _saving ? 'Saving…' : 'Save to patient files',
              icon: CruIcons.fileText,
              onPressed: _saving ? null : _save,
            ),
      children: [
        if (error != null)
          ScanProblem(message: error, onRetry: _read)
        else if (record == null)
          ScanReading(
            page: widget.pages.first,
            label: 'Reading the document…',
          )
        else ...[
          ScanAiNote(
            text:
                'Digitised by AI. Check it before saving — the scanned pages '
                'are saved with it.',
            unclear: record.unclear,
          ),
          MobileRowGroup(
            indent: CruSpace.s16,
            children: [
              MobileRow(
                title: 'Type',
                trailing: Text(_kind, style: MobileType.row.tint(c.label2)),
                chevron: true,
                onTap: _saving ? null : _pickKind,
              ),
              MobileRow(
                title: 'Date',
                trailing: Text(
                  _date == null
                      ? 'Not printed'
                      : DateFormat('d MMM yyyy').format(_date!),
                  style: MobileType.row.tabular.tint(c.label2),
                ),
                chevron: true,
                onTap: _saving ? null : _pickDate,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileMetrics.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScanTextField(
                  label: 'File name',
                  controller: _title,
                  enabled: !_saving,
                ),
                const SizedBox(height: CruSpace.s12),
                ScanTextField(
                  label: 'From',
                  controller: _source,
                  enabled: !_saving,
                  hint: 'Lab, hospital or doctor',
                ),
                const SizedBox(height: CruSpace.s12),
                ScanTextField(
                  label: 'Summary',
                  controller: _summary,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  enabled: !_saving,
                ),
              ],
            ),
          ),
          if (record.findings.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s12),
            MobileRowGroup(
              title: 'Results',
              indent: CruSpace.s16,
              children: [
                for (final f in record.findings)
                  MobileRow(
                    title: f.name,
                    subtitle: f.range.isEmpty ? null : 'Range ${f.range}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          [f.value, f.unit].where((s) => s.isNotEmpty).join(' '),
                          style: MobileType.row.tabular
                              .copyWith(fontWeight: FontWeight.w600)
                              .tint(c.label),
                        ),
                        if (f.flag.isNotEmpty) ...[
                          const SizedBox(width: CruSpace.s8),
                          MobilePill(
                            f.flag == 'high' ? 'High' : 'Low',
                            tone: MobileTone.amber,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          const MobileGroupTitle('Scanned pages', onBackground: true),
          const SizedBox(height: CruSpace.s8),
          ScanPagesStrip(pages: widget.pages),
        ],
      ],
    );
  }
}
