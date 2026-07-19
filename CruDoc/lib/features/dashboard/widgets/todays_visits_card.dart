import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart'
    as vmodel;
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/visit_details.dart';

/// Dashboard card showing today's scheduled visits — both home
/// visitations and clinic appointments combined, chronological order.
///
/// Backed by [todaysVisitsWithPatientsProvider], which is deliberately
/// its own stream rather than reusing the "upcoming visits" stream the
/// Events screen tabs use — see [VisitLocalService.watchTodaysVisits]
/// for why (the shell keeps every tab alive at once).
class TodaysVisitsCard extends ConsumerWidget {
  const TodaysVisitsCard({super.key, this.onViewAll});

  /// Navigates to the Events (Visitations/Appointments) screen.
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: visitsAsync.when(
        loading: () => _CardShell(
          count: null,
          onViewAll: onViewAll,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.slateBlue,
                ),
              ),
            ),
          ),
        ),
        error: (error, stack) => _CardShell(
          count: null,
          onViewAll: onViewAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Could not load today\'s visits.',
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
        data: (visits) {
          // Matches the Events screen's own convention (see
          // _buildVisitsList): a visit whose patient couldn't be
          // resolved (e.g. deleted/archived after the visit was made)
          // isn't rendered.
          final resolved = visits.where((vw) => vw.patient != null).toList();

          return _CardShell(
            count: resolved.length,
            onViewAll: onViewAll,
            child: resolved.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No visits scheduled for today.',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < resolved.length; i++) ...[
                        _VisitRow(
                          visitWithPatient: resolved[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VisitDetailsPage(initial: resolved[i]),
                            ),
                          ),
                        ),
                        if (i != resolved.length - 1)
                          const Divider(
                            height: 24,
                            color: Color(0xFFDDE6F0),
                          ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// Shared header ("Today's Visits" + count badge) wrapped around
/// whichever body (loading/error/list) the parent passes in.
class _CardShell extends StatelessWidget {
  final int? count;
  final VoidCallback? onViewAll;
  final Widget child;

  const _CardShell({
    required this.count,
    required this.onViewAll,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Visits",
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.chartBarLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  count == null ? '—' : '$count scheduled',
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _VisitRow extends StatelessWidget {
  final VisitWithPatient visitWithPatient;
  final VoidCallback onTap;

  const _VisitRow({required this.visitWithPatient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visit = visitWithPatient.visit;
    final patient = visitWithPatient.patient!;
    final isHome = visit.visitType == vmodel.VisitType.home;
    final timeLabel = DateFormat('h:mm a').format(visit.scheduledStart);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.cardSurfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isHome ? Icons.home_outlined : Icons.local_hospital_outlined,
                color: AppColors.beige,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isHome ? 'Home visitation' : 'Clinic appointment',
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              timeLabel,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.silver,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}