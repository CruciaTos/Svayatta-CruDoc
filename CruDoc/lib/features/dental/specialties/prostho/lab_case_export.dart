import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_rx_pdf.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dialog explaining the ZIP contents and CAD integration status, with Export action.
class ExportLabCaseDialog extends ConsumerStatefulWidget {
  const ExportLabCaseDialog({
    super.key,
    required this.labCase,
    required this.patient,
  });

  final LabCase labCase;
  final Patient patient;

  @override
  ConsumerState<ExportLabCaseDialog> createState() => _ExportLabCaseDialogState();
}

class _ExportLabCaseDialogState extends ConsumerState<ExportLabCaseDialog> {
  bool _exporting = false;

  Future<void> _doExport() async {
    setState(() => _exporting = true);
    try {
      final success = await exportLabCaseZip(
        context: context,
        ref: ref,
        labCase: widget.labCase,
        patient: widget.patient,
      );
      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        recToast(context, 'Export failed: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final lc = widget.labCase;
    final p = widget.patient;

    return CruFormDialog(
      title: 'Export case for lab',
      subtitle: '${p.fullName} · ${lc.type}',
      width: 520,
      busy: _exporting,
      submitLabel: 'Export ZIP',
      onSubmit: _doExport,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Exports all clinical specifications, Rx prescription, and 3D scan files into a single ZIP archive for laboratory processing.',
            style: CruType.body.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s16),

          // Direct integration notice
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CruIcon(CruIcons.box, size: 16, color: c.accent),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct exocad / 3Shape integration: not connected yet.',
                        style: CruType.caption.w600.tint(c.label),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        'Labs import this ZIP archive manually into exocad DentalCAD, 3Shape Dental System, or other CAM software.',
                        style: CruType.micro.tint(c.label2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),

          // Archive content summary
          Text(
            'ARCHIVE CONTENTS',
            style: CruType.micro.w600.tint(c.label3),
          ),
          const SizedBox(height: CruSpace.s8),
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _contentRow(
                  icon: CruIcons.download,
                  name: 'order.pdf',
                  desc: 'Laboratory prescription form with clinical specs & signatures',
                  c: c,
                ),
                const CruSeparator(),
                _contentRow(
                  icon: CruIcons.download,
                  name: 'order.json',
                  desc: 'Machine-readable order specification & tooth mapping',
                  c: c,
                ),
                if (lc.files.isNotEmpty) ...[
                  const CruSeparator(),
                  for (final f in lc.files)
                    _contentRow(
                      icon: f.is3dScan ? CruIcons.box : CruIcons.download,
                      name: f.name,
                      desc: f.is3dScan ? '3D optical scan mesh' : 'Attached clinical file',
                      is3d: f.is3dScan,
                      c: c,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentRow({
    required CruIconData icon,
    required String name,
    required String desc,
    bool is3d = false,
    required CruColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      child: Row(
        children: [
          CruIcon(icon, size: 16, color: is3d ? c.accent : c.label2),
          const SizedBox(width: CruSpace.s8),
          Text(name, style: CruType.caption.w600.tint(c.label)),
          if (is3d) ...[
            const SizedBox(width: CruSpace.s6),
            CruPill(text: '3D', background: c.accentTint, foreground: c.accent),
          ],
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.micro.tint(c.label2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generates a ZIP archive containing order.json, order.pdf, and all attached files.
Future<bool> exportLabCaseZip({
  required BuildContext context,
  required WidgetRef ref,
  required LabCase labCase,
  required Patient patient,
}) async {
  final identity = ref.read(doctorIdentityProvider);
  final numbering = ref.read(toothNumberingProvider).value ?? ToothNumbering.fdi;

  // 1. Generate order.pdf
  final pdfBytes = await LabRxPdfService.buildRx(
    labCase: labCase,
    patient: patient,
    clinicName: identity.clinicName ?? '',
    doctorName: identity.fullName ?? '',
    numbering: numbering,
  );

  // 2. Build order.json
  final orderJsonMap = {
    'id': labCase.id,
    'exportedAt': DateTime.now().toIso8601String(),
    'patient': {
      'id': patient.id,
      'name': patient.fullName,
      'age': patient.age,
      'gender': patient.gender,
      'phone': patient.phone,
    },
    'clinic': {
      'name': identity.clinicName ?? '',
      'doctor': identity.fullName ?? '',
    },
    'case': {
      'type': labCase.type,
      'teeth': labCase.teeth,
      'teethFormatted': labCase.teeth.map((t) => toothLabel(t, numbering)).toList(),
      'material': labCase.material,
      'shade': labCase.shade,
      'shadeSystem': labCase.shadeSystem,
      'margin': labCase.margin,
      'notes': labCase.notes,
      'due': labCase.due.toIso8601String(),
      'stage': labCase.stage.name,
      'labName': labCase.labName,
      'labContactId': labCase.labContactId,
    },
    'attachments': [
      for (final f in labCase.files)
        {
          'name': f.name,
          'is3dScan': f.is3dScan,
        }
    ],
    'softwareIntegration': {
      'exocad': 'Direct integration not connected yet',
      'threeShape': 'Direct integration not connected yet',
    }
  };

  final jsonStr = const JsonEncoder.withIndent('  ').convert(orderJsonMap);
  final jsonBytes = utf8.encode(jsonStr);

  // 3. Assemble archive
  final archive = Archive();
  archive.addFile(ArchiveFile('order.json', jsonBytes.length, jsonBytes));
  archive.addFile(ArchiveFile('order.pdf', pdfBytes.length, pdfBytes));

  for (final file in labCase.files) {
    try {
      final f = File(file.path);
      if (f.existsSync()) {
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }
    } catch (_) {
      // Continue with remaining files if one fails to read
    }
  }

  final zipData = ZipEncoder().encode(archive);
  final zipBytes = Uint8List.fromList(zipData);

  final patientSlug = patient.fullName.trim().replaceAll(RegExp(r'[^\w\-]'), '_');
  final dateSlug = DateFormat('yyyyMMdd').format(DateTime.now());
  final fileName = 'Case_${patientSlug}_$dateSlug.zip';

  final savePath = await FilePicker.saveFile(
    dialogTitle: 'Export lab case ZIP',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['zip'],
    bytes: zipBytes,
  );

  if (savePath == null) return false;

  final outFile = File(savePath);
  if (!await outFile.exists() || await outFile.length() == 0) {
    await outFile.writeAsBytes(zipBytes, flush: true);
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Case exported: ${p.basename(savePath)}'),
        action: SnackBarAction(
          label: 'Show in folder',
          onPressed: () => launchUrl(Uri.file(p.dirname(savePath))),
        ),
      ),
    );
  }
  return true;
}
