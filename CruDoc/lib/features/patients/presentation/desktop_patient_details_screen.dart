// desktop_patient_details_screen.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';

// ---------- Color Palette (matches Desktop Shell & Records Theme) ----------
const Color _kTextPrimary = Color(0xFF1F2937);
const Color _kTextSecondary = Color(0xFF6B7280);
const Color _kTextMuted = Color(0xFF9CA3AF);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kBorderDark = Color.fromARGB(255, 150, 150, 150);
const Color _kAccentBlue = Color(0xFF2563EB);
const Color _kAccentBlueBg = Color(0xFFEFF6FF);
const Color _kSuccess = Color(0xFF00C853);
const Color _kSuccessBg = Color(0xFFE8F5E9);
const Color _kAmber = Color(0xFFFFA000);
const Color _kAmberBg = Color(0xFFFFF8E1);
const Color _kRed = Color(0xFFDC2626);
const Color _kRedBg = Color(0xFFFEF2F2);
const Color _kCardBg = Colors.white;
const Color _kFrostedBg = Color(0xFFF0F9FF);

/// Embeddable patient-details body.
/// Matches the frosted glass layout of DesktopPatientRecordsScreen.
class PatientDetailsBody extends ConsumerStatefulWidget {
  final Patient patient;
  final VoidCallback onBack;

  const PatientDetailsBody({
    super.key,
    required this.patient,
    required this.onBack,
  });

  @override
  ConsumerState<PatientDetailsBody> createState() => _PatientDetailsBodyState();
}

class _PatientDetailsBodyState extends ConsumerState<PatientDetailsBody> {
  late String _note = widget.patient.notes;
  String? _localImagePath;

  @override
  void initState() {
    super.initState();
    _loadPatientImage();
  }

