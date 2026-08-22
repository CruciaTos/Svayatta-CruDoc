import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Lightweight medical report generator that reuses the shared CruDoc
/// letterhead PDF layer for clinical summaries, investigation reports,
/// fitness notes, follow-up summaries, and referral-style report documents.
class MedicalReportGenerationSheet extends StatefulWidget {
  const MedicalReportGenerationSheet({
    super.key,
    required this.letterheadConfig,
    this.initialPatient,
  });

  final DoctorLetterheadConfig letterheadConfig;
  final Patient? initialPatient;

  @override
  State<MedicalReportGenerationSheet> createState() =>
      _MedicalReportGenerationSheetState();
}

class _MedicalReportGenerationSheetState
    extends State<MedicalReportGenerationSheet> {
  late final TextEditingController _patientNameCtrl;
  late final TextEditingController _patientAgeGenderCtrl;
  late final TextEditingController _patientPhoneCtrl;
  late final TextEditingController _reportNumberCtrl;
  late final TextEditingController _reportTitleCtrl;
  late final TextEditingController _clinicalSummaryCtrl;
  late final TextEditingController _observationsCtrl;
  late final TextEditingController _investigationsCtrl;
  late final TextEditingController _impressionCtrl;
  late final TextEditingController _recommendationsCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _reportDate;

  @override
  void initState() {
    super.initState();
    final reportSeq = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    final patient = widget.initialPatient;
    _reportDate = DateTime.now();
    _patientNameCtrl = TextEditingController(text: patient?.fullName ?? '');
    _patientAgeGenderCtrl = TextEditingController(
      text: patient == null
          ? '35 Y / M'
          : '${patient.age} Y / ${patient.gender.trim().isEmpty ? 'N/A' : patient.gender.trim()}',
    );
    _patientPhoneCtrl = TextEditingController(text: patient?.phone ?? '');
    _reportNumberCtrl = TextEditingController(text: 'RPT-$reportSeq');
    _reportTitleCtrl = TextEditingController(text: 'Clinical Summary Report');
    _clinicalSummaryCtrl = TextEditingController(
      text: patient?.notes.trim().isNotEmpty == true
          ? patient!.notes
          : 'Patient reviewed clinically. Symptoms, examination findings, and treatment plan are documented below.',
    );
    _observationsCtrl = TextEditingController(
      text: patient?.diagnosis.isNotEmpty == true
          ? 'Known / working diagnosis: ${patient!.diagnosisDisplay}'
          : 'General examination stable. No acute distress noted at the time of evaluation.',
    );
    _investigationsCtrl = TextEditingController(
      text: 'Relevant investigations reviewed / advised as clinically indicated.',
    );
    _impressionCtrl = TextEditingController(
      text: patient?.diagnosis.isNotEmpty == true
          ? patient!.diagnosisDisplay
          : 'Clinical condition stable as per current assessment.',
    );
    _recommendationsCtrl = TextEditingController(
      text: 'Continue prescribed treatment, maintain hydration, and follow up as advised.',
    );
    _notesCtrl = TextEditingController(
      text: 'This report is generated based on available clinical information and examination records.',
    );
  }

  @override
  void dispose() {
    _patientNameCtrl.dispose();
    _patientAgeGenderCtrl.dispose();
    _patientPhoneCtrl.dispose();
    _reportNumberCtrl.dispose();
    _reportTitleCtrl.dispose();
    _clinicalSummaryCtrl.dispose();
    _observationsCtrl.dispose();
    _investigationsCtrl.dispose();
    _impressionCtrl.dispose();
    _recommendationsCtrl.dispose();
    _notesCtrl.dispose();
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
          _buildTopBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildLetterheadBanner(cfg),
                const SizedBox(height: 16),
                _buildMetadataSection(),
                const SizedBox(height: 16),
                _buildClinicalSections(),
                const SizedBox(height: 16),
                _buildSignaturePreview(cfg),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
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
                      color: const Color(0xFF1E78FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: Color(0xFF1E78FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Generate Medical Report',
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
    );
  }

  Widget _buildLetterheadBanner(DoctorLetterheadConfig cfg) {
    return Container(
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
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.local_hospital_rounded,
                        size: 36,
                        color: Color(0xFF1E78FF),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 54,
                  height: 54,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_hospital_rounded,
                    size: 30,
                    color: Color(0xFF1E78FF),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cfg.clinicName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cfg.doctorName} • ${cfg.qualifications}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E78FF),
                      ),
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
                colors: [Color(0xFF1E78FF), Color(0xFF475569)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Report Details & Patient Info',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInput(
                  _reportNumberCtrl,
                  'Report #',
                  Icons.tag_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildDatePicker()),
            ],
          ),
          const SizedBox(height: 12),
          _buildInput(
            _reportTitleCtrl,
            'Report Title',
            Icons.title_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildInput(
                  _patientNameCtrl,
                  'Patient Full Name',
                  Icons.person_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildInput(
                  _patientAgeGenderCtrl,
                  'Age / Gender',
                  Icons.cake_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInput(
            _patientPhoneCtrl,
            'WhatsApp / Phone',
            Icons.phone_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: _reportDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (pickedDate != null) setState(() => _reportDate = pickedDate);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF1E78FF)),
            const SizedBox(width: 8),
            Text(
              DateFormat('dd MMM yyyy').format(_reportDate),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicalSections() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Structured Report Sections',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
          _buildInput(
            _clinicalSummaryCtrl,
            'Clinical Summary',
            Icons.summarize_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInput(
            _observationsCtrl,
            'Observations / Findings',
            Icons.visibility_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInput(
            _investigationsCtrl,
            'Investigation Results',
            Icons.biotech_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInput(
            _impressionCtrl,
            'Impression / Conclusion',
            Icons.fact_check_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInput(
            _recommendationsCtrl,
            'Recommendations',
            Icons.recommend_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInput(
            _notesCtrl,
            'Footer Notes for this Report',
            Icons.notes_rounded,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildSignaturePreview(DoctorLetterheadConfig cfg) {
    return Container(
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
              const Icon(Icons.draw_rounded, color: Color(0xFF1E78FF), size: 24),
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
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _generateReportPreview,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
          label: const Text('Preview & Print Report'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E78FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 16, color: const Color(0xFF1E78FF)),
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
          borderSide: const BorderSide(color: Color(0xFF1E78FF), width: 1.5),
        ),
      ),
    );
  }

  Future<void> _generateReportPreview() async {
    final reportNumber = _reportNumberCtrl.text.trim().isEmpty
        ? 'RPT-${DateTime.now().millisecondsSinceEpoch}'
        : _reportNumberCtrl.text.trim();

    final documentData = PdfMedicalReportDocumentData(
      letterheadConfig: widget.letterheadConfig,
      patient: _buildPatientSnapshot(),
      documentNumber: reportNumber,
      documentDate: _reportDate,
      reportTitle: _reportTitleCtrl.text.trim().isEmpty
          ? 'Medical Report'
          : _reportTitleCtrl.text.trim(),
      sections: [
        PdfReportSection(
          title: 'Clinical Summary',
          content: _clinicalSummaryCtrl.text.trim(),
        ),
        PdfReportSection(
          title: 'Observations / Findings',
          content: _observationsCtrl.text.trim(),
        ),
        PdfReportSection(
          title: 'Investigation Results',
          content: _investigationsCtrl.text.trim(),
        ),
        PdfReportSection(
          title: 'Impression / Conclusion',
          content: _impressionCtrl.text.trim(),
        ),
        PdfReportSection(
          title: 'Recommendations',
          content: _recommendationsCtrl.text.trim(),
        ),
      ],
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    await MedicalPdfPreviewScreen.open(context, documentData: documentData);
  }

  PdfPatientSnapshot _buildPatientSnapshot() {
    final patient = widget.initialPatient;

    return PdfPatientSnapshot(
      fullName: _patientNameCtrl.text.trim().isEmpty
          ? (patient?.fullName.trim().isNotEmpty == true ? patient!.fullName : 'Patient')
          : _patientNameCtrl.text.trim(),
      phone: _patientPhoneCtrl.text.trim().isEmpty
          ? (patient?.phone.trim().isEmpty == true ? null : patient?.phone.trim())
          : _patientPhoneCtrl.text.trim(),
      ageGender: _patientAgeGenderCtrl.text.trim().isEmpty
          ? null
          : _patientAgeGenderCtrl.text.trim(),
      email: patient?.email.trim().isEmpty == true ? null : patient?.email.trim(),
      patientId: patient?.id.trim().isEmpty == true ? null : patient?.id.trim(),
    );
  }
}