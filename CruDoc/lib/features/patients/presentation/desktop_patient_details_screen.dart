// desktop_patient_details_screen.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';

// ---------- Desktop dashboard palette (matches desktop_patient_records_screen.dart) ----------
const Color _kTextPrimary = Color(0xFF0F172A);
const Color _kTextSecondary = Color(0xFF64748B);
const Color _kTextMuted = Color(0xFF94A3B8);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kAccentBlue = Color(0xFF2563EB);
const Color _kAccentBlueBg = Color(0xFFEFF6FF);
const Color _kSuccess = Color(0xFF00C853);
const Color _kAmber = Color(0xFFFFA000);
const Color _kRed = Color(0xFFD32F2F);

/// Embeddable patient-details body.
///
/// Use this widget to show patient details inline (without pushing a new
/// route), so the sidebar and overall scaffold remain visible.
/// [onBack] is called when the user taps the back button.
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

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Doctor's Note"),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            minLines: 4,
            decoration: InputDecoration(
              hintText: 'Type notes for this patient…',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccentBlue),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text('Delete Patient'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${patient.fullName}? This will remove the patient record from your active list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await ref.read(patientRepositoryProvider).deletePatient(patient.id);
      if (!mounted) return;
      ref.invalidate(patientsStreamProvider);
      // Go back to the table view instead of popping the whole route.
      widget.onBack();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${patient.fullName} deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete patient: $e')));
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
    // Always resolve the live patient so edits are reflected immediately.
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back button + patient name header ──────────────────────────
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: _kTextPrimary),
                tooltip: 'Back to patient list',
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  patient.fullName,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: _kTextSecondary,
                  size: 22,
                ),
                tooltip: 'Edit patient',
                onPressed: () => _editPatient(patient),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 22,
                ),
                tooltip: 'Delete patient',
                onPressed: () => _deletePatient(patient),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Content ────────────────────────────────────────────────────
          _PatientHeader(patient: patient),
          const SizedBox(height: 20),
          visitsAsync.when(
            loading: () => const _StatsRowSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
            data: (visits) {
              final completedCount = visits
                  .where((v) => v.status == VisitStatus.completed)
                  .length;
              final lastVisitLabel = visits.isEmpty
                  ? 'No visits yet'
                  : _formatRelativeTime(visits.first.scheduledStart);
              return _StatsRow(
                sessionsAttended: completedCount,
                lastVisit: lastVisitLabel,
              );
            },
          ),
          const SizedBox(height: 20),
          _DoctorsNoteCard(note: _note, onTap: _editNote),
          const SizedBox(height: 20),
          const _SectionLabel(text: 'CONTACT'),
          const SizedBox(height: 10),
          _ContactCard(phone: patient.phone, email: patient.email),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionLabel(text: 'SESSION HISTORY'),
              TextButton.icon(
                onPressed: () => _scheduleSession(patient),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Schedule Session'),
                style: TextButton.styleFrom(
                  foregroundColor: _kAccentBlue,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          visitsAsync.when(
            loading: () => const _EmptyStateCard(
              icon: Icons.history,
              message: 'Loading session history…',
            ),
            error: (_, __) => const _EmptyStateCard(
              icon: Icons.error_outline,
              message: 'Could not load visit history',
            ),
            data: (visits) {
              if (visits.isEmpty) {
                return const _EmptyStateCard(
                  icon: Icons.event_busy_outlined,
                  message: 'No sessions recorded yet.',
                );
              }
              return Column(
                children: [
                  for (final visit in visits)
                    _SessionTile(visit: visit, patient: patient),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Full-screen patient details page for desktop (retained for any existing
/// [Navigator.push] call-sites).
class DesktopPatientDetailsScreen extends ConsumerWidget {
  final Patient patient;
  const DesktopPatientDetailsScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PatientDetailsBody(
        patient: patient,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}

// ---------- Header (replaces _DialogHeader) ----------
class _PatientHeader extends StatelessWidget {
  final Patient patient;
  const _PatientHeader({required this.patient});

  @override
  Widget build(BuildContext context) {
    final initial = patient.firstName.isNotEmpty
        ? patient.firstName[0].toUpperCase()
        : 'P';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: _kAccentBlueBg,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kAccentBlue,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                patient.fullName.trim().isEmpty
                    ? 'Unnamed Patient'
                    : patient.fullName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _kTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoPill(
                    icon: Icons.person_outline,
                    label:
                        '${patient.gender.isEmpty ? "—" : patient.gender}, ${patient.age} yrs',
                  ),
                  for (final diagnosis in patient.diagnosis)
                    _InfoPill(icon: Icons.healing_outlined, label: diagnosis),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- Info Pill ----------
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kAccentBlue),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Quick stats ----------
class _StatsRow extends StatelessWidget {
  final int sessionsAttended;
  final String lastVisit;
  const _StatsRow({required this.sessionsAttended, required this.lastVisit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_repeat,
            value: '$sessionsAttended',
            label: 'Sessions Completed',
            accent: _kSuccess,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.event_available,
            value: lastVisit,
            label: 'Last Session',
            accent: _kAccentBlue,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kTextPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _kTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatsRowSkeleton extends StatelessWidget {
  const _StatsRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SkeletonBox()),
        const SizedBox(width: 12),
        Expanded(child: _SkeletonBox()),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// ---------- Section label ----------
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: _kTextSecondary,
      ),
    );
  }
}

// ---------- Doctor's note ----------
class _DoctorsNoteCard extends StatelessWidget {
  final String note;
  final VoidCallback onTap;
  const _DoctorsNoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasNote = note.trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.sticky_note_2_outlined,
                color: _kAccentBlue,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "DOCTOR'S NOTE",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: _kTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: _kTextMuted.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasNote ? note : 'Click to add a note for this patient.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: hasNote
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: hasNote ? _kTextPrimary : _kTextSecondary,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Contact ----------
class _ContactCard extends StatelessWidget {
  final String phone;
  final String email;
  const _ContactCard({required this.phone, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _ContactRow(
            icon: Icons.call_outlined,
            value: phone.isNotEmpty ? phone : 'No phone number',
            emphasize: phone.isNotEmpty,
          ),
          const SizedBox(height: 10),
          _ContactRow(
            icon: Icons.email_outlined,
            value: email.isNotEmpty ? email : 'No email registered',
            emphasize: email.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool emphasize;
  const _ContactRow({
    required this.icon,
    required this.value,
    required this.emphasize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _kAccentBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: _kAccentBlue, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontStyle: emphasize ? FontStyle.normal : FontStyle.italic,
              color: emphasize ? _kTextPrimary : _kTextSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Session history ----------
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
        borderRadius: BorderRadius.circular(10),
        onTap: () => showSessionDetailsSheet(
          context,
          VisitWithPatient(visit: visit, patient: patient),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(10),
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
              const SizedBox(width: 12),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kTextPrimary,
                          ),
                        ),
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PaymentChip(visit: visit),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
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
    final label = isPaid && visit.amountCharged != null
        ? 'Paid ₹${visit.amountCharged!.toStringAsFixed(0)}'
        : (isPaid ? 'Paid' : 'Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ---------- Empty state ----------
class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kTextSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: _kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Helpers ----------
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
    return '$mins ${mins == 1 ? 'minute' : 'minutes'} ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
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
