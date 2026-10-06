import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/reports/presentation/medical_report_generation_sheet.dart';
import 'package:doctor_management_app/features/revenue/presentation/bill_generation_sheet.dart';
import 'package:doctor_management_app/features/scribe/presentation/prescription_generation_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Interactive Profile Card for configuring custom Clinic Letterhead & Logo branding
/// for automated Bill (Receipt) and Prescription (Rx) generation.
class LetterheadBrandingCard extends StatelessWidget {
  const LetterheadBrandingCard({
    super.key,
    required this.profileData,
    this.user,
  });

  final Map<String, dynamic>? profileData;
  final User? user;

  @override
  Widget build(BuildContext context) {
    final config = DoctorLetterheadConfig.fromProfileData(profileData, user);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header Banner ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.branding_watermark_rounded,
                    color: Color(0xFF1E78FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Document Letterhead Branding',
                        style: TextStyle(
                          fontFamily: AppColors.headingFontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Custom logo, clinic details, doctor credentials, and footer notes',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF1E78FF),
                  ),
                  tooltip: 'Customize Letterhead',
                  onPressed: () =>
                      _openLetterheadCustomizerSheet(context, config),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ---- Live Letterhead Mini-Preview ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo or Clinic Emblem
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1E78FF,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFF1E78FF,
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child:
                            (config.logoUrl != null &&
                                config.logoUrl!.trim().isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: CachedNetworkImage(
                                  imageUrl: config.logoUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(
                                    Icons.local_hospital_rounded,
                                    color: Color(0xFF1E78FF),
                                    size: 24,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.local_hospital_rounded,
                                color: Color(0xFF1E78FF),
                                size: 26,
                              ),
                      ),
                      const SizedBox(width: 12),
                      // Clinic & Doctor Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.clinicName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${config.doctorName} • ${config.qualifications}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E78FF),
                              ),
                            ),
                            Text(
                              '${config.specialty} • ${config.registrationNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📍 ${config.clinicAddress} • 📞 ${config.clinicPhone}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // ---- Quick Action Launch Buttons ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openBillGenerator(context, config),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Generate Bill'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      side: const BorderSide(color: Color(0xFF99F6E4)),
                      backgroundColor: const Color(0xFFF0FDFA),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openPrescriptionGenerator(context, config),
                    icon: const Icon(Icons.medication_rounded, size: 16),
                    label: const Text('Generate Rx'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8B5CF6),
                      side: const BorderSide(color: Color(0xFFDDD6FE)),
                      backgroundColor: const Color(0xFFF5F3FF),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openMedicalReportGenerator(context, config),
                    icon: const Icon(Icons.description_rounded, size: 16),
                    label: const Text('Report'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E78FF),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

  void _openLetterheadCustomizerSheet(
    BuildContext context,
    DoctorLetterheadConfig config,
  ) {
    final clinicNameCtrl = TextEditingController(text: config.clinicName);
    final qualCtrl = TextEditingController(text: config.qualifications);
    final regNoCtrl = TextEditingController(text: config.registrationNumber);
    final addressCtrl = TextEditingController(text: config.clinicAddress);
    final phoneCtrl = TextEditingController(text: config.clinicPhone);
    final emailCtrl = TextEditingController(text: config.clinicEmail);
    final taglineCtrl = TextEditingController(text: config.tagline);
    final footerCtrl = TextEditingController(text: config.footerDisclaimer);
    final logoUrlCtrl = TextEditingController(text: config.logoUrl ?? '');

    bool isSaving = false;
    final c = context.cru;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: ShapeDecoration(
                      color: c.track,
                      shape: cruShape(CruRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      color: c.accent,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Customize Letterhead & Logo',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.label,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This header will automatically appear on all generated Bills and Prescriptions.',
                  style: TextStyle(fontSize: 12.5, color: c.label2),
                ),
                const SizedBox(height: 20),

                // Clinic Name
                _buildField(
                  c,
                  clinicNameCtrl,
                  'Clinic / Hospital Name',
                  Icons.local_hospital_rounded,
                ),
                const SizedBox(height: 12),

                // Qualifications & Registration
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        c,
                        qualCtrl,
                        'Degrees (e.g. MBBS, MD)',
                        Icons.school_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildField(
                        c,
                        regNoCtrl,
                        'Reg. No (e.g. MMC-1234)',
                        Icons.badge_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Address
                _buildField(
                  c,
                  addressCtrl,
                  'Clinic Address / Location',
                  Icons.location_on_rounded,
                ),
                const SizedBox(height: 12),

                // Contact Phone & Email
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        c,
                        phoneCtrl,
                        'Contact Phone',
                        Icons.phone_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildField(
                        c,
                        emailCtrl,
                        'Clinic Email',
                        Icons.email_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Logo URL
                _buildField(
                  c,
                  logoUrlCtrl,
                  'Logo Image URL (Optional)',
                  Icons.image_rounded,
                ),
                const SizedBox(height: 12),

                // Tagline & Footer
                _buildField(
                  c,
                  taglineCtrl,
                  'Header Tagline / Subtitle',
                  Icons.short_text_rounded,
                ),
                const SizedBox(height: 12),
                _buildField(
                  c,
                  footerCtrl,
                  'Footer Disclaimer / Notes',
                  Icons.notes_rounded,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Save Button (Royal Blue Payment Gradient)
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(CruRadius.control),
                      onTap: isSaving
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              try {
                                await DoctorProfileHelper.updateLetterheadBranding(
                                  clinicName: clinicNameCtrl.text,
                                  doctorQualifications: qualCtrl.text,
                                  registrationNumber: regNoCtrl.text,
                                  clinicAddress: addressCtrl.text,
                                  clinicPhone: phoneCtrl.text,
                                  clinicEmail: emailCtrl.text,
                                  tagline: taglineCtrl.text,
                                  footerDisclaimer: footerCtrl.text,
                                  logoUrl: logoUrlCtrl.text.isNotEmpty
                                      ? logoUrlCtrl.text
                                      : null,
                                  user: user,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Letterhead & Branding saved successfully!',
                                      ),
                                      backgroundColor: Color(0xFF16A34A),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Error saving: $e'),
                                      backgroundColor: const Color(0xFFEF4444),
                                    ),
                                  );
                                }
                              }
                            },
                      child: Center(
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Letterhead Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    CruColors c,
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: c.label, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.label2),
        prefixIcon: Icon(icon, size: 18, color: c.accent),
        filled: true,
        fillColor: c.inset,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
    );
  }

  void _openBillGenerator(BuildContext context, DoctorLetterheadConfig config) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BillGenerationSheet(letterheadConfig: config),
    );
  }

  void _openPrescriptionGenerator(
    BuildContext context,
    DoctorLetterheadConfig config,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PrescriptionGenerationSheet(letterheadConfig: config),
    );
  }

  void _openMedicalReportGenerator(
    BuildContext context,
    DoctorLetterheadConfig config,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MedicalReportGenerationSheet(letterheadConfig: config),
    );
  }
}