  @override
  void didUpdateWidget(covariant PatientDetailsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patient.id != widget.patient.id) {
      _loadPatientImage();
    }
  }

  Future<void> _loadPatientImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('patient_avatar_${widget.patient.id}');
      if (mounted) {
        setState(() => _localImagePath = path);
      }
    } catch (_) {}
  }

  Future<void> _pickPatientImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('patient_avatar_${widget.patient.id}', picked.path);
      if (mounted) {
        setState(() => _localImagePath = picked.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient photo saved locally')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick photo: $e')),
      );
    }
  }

  // ---- Actions ----
  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        title: const Row(
          children: [
            Icon(Icons.sticky_note_2_outlined, color: _kAccentBlue, size: 20),
            SizedBox(width: 8),
            Text("Doctor's Note", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              hintText: 'Type clinical notes for this patient…',
              hintStyle: const TextStyle(fontSize: 12.5, color: _kTextMuted),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kAccentBlue, width: 1.5),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            child: const Text('Cancel', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kAccentBlue,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final trimmed = result.trim();
    final previous = _note;
    setState(() => _note = trimmed);
    try {
      await ref
          .read(patientRepositoryProvider)
          .updateDoctorsNote(widget.patient.id, trimmed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save note: $e')),
      );
    }
  }

  Future<void> _editPatient(Patient patient) async {
    final updated = await showEditPatientSheet(
      context,
      patient: patient,
      repository: ref.read(patientRepositoryProvider),
    );
    if (updated == true && mounted) {
      ref.invalidate(patientsStreamProvider);
    }
  }

  Future<void> _deletePatient(Patient patient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: _kRed, size: 20),
            SizedBox(width: 8),
            Text('Delete Patient Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${patient.fullName}? This will remove the patient record from your active list.',
          style: const TextStyle(fontSize: 13, color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            child: const Text('Cancel', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await ref.read(patientRepositoryProvider).deletePatient(patient.id);
      if (!mounted) return;
      ref.invalidate(patientsStreamProvider);
      widget.onBack();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${patient.fullName} deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete patient: $e')),
      );
    }
  }

  Future<void> _scheduleSession(Patient patient) async {
    final scheduled = await showScheduleVisitSheet(
      context,
      patient: patient,
      visitRepository: ref.read(visitRepositoryProvider),
    );
    if (!scheduled || !mounted) return;
    ref.invalidate(visitsForPatientProvider(patient.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Session scheduled for ${patient.fullName}')),
    );
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

    // Outer frosted glass container matching desktop screens
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: _kFrostedBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _kBorderDark,
                width: 0.25,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Bar (Desktop Styled) ─────────────────────────
                _DetailsHeaderBar(
                  patient: patient,
                  onBack: widget.onBack,
                  onEdit: () => _editPatient(patient),
                ),
                const SizedBox(height: 10),

                // ── Scrollable Body ────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Profile Header Card (with contacts & vertical stats & image upload) ──
                        _ProfileHeaderCard(
                          patient: patient,
                          visitsAsync: visitsAsync,
                          localImagePath: _localImagePath,
                          onPickImage: _pickPatientImage,
                          onEdit: () => _editPatient(patient),
                          onDelete: () => _deletePatient(patient),
                        ),
                        const SizedBox(height: 12),

                        // ── Two-Column Layout ────────────────────────────────────
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 920;
                            if (isWide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // LEFT COLUMN: Doctor's Note, Treatments, Medical History
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      children: [
                                        _DoctorNoteCard(
                                          note: _note,
                                          onTap: _editNote,
                                        ),
                                        const SizedBox(height: 12),
                                        _MedicationCard(
                                          visitsAsync: visitsAsync,
                                        ),
                                        const SizedBox(height: 12),
                                        _MedicalHistoryCard(
                                          patient: patient,
                                          visitsAsync: visitsAsync,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // RIGHT COLUMN: Timeline
                                  Expanded(
                                    flex: 5,
                                    child: _TimelineCard(
                                      patient: patient,
                                      visitsAsync: visitsAsync,
                                      onSchedule: () => _scheduleSession(patient),
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              // Narrow Fallback
                              return Column(
                                children: [
                                  _DoctorNoteCard(
                                    note: _note,
                                    onTap: _editNote,
                                  ),
                                  const SizedBox(height: 12),
                                  _MedicationCard(
                                    visitsAsync: visitsAsync,
                                  ),
                                  const SizedBox(height: 12),
                                  _MedicalHistoryCard(
                                    patient: patient,
                                    visitsAsync: visitsAsync,
                                  ),
                                  const SizedBox(height: 12),
                                  _TimelineCard(
                                    patient: patient,
                                    visitsAsync: visitsAsync,
                                    onSchedule: () => _scheduleSession(patient),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ],
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
}

// =============================================================================
// HEADER BAR (Matches Desktop Header Theme - Schedule Session removed)
// =============================================================================

class _DetailsHeaderBar extends StatelessWidget {
  final Patient patient;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _DetailsHeaderBar({
    required this.patient,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: _kTextPrimary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Back to Patients',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit Patient'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kTextPrimary,
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 1. PROFILE HEADER CARD (Double-click to edit, local image support)
// =============================================================================

class _ProfileHeaderCard extends StatelessWidget {
  final Patient patient;
  final AsyncValue<List<Visit>> visitsAsync;
  final String? localImagePath;
  final VoidCallback onPickImage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileHeaderCard({
    required this.patient,
    required this.visitsAsync,
    required this.localImagePath,
    required this.onPickImage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final initial = patient.firstName.isNotEmpty
        ? patient.firstName[0].toUpperCase()
        : 'P';

    final hasCustomImage = localImagePath != null &&
        localImagePath!.isNotEmpty &&
        File(localImagePath!).existsSync();

    return GestureDetector(
      onDoubleTap: onEdit,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar with click-to-upload image support
            Tooltip(
              message: 'Click to change photo',
              child: InkWell(
                onTap: onPickImage,
                borderRadius: BorderRadius.circular(36),
                child: Stack(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _kAccentBlue.withValues(alpha: 0.15),
                            _kAccentBlue.withValues(alpha: 0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: _kAccentBlue.withValues(alpha: 0.3), width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: hasCustomImage
                          ? Image.file(
                              File(localImagePath!),
                              width: 66,
                              height: 66,
                              fit: BoxFit.cover,
                            )
                          : Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _kAccentBlue,
                              ),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _kBorder),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          size: 11,
                          color: _kAccentBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),

            // Patient Information Column (generously padded with clear spacing)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          patient.fullName,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: _kTextPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kSuccessBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kSuccess.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 5, color: _kSuccess),
                            SizedBox(width: 4),
                            Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _kSuccess,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),

                  // Contacts (phone & email)
                  Wrap(
                    spacing: 18,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (patient.phone.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.call_outlined, size: 14, color: _kAccentBlue),
                            const SizedBox(width: 5),
                            Text(
                              patient.phone,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _kTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      if (patient.email.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.email_outlined, size: 14, color: _kAccentBlue),
                            const SizedBox(width: 5),
                            Text(
                              patient.email,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 11),

                  // Info Pills (Gender, Age, Diagnoses)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _InfoPill(
                        icon: Icons.person_outline_rounded,
                        label: '${patient.gender.isEmpty ? "Not specified" : patient.gender}, ${patient.age} yrs',
                      ),
                      for (final diag in patient.diagnosis)
                        _InfoPill(
                          icon: Icons.healing_outlined,
                          label: diag,
                          color: _kAccentBlue,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Vertical Stats Block (one above the other to the right of patient name)
            visitsAsync.when(
              loading: () => const SizedBox(
                width: 200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SkeletonBox(height: 34),
                    SizedBox(height: 6),
                    _SkeletonBox(height: 34),
                  ],
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (visits) {
                final completedCount = visits
                    .where((v) => v.status == VisitStatus.completed)
                    .length;
                final sortedVisits = [...visits]
                  ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
                final lastVisitLabel = sortedVisits.isEmpty
                    ? 'No visits yet'
                    : _formatRelativeTime(sortedVisits.first.scheduledStart);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CompactStatTile(
                      icon: Icons.event_repeat_rounded,
                      value: '$completedCount',
                      label: 'Sessions Completed',
                      accent: _kSuccess,
                    ),
                    const SizedBox(height: 6),
                    _CompactStatTile(
                      icon: Icons.event_available_rounded,
                      value: lastVisitLabel,
                      label: 'Last Session',
                      accent: _kAccentBlue,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(width: 6),

            // Action menu
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded, color: _kTextSecondary, size: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 15, color: _kTextPrimary),
                      SizedBox(width: 8),
                      Text('Edit Patient', style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 15, color: _kRed),
                      SizedBox(width: 8),
                      Text('Delete Patient', style: TextStyle(fontSize: 12.5, color: _kRed)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoPill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? _kTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: activeColor),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color != null ? _kAccentBlue : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const _CompactStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: accent, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: _kTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 2. TIMELINE CARD (Recent 4 with Toggle to Show All / Less)
// =============================================================================

class _TimelineCard extends StatefulWidget {
  final Patient patient;
  final AsyncValue<List<Visit>> visitsAsync;
  final VoidCallback onSchedule;

  const _TimelineCard({
    required this.patient,
    required this.visitsAsync,
    required this.onSchedule,
  });

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  bool _showAll = false; // whether to display all sessions or just first 4

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: _kAccentBlue, size: 18),
              const SizedBox(width: 6),
              const Text(
                'TIMELINE',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _kTextSecondary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: widget.onSchedule,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                label: const Text('Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: _kAccentBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          widget.visitsAsync.when(
            loading: () => const _EmptyStateCard(
              icon: Icons.history_rounded,
              message: 'Loading session history…',
            ),
            error: (_, __) => const _EmptyStateCard(
              icon: Icons.error_outline_rounded,
              message: 'Could not load visit history',
            ),
            data: (visits) {
              if (visits.isEmpty) {
                return const _EmptyStateCard(
                  icon: Icons.event_busy_outlined,
                  message: 'No sessions recorded yet.',
                );
              }

              // Sort visits by date descending (newest first)
              final sortedVisits = [...visits]
                ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));

              // Limit to 4 unless "show all" is active
              final visibleVisits = _showAll ? sortedVisits : sortedVisits.take(4).toList();

              return Column(
                children: [
                  for (final visit in visibleVisits)
                    _SessionTile(visit: visit, patient: widget.patient),

                  // Toggle button
                  if (sortedVisits.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _showAll = !_showAll),
                          icon: Icon(
                            _showAll
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 15,
                            color: _kAccentBlue,
                          ),
                          label: Text(
                            _showAll
                                ? 'Show less'
                                : 'Show all (${sortedVisits.length} sessions)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kAccentBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Visit visit;
  final Patient patient;
  const _SessionTile({required this.visit, required this.patient});

  @override
  Widget build(BuildContext context) {
    final hasTreatment = visit.treatmentType?.trim().isNotEmpty ?? false;
    final reason = hasTreatment
        ? visit.treatmentType!
        : '${_readableStatus(visit.status)} visit';
    final date = DateFormat.yMMMd().format(visit.scheduledStart);
    final time = DateFormat.jm().format(visit.scheduledStart);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showSessionDetailsSheet(
          context,
          VisitWithPatient(visit: visit, patient: patient),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorForVisitStatus(visit.status),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _kTextPrimary,
                          ),
                        ),
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _kTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _PaymentChip(visit: visit),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _kTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final Visit visit;
  const _PaymentChip({required this.visit});

  @override
  Widget build(BuildContext context) {
    final isPaid = visit.isPaid;
    final color = isPaid ? _kSuccess : _kAmber;
    final bg = isPaid ? _kSuccessBg : _kAmberBg;
    final label = isPaid && visit.amountCharged != null
        ? 'Paid ₹${visit.amountCharged!.toStringAsFixed(0)}'
        : (isPaid ? 'Paid' : 'Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// =============================================================================
// 3. DOCTOR'S NOTE CARD (Compact padding + Fixed Height)
// =============================================================================

class _DoctorNoteCard extends StatelessWidget {
  final String note;
  final VoidCallback onTap;
  const _DoctorNoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasNote = note.trim().isNotEmpty;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sticky_note_2_outlined,
                color: _kAccentBlue,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                "DOCTOR'S NOTE",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _kTextSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 15,
                  color: _kTextSecondary,
                ),
                onPressed: onTap,
                tooltip: 'Edit note',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: SingleChildScrollView(
              child: Text(
                hasNote ? note : 'Click to add a clinical note for this patient.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontStyle: hasNote ? FontStyle.normal : FontStyle.italic,
                  color: hasNote ? _kTextPrimary : _kTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. PRESCRIBED TREATMENTS CARD (Driven from real Visit data)
// =============================================================================

class _MedicationCard extends StatelessWidget {
  final AsyncValue<List<Visit>> visitsAsync;
  const _MedicationCard({required this.visitsAsync});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.medication_outlined,
                color: _kAccentBlue,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'PRESCRIBED TREATMENTS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _kTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          visitsAsync.when(
            loading: () => const _SkeletonBox(height: 40),
            error: (_, __) => const Text(
              'Could not load treatment history.',
              style: TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
            data: (visits) {
              // Collect unique treatment types, ordered by recency
              final seen = <String>{};
              final treatments = <_TreatmentEntry>[];

              final sorted = [...visits]
                ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));

              for (final v in sorted) {
                final t = v.treatmentType?.trim() ?? '';
                if (t.isEmpty) continue;
                final key = t.toLowerCase();
                if (seen.contains(key)) {
                  final idx = treatments
                      .indexWhere((e) => e.name.toLowerCase() == key);
                  if (idx != -1) {
                    treatments[idx] = _TreatmentEntry(
                      name: treatments[idx].name,
                      lastSeen: treatments[idx].lastSeen,
                      count: treatments[idx].count + 1,
                      wasCompleted: treatments[idx].wasCompleted ||
                          v.status == VisitStatus.completed,
                    );
                  }
                } else {
                  seen.add(key);
                  treatments.add(_TreatmentEntry(
                    name: t,
                    lastSeen: v.scheduledStart,
                    count: 1,
                    wasCompleted: v.status == VisitStatus.completed,
                  ));
                }
              }

              if (treatments.isEmpty) {
                return const _EmptyStateCard(
                  icon: Icons.medication_outlined,
                  message: 'No treatments prescribed in session history yet.',
                );
              }

              return Column(
                children: [
                  for (final t in treatments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: _kAccentBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.medication_outlined,
                                size: 14,
                                color: _kAccentBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: _kTextPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Last: ${DateFormat('d MMM y').format(t.lastSeen)} · ${t.count} session${t.count > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.wasCompleted ? _kSuccessBg : _kAmberBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: t.wasCompleted
                                      ? _kSuccess.withValues(alpha: 0.4)
                                      : _kAmber.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                t.wasCompleted ? 'Completed' : 'Ongoing',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.wasCompleted ? _kSuccess : _kAmber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TreatmentEntry {
  final String name;
  final DateTime lastSeen;
  final int count;
  final bool wasCompleted;
  const _TreatmentEntry({
    required this.name,
    required this.lastSeen,
    required this.count,
    required this.wasCompleted,
  });
}

// =============================================================================
// 5. MEDICAL HISTORY CARD (Deep Real Patient & Visit Clinical Data)
// =============================================================================

class _MedicalHistoryCard extends StatelessWidget {
  final Patient patient;
  final AsyncValue<List<Visit>> visitsAsync;
  const _MedicalHistoryCard({
    required this.patient,
    required this.visitsAsync,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.medical_information_outlined,
                color: _kAccentBlue,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'MEDICAL HISTORY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _kTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Active Diagnoses from patient model
          if (patient.diagnosis.isNotEmpty) ...[
            const _MedHistorySection(
              icon: Icons.local_hospital_outlined,
              label: 'Active Diagnoses',
              accent: _kRed,
            ),
            const SizedBox(height: 6),
            for (final diag in patient.diagnosis)
              _MedHistoryDiagRow(
                title: diag,
                subtitle: 'Recorded at registration · active condition',
              ),
            const SizedBox(height: 10),
          ],

          // Clinical Visit Records with therapistNotes / treatmentType
          visitsAsync.when(
            loading: () => const _SkeletonBox(height: 40),
            error: (_, __) => const SizedBox.shrink(),
            data: (visits) {
              final records = visits
                  .where((v) =>
                      v.status == VisitStatus.completed &&
                      (v.treatmentType?.trim().isNotEmpty == true ||
                          v.therapistNotes?.trim().isNotEmpty == true))
                  .toList()
                ..sort((a, b) =>
                    b.scheduledStart.compareTo(a.scheduledStart));

              if (records.isEmpty) {
                return const _EmptyStateCard(
                  icon: Icons.history_edu_outlined,
                  message: 'No clinical notes recorded from past sessions.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _MedHistorySection(
                    icon: Icons.history_edu_outlined,
                    label: 'Clinical Visit Records',
                    accent: _kAccentBlue,
                  ),
                  const SizedBox(height: 8),
                  for (final v in records) _VisitHistoryRow(visit: v),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MedHistorySection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _MedHistorySection({
    required this.icon,
    required this.label,
    required this.accent,
  });
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
}

class _MedHistoryDiagRow extends StatelessWidget {
  final String title;
  final String subtitle;
  const _MedHistoryDiagRow({
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kRed,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _kTextSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _VisitHistoryRow extends StatelessWidget {
  final Visit visit;
  const _VisitHistoryRow({required this.visit});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM y').format(visit.scheduledStart);
    final treatment = visit.treatmentType?.trim() ?? '';
    final notes = visit.therapistNotes?.trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: _kAccentBlue),
              const SizedBox(width: 5),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _kAccentBlue,
                ),
              ),
              if (treatment.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kAccentBlueBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      treatment,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _kAccentBlue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          if (notes.isNotEmpty)
            Text(
              notes,
              style: const TextStyle(
                fontSize: 12,
                color: _kTextPrimary,
                height: 1.4,
              ),
            )
          else
            const Text(
              'No clinical notes recorded.',
              style: TextStyle(
                fontSize: 11.5,
                color: _kTextSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// REUSABLE BASE WIDGETS
// =============================================================================

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF8FAFC),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kTextMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  const _SkeletonBox({this.height = 60});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// =============================================================================
// HELPERS
// =============================================================================

Color _colorForVisitStatus(VisitStatus status) {
  switch (status) {
    case VisitStatus.scheduled:
      return _kAccentBlue;
    case VisitStatus.completed:
      return _kSuccess;
    case VisitStatus.cancelled:
      return _kRed;
    case VisitStatus.missed:
      return _kAmber;
  }
}

String _readableStatus(VisitStatus status) {
  final raw = status.value;
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

String _formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    final mins = difference.inMinutes;
    return '$mins ${mins == 1 ? 'min' : 'mins'} ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hr' : 'hrs'} ago';
  } else if (difference.inDays < 30) {
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  } else if (difference.inDays < 365) {
    final months = (difference.inDays / 30).floor();
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  } else {
    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }
}

// ======================= FULL-SCREEN WRAPPER =======================
class DesktopPatientDetailsScreen extends ConsumerWidget {
  final Patient patient;
  const DesktopPatientDetailsScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PatientDetailsBody(
        patient: patient,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}
