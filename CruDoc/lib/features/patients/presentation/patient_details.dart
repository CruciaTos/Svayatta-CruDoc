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

const Color _accentBlue = Color(0xFF5DADE2);
const Color _accentTeal = Color(0xFF48C9B0);

BoxDecoration _surfaceCardDecoration({BorderRadius? radius}) {
  return BoxDecoration(
    color: AppColors.cardSurface,
    borderRadius: radius ?? BorderRadius.circular(16),
    border: Border.all(
      color: AppColors.chartBarDim.withValues(alpha: 0.22),
    ),
  );
}

String _titleCaseWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed
      .split(RegExp(r'\s+'))
      .map((word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');
}

class PatientDetailsPage extends ConsumerStatefulWidget {
  final Patient patient;

  const PatientDetailsPage({
    super.key,
    required this.patient,
  });

  @override
  ConsumerState<PatientDetailsPage> createState() =>
      _PatientDetailsPageState();
}

class _PatientDetailsPageState extends ConsumerState<PatientDetailsPage> {
  late String _note = widget.patient.notes;

  /// Opens the doctor's-note editor sheet. Triggered by double-tapping the
  /// note card or tapping "Add Note" in the bottom bar.
  Future<void> _openNoteEditor() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _NoteEditorSheet(initialNote: _note),
    );
    if (result == null) return; // sheet was dismissed/cancelled
    await _saveNote(result);
  }

  Future<void> _saveNote(String newNote) async {
    final trimmed = newNote.trim();
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
        content: Text('Session scheduled for ${widget.patient.fullName}'),
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
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Patient',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${currentPatient.fullName}? This will remove the patient record from your active list.',
          style: AppColors.bodyMedium,
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await ref
            .read(patientRepositoryProvider)
            .deletePatient(currentPatient.id);
        if (!mounted) return;
        ref.invalidate(patientsStreamProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${currentPatient.fullName} deleted')),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete patient: $e')),
        );
      }
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                onEdit: () => _editPatient(patient),
                onDelete: () => _deletePatient(patient),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 108),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _PatientHeader(patient: patient),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    _DoctorsNoteCard(note: _note, onTap: _openNoteEditor),
                    const SizedBox(height: 20),
                    const _SectionLabel(text: 'CONTACT'),
                    const SizedBox(height: 10),
                    _ContactCard(phone: patient.phone),
                    const SizedBox(height: 20),
                    const _SectionLabel(text: 'SESSION HISTORY'),
                    const SizedBox(height: 10),
                    visitsAsync.when(
                      loading: () => const _EmptyStateCard(
                        icon: Icons.history,
                        message: 'Loading session history…',
                      ),
                      error: (error, stack) => _EmptyStateCard(
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
                        return _SessionHistorySection(
                          sessions: visits.map((visit) {
                            final hasTreatment =
                                visit.treatmentType?.trim().isNotEmpty ??
                                    false;
                            return _SessionData(
                              visit: visit,
                              date: DateFormat.yMMMd()
                                  .format(visit.scheduledStart),
                              time:
                                  DateFormat.jm().format(visit.scheduledStart),
                              reason: hasTreatment
                                  ? visit.treatmentType!
                                  : '${_readableStatus(visit.status)} visit',
                            );
                          }).toList(),
                          patient: patient,
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
      bottomNavigationBar: _BottomActionBar(
        onAddNote: _openNoteEditor,
        onScheduleSession: _scheduleSession,
      ),
    );
  }
}

// ---------- Top Bar ----------
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Text(
              'Patient Record',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.textPrimary, size: 22),
            tooltip: 'Edit patient',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 22),
            tooltip: 'Delete patient',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ---------- Patient Header ----------
