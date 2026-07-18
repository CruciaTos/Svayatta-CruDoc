import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

const Color _accentBlue = Color(0xFF5DADE2);
const Color _accentTeal = Color(0xFF48C9B0);
const Color _accentAmber = Color(0xFFF2B84B);

class PatientDetailsPage extends StatelessWidget {
  final Patient patient;
  final String? doctorsNote;

  const PatientDetailsPage({
    super.key,
    required this.patient,
    this.doctorsNote,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const _TopBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    _PatientHeader(patient: patient),
                    const SizedBox(height: 20),
                    _DoctorsNoteCard(note: doctorsNote),
                    const SizedBox(height: 24),
                    _StatsRow(
                      // TODO: replace 0 with real session count when visits are available
                      sessionsAttended: 0,
                      lastVisit: _formatRelativeTime(patient.updatedAt),
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'CONTACT'),
                    const SizedBox(height: 12),
                    _ContactCard(phone: patient.phone),
                    const SizedBox(height: 24),
                    const _SectionLabel(text: 'SESSION HISTORY'),
                    const SizedBox(height: 12),
                    const _SessionHistorySection(
                      sessions: [
                        _SessionData(
                          date: 'June 20, 2026',
                          time: '10:30 AM',
                          reason: 'Post-op knee mobility session',
                        ),
                        _SessionData(
                          date: 'June 13, 2026',
                          time: '09:00 AM',
                          reason: 'Therapeutic ultrasound & review',
                        ),
                        _SessionData(
                          date: 'June 06, 2026',
                          time: '11:00 AM',
                          reason: 'Balance & gait re-assessment',
                        ),
                        _SessionData(
                          date: 'May 29, 2026',
                          time: '02:30 PM',
                          reason: 'Soft tissue mobilisation',
                        ),
                        _SessionData(
                          date: 'May 22, 2026',
                          time: '08:00 AM',
                          reason: 'Postural correction exercises',
                        ),
                        _SessionData(
                          date: 'May 15, 2026',
                          time: '02:00 PM',
                          reason: 'Manual therapy — lower back',
                        ),
                        _SessionData(
                          date: 'May 08, 2026',
                          time: '04:00 PM',
                          reason: 'Strength training — upper body',
                        ),
                        _SessionData(
                          date: 'April 02, 2026',
                          time: '09:00 AM',
                          reason: 'Gait training & balance assessment',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _BottomActionBar(),
    );
  }
}

// ---------- Top Bar ----------
class _TopBar extends StatelessWidget {
  const _TopBar();

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
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note,
                color: AppColors.textPrimary, size: 22),
            tooltip: 'Edit patient',
            onPressed: () {},
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
          patient.fullName,
          style: const TextStyle(
            fontFamily: AppColors.headingFontFamily,
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(
              icon: Icons.person_outline,
              label: '${patient.gender}, ${patient.age} yrs',
            ),
            if (patient.diagnosis.isNotEmpty)
              _InfoPill(
                icon: Icons.healing_outlined,
                label: patient.diagnosis,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppColors.bodySmall.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ---------- Doctor's Note ----------
class _DoctorsNoteCard extends StatelessWidget {
  final String? note;
  const _DoctorsNoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final bool hasNote = note != null && note!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _accentAmber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined,
                          color: _accentAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "DOCTOR'S NOTE",
                              style: AppColors.bodySmall.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: _accentAmber.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasNote
                                  ? note!
                                  : 'No notes added for this patient yet.',
                              style: AppColors.bodyMedium.copyWith(
                                color: hasNote
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary.withOpacity(0.7),
                                fontStyle: hasNote
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                height: 1.4,
                              ),
                              maxLines: 3,
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
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
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
        color: AppColors.textSecondary.withOpacity(0.85),
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
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_outlined, color: AppColors.silver, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phone.isNotEmpty ? phone : 'No phone number',
              style: AppColors.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Session History ----------
class _SessionData {
  final String date;
  final String time;
  final String reason;
  const _SessionData({
    required this.date,
    required this.time,
    required this.reason,
  });
}

class _SessionHistorySection extends StatefulWidget {
  final List<_SessionData> sessions;
  const _SessionHistorySection({required this.sessions});

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
        _SessionTimeline(sessions: visible),
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
  const _SessionTimeline({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(sessions.length, (index) {
        final session = sessions[index];
        final isLast = index == sessions.length - 1;
        return _SessionTimelineTile(
          date: session.date,
          time: session.time,
          reason: session.reason,
          isLast: isLast,
        );
      }),
    );
  }
}

class _SessionTimelineTile extends StatelessWidget {
  final String date;
  final String time;
  final String reason;
  final bool isLast;

  const _SessionTimelineTile({
    required this.date,
    required this.time,
    required this.reason,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
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
                    color: Colors.white.withOpacity(0.6),
                    width: 2,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.textSecondary.withOpacity(0.2),
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
                border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                  Text(
                    reason,
                    style: AppColors.bodyMeta,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Bottom Action Bar ----------
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.note_add_outlined, size: 18),
                label: const Text('Add Note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Schedule Session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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