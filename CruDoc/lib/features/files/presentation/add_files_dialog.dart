import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_bars.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Add files": what was chosen or dropped, the patient each file is for
/// (required: a file can't be saved without one) and the folder. Each file
/// can go to a different patient. Returns how many were added, or null
/// when cancelled.
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

/// One chosen file and the patient it is going to.
class _Item {
  _Item(this.source, this.patient);

  final FileSource source;
  Patient? patient;

  bool get ok => source.problem == null;
}

class _AddFilesDialogState extends ConsumerState<_AddFilesDialog> {
  late final List<_Item> _items;
  late String _folderId = widget.folderId;
  bool _saving = false;
  bool _removedAny = false;

  /// After a submit with files still missing a patient, those rows say so.
  bool _showMissing = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    Patient? preset;
    final id = widget.patientId;
    if (id != null) {
      final patients = ref.read(patientsStreamProvider).value ?? const [];
      for (final p in patients) {
        if (p.id == id) preset = p;
      }
    }
    _items = [for (final s in widget.sources) _Item(s, preset)];
  }

  List<_Item> get _ok => [
    for (final i in _items)
      if (i.ok) i,
  ];

  /// Files that can be added but have no patient yet.
  List<_Item> get _missing => [
    for (final i in _ok)
      if (i.patient == null) i,
  ];

  Future<void> _pickPatient(_Item item) async {
    final p = await showPatientPickerDialog(
      context,
      title: 'Who is “${item.source.name}” for?',
    );
    if (p != null && mounted) {
      setState(() {
        item.patient = p;
        if (_missing.isEmpty) _notice = null;
      });
    }
  }

  void _remove(_Item item) {
    setState(() {
      _items.remove(item);
      _removedAny = true;
      if (_missing.isEmpty) _notice = null;
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  /// Gives [item]'s patient to every file that has none yet.
  void _useForRest(_Item item) {
    final p = item.patient;
    if (p == null) return;
    setState(() {
      for (final i in _missing) {
        i.patient = p;
      }
      _notice = null;
    });
  }

  Future<void> _save() async {
    final ok = _ok;
    if (ok.isEmpty) {
      setState(() => _notice = 'None of these files can be added.');
      return;
    }
    final missing = _missing.length;
    if (missing > 0) {
      setState(() {
        _showMissing = true;
        _notice = missing == 1
            ? 'Choose a patient for 1 file, or remove it.'
            : 'Choose a patient for $missing files, or remove them.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });

    // One add per patient, in the order the patients first appear.
    final groups = <String, List<_Item>>{};
    for (final i in ok) {
      groups.putIfAbsent(i.patient!.id, () => []).add(i);
    }
    var added = 0;
    try {
      for (final entry in groups.entries) {
        added += await FilesRepository.instance.addFiles(
          [for (final i in entry.value) i.source],
          patientId: entry.key,
          folderId: _folderId,
        );
        // Saved: drop them, so a retry after an error doesn't add them twice.
        _items.removeWhere(entry.value.contains);
      }
      if (mounted) Navigator.of(context).pop(added);
    } catch (e) {
      if (!mounted) return;
      final why = e is FilesException
          ? e.message
          : "Couldn't add the files. Try again.";
      setState(() {
        _saving = false;
        _notice = added == 0
            ? why
            : '${added == 1 ? '1 file was' : '$added files were'} added. $why';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final ok = _ok;
    final total = ok.fold<int>(0, (sum, i) => sum + i.source.sizeBytes);
    final folders = ref.watch(filesViewProvider).value?.allFolders ?? const [];
    final count = ok.length;
    final missing = _missing.length;
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
      dirty:
          _removedAny ||
          _items.any(
            (i) => i.patient != null && i.patient!.id != widget.patientId,
          ),
      notice: _notice,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Files',
            description:
                'Every file belongs to a patient. Each one can be '
                'for someone different.',
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final i in _items)
                    _ItemRow(
                      item: i,
                      showMissing: _showMissing,
                      remaining: i.patient == null ? 0 : missing,
                      onPickPatient: () => _pickPatient(i),
                      onRemove: () => _remove(i),
                      onUseForRest: () => _useForRest(i),
                    ),
                ],
              ),
            ],
          ),
          CruFormSection(
            title: 'Folder',
            children: [
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
          if (_items.length != ok.length)
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

/// A file: its name, type and size, the patient it goes to, and a ▾ menu
/// to remove it or give its patient to every file that has none yet.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.showMissing,
    required this.remaining,
    required this.onPickPatient,
    required this.onRemove,
    required this.onUseForRest,
  });

  final _Item item;
  final bool showMissing;

  /// Files without a patient that this row's patient could be given to.
  final int remaining;
  final VoidCallback onPickPatient;
  final VoidCallback onRemove;
  final VoidCallback onUseForRest;

  static String _typeAndSize(FileSource s) {
    final dot = s.name.lastIndexOf('.');
    final ext = dot >= 0 && dot < s.name.length - 1
        ? s.name.substring(dot + 1).toUpperCase()
        : '';
    final size = PatientFileTypes.sizeLabel(s.sizeBytes);
    return ext.isEmpty ? size : '$ext · $size';
  }

  /// The patient's name, cut short so the row keeps one line.
  static String _short(String name) =>
      name.length > 22 ? '${name.substring(0, 21).trimRight()}…' : name;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final source = item.source;
    final type = source.contentType;
    final problem = source.problem;
    final patient = item.patient;
    final needsPatient = problem == null && patient == null && showMissing;
    final narrow = MediaQuery.sizeOf(context).width < CruBreakpoint.phone;
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
                  problem ??
                      (needsPatient
                          ? '${_typeAndSize(source)} · Needs a patient'
                          : _typeAndSize(source)),
                  style: problem == null && !needsPatient
                      ? CruType.subhead.tabular.tint(c.label2)
                      : CruType.subhead.w600.tint(c.amberText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (problem == null) ...[
            const SizedBox(width: CruSpace.s8),
            CruCapsuleButton(
              // Phones get a shorter label so the file name keeps room.
              label: narrow
                  ? (patient == null
                        ? 'Choose'
                        : _short(patient.firstName.trim()))
                  : (patient == null
                        ? 'Choose patient'
                        : _short(patient.fullName.trim())),
              icon: CruIcons.user,
              onPressed: onPickPatient,
            ),
          ],
          const SizedBox(width: CruSpace.s4),
          FilesMenu(
            // Opens inward so it stays inside the form.
            endAlignedWidth: 160,
            items: [
              FilesMenuItem('Remove', onRemove),
              if (patient != null && remaining > 0)
                FilesMenuItem('Apply to rest', onUseForRest),
            ],
            builder: (context, open) => CruIconButton(
              icon: CruIcons.chevronDown,
              size: CruSize.capsule,
              iconSize: 18,
              semanticLabel: 'Options for ${source.name}',
              tooltip: 'Options',
              onPressed: open,
            ),
          ),
        ],
      ),
    );
  }
}
