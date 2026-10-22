import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/session_scan_card.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens one session note from a patient's record.
Future<void> openSessionNote(
  BuildContext context, {
  required ConsultationNote note,
  Patient? patient,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionNoteScreen(note: note, patient: patient),
    ),
  );
}

/// A session note: what the scribe wrote from the consultation, editable by
/// anyone who writes clinical records. Saving keeps the note in the
/// patient's session history and marks it edited.
class SessionNoteScreen extends ConsumerStatefulWidget {
  const SessionNoteScreen({super.key, required this.note, this.patient});

  final ConsultationNote note;
  final Patient? patient;

  @override
  ConsumerState<SessionNoteScreen> createState() => _SessionNoteScreenState();
}

class _SessionNoteScreenState extends ConsumerState<SessionNoteScreen> {
  static const _maxWidth = 960.0;

  late ConsultationNote _note = widget.note;

  /// Non-null while editing.
  _NoteEdit? _edit;
  bool _saving = false;

  @override
  void dispose() {
    _edit?.dispose();
    super.dispose();
  }

  void _startEditing() => setState(() => _edit = _NoteEdit(_note));

  void _stopEditing() {
    final edit = _edit;
    setState(() => _edit = null);
    // Dispose after the fields have been unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => edit?.dispose());
  }

