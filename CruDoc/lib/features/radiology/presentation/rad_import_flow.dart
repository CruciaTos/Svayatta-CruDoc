import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_import.dart';
import 'package:doctor_management_app/features/radiology/presentation/pacs_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Import scans: pick a source (or take dropped [paths]), find the
/// studies in it, then confirm each one's patient and referral before it
/// joins the worklist. Returns how many studies were added.
Future<int> runRadImport(BuildContext context, WidgetRef ref, {List<String>? paths}) async {
  var picked = paths;
  if (picked == null) {
    picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _SourceDialog(),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return 0;
  }

  final temp = await getTemporaryDirectory();
  final work = p.join(temp.path, 'crudoc_import_${DateTime.now().millisecondsSinceEpoch}');
  if (!context.mounted) return 0;

  final scan = await showDialog<RadImportScan>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScanningDialog(paths: picked!, tempDir: work),
  );
  if (scan == null || !context.mounted) return 0;
  if (scan.isEmpty) {
    radToast(
      context,
      scan.skipped > 0
          ? 'No scans found. ${scan.skipped} files there aren\'t images CruDoc can read.'
          : 'No scans found in what you picked.',
    );
    return 0;
  }

  var added = 0;
  for (var i = 0; i < scan.groups.length; i++) {
    if (!context.mounted) break;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RadStudyFormDialog(
        group: scan.groups[i],
        stepLabel: scan.groups.length > 1 ? 'Study ${i + 1} of ${scan.groups.length}' : null,
      ),
    );
    if (ok == true) added++;
  }
  try {
    await Directory(work).delete(recursive: true);
  } catch (_) {}
  if (added > 0 && context.mounted) {
    radToast(context, added == 1 ? 'Added 1 study to the worklist' : 'Added $added studies to the worklist');
  }
  return added;
}

// ============================================================ source

class _SourceDialog extends StatelessWidget {
  const _SourceDialog();

  Future<void> _files(BuildContext context) async {
    final r = await FilePicker.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Pick scans (DICOM, JPG, PNG, TIFF or ZIP)',
    );
    final paths = r?.files.map((f) => f.path).whereType<String>().toList();
    if (paths != null && paths.isNotEmpty && context.mounted) Navigator.of(context).pop(paths);
  }

  Future<void> _folder(BuildContext context) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Pick a folder or the patient CD',
    );
    if (dir != null && context.mounted) Navigator.of(context).pop([dir]);
  }

  @override
  Widget build(BuildContext context) {
    return DentalPanelDialog(
      title: 'Import scans',
      subtitle: 'Or drop files and folders anywhere on the worklist',
      leading: const CruIconTile(icon: RadIcons.import, tone: CruTileTone.accent),
      width: CruSize.dialog + 180,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SourceTile(
              icon: RadIcons.xray,
              title: 'Files',
              body: 'DICOM files, pictures from an intraoral sensor, or a ZIP',
              onTap: () => _files(context),
            ),
            _SourceTile(
              icon: RadIcons.folder,
              title: 'Folder or patient CD',
              body: 'Every scan inside, sub-folders included (DICOMDIR discs work)',
              onTap: () => _folder(context),
            ),
            _SourceTile(
              icon: RadIcons.server,
              title: 'From a PACS',
              body: 'Search the practice or hospital PACS and download a study',
              onTap: () {
                Navigator.of(context).pop();
                showRadPacsQueryDialog(context);
              },
            ),
            _SourceTile(
              icon: RadIcons.cube,
              title: 'Straight from the scanner',
              body: 'Scanners "Send to CruDoc" over the network',
              onTap: () {
                Navigator.of(context).pop();
                showRadDicomReceiverDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final CruIconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalListRow(
      semanticLabel: title,
      onTap: onTap,
      minHeight: 64,
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.neutral),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.tint(c.label)),
                Text(body, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
        ],
      ),
    );
  }
}

// ============================================================ scanning

class _ScanningDialog extends StatefulWidget {
  const _ScanningDialog({required this.paths, required this.tempDir});

  final List<String> paths;
  final String tempDir;

  @override
  State<_ScanningDialog> createState() => _ScanningDialogState();
}

