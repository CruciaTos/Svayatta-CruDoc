import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart'
    show DentalPanelDialog;
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/note_editing.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_choices.dart';
import 'package:doctor_management_app/features/patients/data/providers/session_files_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One file's note and the session it belongs to, changed from the
/// patient's files.
Future<void> showFileNoteDialog(
  BuildContext context, {
  required PatientFile file,
  required Patient patient,
}) => showDialog<void>(
  context: context,
  builder: (_) => _FileNoteDialog(file: file, patient: patient),
);

class _FileNoteDialog extends ConsumerStatefulWidget {
  const _FileNoteDialog({required this.file, required this.patient});

  final PatientFile file;
  final Patient patient;

  @override
  ConsumerState<_FileNoteDialog> createState() => _FileNoteDialogState();
}

class _FileNoteDialogState extends ConsumerState<_FileNoteDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.file.note,
  );

  /// The session picked here ([kNoVisit] for none); null while untouched.
  String? _picked;
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(List<Visit> visits) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await FilesRepository.instance.setNote(widget.file.id, _note.text);
      final picked = _picked;
      if (picked != null) {
        await setFilesVisit(ref, widget.patient.id, [
          widget.file.id,
        ], visits.where((v) => v.id == picked).firstOrNull);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[Files] could not save the note or session: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final now = ref.watch(dashboardNowProvider);
    final summary = ref.watch(patientSummaryProvider(widget.patient.id)).value;
    final visits = sessionChoices(summary?.visits ?? const <Visit>[], now);
    final files = ref.watch(sessionFilesProvider(widget.patient.id));
    // As it stands: the session it was put in, else the one that claims it
    // by its day.
    final current =
        files.links[widget.file.id] ??
        visits
            .where(
              (v) =>
                  v.status != VisitStatus.missed &&
                  DateUtils.isSameDay(v.scheduledStart, widget.file.createdAt),
            )
            .firstOrNull
            ?.id ??
        kNoVisit;
    final selected = _picked ?? current;

    Widget choice(String id, String label) => CruPressable(
      onTap: _saving ? null : () => setState(() => _picked = id),
      scaleOnPress: false,
      semanticLabel: id == selected ? '$label, selected' : label,
      builder: (context, hovered) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: id == selected
              ? c.inset
              : hovered
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: CruType.row.tabular.tint(c.label)),
            ),
            if (id == selected)
              CruIcon(CruIcons.check, size: 16, color: c.accentText),
          ],
        ),
      ),
    );

    return DentalPanelDialog(
      title: 'Note and session',
      subtitle: widget.file.name,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: CruSpace.s8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s16,
              vertical: CruSpace.s12,
            ),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: TextField(
              controller: _note,
              enabled: !_saving,
              minLines: 3,
              maxLines: 6,
              maxLength: kFileNoteLimit,
              inputFormatters: const [NoteListFormatter()],
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: c.accent,
              style: CruType.note.tint(c.label),
              decoration: InputDecoration.collapsed(
                hintText: 'Add a note',
                hintStyle: CruType.note.tint(c.label3),
              ).copyWith(counterText: ''),
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
            child: Text('Session', style: CruType.groupLabel.tint(c.label3)),
          ),
          const SizedBox(height: CruSpace.s4),
          choice(kNoVisit, 'Not in a session'),
          for (final v in visits) choice(v.id, sessionLabel(v, now)),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: _failed
                ? Text(
                    "Couldn't save. Try again.",
                    style: CruType.subhead.tint(c.amberText),
                  )
                : const SizedBox.shrink(),
          ),
          CruButton(
            label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : () => _save(visits),
          ),
        ],
      ),
    );
  }
}
