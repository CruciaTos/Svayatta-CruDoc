import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_export.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_rx_pdf.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/scan_viewer_placeholder.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ───────────────────────────── Create / Edit Lab Case Dialog ─────────────────────────────

/// Dialog to create or edit a prosthodontic lab case.
class LabCaseEditDialog extends ConsumerStatefulWidget {
  const LabCaseEditDialog({
    super.key,
    this.initialCase,
    this.initialPatient,
  });

  final LabCase? initialCase;
  final Patient? initialPatient;

  @override
  ConsumerState<LabCaseEditDialog> createState() => _LabCaseEditDialogState();
}

class _LabCaseEditDialogState extends ConsumerState<LabCaseEditDialog> {
  Patient? _patient;
  ReferralContact? _selectedLab;

  late String _type;
  late final TextEditingController _teeth;
  late String _material;
  late String _shade;
  late String _margin;
  late final TextEditingController _notes;
  late DateTime _due;
  late LabCaseStage _stage;
  List<LabCaseFile> _files = [];

  bool _busy = false;
  String? _teethError;

  @override
  void initState() {
    super.initState();
    final c = widget.initialCase;
    _patient = widget.initialPatient;
    _type = c?.type ?? labCaseTypes.first;
    _teeth = TextEditingController(text: c?.teeth.join(', ') ?? '');
    _material = c?.material ?? labMaterials.first;
    _shade = c?.shade ?? 'A2';
    _margin = c?.margin ?? labMargins.first;
    _notes = TextEditingController(text: c?.notes ?? '');
    _due = c?.due ?? DateTime.now().add(const Duration(days: 7));
    _stage = c?.stage ?? LabCaseStage.scanned;
    _files = c != null ? [...c.files] : [];

    if (c != null && _patient == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final patients = ref.read(patientsStreamProvider).value ?? const [];
        final match = patients.where((p) => p.id == c.patientId).firstOrNull;
        if (match != null && mounted) {
          setState(() => _patient = match);
        }
      });
    }
  }

  @override
  void dispose() {
    _teeth.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _parseAndValidateTeeth(String raw) {
    if (raw.trim().isEmpty) return const [];
    final tokens = raw.split(RegExp(r'[, ]+')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    for (final t in tokens) {
      if (!DentalChart.isValid(t)) {
        throw FormatException('Invalid FDI tooth number: "$t"');
      }
    }
    return tokens;
  }

  Future<void> _pickPatient() async {
    final picked = await pickRadPatient(context);
    if (picked != null && mounted) {
      setState(() => _patient = picked);
    }
  }

  Future<void> _pickDueDate() async {
    final date = await pickDentalDate(context, initial: _due);
    if (date != null && mounted) {
      setState(() => _due = date);
    }
  }

  Future<void> _addAttachment() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final appSupport = await getApplicationSupportDirectory();
    final caseId = widget.initialCase?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final targetDir = Directory(p.join(appSupport.path, 'dental', 'labcases', caseId));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final newFiles = <LabCaseFile>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final src = File(f.path!);
      final destPath = p.join(targetDir.path, p.basename(f.path!));
      await src.copy(destPath);

      final lowerName = f.name.toLowerCase();
      final kind = (lowerName.endsWith('.stl') || lowerName.endsWith('.ply') || lowerName.endsWith('.obj'))
          ? 'scan'
          : (lowerName.endsWith('.jpg') || lowerName.endsWith('.png') ? 'photo' : 'other');

      newFiles.add(LabCaseFile(path: destPath, name: f.name, kind: kind));
    }

    if (mounted) {
      setState(() => _files.addAll(newFiles));
    }
  }

  Future<void> _save() async {
    if (_patient == null) {
      recToast(context, 'Please select a patient');
      return;
    }

    List<String> parsedTeeth = [];
    try {
      parsedTeeth = _parseAndValidateTeeth(_teeth.text);
      _teethError = null;
    } catch (e) {
      setState(() => _teethError = e.toString());
      return;
    }

    setState(() => _busy = true);

    try {
      final c = widget.initialCase;
      final labName = _selectedLab?.name ?? c?.labName ?? '';
      final labContactId = _selectedLab?.id ?? c?.labContactId ?? '';
      final now = DateTime.now();

      final stageChanged = c != null && c.stage != _stage;
      final nextHistory = c != null
          ? [
              ...c.history.map((h) => h.toJson()),
              if (stageChanged)
                {
                  'stage': _stage.name,
                  'at': now.millisecondsSinceEpoch,
                  'note': 'Stage updated to ${_stage.label}',
                }
            ]
          : [
              {
                'stage': _stage.name,
                'at': now.millisecondsSinceEpoch,
                'note': 'Lab case created',
              }
            ];

      if (c == null) {
        final record = DentalRecord.create(
          _patient!.id,
          RecKind.labCase,
          {
            'labContactId': labContactId,
            'labName': labName,
            'type': _type,
            'teeth': parsedTeeth,
            'material': _material,
            'shade': _shade,
            'shadeSystem': 'VITA classical',
            'margin': _margin,
            'notes': _notes.text.trim(),
            'due': _due.millisecondsSinceEpoch,
            'stage': _stage.name,
            'history': nextHistory,
            'files': _files.map((f) => f.toJson()).toList(),
          },
          at: now,
        );
        await saveDentalRecord(ref, record);
        if (mounted) recToast(context, 'Lab case created');
      } else {
        final updatedRecord = c.record.copyWith(
          data: {
            ...c.record.data,
            'labContactId': labContactId,
            'labName': labName,
            'type': _type,
            'teeth': parsedTeeth,
            'material': _material,
            'shade': _shade,
            'margin': _margin,
            'notes': _notes.text.trim(),
            'due': _due.millisecondsSinceEpoch,
            'stage': _stage.name,
            'history': nextHistory,
            'files': _files.map((f) => f.toJson()).toList(),
          },
        );
        await saveDentalRecord(ref, updatedRecord);
        if (mounted) recToast(context, 'Lab case updated');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving lab case: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final labs = ref.watch(labPartnersProvider);
    final allContacts = ref.watch(referralContactsProvider);
    final numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;

    // Resolve selected lab
    if (_selectedLab == null && widget.initialCase != null) {
      _selectedLab = allContacts.where((cnt) => cnt.id == widget.initialCase!.labContactId).firstOrNull;
    }

    return CruFormDialog(
      title: widget.initialCase == null ? 'New lab prescription' : 'Edit lab case',
      subtitle: '${_patient?.fullName ?? 'Patient'} · $_type',
      width: 600,
      busy: _busy,
      submitLabel: widget.initialCase == null ? 'Create order' : 'Save changes',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Patient
          CruFieldFrame(
            label: 'Patient',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _patient != null
                        ? '${_patient!.fullName} (${_patient!.age}y, ${_patient!.gender.toUpperCase()})'
                        : 'No patient selected',
                    style: CruType.body.tint(_patient != null ? c.label : c.label3),
                  ),
                ),
                CruCapsuleButton(
                  label: _patient != null ? 'Change' : 'Pick patient',
                  icon: CruIcons.search,
                  onPressed: _pickPatient,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Lab partner
          CruFieldFrame(
            label: 'Dental lab partner',
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedLab?.id,
                      hint: Text(
                        labs.isEmpty ? 'No dental labs saved' : 'Select dental lab',
                        style: CruType.body.tint(c.label3),
                      ),
                      items: [
                        for (final lab in (labs.isNotEmpty ? labs : allContacts))
                          DropdownMenuItem<String>(
                            value: lab.id,
                            child: Text(
                              '${lab.name}${lab.turnaroundDays != null ? ' (${lab.turnaroundDays}d turnaround)' : ''}',
                              style: CruType.body.tint(c.label),
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        setState(() {
                          _selectedLab = allContacts.where((cnt) => cnt.id == id).firstOrNull;
                          if (_selectedLab?.turnaroundDays != null && widget.initialCase == null) {
                            _due = DateTime.now().add(Duration(days: _selectedLab!.turnaroundDays!));
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                CruCapsuleButton(
                  label: 'Add lab',
                  icon: CruIcons.plus,
                  onPressed: () async {
                    final newContact = await showDialog<ReferralContact>(
                      context: context,
                      builder: (_) => const EditContactDialog(
                        contact: ReferralContact(id: '', name: '', specialty: 'Dental lab'),
                      ),
                    );
                    if (newContact != null && mounted) {
                      setState(() {
                        _selectedLab = newContact;
                        if (newContact.turnaroundDays != null && widget.initialCase == null) {
                          _due = DateTime.now().add(Duration(days: newContact.turnaroundDays!));
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Restoration type & Material row
          Row(
            children: [
              Expanded(
                child: CruFieldFrame(
                  label: 'Restoration type',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _type,
                      items: [
                        for (final t in labCaseTypes)
                          DropdownMenuItem<String>(value: t, child: Text(t, style: CruType.body.tint(c.label))),
                      ],
                      onChanged: (t) {
                        if (t != null) setState(() => _type = t);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: CruFieldFrame(
                  label: 'Material',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _material,
                      items: [
                        for (final m in labMaterials)
                          DropdownMenuItem<String>(value: m, child: Text(m, style: CruType.body.tint(c.label))),
                      ],
                      onChanged: (m) {
                        if (m != null) setState(() => _material = m);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Teeth (FDI)
          CruTextField(
            label: 'Teeth (FDI, comma-separated)',
            controller: _teeth,
            hint: 'e.g. 16, 26, 36 (Universal: ${toothLabel('16', numbering)})',
            help: _teethError,
            onChanged: (_) {
              if (_teethError != null) setState(() => _teethError = null);
            },
          ),
          const SizedBox(height: CruSpace.s12),

          // Shade Guide Selection
          CruFieldFrame(
            label: 'Shade (VITA classical)',
            child: Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final s in vitaShades)
                  DentalChoiceChip(
                    label: s,
                    selected: _shade == s,
                    onTap: () => setState(() => _shade = s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Margin design & Due date row
          Row(
            children: [
              Expanded(
                child: CruFieldFrame(
                  label: 'Margin design',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _margin,
                      items: [
                        for (final m in labMargins)
                          DropdownMenuItem<String>(value: m, child: Text(m, style: CruType.body.tint(c.label))),
                      ],
                      onChanged: (m) {
                        if (m != null) setState(() => _margin = m);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: CruFieldFrame(
                  label: 'Due date',
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DentalFormat.date(_due),
                          style: CruType.body.w600.tabular.tint(c.label),
                        ),
                      ),
                      CruCapsuleButton(
                        label: 'Change',
                        icon: CruIcons.calendar,
                        onPressed: _pickDueDate,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Stage
          CruFieldFrame(
            label: 'Current stage',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<LabCaseStage>(
                isExpanded: true,
                value: _stage,
                items: [
                  for (final st in LabCaseStage.values)
                    DropdownMenuItem<LabCaseStage>(
                      value: st,
                      child: Text(st.label, style: CruType.body.tint(c.label)),
                    ),
                ],
                onChanged: (st) {
                  if (st != null) setState(() => _stage = st);
                },
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Notes
          CruTextField(
            label: 'Clinical instructions & occlusal clearance',
            controller: _notes,
            maxLines: 4,
            hint: 'Provide specific instructions: contact tightness, anatomy, translucency, bite registration...',
          ),
          const SizedBox(height: CruSpace.s16),

          // Attached scan / photo files
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attached Files (${_files.length})',
                style: CruType.callout.w600.tint(c.label),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.initialCase != null && _patient != null) ...[
                    CruCapsuleButton(
                      label: 'Export case (ZIP)',
                      icon: CruIcons.download,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ExportLabCaseDialog(
                          labCase: widget.initialCase!,
                          patient: _patient!,
                        ),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  CruCapsuleButton(
                    label: 'Add files',
                    icon: CruIcons.plus,
                    onPressed: _addAttachment,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          if (_files.isEmpty)
            Text(
              'No scan or design files attached yet (.stl, .ply, photos).',
              style: CruType.caption.tint(c.label3),
            )
          else
            for (final f in _files)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s6),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    children: [
                      CruIcon(CruIcons.box, size: 16, color: c.label2),
                      const SizedBox(width: CruSpace.s8),
                      if (f.is3dScan) ...[
                        CruPill(
                          text: '3D',
                          background: c.accentTint,
                          foreground: c.accent,
                        ),
                        const SizedBox(width: CruSpace.s6),
                      ],
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.note.tint(c.label),
                        ),
                      ),
                      CruIconButton(
                        icon: CruIcons.arrowUpRight,
                        size: CruSize.squareButton,
                        semanticLabel: 'Open file',
                        tooltip: 'Open file',
                        onPressed: () {
                          if (f.is3dScan) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ScanViewerPlaceholderScreen(
                                  filePath: f.path,
                                  fileName: f.name,
                                ),
                              ),
                            );
                          } else {
                            launchUrl(Uri.file(f.path));
                          }
                        },
                      ),
                      CruIconButton(
                        icon: CruIcons.close,
                        size: CruSize.squareButton,
                        semanticLabel: 'Remove file',
                        tooltip: 'Remove',
                        onPressed: () => setState(() => _files.remove(f)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Patient Lab Cases Dialog ─────────────────────────────

/// Dialog opened from DentalRecordsCard showing all lab cases for one specific patient.
class PatientLabCasesDialog extends ConsumerWidget {
  const PatientLabCasesDialog({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final records = ref.watch(patientRecordsProvider((patientId: patient.id, kind: RecKind.labCase))).value ??
        const <DentalRecord>[];
    final cases = records.map(LabCase.fromRecord).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    return DentalPanelDialog(
      title: 'Lab cases: ${patient.fullName}',
      subtitle: '${cases.length} cases prescribed',
      leading: const CruIconTile(icon: CruIcons.box, tone: CruTileTone.neutral),
      width: 560,
      footer: CruButton(
        label: 'New lab case',
        icon: CruIcons.plus,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => LabCaseEditDialog(initialPatient: patient),
        ),
      ),
      body: cases.isEmpty
          ? DentalEmptyState(
              icon: CruIcons.box,
              title: 'No lab cases for this patient',
              body: 'Create an Rx for crowns, bridges, dentures or night guards.',
              actions: [
                CruButton(
                  label: 'New lab case',
                  icon: CruIcons.plus,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => LabCaseEditDialog(initialPatient: patient),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final lc in cases)
                  DentalListRow(
                    semanticLabel: '${lc.type} - ${lc.stage.label}',
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => LabCaseEditDialog(
                        initialCase: lc,
                        initialPatient: patient,
                      ),
                    ),
                    child: Row(
                      children: [
                        CruIconTile(icon: CruIcons.box, tone: CruTileTone.neutral),
                        const SizedBox(width: CruSpace.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${lc.type} (${lc.material})', style: CruType.callout.w600.tint(c.label)),
                              Text(
                                '${lc.teeth.join(', ')} · Due ${DentalFormat.date(lc.due)} · Lab: ${lc.labName.isNotEmpty ? lc.labName : 'Partner'}',
                                style: CruType.caption.tint(c.label2),
                              ),
                            ],
                          ),
                        ),
                        CruPill(
                          text: lc.stage.label,
                          background: lc.stage == LabCaseStage.fitted
                              ? c.greenTint
                              : (lc.isOverdue(DateTime.now()) ? c.amberTint : c.inset),
                          foreground: lc.stage == LabCaseStage.fitted
                              ? c.greenText
                              : (lc.isOverdue(DateTime.now()) ? c.amberText : c.label2),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────────── Actions Helpers ─────────────────────────────

/// Updates lab case stage and appends history log.
Future<void> updateLabCaseStage(
  BuildContext context,
  WidgetRef ref,
  LabCase labCase,
  LabCaseStage nextStage, {
  Patient? patient,
}) async {
  final now = DateTime.now();
  final nextHistory = [
    ...labCase.history.map((h) => h.toJson()),
    {
      'stage': nextStage.name,
      'at': now.millisecondsSinceEpoch,
      'note': 'Stage updated to ${nextStage.label}',
    }
  ];

  final updated = labCase.record.copyWith(
    data: {
      ...labCase.record.data,
      'stage': nextStage.name,
      'history': nextHistory,
    },
  );
  await saveDentalRecord(ref, updated);

  if (context.mounted) {
    recToast(context, 'Case moved to ${nextStage.label}');
  }

  // When stage becomes 'received', offer to message the patient
  if (nextStage == LabCaseStage.received && patient != null && context.mounted) {
    final send = await confirmDental(
      context,
      title: 'Notify patient?',
      body: 'Send WhatsApp to ${patient.fullName}: "Your ${labCase.type.toLowerCase()} is ready. Please book a visit to fit it."',
      action: 'Message patient',
    );
    if (send && context.mounted) {
      await PatientActions.whatsApp(
        context,
        patient,
        message: 'Your ${labCase.type.toLowerCase()} is ready. Please book a visit to fit it.',
      );
    }
  }
}

/// Generates prescription PDF, sets stage to sent, and sends WhatsApp to lab.
Future<void> sendLabCaseToLab(
  BuildContext context,
  WidgetRef ref,
  LabCase labCase,
  Patient patient,
) async {
  final contacts = ref.read(referralContactsProvider);
  final lab = contacts.where((cnt) => cnt.id == labCase.labContactId).firstOrNull;
  final phone = lab?.phone ?? '';

  final pdfPath = await LabRxPdfService.saveRxToFolder(
    labCase: labCase,
    patient: patient,
    ref: ref,
  );

  if (labCase.stage == LabCaseStage.scanned && context.mounted) {
    await updateLabCaseStage(context, ref, labCase, LabCaseStage.sent, patient: patient);
  }

  if (phone.isNotEmpty) {
    final message = 'Hello ${labCase.labName}, prescription for ${patient.fullName} (${labCase.type} ${labCase.teeth.join(',')}). Due: ${DentalFormat.date(labCase.due)}. Prescription PDF generated.';
    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(rawPhone: phone, message: message);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Prescription saved: ${p.basename(pdfPath)}'),
        action: SnackBarAction(
          label: 'Show in folder',
          onPressed: () => launchUrl(Uri.file(p.dirname(pdfPath))),
        ),
      ),
    );
  }
}
