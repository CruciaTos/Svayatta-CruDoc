import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// Amber used only for a [QueueStatus.called] token's badge/border — the
/// one state that means "act now, this patient is being called". Not in
/// [AppColors] today; scoped to this widget the same way
/// `visitation_card.dart` and `bottom_nav_bar.dart` each keep small
/// feature-local color constants alongside the shared palette.
const Color _calledAmber = Color(0xFFF59E0B);

Color _statusColor(QueueStatus status) {
  switch (status) {
    case QueueStatus.waiting:
      return AppColors.slateBlue;
    case QueueStatus.called:
      return _calledAmber;
    case QueueStatus.inConsultation:
      return AppColors.accentBlue;
    case QueueStatus.completed:
      return AppColors.positiveGreen;
    case QueueStatus.skipped:
    case QueueStatus.cancelled:
      return AppColors.negativeRed;
  }
}

String _statusLabel(QueueStatus status) {
  switch (status) {
    case QueueStatus.waiting:
      return 'Waiting';
    case QueueStatus.called:
      return 'Called';
    case QueueStatus.inConsultation:
      return 'In Consultation';
    case QueueStatus.completed:
      return 'Completed';
    case QueueStatus.skipped:
      return 'Skipped';
    case QueueStatus.cancelled:
      return 'Cancelled';
  }
}

/// A single row in the walk-in queue list: token number, patient/walk-in
/// name, optional reason, a status chip, and (when supplied) a row of
/// contextual action buttons.
///
/// Deliberately takes plain display values rather than a
/// `QueueEntryWithPatient` — keeps this widget decoupled from Riverpod
/// and the patient join, matching how `VisitCard` takes primitives
/// rather than a repository type.
class QueueTokenCard extends StatelessWidget {
  final int tokenNumber;
  final String displayName;
  final String? reason;
  final QueueStatus status;
  final QueuePriority priority;
  final DateTime checkedInAt;
  final VoidCallback? onTap;

  /// Action callbacks — pass only the ones that make sense for
  /// [status]; the row only renders buttons for non-null callbacks.
  final VoidCallback? onStartConsultation;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onRequeue;
  final VoidCallback? onCancel;

  const QueueTokenCard({
    super.key,
    required this.tokenNumber,
    required this.displayName,
    this.reason,
    required this.status,
    this.priority = QueuePriority.normal,
    required this.checkedInAt,
    this.onTap,
    this.onStartConsultation,
    this.onComplete,
    this.onSkip,
    this.onRequeue,
    this.onCancel,
  });

  String get _waitLabel {
    final minutes = DateTime.now().difference(checkedInAt).inMinutes;
    if (minutes < 1) return 'Just checked in';
    if (minutes < 60) return 'Waiting $minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return 'Waiting ${hours}h ${remainder}m';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final actions = <Widget>[
      if (onStartConsultation != null)
        _ActionChip(
          label: 'Start',
          icon: Icons.play_arrow_rounded,
          color: AppColors.accentBlue,
          onTap: onStartConsultation!,
        ),
      if (onComplete != null)
        _ActionChip(
          label: 'Complete',
          icon: Icons.check_rounded,
          color: AppColors.positiveGreen,
          onTap: onComplete!,
        ),
      if (onSkip != null)
        _ActionChip(
          label: 'Skip',
          icon: Icons.skip_next_rounded,
          color: AppColors.negativeRed,
          onTap: onSkip!,
        ),
      if (onRequeue != null)
        _ActionChip(
          label: 'Requeue',
          icon: Icons.replay_rounded,
          color: AppColors.slateBlue,
          onTap: onRequeue!,
        ),
      if (onCancel != null)
        _ActionChip(
          label: 'Cancel',
          icon: Icons.close_rounded,
          color: AppColors.negativeRed,
          onTap: onCancel!,
        ),
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TokenBadge(tokenNumber: tokenNumber, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (priority == QueuePriority.urgent) ...[
                            Icon(
                              Icons.priority_high_rounded,
                              size: 16,
                              color: AppColors.negativeRed,
                            ),
                            const SizedBox(width: 2),
                          ],
                          Expanded(
                            child: Text(
                              displayName,
                              style: AppColors.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (reason == null || reason!.trim().isEmpty)
                            ? _waitLabel
                            : '${reason!.trim()} · $_waitLabel',
                        style: AppColors.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(label: _statusLabel(status), color: color),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _TokenBadge extends StatelessWidget {
  final int tokenNumber;
  final Color color;
  const _TokenBadge({required this.tokenNumber, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '#$tokenNumber',
        style: TextStyle(
          fontFamily: AppColors.headingFontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
