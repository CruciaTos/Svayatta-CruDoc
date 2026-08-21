import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

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
  State<PrescriptionGenerationSheet> createState() => _PrescriptionGenerationSheetState();
}

class _PrescriptionGenerationSheetState extends State<PrescriptionGenerationSheet> {
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
      text: widget.initialPatient?.gender != null ? '${widget.initialPatient?.gender}' : '35 Y / M',
    );
    _patientPhoneCtrl = TextEditingController(
      text: widget.initialPatient?.phone ?? '',
    );
    _vitalsCtrl = TextEditingController(
      text: 'BP: 120/80 mmHg | Pulse: 76 bpm | SpO2: 98% | Wt: 68 kg',
    );
    _complaintsCtrl = TextEditingController(
      text: widget.initialVisit?.treatmentType ?? 'Fever with body ache for 3 days',
    );
    _diagnosisCtrl = TextEditingController(
      text: widget.initialPatient?.diagnosis.isNotEmpty == true
          ? widget.initialPatient!.diagnosis.join(', ')
          : 'Acute Upper Respiratory Tract Infection (URTI)',
    );
    _labTestsCtrl = TextEditingController(text: 'Complete Blood Count (CBC), CRP');
    _adviceCtrl = TextEditingController(
      text: 'Adequate hydration, warm saline gargles, light warm diet.',
    );
    _followUpCtrl = TextEditingController(text: 'Follow up after 5 days if fever persists.');
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ---- Drag Handle & Top Bar ----
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.medication_rounded, color: Color(0xFF8B5CF6), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Generate Prescription (Rx)',
                          style: TextStyle(
                            fontFamily: AppColors.headingFontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
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
              padding: const EdgeInsets.all(20),
              children: [
                // ---- Doctor & Clinic Letterhead Banner ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cfg.logoUrl != null && cfg.logoUrl!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: cfg.logoUrl!,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(Icons.local_hospital_rounded, size: 36, color: Color(0xFF8B5CF6)),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 54,
                              height: 54,
                              margin: const EdgeInsets.only(right: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.local_hospital_rounded, size: 30, color: Color(0xFF8B5CF6)),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cfg.clinicName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${cfg.doctorName} • ${cfg.qualifications}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6)),
                                ),
                                Text(
                                  '${cfg.specialty} | Reg. No: ${cfg.registrationNumber}',
                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '📍 ${cfg.clinicAddress} • 📞 ${cfg.clinicPhone}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF1E78FF)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Patient Info & Vitals Header ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Patient & Consultation Info', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF334155))),
                          Text('Rx: $_rxNumber | ${DateFormat('dd MMM yyyy').format(_rxDate)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildInput(_patientNameCtrl, 'Patient Name', Icons.person_rounded),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _buildInput(_patientAgeGenderCtrl, 'Age / Gender', Icons.cake_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildInput(_vitalsCtrl, 'Vitals (BP, Pulse, Weight, SpO2)', Icons.monitor_heart_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Clinical Complaints & Diagnosis ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Clinical Findings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF334155))),
                      const SizedBox(height: 12),
                      _buildInput(_complaintsCtrl, 'Chief Complaints & History', Icons.chat_bubble_outline_rounded),
                      const SizedBox(height: 10),
                      _buildInput(_diagnosisCtrl, 'Diagnosis / Impression', Icons.medical_information_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Rx Medications Table ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Text('℞', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF8B5CF6))),
                              SizedBox(width: 6),
                              Text('Prescribed Medications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF334155))),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _addNewDrug,
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF8B5CF6)),
                            label: const Text('Add Drug', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._drugs.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final drug = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF5FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE9D5FF)),
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
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                      decoration: const InputDecoration(
                                        labelText: 'Drug Name (Tab / Cap / Syp)',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (v) => setState(() => drug.drugName = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      initialValue: drug.dosage,
                                      decoration: const InputDecoration(
                                        labelText: 'Dosage',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (v) => setState(() => drug.dosage = v),
                                    ),
                                  ),
                                  if (_drugs.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                      onPressed: () => setState(() => _drugs.removeAt(idx)),
                                    ),
                                ],
                              ),
                              const Divider(height: 12, color: Color(0xFFE9D5FF)),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: drug.frequency,
                                      decoration: const InputDecoration(
                                        labelText: 'Frequency (e.g. 1-0-1)',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (v) => setState(() => drug.frequency = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: drug.duration,
                                      decoration: const InputDecoration(
                                        labelText: 'Duration (e.g. 5 Days)',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (v) => setState(() => drug.duration = v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: drug.instructions,
                                      decoration: const InputDecoration(
                                        labelText: 'Timing (After Food)',
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (v) => setState(() => drug.instructions = v),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Lab Tests, Advice & Follow Up ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Advice & Investigations', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF334155))),
                      const SizedBox(height: 12),
                      _buildInput(_labTestsCtrl, 'Lab Tests / Investigations Advised', Icons.biotech_rounded),
                      const SizedBox(height: 10),
                      _buildInput(_adviceCtrl, 'Diet & Lifestyle Advice', Icons.tips_and_updates_rounded),
                      const SizedBox(height: 10),
                      _buildInput(_followUpCtrl, 'Follow-up Date / Instructions', Icons.event_repeat_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Signature & Stamp Area ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cfg.footerDisclaimer,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(Icons.draw_rounded, color: Color(0xFF8B5CF6), size: 24),
                          const SizedBox(height: 4),
                          Text(
                            cfg.doctorName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Reg: ${cfg.registrationNumber}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // ---- Bottom Action Toolbar ----
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareRxWhatsApp,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('WhatsApp Rx'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF16A34A),
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      backgroundColor: const Color(0xFFF0FDF4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _generateAndSavePrescription,
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Save & Print Rx'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
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
      _drugs.add(PrescriptionDrugRow(
        drugName: 'Tab. Multivitamin',
        dosage: '1 Tab',
        frequency: '0 - 1 - 0',
        duration: '15 Days',
        instructions: 'After Food',
      ));
    });
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 16, color: const Color(0xFF8B5CF6)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
        ),
      ),
    );
  }

  void _generateAndSavePrescription() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Prescription $_rxNumber saved! (Ready for PDF Generation)'),
        backgroundColor: const Color(0xFF8B5CF6),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _shareRxWhatsApp() async {
    final phone = _patientPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final patientName = _patientNameCtrl.text.isNotEmpty ? _patientNameCtrl.text : 'Patient';

    final drugListText = _drugs
        .map((d) => '• *${d.drugName}* (${d.dosage}) — ${d.frequency} x ${d.duration} (${d.instructions})')
        .join('\n');

    final text = '''
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

    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
