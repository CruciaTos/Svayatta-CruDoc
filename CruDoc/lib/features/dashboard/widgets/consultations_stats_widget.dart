import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

/// Displays consultation / new patient statistics in the last month using real data from [patientsStreamProvider].
class ConsultationsStatsWidget extends ConsumerWidget {
  const ConsultationsStatsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsStreamProvider);

    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: patientsAsync.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Consultations',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 16),
            Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
            SizedBox(height: 12),
          ],
        ),
        error: (error, stack) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Consultations',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading data',
              style: TextStyle(color: Colors.red[300], fontSize: 12),
            ),
          ],
        ),
        data: (patients) {
          final now = DateTime.now();
          final startOfThisMonth = DateTime(now.year, now.month, 1);
          final startOfLastMonth = DateTime(now.year, now.month - 1, 1);

          // Patients registered in the last calendar month & past 30 days
          final patientsLastMonth = patients
              .where((p) => p.createdAt.isAfter(startOfLastMonth) && p.createdAt.isBefore(startOfThisMonth))
              .length;
          final patientsThisMonth = patients
              .where((p) => p.createdAt.isAfter(startOfThisMonth))
              .length;
          final past30Days = patients
              .where((p) => p.createdAt.isAfter(now.subtract(const Duration(days: 30))))
              .length;

          // Count per day for last 3 days
          final day0Count = patients.where((p) =>
              p.createdAt.year == now.year &&
              p.createdAt.month == now.month &&
              p.createdAt.day == now.day).length;

          final yesterday = now.subtract(const Duration(days: 1));
          final day1Count = patients.where((p) =>
              p.createdAt.year == yesterday.year &&
              p.createdAt.month == yesterday.month &&
              p.createdAt.day == yesterday.day).length;

          final twoDaysAgo = now.subtract(const Duration(days: 2));
          final day2Count = patients.where((p) =>
              p.createdAt.year == twoDaysAgo.year &&
              p.createdAt.month == twoDaysAgo.month &&
              p.createdAt.day == twoDaysAgo.day).length;

          final displayCount = past30Days > 0 ? past30Days : patientsLastMonth;
          final labelSuffix = past30Days > 0 ? 'past 30 days' : 'last month';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Consultations',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+$patientsThisMonth this mo',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$displayCount ',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: labelSuffix,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Last 3 days: $day2Count · $day1Count · $day0Count',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}