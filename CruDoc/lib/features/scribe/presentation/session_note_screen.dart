import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens one session from a patient's history.
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

/// A confirmed session note: read as a SOAP note, and editable by anyone
/// who writes clinical records. Saving keeps the note in the patient's
/// session history and marks it edited.
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
  ScribeDraftFormController? _form;
  bool _saving = false;

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  void _startEditing() => setState(() => _form = ScribeDraftFormController(_note));

  void _stopEditing() {
    final form = _form;
    setState(() => _form = null);
    form?.dispose();
  }

  bool get _hasChanges {
    final form = _form;
    return form != null && contentKeyOf(form.toNote()) != contentKeyOf(_note);
  }

  Future<void> _save() async {
    final form = _form;
    if (form == null || _saving || form.isEmpty) return;
    if (!_hasChanges) {
      _stopEditing();
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(consultationNoteRepositoryProvider)
          .updateSessionNote(form.toNote());
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
    if (!_hasChanges) {
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
    final form = _form;
    return PopScope(
      canPop: form == null && !_saving,
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
                    title: form == null ? 'Session note' : 'Edit session note',
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
                        if (form == null)
                          SessionNoteBody(note: _note)
                        else
                          ScribeDraftForm(
                            controller: form,
                            palette: ScribePalette.of(context),
                            existingDiagnoses:
                                widget.patient?.diagnosis ?? const [],
                          ),
                      ],
                    ),
                  ),
                  if (form != null)
                    _EditBar(
                      form: form,
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

/// What a note says, ignoring when and by whom it was saved — used to tell
/// whether an edit changed anything.
@visibleForTesting
String contentKeyOf(ConsultationNote note) {
  final map = note.toLocalMap()
    ..remove('updatedAt')
    ..remove('editedAt')
    ..remove('editedByUid')
    ..remove('confirmedAt')
    ..remove('status');
  return jsonEncode(map);
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

/// Date, time, token and specialty of a session, with its AI and edited
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
        Text(
          meta,
          style: CruType.subhead.tabular.tint(c.label2),
        ),
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

/// The note laid out as a SOAP note — the same sections that were added to
/// the visit when it was confirmed.
class SessionNoteBody extends StatelessWidget {
  const SessionNoteBody({super.key, required this.note});

  final ConsultationNote note;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final groups = ConsultationNoteRepository.soapSections(note);
    return CruCard(
      semanticLabel: 'Session note',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: groups.isEmpty
          ? Text(
              'Nothing was recorded in this note.',
              style: CruType.text.tint(c.label2),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

/// What a session was about: the chief complaint, else the first
/// diagnosis, else the kind of session.
String sessionTitle(ConsultationNote note) {
  final complaint = note.chiefComplaint.trim();
  if (complaint.isNotEmpty) return complaint;
  for (final d in note.diagnosisSuggestions) {
    if (d.trim().isNotEmpty) return d.trim();
  }
  final kind = sessionSpecialtyLabel(note.specialty);
  return kind == null ? 'Session' : '$kind session';
}

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.form,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final ScribeDraftFormController form;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ListenableBuilder(
      listenable: form,
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
            if (form.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s8),
                child: Text(
                  'Add at least one detail to save the note.',
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
                    onPressed: saving || form.isEmpty ? null : onSave,
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
