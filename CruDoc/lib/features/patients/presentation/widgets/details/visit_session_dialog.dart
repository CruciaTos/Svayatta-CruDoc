import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart'
    show DentalPanelDialog;
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_files_provider.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/prescription_generation_sheet.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_recording_sheet.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_photos_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One column: notes and files read best at this width.
const double _dialogWidth = 600;

/// Typing pauses this long before the session note saves itself.
const Duration _autosaveDelay = Duration(milliseconds: 900);

/// Opens one visit of the patient: how it went, the session note (typed
/// or transcribed with Scribe), Scribe's notes, the files added for it,
/// and the prescription, bill and photos for this session.
Future<void> showVisitSessionDialog(
  BuildContext context, {
  required Visit visit,
  required Patient patient,
}) => showDialog<void>(
  context: context,
  builder: (_) => VisitSessionDialog(visit: visit, patient: patient),
);

class VisitSessionDialog extends ConsumerStatefulWidget {
  const VisitSessionDialog({
    super.key,
    required this.visit,
    required this.patient,
  });

  /// The visit as it was when opened; the dialog follows its updates.
  final Visit visit;
  final Patient patient;

  @override
  ConsumerState<VisitSessionDialog> createState() => _VisitSessionDialogState();
}

class _VisitSessionDialogState extends ConsumerState<VisitSessionDialog> {
  late final VisitRepository _repo;
  late final TextEditingController _note = TextEditingController(
    text: widget.visit.therapistNotes ?? '',
  );

  /// The note as last saved, trimmed.
  late String _savedNote = (widget.visit.therapistNotes ?? '').trim();
  Timer? _autosave;
  bool _savingNote = false;
  bool _saveFailed = false;
  bool _updatingStatus = false;
  bool _addingFiles = false;