class _ScanningDialogState extends State<_ScanningDialog> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    RadImportScan scan;
    try {
      scan = await scanForImport(widget.paths, tempDir: widget.tempDir);
    } catch (_) {
      scan = const RadImportScan(groups: [], skipped: 0);
    }
    if (mounted) Navigator.of(context).pop(scan);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'Reading the files…',
      width: CruSize.dialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.bar),
              child: LinearProgressIndicator(
                minHeight: CruSize.progressBar,
                color: c.accent,
                backgroundColor: c.track,
              ),
            ),
            const SizedBox(height: CruSpace.s12),
            Text(
              'Finding the scans and grouping them by patient and study.',
              style: CruType.subhead.tint(c.label2),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ study form

/// Confirms an imported study ([group]) or edits an existing one's
/// referral ([existing]): study type, patient, referrer, question,
/// priority and fee.
class RadStudyFormDialog extends ConsumerStatefulWidget {
  const RadStudyFormDialog({super.key, this.group, this.existing, this.stepLabel})
      : assert(group != null || existing != null);

  final RadImportGroup? group;
  final RadStudy? existing;
  final String? stepLabel;

  @override
  ConsumerState<RadStudyFormDialog> createState() => _RadStudyFormDialogState();
}

enum _PatientLink { existing, create, none }

class _RadStudyFormDialogState extends ConsumerState<RadStudyFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _question;
  late final TextEditingController _description;
  late final TextEditingController _fee;
  late RadModality _modality;
  late RadPriority _priority;
  late DateTime _studyDate;
  DateTime? _dob;
  String _sex = '';
  RadReferrer? _referrer;
  Patient? _patient;
  late _PatientLink _link;
  bool _feeEdited = false;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  bool get _isImport => widget.group != null;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    final e = widget.existing;
    _name = TextEditingController(text: e?.patientName ?? g?.patientName ?? '');
    _question = TextEditingController(text: e?.clinicalQuestion ?? '');
    _description = TextEditingController(text: e?.description ?? g?.description ?? '');
    _modality = e?.modality ?? g?.modality ?? RadModality.other;
    _priority = e?.priority ?? RadPriority.routine;
    _studyDate = e?.studyDate ?? g?.studyDate ?? DateTime.now();
    _dob = e?.patientDob ?? g?.patientDob;
    _sex = e?.patientSex ?? g?.patientSex ?? '';
    _fee = TextEditingController(text: e?.fee?.toStringAsFixed(0) ?? '');
    _link = e != null && e.patientId.isNotEmpty ? _PatientLink.existing : _PatientLink.none;

    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  /// Patient match, referrer from the scan, fee from the fee list.
  Future<void> _prefill() async {
    final e = widget.existing;
    final patients = ref.read(patientsStreamProvider).value ?? const <Patient>[];
    if (e != null && e.patientId.isNotEmpty) {
      for (final p in patients) {
        if (p.id == e.patientId) _patient = p;
      }
    } else if (_isImport) {
      final matches = _matches(patients);
      if (matches.isNotEmpty) {
        _patient = matches.first;
        _link = _PatientLink.existing;
      } else if (_name.text.trim().isNotEmpty) {
        _link = _PatientLink.create;
      }
    }
    final referrers = await ref.read(radReferrersProvider.future);
    final byId = {for (final r in referrers) r.id: r};
    if (e != null) {
      _referrer = byId[e.referrerId];
    } else {
      final fromScan = widget.group!.referringPhysician.toLowerCase();
      if (fromScan.isNotEmpty) {
        for (final r in referrers) {
          final n = r.name.toLowerCase().replaceAll('dr. ', '').replaceAll('dr ', '');
          if (n.isNotEmpty && (fromScan.contains(n) || n.contains(fromScan))) _referrer = r;
        }
      }
    }
    if (_fee.text.isEmpty) await _feeFromList();
    if (mounted) setState(() {});
  }

  Future<void> _feeFromList() async {
    final f = await ref.read(radiologyProvider).feeFor(_modality);
    if (f != null) _fee.text = f.toStringAsFixed(0);
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// Clinic patients whose name (either order) matches the scan's name,
  /// date of birth breaking ties.
  List<Patient> _matches(List<Patient> patients) {
    final name = _name.text.trim();
    if (name.isEmpty) return const [];
    final parts = name.split(RegExp(r'\s+'));
    final a = _norm(name);
    final b = _norm([...parts.skip(1), parts.first].join());
    final out = patients.where((p) {
      if (p.isArchived) return false;
      final full = _norm(p.fullName);
      return full == a || full == b;
    }).toList();
    final dob = _dob;
    if (dob != null) {
      out.sort((x, y) {
        bool same(Patient p) =>
            p.dateOfBirth.year == dob.year &&
            p.dateOfBirth.month == dob.month &&
            p.dateOfBirth.day == dob.day;
        return (same(y) ? 1 : 0) - (same(x) ? 1 : 0);
      });
    }
    return out;
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<String> _patientId() async {
    switch (_link) {
      case _PatientLink.existing:
        return _patient?.id ?? '';
      case _PatientLink.none:
        return '';
      case _PatientLink.create:
        final parts = _name.text.trim().split(RegExp(r'\s+'));
        final now = DateTime.now();
        return ref.read(patientRepositoryProvider).createPatient(Patient(
              id: '',
              firstName: parts.first,
              lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
              phone: '',
              gender: _sex,
              dateOfBirth: _dob ?? DateTime(now.year - 30, 1, 1),
              diagnosis: const [],
              notes: 'Added from a radiology referral',
              packageBalance: 0,
              isArchived: false,
              createdAt: now,
              updatedAt: now,
            ));
    }
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    final ctrl = ref.read(radiologyProvider);
    try {
      final patientId = await _patientId();
      final name = _link == _PatientLink.existing && _patient != null
          ? _patient!.fullName
          : _name.text.trim();
      final fee = double.tryParse(_fee.text.trim());
      final e = widget.existing;
      if (e != null) {
        final due = e.priority != _priority ? await ctrl.dueFor(_priority, e.receivedAt) : e.dueAt;
        await ctrl.saveStudy(
          e.copyWith(
            patientId: patientId,
            patientName: name,
            patientSex: _sex,
            patientDob: _dob,
            modality: _modality,
            studyDate: _studyDate,
            description: _description.text.trim(),
            referrerId: _referrer?.id ?? '',
            clinicalQuestion: _question.text.trim(),
            priority: _priority,
            dueAt: due,
            fee: fee,
          ),
          auditAction: 'Edited referral',
          detail: name,
        );
      } else {
        final g = widget.group!;
        final id = radId('study_');
        final dir = await ctrl.studyDir(id);
        final images = await copyIntoStudy(g, dir.path);
        final now = DateTime.now();
        await ctrl.saveStudy(
          RadStudy(
            id: id,
            patientId: patientId,
            patientName: name,
            patientSex: _sex,
            patientDob: _dob,
            patientExternalId: g.patientExternalId,
            modality: _modality,
            studyDate: _studyDate,
            receivedAt: now,
            description: _description.text.trim(),
            referrerId: _referrer?.id ?? '',
            clinicalQuestion: _question.text.trim(),
            priority: _priority,
            dueAt: await ctrl.dueFor(_priority, now),
            images: images,
            dose: g.dose,
            studyUid: g.studyUid,
            accession: g.accession,
            institution: g.institution,
            equipment: g.equipment,
            bodyPart: g.bodyPart,
            fee: fee,
            createdAt: now,
            updatedAt: now,
          ),
          auditAction: 'Imported',
          detail: '$name · ${_modality.short} · ${RadFormat.images(images.length)}',
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the study. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final g = widget.group;
    final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
    final matches = _isImport ? _matches(patients).take(3).toList() : const <Patient>[];
    final files = g == null
        ? RadFormat.images(widget.existing!.imageCount)
        : [
            RadFormat.images(g.files.length),
            if (g.seriesCount > 1) '${g.seriesCount} series',
            if (g.equipment.isNotEmpty) g.equipment,
          ].join(' · ');

    return CruFormDialog(
      title: _isImport ? 'Add to worklist' : 'Edit referral',
      subtitle: [?widget.stepLabel, files].join(' · '),
      leading: CruIconTile(
          icon: _modality.isVolume ? RadIcons.cube : RadIcons.xray, tone: CruTileTone.accent),
      submitLabel: _isImport ? 'Add to worklist' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Study',
              description: 'The type picks the viewer, the report template and the fee.',
              children: [
                CruFieldFrame(
                  label: 'Type',
                  child: DentalChipWrap<RadModality>(
                    options: RadModality.values,
                    label: (m) => m.short,
                    isSelected: (m) => m == _modality,
                    onTap: (m) async {
                      setState(() => _modality = m);
                      _edited();
                      if (!_feeEdited) {
                        await _feeFromList();
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                ),
                CruFieldRow(children: [
                  CruPickerField(
                    label: 'Taken on',
                    icon: CruIcons.calendar,
                    value: RadFormat.date(_studyDate),
                    placeholder: 'Pick a date',
                    onTap: () async {
                      final d = await pickDentalDate(context,
                          initial: _studyDate, last: DateTime.now());
                      if (d != null) {
                        setState(() => _studyDate = d);
                        _edited();
                      }
                    },
                  ),
                  CruTextField(
                    label: 'Description',
                    optional: true,
                    controller: _description,
                    hint: 'Full volume, 16 × 10 cm',
                    onChanged: (_) => _edited(),
                  ),
                ]),
                if (g != null && g.compressedCount > 0)
                  RadNotConnected(
                    title: '${RadFormat.images(g.compressedCount)} use a compressed format',
                    body: 'JPEG 2000 / JPEG-LS scans are kept with the study but can\'t be '
                        'shown yet. Ask the scanner or PACS to export uncompressed DICOM '
                        'to read them now.',
                  ),
              ],
            ),
            CruFormSection(
              title: 'Patient',
              description: g?.patientName.isNotEmpty == true
                  ? 'The scan says ${g!.patientName}${g.patientExternalId.isNotEmpty ? ' (ID ${g.patientExternalId})' : ''}.'
                  : 'Who the scan is of.',
              children: [
                CruFieldFrame(
                  label: 'Patient record',
                  child: Wrap(
                    spacing: CruSpace.s8,
                    runSpacing: CruSpace.s8,
                    children: [
                      for (final m in matches)
                        DentalChoiceChip(
                          label: '${m.fullName} · ${m.age} y',
                          selected: _link == _PatientLink.existing && _patient?.id == m.id,
                          onTap: () {
                            setState(() {
                              _link = _PatientLink.existing;
                              _patient = m;
                            });
                            _edited();
                          },
                        ),
                      if (_patient != null && !matches.any((m) => m.id == _patient!.id))
                        DentalChoiceChip(
                          label: _patient!.fullName,
                          selected: _link == _PatientLink.existing,
                          onTap: () => setState(() => _link = _PatientLink.existing),
                        ),
                      DentalChoiceChip(
                        label: 'Pick a patient…',
                        selected: false,
                        onTap: () async {
                          final picked =
                              await pickRadPatient(context, initialQuery: _name.text.trim());
                          if (picked != null) {
                            setState(() {
                              _patient = picked;
                              _link = _PatientLink.existing;
                            });
                            _edited();
                          }
                        },
                      ),
                      DentalChoiceChip(
                        label: 'New patient record',
                        selected: _link == _PatientLink.create,
                        onTap: () {
                          setState(() => _link = _PatientLink.create);
                          _edited();
                        },
                      ),
                      DentalChoiceChip(
                        label: "Don't link",
                        selected: _link == _PatientLink.none,
                        onTap: () {
                          setState(() => _link = _PatientLink.none);
                          _edited();
                        },
                      ),
                    ],
                  ),
                ),
                if (_link != _PatientLink.existing) ...[
                  CruTextField(
                    label: 'Name',
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Add the patient\'s name.' : null,
                    onChanged: (_) {
                      _edited();
                      setState(() {});
                    },
                  ),
                  CruFieldRow(children: [
                    CruPickerField(
                      label: 'Date of birth',
                      optional: true,
                      icon: CruIcons.calendar,
                      value: _dob == null ? null : RadFormat.date(_dob!),
                      placeholder: 'Pick a date',
                      onTap: () async {
                        final d = await pickDentalDate(context,
                            initial: _dob ?? DateTime(DateTime.now().year - 30),
                            last: DateTime.now());
                        if (d != null) {
                          setState(() => _dob = d);
                          _edited();
                        }
                      },
                    ),
                    CruFieldFrame(
                      label: 'Sex',
                      optional: true,
                      child: DentalChipWrap<String>(
                        options: const ['Female', 'Male', 'Other'],
                        label: (s) => s,
                        isSelected: (s) => s == _sex,
                        onTap: (s) {
                          setState(() => _sex = _sex == s ? '' : s);
                          _edited();
                        },
                      ),
                    ),
                  ]),
                ],
              ],
            ),
            CruFormSection(
              title: 'Referral',
              description: 'Who sent it, what they want to know, and how soon.',
              children: [
                CruPickerField(
                  label: 'Referred by',
                  optional: true,
                  icon: RadIcons.referrer,
                  value: _referrer?.display,
                  placeholder: g?.referringPhysician.isNotEmpty == true
                      ? 'The scan says ${g!.referringPhysician}'
                      : 'Pick a referrer',
                  onTap: () async {
                    final r = await pickRadReferrer(context, selectedId: _referrer?.id);
                    if (r != null) {
                      setState(() => _referrer = r);
                      _edited();
                    }
                  },
                ),
                CruTextField(
                  label: 'Clinical question',
                  optional: true,
                  controller: _question,
                  maxLines: 2,
                  hint: 'Implant site 36 — bone width and canal distance',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
                CruFieldRow(children: [
                  CruFieldFrame(
                    label: 'Priority',
                    help: 'Sets when the report is due.',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CruSegmentedControl<RadPriority>(
                        semanticLabel: 'Priority',
                        segments: [
                          for (final p in RadPriority.values) CruSegment(p, p.label),
                        ],
                        selected: _priority,
                        onChanged: (p) {
                          setState(() => _priority = p);
                          _edited();
                        },
                      ),
                    ),
                  ),
                  CruTextField(
                    label: 'Reading fee',
                    optional: true,
                    controller: _fee,
                    prefix: '₹',
                    tabular: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      _feeEdited = true;
                      _edited();
                    },
                  ),
                ]),
                if (_priority == RadPriority.stat)
                  Text(
                    'STAT studies go to the top of the worklist.',
                    style: CruType.caption.tint(c.label2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
