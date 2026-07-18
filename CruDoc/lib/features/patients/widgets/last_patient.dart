import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

class LastPatientsCard extends ConsumerWidget {
  const LastPatientsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPatientAsync = ref.watch(lastPatientProvider);

    return lastPatientAsync.when(
      loading: () => const _CardShell(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => const _CardShell(
        child: Center(
          child: Text('Could not load last patient', style: AppColors.bodyMedium),
        ),
      ),
      data: (result) {
        if (result == null) {
          return const _CardShell(
            child: Center(
              child: Text('No visits recorded yet', style: AppColors.bodyMedium),
            ),
          );
        }
        return _LastPatientContent(patient: result.patient, visit: result.visit);
      },
    );
  }
}

// ---------- Real content, once we have a patient + their last visit ----------
class _LastPatientContent extends ConsumerWidget {
  final Patient patient;
  final Visit visit;
  const _LastPatientContent({required this.patient, required this.visit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(visitsForPatientProvider(patient.id));
    final sessionsCount = visitsAsync.value
            ?.where((v) => v.status == VisitStatus.completed)
            .length ??
        0;

    final initial = patient.fullName.isNotEmpty
        ? patient.fullName[0].toUpperCase()
        : '?';

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Last Patient',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.silver.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _formatRelativeTime(visit.scheduledStart),
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Patient Info Row
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.silver.withOpacity(0.2),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.fullName,
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      patient.diagnosis.isNotEmpty
                          ? '${patient.diagnosis}  •  ${patient.gender}, ${patient.age}'
                          : '${patient.gender}, ${patient.age}',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary.withOpacity(0.9),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 16, color: AppColors.silver),
                        const SizedBox(width: 4),
                        Text(
                          _formatRelativeTime(visit.scheduledStart),
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.calendar_today,
                            size: 16, color: AppColors.silver),
                        const SizedBox(width: 4),
                        Text(
                          '$sessionsCount ${sessionsCount == 1 ? 'session' : 'sessions'}',
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ---------- Helper: relative time formatting ----------
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