class _PatientHeader extends StatelessWidget {
  final Patient patient;
  const _PatientHeader({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _titleCaseWords(patient.fullName),
          style: const TextStyle(
            fontFamily: AppColors.headingFontFamily,
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(
              icon: Icons.person_outline,
              label:
                  '${_titleCaseWords(patient.gender)}, ${patient.age} yrs',
            ),
            for (final diagnosis in patient.diagnosis)
              _InfoPill(
                icon: Icons.healing_outlined,
                label: _titleCaseWords(diagnosis),
              ),
          ],
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.chartBarDim.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.chartBarLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppColors.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Doctor's Note ----------
class _DoctorsNoteCard extends StatelessWidget {
  final String? note;
  final VoidCallback onTap;
  const _DoctorsNoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool hasNote = note != null && note!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: _surfaceCardDecoration(),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: AppColors.chartBarLight,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          color: AppColors.chartBarLight,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "DOCTOR'S NOTE",
                                    style: AppColors.bodySmall.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                      color: AppColors.slateBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 12,
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.6),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hasNote
                                    ? note!
                                    : 'Tap to add a note for this patient.',
                                style: AppColors.bodyMedium.copyWith(
                                  color: hasNote
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontStyle: hasNote
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  height: 1.4,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Doctor's Note Editor Sheet ----------
class _NoteEditorSheet extends StatefulWidget {
  final String initialNote;
  const _NoteEditorSheet({required this.initialNote});

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.silver.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              "Doctor's Note",
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 4,
              style: AppColors.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Type notes for this patient…',
                hintStyle: AppColors.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.chartBarLight,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.slateBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _controller.text),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    backgroundColor: AppColors.chartBarLight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
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

// ---------- Quick Stats ----------
class _StatsRow extends StatelessWidget {
  final int sessionsAttended;
  final String lastVisit;

  const _StatsRow({
    required this.sessionsAttended,
    required this.lastVisit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_repeat,
            value: '$sessionsAttended',
            label: 'Sessions Completed',
            accent: _accentTeal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.event_available,
            value: lastVisit,
            label: 'Last Session',
            accent: _accentBlue,
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
      padding: const EdgeInsets.all(16),
      decoration: _surfaceCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppColors.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------- Section Label ----------
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppColors.bodySmall.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.textSecondary.withValues(alpha: 0.85),
      ),
    );
  }
}

// ---------- Contact Card ----------
class _ContactCard extends StatelessWidget {
  final String phone;

  const _ContactCard({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _surfaceCardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.chartBarLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.call_outlined,
              color: AppColors.chartBarLight,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              phone.isNotEmpty ? phone : 'No phone number',
              style: AppColors.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Session History ----------
class _SessionData {
  final Visit visit;
  final String date;
  final String time;
  final String reason;
  const _SessionData({
    required this.visit,
    required this.date,
    required this.time,
    required this.reason,
  });
}

class _SessionHistorySection extends StatefulWidget {
  final List<_SessionData> sessions;
  final Patient patient;
  const _SessionHistorySection({required this.sessions, required this.patient});

  @override
  State<_SessionHistorySection> createState() =>
      _SessionHistorySectionState();
}

class _SessionHistorySectionState extends State<_SessionHistorySection> {
  static const int _collapsedCount = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bool canCollapse = widget.sessions.length > _collapsedCount;
    final List<_SessionData> visible = (_expanded || !canCollapse)
        ? widget.sessions
        : widget.sessions.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionTimeline(sessions: visible, patient: widget.patient),
        if (canCollapse)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: _accentBlue,
              ),
              child: Text(
                _expanded
                    ? 'Show less'
                    : 'View all ${widget.sessions.length} sessions',
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SessionTimeline extends StatelessWidget {
  final List<_SessionData> sessions;
  final Patient patient;
  const _SessionTimeline({required this.sessions, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(sessions.length, (index) {
        final session = sessions[index];
        final isLast = index == sessions.length - 1;
        return _SessionTimelineTile(
          visit: session.visit,
          date: session.date,
          time: session.time,
          reason: session.reason,
          isLast: isLast,
          patient: patient,
        );
      }),
    );
  }
}

class _SessionTimelineTile extends StatelessWidget {
  final Visit visit;
  final Patient patient;
  final String date;
  final String time;
  final String reason;
  final bool isLast;

  const _SessionTimelineTile({
    required this.visit,
    required this.patient,
    required this.date,
    required this.time,
    required this.reason,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showSessionDetailsSheet(
          context,
          VisitWithPatient(visit: visit, patient: patient),
        );
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentBlue,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.chartBarDim.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          date,
                          style: AppColors.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          time,
                          style: AppColors.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            reason,
                            style: AppColors.bodyMeta,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PaymentChip(visit: visit),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Payment status chip (paid / pending), shown on each
// session tile in _SessionTimelineTile ----------
class _PaymentChip extends StatelessWidget {
  final Visit visit;
  const _PaymentChip({required this.visit});

  @override
  Widget build(BuildContext context) {
    final isPaid = visit.isPaid;
    final color = isPaid ? _accentTeal : AppColors.chartBarLight;
    final label = isPaid && visit.amountCharged != null
        ? 'Paid ₹${visit.amountCharged!.toStringAsFixed(0)}'
        : (isPaid ? 'Paid' : 'Payment Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ---------- Bottom Action Bar ----------
class _BottomActionBar extends StatelessWidget {
  final VoidCallback onAddNote;
  final VoidCallback onScheduleSession;

  const _BottomActionBar({
    required this.onAddNote,
    required this.onScheduleSession,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddNote,
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: const Text('Add Note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.slateBlue,
                  side: BorderSide(
                    color: AppColors.chartBarDim.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onScheduleSession,
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Schedule Session'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.chartBarLight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Empty state card ----------
class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyStateCard({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: _surfaceCardDecoration(),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppColors.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
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
        Expanded(child: _StatCardSkeleton()),
        const SizedBox(width: 12),
        Expanded(child: _StatCardSkeleton()),
      ],
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      decoration: _surfaceCardDecoration(),
    );
  }
}

// ---------- Helper: readable status fallback (used when a visit has no
// treatmentType set) ----------
String _readableStatus(VisitStatus status) {
  final raw = status.value;
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

// ---------- Helper: relative time ----------
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