  /// Typed in since opening: only then is "Saved" worth saying.
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    // Read now: the note may still need saving in dispose, after ref is gone.
    _repo = ref.read(visitRepositoryProvider);
  }

  bool get _noteDirty => _note.text.trim() != _savedNote;

  @override
  void dispose() {
    _autosave?.cancel();
    // Closed mid-pause: keep what was typed.
    if (_noteDirty) unawaited(_writeNote(_note.text.trim()));
    _note.dispose();
    super.dispose();
  }

  /// The visit as it is now (status, note), from the patient's summary.
  Visit _live() {
    final s = ref.watch(patientSummaryProvider(widget.patient.id)).value;
    if (s != null) {
      for (final v in s.visits) {
        if (v.id == widget.visit.id) return v;
      }
    }
    return widget.visit;
  }

  Future<void> _writeNote(String text) => _repo.updateVisit(widget.visit.id, {
    'therapistNotes': text.isEmpty ? null : text,
  });

  void _noteChanged(String _) {
    setState(() {
      _saveFailed = false;
      _edited = true;
    });
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, _saveNote);
  }

  Future<void> _saveNote() async {
    _autosave?.cancel();
    if (!_noteDirty || _savingNote) return;
    final text = _note.text.trim();
    setState(() => _savingNote = true);
    try {
      await _writeNote(text);
      _savedNote = text;
    } catch (_) {
      _saveFailed = true;
    }
    if (!mounted) return;
    setState(() => _savingNote = false);
    // More was typed while saving.
    if (_noteDirty && !_saveFailed) {
      _autosave = Timer(_autosaveDelay, _saveNote);
    }
  }

  /// Records the consultation with Scribe. A confirmed Scribe note is
  /// added to the session note, so the field reloads afterwards.
  Future<void> _transcribe(Visit visit) async {
    await _saveNote();
    if (!mounted) return;
    final saved = await showScribeFlow(
      context,
      visit: visit,
      patient: widget.patient,
    );
    if (!saved || !mounted) return;
    final refreshed = await _repo.getVisit(visit.id);
    if (!mounted || refreshed == null || _noteDirty) return;
    final text = refreshed.therapistNotes ?? '';
    setState(() {
      _note.text = text;
      _savedNote = text.trim();
    });
  }

  Future<void> _setStatus(VisitStatus status) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _updatingStatus = true);
    try {
      await _repo.updateStatus(widget.visit.id, status);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't change the visit: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  /// Adds files for the patient and links the new ones to this visit.
  Future<void> _addFiles(Visit visit) async {
    final patientId = widget.patient.id;
    setState(() => _addingFiles = true);
    try {
      final before = {
        for (final f in await FilesRepository.instance.files(
          patientId: patientId,
        ))
          f.id,
      };
      if (!mounted) return;
      await FilesActions.pickAndAdd(context, patientId: patientId);
      final after = await FilesRepository.instance.files(patientId: patientId);
      final added = [
        for (final f in after)
          if (!before.contains(f.id)) f.id,
      ];
      if (added.isNotEmpty && mounted) {
        await linkFilesToVisit(ref, visit, added);
      }
    } finally {
      if (mounted) setState(() => _addingFiles = false);
    }
  }

  void _prescription(Visit visit) {
    final cfg = DoctorLetterheadConfig.fromProfileData(
      ref.read(doctorProfileProvider).value,
      FirebaseAuth.instance.currentUser,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrescriptionGenerationSheet(
        letterheadConfig: cfg,
        initialVisit: visit,
        initialPatient: widget.patient,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final visit = _live();
    final now = ref.watch(dashboardNowProvider);
    final clinical = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalView),
    );
    final canWrite = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalEdit),
    );
    final canSchedule = ref.watch(clinicCanProvider(ClinicPermission.schedule));
    final canBill = ref.watch(clinicCanProvider(ClinicPermission.billing));
    final isPhysio = clinical && ref.watch(isPhysiotherapyProvider);

    final scribeNotes = clinical
        ? [
            for (final n
                in ref.watch(notesForVisitProvider(visit.id)).value ??
                    const <ConsultationNote>[])
              if (n.status != ConsultationNoteStatus.discarded) n,
          ]
        : const <ConsultationNote>[];
    final files = clinical
        ? ref
              .watch(sessionFilesProvider(widget.patient.id))
              .forVisit(
                visit,
                extraIds: [for (final n in scribeNotes) ...n.scanFileIds],
              )
        : const <PatientFile>[];

    final t = visit.scheduledStart;
    final upcoming = t.isAfter(now);
    final status = PatientsBuilder.visitStatus(visit, now);
    final subtitle = [
      DateFormat('EEE, d MMM y').format(t),
      DateFormat('h:mm a').format(t),
      '${visit.durationMinutes} min',
      if (visit.visitType == VisitType.home) 'Home visit',
    ].join(' · ');

    final sections = <Widget>[
      if (canSchedule)
        _Section(
          label: 'How it went',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status == VisitRowStatus.notRecorded) ...[
                Text(
                  'Not recorded yet. Mark how the visit went.',
                  style: CruType.subhead.tint(c.amberText),
                ),
                const SizedBox(height: CruSpace.s8),
              ],
              Opacity(
                opacity: _updatingStatus ? 0.6 : 1,
                child: CruSegmentedControl<VisitStatus>(
                  semanticLabel: 'Visit status',
                  segments: [
                    const CruSegment(VisitStatus.scheduled, 'Booked'),
                    const CruSegment(VisitStatus.completed, 'Done'),
                    if (!upcoming || visit.status == VisitStatus.missed)
                      const CruSegment(VisitStatus.missed, 'Missed'),
                    const CruSegment(VisitStatus.cancelled, 'Cancelled'),
                  ],
                  selected: visit.status,
                  onChanged: (s) {
                    if (_updatingStatus || s == visit.status) return;
                    _setStatus(s);
                  },
                ),
              ),
            ],
          ),
        ),
      if (clinical)
        _Section(
          label: 'Session note',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_edited)
                _SaveState(
                  saving: _savingNote,
                  failed: _saveFailed,
                  dirty: _noteDirty,
                  hasNote: _savedNote.isNotEmpty,
                  onRetry: _saveNote,
                ),
              if (canWrite) ...[
                const SizedBox(width: CruSpace.s12),
                _TranscribeButton(onPressed: () => _transcribe(visit)),
              ],
            ],
          ),
          child: _NoteField(
            controller: _note,
            readOnly: !canWrite,
            onChanged: _noteChanged,
          ),
        ),
      if (scribeNotes.isNotEmpty)
        _Section(
          label: 'Scribe notes',
          rows: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in scribeNotes)
                _ScribeNoteRow(
                  note: n,
                  onOpen: () => openSessionNote(
                    context,
                    note: n,
                    patient: widget.patient,
                  ),
                ),
            ],
          ),
        ),
      if (clinical)
        _Section(
          label: files.isEmpty ? 'Files' : 'Files · ${files.length}',
          rows: files.isNotEmpty,
          trailing: canWrite
              ? CruCapsuleButton(
                  label: _addingFiles ? 'Adding…' : 'Add',
                  icon: FileIcons.upload,
                  height: CruSize.rowCapsule,
                  semanticLabel: 'Add files to this visit',
                  onPressed: _addingFiles ? null : () => _addFiles(visit),
                )
              : null,
          child: files.isEmpty
              ? Text(
                  'Nothing filed for this visit yet.',
                  style: CruType.subhead.tint(c.label2),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in files)
                      _FileRow(
                        file: f,
                        now: now,
                        onOpen: () => FilesActions.open(
                          context,
                          f,
                          patientName: widget.patient.fullName,
                        ),
                      ),
                  ],
                ),
        ),
      if (canWrite || canBill || isPhysio)
        _Section(
          label: 'For this visit',
          child: Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              if (canWrite)
                CruCapsuleButton(
                  label: 'Prescription',
                  icon: CruIcons.fileText,
                  onPressed: () => _prescription(visit),
                ),
              if (canBill)
                CruCapsuleButton(
                  label: 'Bill',
                  icon: CruIcons.rupee,
                  onPressed: () => showDesktopCreateInvoiceDialog(
                    context,
                    initialPatient: widget.patient,
                    attendingDoctorUid: visit.attendingDoctorUid.isNotEmpty
                        ? visit.attendingDoctorUid
                        : null,
                  ),
                ),
              if (isPhysio)
                CruCapsuleButton(
                  label: 'Session photos',
                  icon: FileIcons.image,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => PhysioPhotosDialog(
                      patient: widget.patient,
                      initialVisitId: visit.id,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];

    return DentalPanelDialog(
      title: visitTitle(visit),
      subtitle: subtitle,
      leading: CruDateTile(
        month: PatientFormat.month(t),
        day: PatientFormat.dayOfMonth(t),
        upcoming: upcoming,
      ),
      width: _dialogWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canSchedule) ...[
            const SizedBox(height: CruSpace.s12),
            Padding(
              padding: _Section._inset,
              child: Align(
                alignment: Alignment.centerLeft,
                child: VisitStatusText(status: status),
              ),
            ),
          ],
          for (final s in sections) ...[
            const SizedBox(height: CruSpace.s16),
            s,
          ],
          const SizedBox(height: CruSpace.s8),
        ],
      ),
    );
  }
}

