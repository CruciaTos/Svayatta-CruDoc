import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/data/scan_reader.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_flow.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Handwritten session notes, read by the AI and written up properly:
/// shorthand expanded, phrasing tidied, headings and lists. The doctor
/// checks and edits the write-up, picks the session it belongs to, and it
/// joins the patient's session history with the photographed pages kept
/// beside it in their files.
class ScanNotePage extends ConsumerStatefulWidget {
  const ScanNotePage({super.key, required this.pages, required this.patient});

  final List<ScannedPage> pages;
  final Patient patient;

  @override
  ConsumerState<ScanNotePage> createState() => _ScanNotePageState();
}

class _ScanNotePageState extends ConsumerState<ScanNotePage> {
  final _reader = ScanReader();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  ScannedNote? _note;
  String? _error;
  bool _saving = false;
  bool _showWritten = false;

  /// The patient's recent visits, newest first.
  List<Visit> _visits = const [];

  /// The session the note belongs to; null: not tied to a visit.
  Visit? _visit;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _loadVisits();
    await _read();
  }

  Future<void> _loadVisits() async {
    try {
      final all = await ref
          .read(visitRepositoryProvider)
          .watchVisitsForPatient(widget.patient.id)
          .first
          .timeout(const Duration(seconds: 4));
      final now = DateTime.now();
      final recent =
          all
              .where(
                (v) =>
                    !v.isDeleted &&
                    v.status != VisitStatus.cancelled &&
                    v.scheduledStart.isBefore(now.add(const Duration(days: 1))),
              )
              .toList()
            ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      // Today's visit (the nearest to now) unless the doctor picks another.
      Visit? today;
      for (final v in recent) {
        if (DateUtils.isSameDay(v.scheduledStart, now)) {
          if (today == null ||
              v.scheduledStart.difference(now).abs() <
                  today.scheduledStart.difference(now).abs()) {
            today = v;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _visits = recent.take(12).toList();
        _visit = today;
      });
    } catch (e) {
      debugPrint('[ScanNote] visits unavailable: $e');
    }
  }

  Future<void> _read() async {
    setState(() {
      _error = null;
      _note = null;
    });
    try {
      final note = await _reader.readSessionNote(
        widget.pages,
        sessionDate: _visit?.scheduledStart ?? DateTime.now(),
      );
      if (!mounted) return;
      _title.text = note.title;
      _notes.text = note.notes;
      setState(() => _note = note);
    } on ScanReadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _visitLabel(Visit? v) {
    if (v == null) return 'Not tied to a visit · dated today';
    final day = DateUtils.isSameDay(v.scheduledStart, DateTime.now())
        ? 'Today'
        : DateFormat('EEE d MMM').format(v.scheduledStart);
    final reason = v.treatmentType?.trim() ?? '';
    return [
      day,
      DateFormat('h:mm a').format(v.scheduledStart),
      if (reason.isNotEmpty) reason,
    ].join(' · ');
  }

  Future<void> _pickVisit() async {
    await showMobileActionSheet(
      context,
      title: 'Which session?',
      subtitle: widget.patient.fullName,
      actions: [
        for (final v in _visits)
          MobileSheetAction(
            label: _visitLabel(v),
            icon: v.id == _visit?.id ? CruIcons.check : CruIcons.calendar,
            tone: v.id == _visit?.id ? MobileTone.blue : MobileTone.slate,
            onTap: () => setState(() => _visit = v),
          ),
        MobileSheetAction(
          label: 'Not tied to a visit',
          detail: 'Saved in session history with today’s date',
          icon: _visit == null ? CruIcons.check : CruIcons.pen,
          tone: _visit == null ? MobileTone.blue : MobileTone.slate,
          onTap: () => setState(() => _visit = null),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final note = _note;
    final text = _notes.text.trim();
    if (note == null || _saving) return;
    if (text.isEmpty) {
      mobileSay(context, 'The session note is empty.');
      return;
    }
    setState(() => _saving = true);
    final root = mobileRoot(context);
    try {
      final when = _visit?.scheduledStart ?? DateTime.now();
      // The pages first: the note points at them.
      final fileIds = await FilesRepository.instance.addFilesWithIds(
        scanFileSources(
          widget.pages,
          'Session note ${DateFormat('d MMM yyyy').format(when)}',
        ),
        patientId: widget.patient.id,
      );
      final saved = await ref
          .read(consultationNoteRepositoryProvider)
          .saveSessionNote(
            ConsultationNote(
              id: const Uuid().v4(),
              doctorId: '',
              patientId: widget.patient.id,
              visitId: _visit?.id ?? '',
              transcript: note.transcript,
              notes: text,
              chiefComplaint: _title.text.trim(),
              scanFileIds: fileIds,
              createdAt: when,
            ),
          );
      if (!mounted || !root.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(root)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              "Saved to ${widget.patient.firstName}'s session notes, "
              'with the scanned pages.',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () =>
                  openSessionNote(root, note: saved, patient: widget.patient),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      mobileSay(context, "Couldn't save the session note: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final error = _error;
    return ScanScaffold(
      title: 'Session note',
      subtitle: widget.patient.fullName,
      bottom: note == null
          ? null
          : MobilePrimaryButton(
              label: _saving ? 'Saving…' : 'Save to session notes',
              icon: CruIcons.check,
              onPressed: _saving ? null : _save,
            ),
      children: [
        if (error != null)
          ScanProblem(message: error, onRetry: _read)
        else if (note == null)
          ScanReading(
            page: widget.pages.first,
            label: 'Reading the handwriting…',
          )
        else ...[
          ScanAiNote(
            text:
                'Written up by AI from the handwriting. Check it before '
                'saving.',
            unclear: note.unclear,
          ),
          MobileRowGroup(
            indent: CruSpace.s16,
            children: [
              MobileRow(
                title: 'Session',
                subtitle: _visitLabel(_visit),
                chevron: true,
                onTap: _saving ? null : _pickVisit,
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
                  label: 'Title',
                  controller: _title,
                  enabled: !_saving,
                ),
                const SizedBox(height: CruSpace.s12),
                ScanTextField(
                  label: 'Session note',
                  controller: _notes,
                  minLines: 10,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  enabled: !_saving,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          const MobileGroupTitle('Scanned pages', onBackground: true),
          const SizedBox(height: CruSpace.s8),
          ScanPagesStrip(pages: widget.pages),
          if (note.transcript.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter,
              ),
              child: MobileCard(
                padding: const EdgeInsets.all(CruSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'As written',
                            style: MobileType.headline.tint(context.cru.label),
                          ),
                        ),
                        CruLink(
                          label: _showWritten ? 'Hide' : 'Show',
                          onPressed: () =>
                              setState(() => _showWritten = !_showWritten),
                        ),
                      ],
                    ),
                    if (_showWritten) ...[
                      const SizedBox(height: CruSpace.s8),
                      SelectableText(
                        note.transcript,
                        style: MobileType.text.tint(context.cru.label2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
