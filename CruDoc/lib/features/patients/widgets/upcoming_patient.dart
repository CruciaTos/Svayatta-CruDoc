import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    as vmodel;
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart'
    show VisitWithPatient;
import 'package:doctor_management_app/features/appointments/presentation/visit_details.dart';

/// "Upcoming" summary card for the Patient Records screen.
///
/// Shows the next scheduled visit with a pill‑shaped countdown at top‑right,
/// plus the day of the week and time (12‑hour AM/PM, no date).
/// The visit type label is removed; for clinic appointments the patient's
/// age/gender/diagnosis now appears directly below the name.
class UpcomingPatientCard extends ConsumerWidget {
  const UpcomingPatientCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingPatientProvider);

    return upcomingAsync.when(
      loading: () => const _Shell(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => const _Shell(
        child: Center(
          child: Text(
            'Could not load upcoming visit',
            style: AppColors.bodyMedium,
          ),
        ),
      ),
      data: (result) {
        if (result == null) {
          return const _Shell(
            child: Center(
              child: Text(
                'No upcoming visits scheduled',
                style: AppColors.bodyMedium,
              ),
            ),
          );
        }

        final patient = result.patient;
        final visit = result.visit;
        final isClinic = visit.visitType == vmodel.VisitType.clinic;

        // Day of the week
        final dayStr = _dayName(visit.scheduledStart.weekday);

        // 12-hour time with AM/PM
        final hour24 = visit.scheduledStart.hour;
        final hour12 =
            hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
        final amPm = hour24 >= 12 ? 'PM' : 'AM';
        final timeStr = '${hour12.toString().padLeft(2, '0')}:'
            '${visit.scheduledStart.minute.toString().padLeft(2, '0')} '
            '$amPm';

        final durationLabel = '${visit.durationMinutes} min';

        // Countdown
        final now = DateTime.now();
        final timeUntil = visit.scheduledStart.difference(now);
        final countdownText = _formatCountdown(timeUntil);

        void openDetails() {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VisitDetailsPage(
                initial: VisitWithPatient(visit: visit, patient: patient),
              ),
            ),
          );
        }

        final mapUrl = _mapUrlFor(visit);

        // ---------------------------------------------------------------
        //  Card UI – unchanged content, inside a taller shell
        // ---------------------------------------------------------------
        return _Shell(
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: openDetails,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          patient.fullName,
                          style: AppColors.bodyLarge.copyWith(
                            fontSize: 25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isClinic) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${patient.age} yrs  •  ${patient.gender}'
                            '${patient.diagnosis.isNotEmpty ? '  •  ${patient.diagnosisDisplay}' : ''}',
                            style: AppColors.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '$dayStr  •  $timeStr',
                          style: AppColors.bodyMeta,
                        ),
                        if (!isClinic) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$durationLabel  •  ${visit.address}',
                            style: AppColors.bodyMeta,
                          ),
                          if (mapUrl != null)
                            TextButton(
                              onPressed: () => _launchUrl(context, mapUrl),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Open in maps'),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Pill‑shaped countdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      countdownText,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Formats the time remaining in a human‑friendly way.
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
      return minutes > 0 ? '${hours}h ${minutes}mins' : '${hours}hrs';
    }
    return '${d.inMinutes}mins';
  }
}

// ---------- Taller shell (only height increased) ----------
class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 130),   // increased from 80 → 130
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), // original padding kept
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

// ---------- Maps URL ----------
String? _mapUrlFor(vmodel.Visit visit) {
  final link = visit.mapsLink?.trim();
  if (link != null && link.isNotEmpty) {
    return (link.startsWith('http://') || link.startsWith('https://'))
        ? link
        : 'https://$link';
  }
  final hasCoords = visit.latitude != null && visit.longitude != null;
  final query =
      hasCoords ? '${visit.latitude},${visit.longitude}' : visit.address;
  if (query.isEmpty) return null;
  return 'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(query)}';
}

// ---------- Maps launcher ----------
Future<void> _launchUrl(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not open the link')),
  );
}

// ---------- Helpers ----------
String _dayName(int weekday) {
  const days = [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return days[weekday];
}