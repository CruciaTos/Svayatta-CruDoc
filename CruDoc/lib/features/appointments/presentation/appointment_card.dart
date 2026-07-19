import 'dart:async';

import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    show VisitStatus;

/// Card for a clinic appointment.
///
/// Deliberately a separate widget from `VisitCard` rather than a variant
/// of it: a clinic booking has nowhere to send a doctor via "open in
/// maps" (it's always at the clinic — see [VisitType.clinic] in
/// `visits_model.dart`), so there's no map preview here. In its place,
/// this card surfaces what actually matters for a clinic appointment —
/// the patient's age, gender, and condition at a glance, plus a large,
/// live-updating countdown to the appointment.
class AppointmentCard extends StatefulWidget {
  final String patientName;
  final int age;
  final String gender;
  final String condition;
  final String date;
  final String day;
  final String time;

  /// Used to derive the live countdown / "ongoing now" state — kept as
  /// raw [DateTime]s (rather than a pre-formatted string) so the
  /// countdown can recompute itself every tick without the parent
  /// needing to re-render.
  final DateTime scheduledStart;
  final DateTime scheduledEnd;

  final VisitStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onReschedule;
  final VoidCallback? onMarkCompleted;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  const AppointmentCard({
    super.key,
    required this.patientName,
    required this.age,
    required this.gender,
    required this.condition,
    required this.date,
    required this.day,
    required this.time,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    this.onTap,
    this.onReschedule,
    this.onMarkCompleted,
    this.onCancel,
    this.onDelete,
  });

  @override
  State<AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<AppointmentCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The underlying visit data doesn't change minute to minute, but the
    // "time left" display needs to — a periodic tick is simpler and more
    // reliable here than waiting on the next Firestore/SQLite emission.
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOngoing = !now.isBefore(widget.scheduledStart) &&
        now.isBefore(widget.scheduledEnd);
    final countdownLabel = isOngoing
        ? 'Ongoing now'
        : _formatCountdown(widget.scheduledStart.difference(now));

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 260,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(36),
        ),
        child: Stack(
          children: [
            // --- Patient name (top-left) ---
            Positioned(
              top: 12,
              left: 12,
              right: 50, // room for popup menu
              child: Text(
                widget.patientName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
            ),

            // --- Status badge & PopupMenuButton (top-right) ---
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(widget.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(widget.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (widget.onReschedule != null ||
                      widget.onMarkCompleted != null ||
                      widget.onCancel != null ||
                      widget.onDelete != null)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: AppColors.textSecondary, size: 20),
                      color: AppColors.cardSurface,
                      itemBuilder: (context) => [
                        if (widget.onReschedule != null)
                          const PopupMenuItem(
                            value: 'reschedule',
                            child: Text('Reschedule'),
                          ),
                        if (widget.onMarkCompleted != null)
                          const PopupMenuItem(
                            value: 'complete',
                            child: Text('Mark Completed'),
                          ),
                        if (widget.onCancel != null)
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel Appointment'),
                          ),
                        if (widget.onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete Appointment'),
                          ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'reschedule':
                            widget.onReschedule?.call();
                            break;
                          case 'complete':
                            widget.onMarkCompleted?.call();
                            break;
                          case 'cancel':
                            widget.onCancel?.call();
                            break;
                          case 'delete':
                            widget.onDelete?.call();
                            break;
                        }
                      },
                    ),
                ],
              ),
            ),

            // --- Age & Gender (below name) ---
            Positioned(
              top: 52,
              left: 12,
              right: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.age} yrs  •  ${widget.gender}',
                    style: AppColors.bodyMeta,
                  ),
                ],
              ),
            ),

            // --- Condition (below age/gender) ---
            Positioned(
              top: 76,
              left: 12,
              right: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medical_information_outlined,
                      size: 16, color: Colors.black),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.condition.trim().isEmpty
                          ? 'No condition on file'
                          : widget.condition,
                      style: AppColors.bodyMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // --- Date & Time (below condition) ---
            Positioned(
              top: 100,
              left: 12,
              right: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.date}  •  ${widget.day}',
                    style: AppColors.bodyMeta,
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.access_time, size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(widget.time, style: AppColors.bodyMeta),
                ],
              ),
            ),

            // --- Big countdown (bottom) — this is the space a VisitCard
            // spends on a map preview; a clinic appointment has nowhere
            // to navigate to, so it goes to the one thing a home-visit
            // card doesn't show front-and-center: how soon it is. ---
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.slateBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.slateBlue,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      countdownLabel,
                      style: const TextStyle(
                        color: AppColors.slateBlue,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                    if (!isOngoing) ...[
                      const SizedBox(height: 2),
                      Text(
                        'until appointment',
                        style: AppColors.bodySmall.copyWith(
                          color: AppColors.slateBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Formats the time remaining as e.g. "2h 15m", "45m", or "3d 4h" — the
  /// coarsest two units that matter, matching how a doctor actually
  /// thinks about "how soon" rather than showing exact seconds.
  String _formatCountdown(Duration d) {
    if (d.isNegative || d.inMinutes <= 0) return 'Starting now';
    if (d.inDays >= 1) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (d.inHours >= 1) {
      final hours = d.inHours;
      final minutes = d.inMinutes % 60;
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    return '${d.inMinutes}m';
  }

  Color _statusColor(VisitStatus status) {
    switch (status) {
      case VisitStatus.scheduled:
        return Colors.blue;
      case VisitStatus.completed:
        return Colors.green;
      case VisitStatus.cancelled:
        return Colors.orange;
      case VisitStatus.missed:
        return Colors.red;
    }
  }

  String _statusLabel(VisitStatus status) {
    switch (status) {
      case VisitStatus.scheduled:
        return 'Scheduled';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.cancelled:
        return 'Cancelled';
      case VisitStatus.missed:
        return 'Missed';
    }
  }
}