/// A group label ("Session note") with an optional action on the right,
/// then its content. Content lines up with the dialog title; [rows] lets
/// pressable rows run 8 px wider so their hover fill has room and their
/// text still lines up.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.child,
    this.trailing,
    this.rows = false,
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final bool rows;

  static const _inset = EdgeInsets.symmetric(horizontal: CruSpace.s8);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _inset,
          child: SizedBox(
            height: CruSize.rowCapsule,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: CruType.groupLabel.tabular.tint(c.label3),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s8),
        if (rows) child else Padding(padding: _inset, child: child),
      ],
    );
  }
}

/// The session note: an inset field that grows with the text.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.readOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onChanged: onChanged,
        minLines: 4,
        maxLines: 12,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.accent,
        style: CruType.note.tint(c.label),
        decoration: InputDecoration.collapsed(
          hintText: readOnly
              ? 'No note for this visit'
              : 'What was done, findings, advice…',
          hintStyle: CruType.note.tint(c.label3),
        ),
      ),
    );
  }
}

/// "Saving…", "Saved", or "Not saved · Retry" beside the note label.
class _SaveState extends StatelessWidget {
  const _SaveState({
    required this.saving,
    required this.failed,
    required this.dirty,
    required this.hasNote,
    required this.onRetry,
  });

  final bool saving;
  final bool failed;
  final bool dirty;
  final bool hasNote;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (failed) {
      return CruLink(
        label: 'Not saved · Retry',
        color: c.amberText,
        onPressed: onRetry,
      );
    }
    final text = saving || dirty ? 'Saving…' : (hasNote ? 'Saved' : null);
    if (text == null) return const SizedBox.shrink();
    return Text(text, style: CruType.caption.tint(c.label3));
  }
}

/// "✦ Transcribe" in AI violet: records the consultation with Scribe.
class _TranscribeButton extends StatelessWidget {
  const _TranscribeButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'Transcribe this visit with Scribe',
      tooltip: 'Record the consultation; Scribe writes the note',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.rowCapsule,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? c.aiTint : c.surface,
          shape: StadiumBorder(side: BorderSide(color: c.hairline)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(CruIcons.mic, size: 14, strokeWidth: 2, color: c.ai),
            const SizedBox(width: CruSpace.s6),
            Text('Transcribe', style: CruType.subhead.w500.tint(c.ai)),
          ],
        ),
      ),
    );
  }
}

/// A note Scribe wrote for this visit: its title and time. Opens it.
class _ScribeNoteRow extends StatelessWidget {
  const _ScribeNoteRow({required this.note, required this.onOpen});

  final ConsultationNote note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final sub = [
      DateFormat('h:mm a').format(note.createdAt),
      if (note.status == ConsultationNoteStatus.draft) 'Draft',
      if (note.isEdited) 'Edited',
    ].join(' · ');
    return _HoverRow(
      onTap: onOpen,
      semanticLabel: 'Open the Scribe note ${sessionTitle(note)}',
      leading: Container(
        width: CruSize.iconTile,
        height: CruSize.iconTile,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: c.aiTint,
          shape: cruShape(CruRadius.iconTile),
        ),
        child: CruIcon(
          CruIcons.sparkleSingle,
          size: 16,
          strokeWidth: 2,
          color: c.ai,
        ),
      ),
      title: sessionTitle(note),
      subtitle: sub,
      trailing: CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
    );
  }
}

/// A file of this visit: thumbnail, name, when it was added and its type.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.now, required this.onOpen});

  final PatientFile file;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _HoverRow(
    onTap: onOpen,
    semanticLabel: 'Open ${file.name}',
    leading: FileThumb(file: file),
    title: file.name,
    subtitle:
        '${FilesBuilder.dateLabel(file.createdAt, now)} · '
        '${FilesBuilder.typeLabel(file)}',
  );
}

/// A pressable row with a hover fill: 36 px leading, title and subtitle.
class _HoverRow extends StatelessWidget {
  const _HoverRow({
    required this.onTap,
    required this.semanticLabel,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final VoidCallback onTap;
  final String semanticLabel;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: semanticLabel,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s8,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: CruType.row.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: CruSpace.s12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
