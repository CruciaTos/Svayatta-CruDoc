import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Drug row model for clinical prescription.
class PrescriptionDrugRow {
  PrescriptionDrugRow({
    required this.drugName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.instructions,
  });

  String drugName;
  String dosage;
  String frequency;
  String duration;
  String instructions;
}

/// Rich, clinical Prescription (Rx) Generation Interface with Letterhead Branding.
class PrescriptionGenerationSheet extends StatefulWidget {
  const PrescriptionGenerationSheet({
    super.key,
    required this.letterheadConfig,
    this.initialVisit,
    this.initialPatient,
  });

  final DoctorLetterheadConfig letterheadConfig;
  final Visit? initialVisit;
  final Patient? initialPatient;

  @override
  State<PrescriptionGenerationSheet> createState() =>
      _PrescriptionGenerationSheetState();
}

class _PrescriptionGenerationSheetState
    extends State<PrescriptionGenerationSheet> {
  late final TextEditingController _patientNameCtrl;
  late final TextEditingController _patientAgeGenderCtrl;
  late final TextEditingController _patientPhoneCtrl;
  late final TextEditingController _vitalsCtrl;
  late final TextEditingController _complaintsCtrl;
  late final TextEditingController _diagnosisCtrl;
  late final TextEditingController _labTestsCtrl;
  late final TextEditingController _adviceCtrl;
  late final TextEditingController _followUpCtrl;

  late DateTime _rxDate;
  late String _rxNumber;

  final List<PrescriptionDrugRow> _drugs = [
    PrescriptionDrugRow(
      drugName: 'Tab. Paracetamol',
      dosage: '650 mg',
      frequency: '1 - 0 - 1 (Twice daily)',
      duration: '5 Days',
      instructions: 'After Food',
    ),
    PrescriptionDrugRow(
      drugName: 'Cap. Amoxicillin',
      dosage: '500 mg',
      frequency: '1 - 1 - 1 (Thrice daily)',
      duration: '5 Days',
      instructions: 'After Food',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _rxDate = widget.initialVisit?.scheduledStart ?? DateTime.now();
    final rxSeq = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    _rxNumber = 'RX-$rxSeq';

    _patientNameCtrl = TextEditingController(
      text: widget.initialPatient?.fullName ?? '',
    );
    _patientAgeGenderCtrl = TextEditingController(
      text: widget.initialPatient?.gender != null
          ? '${widget.initialPatient?.gender}'
          : '35 Y / M',
    );
    _patientPhoneCtrl = TextEditingController(
      text: widget.initialPatient?.phone ?? '',
    );
    _vitalsCtrl = TextEditingController(
      text: 'BP: 120/80 mmHg | Pulse: 76 bpm | SpO2: 98% | Wt: 68 kg',
    );
    _complaintsCtrl = TextEditingController(
      text:
          widget.initialVisit?.treatmentType ??
          'Fever with body ache for 3 days',
    );
    _diagnosisCtrl = TextEditingController(
      text: widget.initialPatient?.diagnosis.isNotEmpty == true
          ? widget.initialPatient!.diagnosis.join(', ')
          : 'Acute Upper Respiratory Tract Infection (URTI)',
    );
    _labTestsCtrl = TextEditingController(
      text: 'Complete Blood Count (CBC), CRP',
    );
    _adviceCtrl = TextEditingController(
      text: 'Adequate hydration, warm saline gargles, light warm diet.',
    );
    _followUpCtrl = TextEditingController(
      text: 'Follow up after 5 days if fever persists.',
    );
  }

  @override
  void dispose() {
    _patientNameCtrl.dispose;
    _patientAgeGenderCtrl.dispose;
    _patientPhoneCtrl.dispose;
    _vitalsCtrl.dispose;
    _complaintsCtrl.dispose;
    _diagnosisCtrl.dispose;
    _labTestsCtrl.dispose;
    _adviceCtrl.dispose;
    _followUpCtrl.dispose;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.letterheadConfig;
    final c = context.cru;

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      child: Column(
        children: [
          // ---- Drag Handle & Top Bar ----
          Container(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              CruSpace.s12,
              CruSpace.s16,
              CruSpace.s12,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CruRadius.card),
              ),
              border: Border(bottom: BorderSide(color: c.separator)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: ShapeDecoration(
                      color: c.track,
                      shape: cruShape(CruRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s10),
                Row(
                  children: [
                    Container(
                      width: CruSize.iconTile,
                      height: CruSize.iconTile,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: c.inset,
                        shape: cruShape(CruRadius.iconTile),
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        color: c.label2,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: CruSpace.s10),
                    Expanded(
                      child: Text(
                        'Generate prescription (Rx)',
                        style: CruType.headline.tint(c.label),
                      ),
                    ),
                    CruIconButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Close',
                      size: CruSize.control,
                      iconSize: 18,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Prescription Body & Live Letterhead ----
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s20),
              children: [
                // ---- Doctor & Clinic Letterhead Banner ----
                _section(
                  c,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (cfg.logoUrl != null &&
                            cfg.logoUrl!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: CruSpace.s14,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CruRadius.control,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: cfg.logoUrl!,
                                width: 54,
                                height: 54,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Icon(
                                  Icons.local_hospital_rounded,
                                  size: 36,
                                  color: c.label3,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 54,
                            height: 54,
                            margin: const EdgeInsets.only(right: CruSpace.s14),
                            decoration: ShapeDecoration(
                              color: c.inset,
                              shape: cruShape(CruRadius.control),
                            ),
                            child: Icon(
                              Icons.local_hospital_rounded,
                              size: 30,
                              color: c.label3,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cfg.clinicName,
                                style: CruType.headline.tint(c.label),
                              ),
                              const SizedBox(height: CruSpace.s2),
                              Text(
                                '${cfg.doctorName} • ${cfg.qualifications}',
                                style: CruType.subhead.w600.tint(c.label2),
                              ),
                              Text(
                                '${cfg.specialty} | Reg. No: ${cfg.registrationNumber}',
                                style: CruType.caption.tint(c.label3),
                              ),
                              const SizedBox(height: CruSpace.s2),
                              Text(
                                '📍 ${cfg.clinicAddress} • 📞 ${cfg.clinicPhone}',
                                style: CruType.caption.tabular.tint(c.label3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Patient Info & Vitals Header ----
                _section(
                  c,
                  title: 'Patient & consultation info',
                  trailing: Text(
                    'Rx: $_rxNumber | ${DateFormat('dd MMM yyyy').format(_rxDate)}',
                    style: CruType.caption.w500.tabular.tint(c.label3),
                  ),
                  children: [
                    CruFieldRow(
                      flex: const [3, 2],
                      children: [
                        CruTextField(
                          label: 'Patient name',
                          controller: _patientNameCtrl,
                          icon: CruIcons.user,
                          textCapitalization: TextCapitalization.words,
                        ),
                        CruTextField(
                          label: 'Age / gender',
                          controller: _patientAgeGenderCtrl,
                          tabular: true,
                        ),
                      ],
                    ),
                    CruTextField(
                      label: 'Vitals (BP, pulse, weight, SpO2)',
                      controller: _vitalsCtrl,
                      tabular: true,
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Clinical Complaints & Diagnosis ----
                _section(
                  c,
                  title: 'Clinical findings',
                  children: [
                    CruTextField(
                      label: 'Chief complaints & history',
                      controller: _complaintsCtrl,
                    ),
                    CruTextField(
                      label: 'Diagnosis / impression',
                      controller: _diagnosisCtrl,
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Rx Medications Table ----
                _section(
                  c,
                  title: '℞  Prescribed medications',
                  trailing: CruCapsuleButton(
                    label: 'Add drug',
                    icon: CruIcons.plus,
                    onPressed: _addNewDrug,
                  ),
                  gap: CruSpace.s12,
                  children: [
                    for (final entry in _drugs.asMap().entries)
                      _buildDrugCard(c, entry.key, entry.value),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Lab Tests, Advice & Follow Up ----
                _section(
                  c,
                  title: 'Advice & investigations',
                  children: [
                    CruTextField(
                      label: 'Lab tests / investigations advised',
                      controller: _labTestsCtrl,
                    ),
                    CruTextField(
                      label: 'Diet & lifestyle advice',
                      controller: _adviceCtrl,
                    ),
                    CruTextField(
                      label: 'Follow-up date / instructions',
                      controller: _followUpCtrl,
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // ---- Signature & Stamp Area ----
                Container(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  decoration: ShapeDecoration(
                    color: c.inset,
                    shape: cruShape(CruRadius.card),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cfg.footerDisclaimer,
                          style: CruType.caption.tint(c.label3),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(Icons.draw_rounded, color: c.label2, size: 24),
                          const SizedBox(height: CruSpace.s4),
                          Text(
                            cfg.doctorName,
                            style: CruType.subhead.w600.tint(c.label),
                          ),
                          Text(
                            'Reg: ${cfg.registrationNumber}',
                            style: CruType.micro.tabular.tint(c.label3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CruSpace.s24),
              ],
            ),
          ),

          // ---- Bottom Action Toolbar ----
          Container(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              CruSpace.s14,
              CruSpace.s20,
              CruSpace.s24,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.separator)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: CruButton(
                    label: 'WhatsApp Rx',
                    icon: CruIcons.whatsapp,
                    kind: CruButtonKind.secondary,
                    large: true,
                    expand: true,
                    onPressed: _shareRxWhatsApp,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: CruButton(
                    label: 'Save & print Rx',
                    icon: CruIcons.fileText,
                    large: true,
                    expand: true,
                    onPressed: _generateAndSavePrescription,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewDrug() {
    setState(() {
      _drugs.add(
        PrescriptionDrugRow(
          drugName: 'Tab. Multivitamin',
          dosage: '1 Tab',
          frequency: '0 - 1 - 0',
          duration: '15 Days',
          instructions: 'After Food',
        ),
      );
    });
  }

  /// A surface card (radius 24) with an optional title row.
  Widget _section(
    CruColors c, {
    String? title,
    Widget? trailing,
    double gap = CruSpace.s16,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(title, style: CruType.callout.tint(c.label)),
                ),
                ?trailing,
              ],
            ),
            SizedBox(height: gap),
          ],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }

  /// One drug: an inset panel (radius 12) of borderless fields — name and
  /// dosage, then frequency, duration and timing.
  Widget _buildDrugCard(CruColors c, int idx, PrescriptionDrugRow drug) {
    final input = CruType.input.tint(c.label);
    InputDecoration cell(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: false,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
    );
    return Container(
      key: ObjectKey(drug),
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s8,
        CruSpace.s4,
        CruSpace.s8,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: drug.drugName,
                  style: input.w600,
                  decoration: cell('Drug name (Tab / Cap / Syp)'),
                  onChanged: (v) => setState(() => drug.drugName = v),
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                flex: 1,
                child: TextFormField(
                  initialValue: drug.dosage,
                  style: input.tabular,
                  decoration: cell('Dosage'),
                  onChanged: (v) => setState(() => drug.dosage = v),
                ),
              ),
              if (_drugs.length > 1)
                IconButton(
                  tooltip: 'Remove drug',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: c.label3,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _drugs.removeAt(idx)),
                )
              else
                const SizedBox(width: CruSpace.s8),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: CruSpace.s6,
              bottom: CruSpace.s6,
              right: CruSpace.s8,
            ),
            child: Divider(height: 1, thickness: 1, color: c.separator),
          ),
          Padding(
            padding: const EdgeInsets.only(right: CruSpace.s8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: drug.frequency,
                    style: input.tabular,
                    decoration: cell('Frequency (e.g. 1-0-1)'),
                    onChanged: (v) => setState(() => drug.frequency = v),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: TextFormField(
                    initialValue: drug.duration,
                    style: input.tabular,
                    decoration: cell('Duration (e.g. 5 Days)'),
                    onChanged: (v) => setState(() => drug.duration = v),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: TextFormField(
                    initialValue: drug.instructions,
                    style: input,
                    decoration: cell('Timing (After Food)'),
                    onChanged: (v) => setState(() => drug.instructions = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _generateAndSavePrescription() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Prescription $_rxNumber saved! (Ready for PDF Generation)',
        ),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _shareRxWhatsApp() async {
    final phone = _patientPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final patientName = _patientNameCtrl.text.isNotEmpty
        ? _patientNameCtrl.text
        : 'Patient';

    final drugListText = _drugs
        .map(
          (d) =>
              '• *${d.drugName}* (${d.dosage}) — ${d.frequency} x ${d.duration} (${d.instructions})',
        )
        .join('\n');

    final text =
        '''
🏥 *${widget.letterheadConfig.clinicName}*
💊 *Prescription (Rx)*
Doctor: *${widget.letterheadConfig.doctorName}* (${widget.letterheadConfig.qualifications})
Reg No: ${widget.letterheadConfig.registrationNumber}

Patient: *$patientName*
Date: *${DateFormat('dd MMM yyyy').format(_rxDate)}*
Diagnosis: ${_diagnosisCtrl.text}

*Prescribed Medications:*
$drugListText

*Advice:* ${_adviceCtrl.text}
*Follow-up:* ${_followUpCtrl.text}

Contact: ${widget.letterheadConfig.clinicPhone}
''';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
