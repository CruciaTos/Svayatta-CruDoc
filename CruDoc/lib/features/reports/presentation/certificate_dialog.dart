import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/pdf/data/doc_numbering.dart';
import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context_builder.dart';
import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

Future<void> showCertificateDialog(
  BuildContext context, {
  required Patient patient,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CertificateDialog(patient: patient),
  );
}

class CertificateDialog extends StatefulWidget {
  const CertificateDialog({super.key, required this.patient});

  final Patient patient;

  @override
  State<CertificateDialog> createState() => _CertificateDialogState();
}

class _CertificateDialogState extends State<CertificateDialog> {
  static const _types = [
    'Sick leave',
    'Fitness to resume work',
    'Custom certificate',
  ];

  String _selectedType = 'Sick leave';
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now().add(const Duration(days: 3));
  final _diagnosisCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  late final TextEditingController _bodyCtrl;

  bool _manuallyEdited = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _diagnosisCtrl.text = widget.patient.diagnosisDisplay;
    _bodyCtrl = TextEditingController(text: _composeBody());
  }

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _remarksCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String _composeBody() {
    final p = widget.patient;
    final now = formatDocDate(DateTime.now());
    final from = formatDocDate(_fromDate);
    final to = formatDocDate(_toDate);
    final days = _toDate.difference(_fromDate).inDays + 1;
    final diag = _diagnosisCtrl.text.trim();
    final rem = _remarksCtrl.text.trim();

    final ageStr = p.age > 0 ? '${p.age} years' : '';
    final diagStr = diag.isNotEmpty ? ' for $diag' : '';
    final remStr = rem.isNotEmpty ? ' $rem' : '';

    switch (_selectedType) {
      case 'Sick leave':
        return 'This is to certify that ${p.fullName}, $ageStr was examined by me on $now and is advised medical rest from $from to $to ($days days)$diagStr.$remStr';
      case 'Fitness to resume work':
        return 'This is to certify that ${p.fullName}, $ageStr who was under medical treatment$diagStr, was examined by me on $now. The patient is found medically fit to resume normal duties / work from $from.$remStr';
      case 'Custom certificate':
      default:
        return 'This is to certify that ${p.fullName}, $ageStr was clinically examined on $now.$diagStr$remStr';
    }
  }

  void _syncBodyIfUntouched() {
    if (!_manuallyEdited) {
      _bodyCtrl.text = _composeBody();
    }
  }

  Future<void> _submit() async {
    if (_bodyCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);

    try {
      final now = DateTime.now();
      final num = await DocNumbering.next(DocKind.certificate, now);
      final issuing = defaultIssuingDoctorUid();
      final signer = docSignerFor(issuing);

      final p = widget.patient;
      final docData = PdfCertificateDocumentData(
        title: _selectedType,
        body: _bodyCtrl.text.trim(),
        documentNumber: num,
        documentDate: now,
        issuingDoctorUid: issuing,
        signedByUid: signer,
        patient: PdfPatientSnapshot(
          fullName: p.fullName,
          phone: p.phone.isNotEmpty ? p.phone : null,
          email: p.email.isNotEmpty ? p.email : null,
          ageGender: p.gender.isNotEmpty ? '${p.age} Y / ${p.gender}' : '${p.age} Y',
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      await MedicalPdfPreviewScreen.open(context, documentData: docData);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: 'Medical certificate',
      subtitle: 'Issued for ${widget.patient.fullName}',
      submitLabel: 'Preview',
      busy: _busy,
      onSubmit: _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Certificate type',
            description: 'Choose template and timeframe.',
            children: [
              CruFieldFrame(
                label: 'Type',
                child: CruSegmentedControl<String>(
                  semanticLabel: 'Certificate type',
                  segments: [for (final t in _types) CruSegment(t, t)],
                  selected: _selectedType,
                  onChanged: (t) {
                    setState(() {
                      _selectedType = t;
                      _syncBodyIfUntouched();
                    });
                  },
                ),
              ),
              CruFieldRow(
                children: [
                  CruPickerField(
                    label: _selectedType == 'Fitness to resume work'
                        ? 'Fit from'
                        : 'Rest from',
                    icon: CruIcons.calendar,
                    placeholder: 'Select date',
                    value: DateFormat('d MMM yyyy').format(_fromDate),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _fromDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() {
                          _fromDate = picked;
                          if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
                          _syncBodyIfUntouched();
                        });
                      }
                    },
                  ),
                  if (_selectedType == 'Sick leave')
                    CruPickerField(
                      label: 'Rest to',
                      icon: CruIcons.calendar,
                      placeholder: 'Select date',
                      value: DateFormat('d MMM yyyy').format(_toDate),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _toDate,
                          firstDate: _fromDate,
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() {
                            _toDate = picked;
                            _syncBodyIfUntouched();
                          });
                        }
                      },
                    ),
                ],
              ),
              CruTextField(
                label: 'Diagnosis',
                optional: true,
                controller: _diagnosisCtrl,
                hint: 'e.g. Acute viral gastroenteritis',
                onChanged: (_) => _syncBodyIfUntouched(),
              ),
              CruTextField(
                label: 'Remarks',
                optional: true,
                controller: _remarksCtrl,
                hint: 'e.g. Advised complete bed rest and hydration',
                onChanged: (_) => _syncBodyIfUntouched(),
              ),
            ],
          ),
          CruFormSection(
            title: 'Certificate text',
            description: 'You can edit the composed wording directly.',
            children: [
              CruTextField(
                label: 'Body text',
                controller: _bodyCtrl,
                maxLines: 5,
                onChanged: (_) => _manuallyEdited = true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