  Future<void> _save() async {
    final edit = _edit;
    if (edit == null || _saving || edit.isEmpty) return;
    if (!edit.hasChanges) {
      _stopEditing();
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(consultationNoteRepositoryProvider)
          .updateSessionNote(edit.toNote());
      if (!mounted) return;
      _note = saved;
      _saving = false;
      _stopEditing();
      _say('Session note updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say("Couldn't save the changes: $e");
    }
  }

  /// Cancel or back while editing: ask before throwing edits away.
  Future<bool> _leaveEditing() async {
    if (!(_edit?.hasChanges ?? false)) {
      _stopEditing();
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('The session note stays as it was.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _stopEditing();
      return true;
    }
    return false;
  }

  void _say(String message) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CruTheme.of(ref.watch(resolvedAppearanceProvider)),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final c = context.cru;
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));
    final edit = _edit;
    return PopScope(
      canPop: edit == null && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await _leaveEditing() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    title: edit == null ? 'Session note' : 'Edit session note',
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        CruSpace.s16,
                        CruSpace.s8,
                        CruSpace.s16,
                        CruSpace.s24,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        SessionNoteHeader(note: _note, patient: widget.patient),
                        const SizedBox(height: CruSpace.s16),
                        if (edit == null) ...[
                          SessionNoteBody(note: _note),
                          if (_note.scanFileIds.isNotEmpty) ...[
                            const SizedBox(height: CruSpace.s16),
                            SessionScanCard(
                              fileIds: _note.scanFileIds,
                              patientName: widget.patient?.fullName ?? '',
                            ),
                          ],
                          if (_showsTranscript(_note)) ...[
                            const SizedBox(height: CruSpace.s16),
                            SessionTranscriptCard(
                              transcript: _note.transcript,
                              title: _note.scanFileIds.isEmpty
                                  ? 'CONVERSATION TRANSCRIPT'
                                  : 'AS WRITTEN',
                            ),
                          ],
                        ] else
                          _NoteEditor(edit: edit, enabled: !_saving),
                      ],
                    ),
                  ),
                  if (edit != null)
                    _EditBar(
                      edit: edit,
                      saving: _saving,
                      onCancel: _leaveEditing,
                      onSave: _save,
                    )
                  else if (canEdit)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CruSpace.s16,
                        CruSpace.s8,
                        CruSpace.s16,
                        CruSpace.s16,
                      ),
                      child: CruButton(
                        label: 'Edit note',
                        icon: CruIcons.pen,
                        large: true,
                        expand: true,
                        onPressed: _startEditing,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A transcript saved in place of notes is already the body.
bool _showsTranscript(ConsultationNote note) {
  final transcript = note.transcript.trim();
  return transcript.isNotEmpty && transcript != note.notes.trim();
}

/// The text the doctor edits: the notes as written, or an older structured
/// note laid out as SOAP sections.
@visibleForTesting
String editableNotesOf(ConsultationNote note) {
  final notes = note.notes.trim();
  if (notes.isNotEmpty) return notes;
  return [
    for (final group in ConsultationNoteRepository.soapSections(note))
      [group.section.title, ...group.lines].join('\n'),
  ].join('\n\n');
}

/// The title and notes being edited, and what they started as.
class _NoteEdit {
  _NoteEdit(this.original)
    : _startTitle = original.chiefComplaint.trim(),
      _startNotes = editableNotesOf(original) {
    title = TextEditingController(text: _startTitle);
    notes = TextEditingController(text: _startNotes);
  }

  final ConsultationNote original;
  final String _startTitle;
  final String _startNotes;
  late final TextEditingController title;
  late final TextEditingController notes;

  bool get isEmpty => notes.text.trim().isEmpty;

  bool get hasChanges =>
      title.text.trim() != _startTitle || notes.text.trim() != _startNotes;

  ConsultationNote toNote() => original.copyWith(
    chiefComplaint: title.text.trim(),
    notes: notes.text.trim(),
  );

  void dispose() {
    title.dispose();
    notes.dispose();
  }
}

class _NoteEditor extends StatelessWidget {
  const _NoteEditor({required this.edit, required this.enabled});

  final _NoteEdit edit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      semanticLabel: 'Edit session note',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Title',
            controller: edit.title,
            hint: 'What the session was about',
            textCapitalization: TextCapitalization.sentences,
            enabled: enabled,
          ),
          const SizedBox(height: CruSpace.s16),
          CruTextField(
            label: 'Notes',
            controller: edit.notes,
            maxLines: 18,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s4,
        CruSpace.s8,
        CruSpace.s16,
        CruSpace.s4,
      ),
      child: Row(
        children: [
          CruIconButton(
            icon: CruIcons.chevronLeft,
            semanticLabel: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: CruSpace.s4),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: CruType.title.tint(c.label)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Title, date, time and specialty of a session, with its AI and edited
/// markers.
class SessionNoteHeader extends StatelessWidget {
  const SessionNoteHeader({super.key, required this.note, this.patient});

  final ConsultationNote note;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final meta = [
      ?patient?.fullName,
      DateFormat('EEE d MMM yyyy · h:mm a').format(note.createdAt),
      ?sessionSpecialtyLabel(note.specialty),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sessionTitle(note), style: CruType.title.tint(c.label)),
        const SizedBox(height: CruSpace.s4),
        Text(meta, style: CruType.subhead.tabular.tint(c.label2)),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            CruPill(
              text: 'AI scribe',
              icon: CruIcons.sparkle,
              background: c.aiTint,
              foreground: c.ai,
            ),
            if (note.isEdited)
              CruPill(
                text:
                    'Edited ${DateFormat('d MMM yyyy').format(note.editedAt!)}',
                icon: CruIcons.pen,
                background: c.inset,
                foreground: c.label2,
              ),
          ],
        ),
      ],
    );
  }
}

/// The session notes as the scribe wrote them, with anything it was unsure
/// of called out first. Older structured notes show as SOAP sections.
class SessionNoteBody extends StatelessWidget {
  const SessionNoteBody({super.key, required this.note});

