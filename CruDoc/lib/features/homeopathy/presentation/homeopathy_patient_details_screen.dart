import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_case_taking_sheet.dart';

const Color _accentEmerald = Color(0xFF059669);
const Color _accentEmeraldLight = Color(0xFFD1FAE5);

BoxDecoration _cardDecoration({BorderRadius? radius}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: radius ?? BorderRadius.circular(16),
    border: Border.all(
      color: const Color(0xFFE2E8F0),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        offset: const Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  );
}

class HomeopathyPatientDetailsScreen extends ConsumerStatefulWidget {
  final Patient patient;

  const HomeopathyPatientDetailsScreen({
    super.key,
    required this.patient,
  });

  @override
  ConsumerState<HomeopathyPatientDetailsScreen> createState() =>
      _HomeopathyPatientDetailsScreenState();
}

class _HomeopathyPatientDetailsScreenState
    extends ConsumerState<HomeopathyPatientDetailsScreen> {
  late String _note = widget.patient.notes;

  Future<void> _openNoteEditor() async {
    final controller = TextEditingController(text: _note);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Doctor\'s Note',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add general clinical observations...',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accentEmerald,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save Note'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != _note) {
      setState(() => _note = result);
      await ref
          .read(patientRepositoryProvider)
          .updateDoctorsNote(widget.patient.id, result);
    }
  }

  Future<void> _scheduleSession() async {
    final scheduled = await showScheduleVisitSheet(
      context,
      patient: widget.patient,
      visitRepository: ref.read(visitRepositoryProvider),
    );

    if (!scheduled || !mounted) return;
    ref.invalidate(visitsForPatientProvider(widget.patient.id));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Consultation scheduled for ${widget.patient.fullName}'),
      ),
    );
  }

  Future<void> _editPatient(Patient currentPatient) async {
    final updated = await showEditPatientSheet(
      context,
      patient: currentPatient,
      repository: ref.read(patientRepositoryProvider),
    );
    if (updated == true && mounted) {
      ref.invalidate(patientsStreamProvider);
    }
  }

  Future<void> _deletePatient(Patient currentPatient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Patient Record'),
        content: Text('Are you sure you want to delete ${currentPatient.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref
          .read(patientRepositoryProvider)
          .deletePatient(currentPatient.id);
      if (!mounted) return;
      ref.invalidate(patientsStreamProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsStreamProvider);
    final patient = patientsAsync.maybeWhen(
      data: (list) {
        for (final p in list) {
          if (p.id == widget.patient.id) return p;
        }
        return widget.patient;
      },
      orElse: () => widget.patient,
    );

    final visitsAsync = ref.watch(visitsForPatientProvider(patient.id));
    final caseSheetAsync = ref.watch(homeopathyCaseSheetProvider(patient.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top Bar
              _HomeopathyTopBar(
                patient: patient,
                onEdit: () => _editPatient(patient),
                onDelete: () => _deletePatient(patient),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 108),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    // Shared Patient Header
                    _PatientHeaderCard(patient: patient),
                    const SizedBox(height: 16),

                    // Homeopathy Clinical Case Sheet Highlight Card
                    caseSheetAsync.when(
                      loading: () => Container(
                        padding: const EdgeInsets.all(20),
                        decoration: _cardDecoration(),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (err, _) => Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Text('Error loading case sheet: $err'),
                      ),
                      data: (caseSheet) => _HomeopathyCaseSheetCard(
                        patient: patient,
                        caseSheet: caseSheet,
                        onOpenCaseTaking: () async {
                          final updated = await HomeopathyCaseTakingSheet.show(
                            context,
                            patient: patient,
                            initialCaseSheet: caseSheet,
                          );
                          if (updated == true && mounted) {
                            ref.invalidate(
                              homeopathyCaseSheetProvider(patient.id),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Doctor's Common Note
                    _HomeoDoctorsNoteCard(
                      note: _note,
                      onTap: _openNoteEditor,
                    ),
                    const SizedBox(height: 20),

                    // Contact Section
                    const _SectionHeading(title: 'CONTACT & COMMUNICATION'),
                    const SizedBox(height: 10),
                    _ContactCard(
                      phone: patient.phone,
                      email: patient.email,
                    ),
                    const SizedBox(height: 20),

                    // Session / Appointment History
                    const _SectionHeading(title: 'CONSULTATION HISTORY'),
                    const SizedBox(height: 10),
                    visitsAsync.when(
                      loading: () => Container(
                        padding: const EdgeInsets.all(24),
                        decoration: _cardDecoration(),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, st) => Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: const Text('Could not load consultation history'),
                      ),
                      data: (visits) {
                        if (visits.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 28, horizontal: 20),
                            decoration: _cardDecoration(),
                            child: const Column(
                              children: [
                                Icon(Icons.event_note_outlined,
                                    size: 36, color: AppColors.slateBlue),
                                SizedBox(height: 8),
                                Text(
                                  'No Consultations Logged',
                                  style: TextStyle(
                                    fontFamily: AppColors.headingFontFamily,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Schedule the patient\'s first homeopathic consultation below.',
                                  style: AppColors.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: visits.map((v) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _VisitItemCard(
                                visit: v,
                                onTap: () => showSessionDetailsSheet(
                                  context,
                                  VisitWithPatient(visit: v, patient: patient),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              offset: const Offset(0, -3),
              blurRadius: 10,
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('Add Note'),
                  onPressed: _openNoteEditor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentEmerald,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: const Text('Consultation'),
                  onPressed: _scheduleSession,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeopathyTopBar extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HomeopathyTopBar({
    required this.patient,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Patient Details',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accentEmeraldLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.spa_rounded, size: 14, color: _accentEmerald),
                SizedBox(width: 4),
                Text(
                  'Homeopathy',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accentEmerald,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  final Patient patient;

  const _PatientHeaderCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _accentEmeraldLight,
            child: Text(
              patient.fullName.isNotEmpty ? patient.fullName[0].toUpperCase() : 'P',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _accentEmerald,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.fullName,
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${patient.age} years • ${patient.gender}',
                  style: AppColors.bodySmall,
                ),
                if (patient.diagnosis.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: patient.diagnosis.map((d) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.slateBlue,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeopathyCaseSheetCard extends StatelessWidget {
  final Patient patient;
  final HomeopathyCaseSheet? caseSheet;
  final VoidCallback onOpenCaseTaking;

  const _HomeopathyCaseSheetCard({
    required this.patient,
    required this.caseSheet,
    required this.onOpenCaseTaking,
  });

  @override
  Widget build(BuildContext context) {
    final isFemale = patient.gender.toLowerCase().trim() == 'female';
    final hasSheet = caseSheet != null;
    final completedSections =
        hasSheet ? caseSheet!.completedSectionsCount(isFemale: isFemale) : 0;
    final totalSections = hasSheet
        ? caseSheet!.totalSectionsCount(isFemale: isFemale)
        : (isFemale ? 15 : 14);
    final remedy = caseSheet?.prescriptionNotes.prescribedRemedy.trim() ?? '';
    final thermal = caseSheet?.generalSymptoms.thermalState ??
        HomeopathyThermalState.unspecified;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasSheet
              ? _accentEmerald.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _accentEmeraldLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      size: 18,
                      color: _accentEmerald,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Clinical Case Sheet',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasSheet &&
                          (caseSheet!.isCompleted || completedSections >= 8)
                      ? _accentEmeraldLight
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasSheet
                      ? (caseSheet!.isCompleted
                          ? 'Complete'
                          : '$completedSections/$totalSections Sections')
                      : 'Not Started',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasSheet &&
                            (caseSheet!.isCompleted || completedSections >= 8)
                        ? _accentEmerald
                        : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasSheet && caseSheet!.overview.chiefProblem.isNotEmpty) ...[
            Text(
              'Chief Complaint: ${caseSheet!.overview.chiefProblem}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (hasSheet)
                _buildMiniBadge(
                  caseSheet!.overview.caseType.label,
                  const Color(0xFFE0E7FF),
                  const Color(0xFF4F46E5),
                ),
              if (thermal != HomeopathyThermalState.unspecified)
                _buildMiniBadge(
                  thermal.label,
                  const Color(0xFFFEF3C7),
                  const Color(0xFFB45309),
                ),
              if (remedy.isNotEmpty)
                _buildMiniBadge(
                  'Rx: $remedy',
                  _accentEmeraldLight,
                  _accentEmerald,
                ),
              if (hasSheet && caseSheet!.followUp.responseRating.isNotEmpty)
                _buildMiniBadge(
                  caseSheet!.followUp.responseRating,
                  const Color(0xFFDCFCE7),
                  const Color(0xFF15803D),
                ),
              if (hasSheet &&
                  caseSheet!.followUp.nextPrescriptionPlan.isNotEmpty)
                _buildMiniBadge(
                  caseSheet!.followUp.nextPrescriptionPlan,
                  const Color(0xFFF3E8FF),
                  const Color(0xFF7E22CE),
                ),
              if (hasSheet &&
                  caseSheet!.prescriptionNotes.totalityOfSymptoms.isNotEmpty)
                _buildMiniBadge(
                  'Totality Synthesized',
                  const Color(0xFFFEE2E2),
                  const Color(0xFFB91C1C),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accentEmerald,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(
                hasSheet ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                size: 18,
              ),
              label: Text(
                hasSheet ? 'Review & Edit Case Sheet' : '📋 Start Case Taking',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: onOpenCaseTaking,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textCol,
        ),
      ),
    );
  }
}

class _HomeoDoctorsNoteCard extends StatelessWidget {
  final String note;
  final VoidCallback onTap;

  const _HomeoDoctorsNoteCard({
    required this.note,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = note.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'DOCTOR\'S NOTE',
                  style: TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                Icon(
                  hasNote ? Icons.edit_outlined : Icons.add_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasNote ? note : 'Tap to add clinical notes or general observations...',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: hasNote ? AppColors.textPrimary : const Color(0xFF94A3B8),
                fontStyle: hasNote ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final String phone;
  final String email;

  const _ContactCard({
    required this.phone,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 18, color: AppColors.slateBlue),
              const SizedBox(width: 10),
              Text(
                phone.isNotEmpty ? phone : 'No phone number',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 18, color: AppColors.slateBlue),
                const SizedBox(width: 10),
                Text(
                  email,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VisitItemCard extends StatelessWidget {
  final Visit visit;
  final VoidCallback onTap;

  const _VisitItemCard({
    required this.visit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM yyyy • h:mm a');
    final formattedDate = dateFormat.format(visit.scheduledStart);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentEmeraldLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.medical_services_outlined, size: 18, color: _accentEmerald),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (visit.treatmentType != null && visit.treatmentType!.trim().isNotEmpty)
                        ? visit.treatmentType!
                        : 'Homeopathic Consultation',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: AppColors.headingFontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: AppColors.textSecondary,
      ),
    );
  }
}
