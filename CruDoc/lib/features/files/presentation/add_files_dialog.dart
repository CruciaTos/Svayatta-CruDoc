import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Add files": what was chosen or dropped, the patient they are for
/// (required: a file can't be saved without one) and the folder. Returns
/// how many were added, or null when cancelled.
Future<int?> showAddFilesDialog(
  BuildContext context, {
  required List<FileSource> sources,
  String? patientId,
  String folderId = '',
}) => showDialog<int>(
  context: context,
  builder: (_) => _AddFilesDialog(
    sources: sources,
    patientId: patientId,
    folderId: folderId,
  ),
);

class _AddFilesDialog extends ConsumerStatefulWidget {
  const _AddFilesDialog({
    required this.sources,
    required this.patientId,
    required this.folderId,
  });

  final List<FileSource> sources;
  final String? patientId;
  final String folderId;

  @override
  ConsumerState<_AddFilesDialog> createState() => _AddFilesDialogState();
}

class _AddFilesDialogState extends ConsumerState<_AddFilesDialog> {
  Patient? _patient;
  late String _folderId = widget.folderId;
  bool _saving = false;
  String? _patientError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final id = widget.patientId;
    if (id != null) {
      final patients = ref.read(patientsStreamProvider).value ?? const [];
      for (final p in patients) {
        if (p.id == id) _patient = p;
      }
    }
  }

  List<FileSource> get _ok => [
    for (final s in widget.sources)
      if (s.problem == null) s,
  ];

  Future<void> _pickPatient() async {
    final p = await showPatientPickerDialog(
      context,
      title: 'Who are these files for?',
    );
    if (p != null && mounted) {
      setState(() {
        _patient = p;
        _patientError = null;
      });
    }
  }

  Future<void> _save() async {
    final patient = _patient;
    if (patient == null) {
      setState(() => _patientError = 'Choose the patient these files are for.');
      return;
    }
    if (_ok.isEmpty) {
      setState(() => _notice = 'None of these files can be added.');
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final added = await FilesRepository.instance.addFiles(
        _ok,
        patientId: patient.id,
        folderId: _folderId,
      );
      if (mounted) Navigator.of(context).pop(added);
    } catch (e) {
      setState(() {
        _saving = false;
        _notice = e is FilesException
            ? e.message
            : "Couldn't add the files. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final ok = _ok;
    final total = ok.fold<int>(0, (sum, s) => sum + s.sizeBytes);
    final folders = ref.watch(filesViewProvider).value?.allFolders ?? const [];
    final count = ok.length;
    return CruFormDialog(
      title: count == 1 ? 'Add file' : 'Add $count files',
      subtitle: count == 0
          ? 'Nothing here can be added'
          : PatientFileTypes.sizeLabel(total),
      leading: const CruIconTile(
        icon: FileIcons.upload,
        tone: CruTileTone.neutral,
      ),
      submitLabel: count == 1 ? 'Add file' : 'Add files',
      onSubmit: _save,
      busy: _saving,
      dirty: _patient != null && _patient!.id != widget.patientId,
      notice: _notice,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Files',
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in widget.sources) _SourceRow(source: s),
                ],
              ),
            ],
          ),
          CruFormSection(
            title: 'Where',
            description: 'Every file belongs to a patient.',
            children: [
              CruPickerField(
                label: 'Patient',
                icon: CruIcons.user,
                value: _patient?.fullName,
                placeholder: 'Choose a patient',
                onTap: _pickPatient,
                error: _patientError,
              ),
              CruDropdownField<String>(
                label: 'Folder',
                icon: FileIcons.folder,
                value: _folderId,
                items: ['', for (final f in folders) f.id],
                itemLabel: (id) => id.isEmpty
                    ? 'No folder (only you)'
                    : FilesBuilder.pathOf(id, folders),
                onChanged: (id) => setState(() => _folderId = id),
              ),
            ],
          ),
          if (widget.sources.length != ok.length)
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s8),
              child: Text(
                'Files marked above are skipped. CruDoc takes pictures, '
                'X-rays (DICOM), PDFs, office documents, 3D scans, video '
                'and audio up to 50 MB (DICOM and TIFF up to 250 MB).',
                style: CruType.caption.tint(c.label2),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});

  final FileSource source;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final type = source.contentType;
    final problem = source.problem;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      child: Row(
        children: [
          CruIconTile(
            icon: type == null
                ? CruIcons.fileText
                : fileKindIcon(PatientFileTypes.kindOf(type)),
            tone: problem == null ? CruTileTone.neutral : CruTileTone.amber,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: CruType.row.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  problem ?? PatientFileTypes.sizeLabel(source.sizeBytes),
                  style: problem == null
                      ? CruType.subhead.tabular.tint(c.label2)
                      : CruType.subhead.w600.tint(c.amberText),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