  final ConsultationNote note;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final unsure = note.confidenceNote.trim();
    final notes = note.notes.trim();
    return CruCard(
      semanticLabel: 'Session note',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unsure.isNotEmpty) ...[
            Text('⚠ Check: $unsure', style: CruType.subhead.tint(c.amberText)),
            const SizedBox(height: CruSpace.s16),
          ],
          if (notes.isNotEmpty)
            ..._notesBlocks(context, notes)
          else
            ..._soapBlocks(context),
        ],
      ),
    );
  }

  /// Blank-line separated blocks; a block's short first line followed by
  /// more lines is its heading.
  List<Widget> _notesBlocks(BuildContext context, String notes) {
    final c = context.cru;
    final blocks = notes
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    return [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const SizedBox(height: CruSpace.s16),
        ...() {
          final lines = blocks[i].split('\n');
          final first = lines.first.trim();
          final isHeading =
              lines.length > 1 && first.length <= 40 && !first.startsWith('-');
          final body = (isHeading ? lines.skip(1) : lines).join('\n').trim();
          return [
            if (isHeading) ...[
              Semantics(
                header: true,
                child: Text(
                  first.replaceFirst(RegExp(r':$'), '').toUpperCase(),
                  style: CruType.groupLabel.tint(c.label2),
                ),
              ),
              const SizedBox(height: CruSpace.s8),
            ],
            SelectableText(body, style: CruType.body.tabular.tint(c.label)),
          ];
        }(),
      ],
    ];
  }

  List<Widget> _soapBlocks(BuildContext context) {
    final c = context.cru;
    final groups = ConsultationNoteRepository.soapSections(note);
    if (groups.isEmpty) {
      return [
        Text(
          'Nothing was recorded in this note.',
          style: CruType.text.tint(c.label2),
        ),
      ];
    }
    return [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0) ...[
          const SizedBox(height: CruSpace.s16),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s16),
        ],
        Semantics(
          header: true,
          child: Text(
            groups[i].section.title.toUpperCase(),
            style: CruType.groupLabel.tint(c.label2),
          ),
        ),
        const SizedBox(height: CruSpace.s8),
        for (final line in groups[i].lines)
          Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s4),
            child: SelectableText(
              line,
              style: CruType.body.tabular.tint(
                line.startsWith('⚠') ? c.redText : c.label,
              ),
            ),
          ),
      ],
    ];
  }
}

/// What the notes were written from — the conversation, or the handwriting
/// as written — folded away by default.
class SessionTranscriptCard extends StatefulWidget {
  const SessionTranscriptCard({
    super.key,
    required this.transcript,
    this.title = 'CONVERSATION TRANSCRIPT',
  });

  final String transcript;
  final String title;

  @override
  State<SessionTranscriptCard> createState() => _SessionTranscriptCardState();
}

class _SessionTranscriptCardState extends State<SessionTranscriptCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Conversation transcript',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: CruType.groupLabel.tint(c.label2),
                ),
              ),
              CruLink(
                label: _open ? 'Hide' : 'Show',
                onPressed: () => setState(() => _open = !_open),
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: CruSpace.s12),
            SelectableText(
              widget.transcript.trim(),
              style: CruType.body.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Homeopathy" / "Physiotherapy" for a [SessionSpecialty], or null.
String? sessionSpecialtyLabel(String specialty) => switch (specialty) {
  SessionSpecialty.homeopathy => 'Homeopathy',
  SessionSpecialty.physiotherapy => 'Physiotherapy',
  _ => null,
};

/// The session note's name: the title the scribe gave it, else the first
/// diagnosis of an older note, else the kind of session.
String sessionTitle(ConsultationNote note) {
  final title = note.chiefComplaint.trim();
  if (title.isNotEmpty) return title;
  for (final d in note.diagnosisSuggestions) {
    if (d.trim().isNotEmpty) return d.trim();
  }
  final kind = sessionSpecialtyLabel(note.specialty);
  return kind == null ? 'Session note' : '$kind session note';
}

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.edit,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final _NoteEdit edit;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ListenableBuilder(
      listenable: Listenable.merge([edit.title, edit.notes]),
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s12,
          CruSpace.s16,
          CruSpace.s16,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.separator)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (edit.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s8),
                child: Text(
                  'Write something in the notes to save them.',
                  style: CruType.subhead.tint(c.amberText),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: CruButton(
                    label: 'Cancel',
                    kind: CruButtonKind.inset,
                    large: true,
                    expand: true,
                    onPressed: saving ? null : onCancel,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: CruButton(
                    label: saving ? 'Saving…' : 'Save changes',
                    icon: CruIcons.check,
                    large: true,
                    expand: true,
                    onPressed: saving || edit.isEmpty ? null : onSave,
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
