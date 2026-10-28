import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/colleague_send.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/colleague_monogram.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Send to `<colleague>`": subject, note and files, like writing an email.
/// Every file is for the patient of the first one.
Future<void> showComposeTransferDialog(
  BuildContext context, {
  required ClinicMember to,
  required List<PatientFile> files,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ComposeDialog(to: to, files: files),
);

class _ComposeDialog extends ConsumerStatefulWidget {
  const _ComposeDialog({required this.to, required this.files});

  final ClinicMember to;
  final List<PatientFile> files;

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  final _subject = TextEditingController();
  final _note = TextEditingController();
  late final List<PatientFile> _files = [...widget.files];
  bool _busy = false;
  bool _adding = false;

  String get _patientId => widget.files.first.patientId;

  @override
  void dispose() {
    _subject.dispose();
    _note.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  Future<void> _addFromPc() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _adding = true);
    try {
      final sources = [
        for (final f in result.files)
          if (f.path != null)
            FileSource(name: f.name, sizeBytes: f.size, path: f.path),
      ];
      final skipped = sources.where((s) => s.problem != null).length;
      final ids = await FilesRepository.instance.addFilesWithIds(
        sources,
        patientId: _patientId,
      );
      final added = [
        for (final id in ids) ?await FilesRepository.instance.file(id),
      ];
      if (!mounted) return;
      setState(() => _files.addAll(added));
      if (skipped > 0) {
        _say('$skipped file(s) skipped: type not supported or too large.');
      }
    } catch (e) {
      _say("Couldn't add files: $e");
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _send() async {
    if (_files.isEmpty) {
      _say('Add at least one file.');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final offers = await sendFilesToColleague(
        clinicId: FilesRepository.instance.doctorId,
        colleague: widget.to,
        files: _files,
        subject: _subject.text.trim(),
        note: _note.text.trim(),
        // Opened from the colleague strip, which sends over Wi-Fi only.
        wifiOnly: true,
      );
      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Sent ${_files.length == 1 ? '1 file' : '${_files.length} files'} '
            'to ${widget.to.name} on clinic Wi-Fi',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => undoSend(offers),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _say("Couldn't send: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patients = ref.watch(patientsStreamProvider).value ?? const [];
    final patient = patients.where((p) => p.id == _patientId).firstOrNull;
    final patientName = patient?.fullName.trim() ?? '';
    final canAdd = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));
    return CruFormDialog(
      title: 'Send to ${widget.to.name}',
      subtitle: patientName.isEmpty ? null : 'For $patientName',
      leading: ColleagueMonogram(name: widget.to.name),
      submitLabel: 'Send',
      busy: _busy,
      dirty:
          _subject.text.isNotEmpty ||
          _note.text.isNotEmpty ||
          _files.length != widget.files.length,
      footerHint: 'Goes direct on clinic Wi-Fi.',
      onSubmit: _send,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Subject',
            controller: _subject,
            optional: true,
            hint: 'e.g. OPG before extraction',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Note',
            controller: _note,
            optional: true,
            maxLines: 5,
            hint: 'Anything they should know',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CruSpace.s16),
          Text('Files', style: CruType.groupLabel.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          for (final f in _files)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s8),
              child: Row(
                children: [
                  CruIconTile(
                    icon: fileKindIcon(f.kind),
                    tone: CruTileTone.neutral,
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.row.tint(c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Text(
                    PatientFileTypes.sizeLabel(f.sizeBytes),
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                  // The last file can't be removed: nothing to send then.
                  if (_files.length > 1)
                    CruIconButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Remove ${f.name}',
                      size: CruSize.capsule,
                      iconSize: 16,
                      onPressed: () => setState(() => _files.remove(f)),
                    ),
                ],
              ),
            ),
          // Adding a file from the PC saves it to the patient's files, which
          // needs permission to write clinical records.
          if (canAdd) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: CruCapsuleButton(
                label: _adding ? 'Adding…' : 'Add from this PC…',
                icon: CruIcons.plus,
                onPressed: _adding || _busy ? null : _addFromPc,
              ),
            ),
          ],
          if (canAdd && patientName.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s4),
            Text(
              "Files from this PC are also saved to $patientName's files.",
              style: CruType.caption.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}
