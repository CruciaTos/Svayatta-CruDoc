import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

class UpcomingPatientCard extends ConsumerWidget {
  const UpcomingPatientCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingPatientProvider);

    return upcomingAsync.when(
      loading: () => const _CardShell(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => const _CardShell(
        child: Center(
          child: Text('Could not load upcoming visit', style: AppColors.bodyMedium),
        ),
      ),
      data: (result) {
        if (result == null) {
          return const _CardShell(
            child: Center(
              child: Text('No upcoming visits scheduled', style: AppColors.bodyMedium),
            ),
          );
        }

        final patient = result.patient;
        final visit = result.visit;

        return _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                patient.fullName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                patient.diagnosis.isNotEmpty ? patient.diagnosis : patient.gender,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event_available,
                      size: 15, color: AppColors.silver),
                  const SizedBox(width: 4),
                  Text(
                    _formatUpcoming(visit.scheduledStart),
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------- Shared card chrome (loading / empty / real all use this) ----------
class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ---------- Helper: "Today, 3:00 PM" / "Jun 20, 3:00 PM" ----------
String _formatUpcoming(DateTime dateTime) {
  final now = DateTime.now();
  final isToday = dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow = dateTime.year == tomorrow.year &&
      dateTime.month == tomorrow.month &&
      dateTime.day == tomorrow.day;

  final time = DateFormat.jm().format(dateTime);
  if (isToday) return 'Today, $time';
  if (isTomorrow) return 'Tomorrow, $time';
  return '${DateFormat.MMMd().format(dateTime)}, $time';
}