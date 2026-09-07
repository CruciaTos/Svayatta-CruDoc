import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';

import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/recent_activity_provider.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_details_screen.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/dental_quick_actions_row.dart';

/// Desktop version of the Dashboard tab.
///
/// Features a responsive 2-column grid layout containing stats,
/// patient lists, AI insights, appointments, and task tracking.
class DesktopDashboardScreen extends StatelessWidget {
  const DesktopDashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // -- Header --
                  const _DashboardHeader(),
                  const SizedBox(height: 20),

                  // -- Top Stats Row --
                  Row(
                    children: const [
                      Expanded(child: ConsultationsStatsWidget()),
                      SizedBox(width: 16),
                      Expanded(child: TotalPatientsWidget()),
                    ],
                  ),
                  const SizedBox(height: 20),

            // -- Main Body Grid --
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth > 1000;
                if (isDesktop) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column (Stats, Recent Patients, Quick Actions)
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StreamBuilder<Map<String, dynamic>?>(
                              stream: DoctorProfileHelper.watchDoctorProfile(),
                              builder: (context, profileSnapshot) {
                                final rawSpecialty =
                                    DoctorProfileHelper.formatSpecialty(
                                      profileSnapshot.data,
                                    );
                                final isDentist = rawSpecialty
                                    .toLowerCase()
                                    .contains('dent');
                                if (!isDentist) return const SizedBox.shrink();

                                return const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: DentalQuickActionsRow(),
                                );
                              },
                            ),
                            const QuickActionsWidget(),
                            const SizedBox(height: 16),
                            const RecentPatientsWidget(),
                            const SizedBox(height: 16),
                            const ActivityLogsWidget(),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Right Column (Appointments, Visits, AI, Tasks)
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const UpcomingAppointmentsWidget(),
                            const SizedBox(height: 16),
                            const UpcomingVisitsWidget(),
                            const SizedBox(height: 16),
                            const AiInsightWidget(),
                            const SizedBox(height: 16),
                            const PendingTasksSuggestionsWidget(),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  // Mobile / Narrow window fallback
                  return Column(
                    children: [
                      StreamBuilder<Map<String, dynamic>?>(
                        stream: DoctorProfileHelper.watchDoctorProfile(),
                        builder: (context, profileSnapshot) {
                          final rawSpecialty =
                              DoctorProfileHelper.formatSpecialty(
                                profileSnapshot.data,
                              );
                          final isDentist = rawSpecialty.toLowerCase().contains(
                            'dent',
                          );
                          if (!isDentist) return const SizedBox.shrink();

                          return const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: DentalQuickActionsRow(),
                          );
                        },
                      ),
                      const QuickActionsWidget(),
                      const SizedBox(height: 16),
                      const UpcomingAppointmentsWidget(),
                      const SizedBox(height: 16),
                      const RecentPatientsWidget(),
                      const SizedBox(height: 16),
                      const AiInsightWidget(),
                      const SizedBox(height: 16),
                      const PendingTasksSuggestionsWidget(),
                      const SizedBox(height: 16),
                      const ActivityLogsWidget(),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
  ),
),
);
  }
}

// ==============================================================================
// HEADER WIDGET
// ==============================================================================

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: DoctorProfileHelper.watchDoctorProfile(user),
      builder: (context, snapshot) {
        final profileData = snapshot.data;
        final doctorName = DoctorProfileHelper.formatDoctorName(
          user,
          profileData,
        );
        final specialty = DoctorProfileHelper.formatSpecialty(
          profileData,
          user,
        );
        final specMeta = DoctorSpecialty.fromString(specialty);
        final formattedDate =
            DateFormat('EEEE, d MMM yyyy').format(DateTime.now());

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Welcome back, $doctorName',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: _kTextMedium,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kEmerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _kEmerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Active Clinic',
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _kEmerald,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Clinical Dashboard',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _kTextDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Click to switch specialty',
                      waitDuration: const Duration(milliseconds: 300),
                      child: InkWell(
                        onTap: () => showSpecialtySwitcherDialog(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: specMeta.accentColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: specMeta.accentColor.withValues(
                                alpha: 0.25,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                specMeta.icon,
                                size: 14,
                                color: specMeta.accentColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                specialty,
                                style: TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: specMeta.accentColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 14,
                                color: specMeta.accentColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                // Date display pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorderLight),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x040F172A),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.today_rounded,
                        color: _kPrimaryAccent,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Doctor profile avatar
                Tooltip(
                  message: 'Doctor Profile',
                  waitDuration: const Duration(milliseconds: 300),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorderLight),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x040F172A),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: specMeta.accentColor.withValues(
                              alpha: 0.15,
                            ),
                            radius: 14,
                            child: Icon(
                              specMeta.icon,
                              color: specMeta.accentColor,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            doctorName,
                            style: const TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _kTextDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ==============================================================================
// INLINED DASHBOARD WIDGETS
// ==============================================================================

// -----------------------------------------------------------------------------
// 1. CONSULTATIONS STATS WIDGET
// -----------------------------------------------------------------------------

const Color _kPrimaryAccent = Color(0xFF2563EB);
const Color _kEmerald = Color(0xFF10B981);
const Color _kRose = Color(0xFFF43F5E);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kTextDark = Color(0xFF0F172A);
const Color _kTextMedium = Color(0xFF475569);
const Color _kCardBg = Colors.white;
const Color _kBorderLight = Color(0xFFE2E8F0);

// Backward-compat aliases for existing references
const _clrPrimary = _kTextDark;
const _clrTextDark = _kTextDark;
const _clrTextMedium = _kTextMedium;
const _clrBlue = _kPrimaryAccent;
const _clrBlueTint = Color(0xFFEFF6FF);
const _clrGreen = _kEmerald;
const _clrRed = _kRose;
const _clrCardBorder = _kBorderLight;
const _clrAmber = _kAmber;
const _clrIcon = _kTextMedium;

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
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                color: _clrPrimary,
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
                  color: _clrGreen,
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
                color: _clrPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading data',
              style: TextStyle(
                color: _clrRed,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        data: (patients) {
          final now = DateTime.now();
          final startOfThisMonth = DateTime(now.year, now.month, 1);
          final startOfLastMonth = DateTime(now.year, now.month - 1, 1);

          final patientsLastMonth = patients
              .where(
                (p) =>
                    p.createdAt.isAfter(startOfLastMonth) &&
                    p.createdAt.isBefore(startOfThisMonth),
              )
              .length;
          final patientsThisMonth = patients
              .where((p) => p.createdAt.isAfter(startOfThisMonth))
              .length;
          final past30Days = patients
              .where(
                (p) =>
                    p.createdAt.isAfter(now.subtract(const Duration(days: 30))),
              )
              .length;

          final day0Count = patients
              .where(
                (p) =>
                    p.createdAt.year == now.year &&
                    p.createdAt.month == now.month &&
                    p.createdAt.day == now.day,
              )
              .length;

          final yesterday = now.subtract(const Duration(days: 1));
          final day1Count = patients
              .where(
                (p) =>
                    p.createdAt.year == yesterday.year &&
                    p.createdAt.month == yesterday.month &&
                    p.createdAt.day == yesterday.day,
              )
              .length;

          final twoDaysAgo = now.subtract(const Duration(days: 2));
          final day2Count = patients
              .where(
                (p) =>
                    p.createdAt.year == twoDaysAgo.year &&
                    p.createdAt.month == twoDaysAgo.month &&
                    p.createdAt.day == twoDaysAgo.day,
              )
              .length;

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
                      color: _clrPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _clrGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _clrGreen.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '+$patientsThisMonth this mo',
                      style: const TextStyle(
                        color: _clrGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
                        color: _clrTextDark,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: labelSuffix,
                      style: const TextStyle(
                        color: _clrTextMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 13,
                    color: _clrTextMedium,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Last 3 days: $day2Count · $day1Count · $day0Count',
                    style: const TextStyle(color: _clrTextMedium, fontSize: 11),
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

// -----------------------------------------------------------------------------
// 2. TOTAL PATIENTS WIDGET
// -----------------------------------------------------------------------------

class TotalPatientsWidget extends ConsumerWidget {
  const TotalPatientsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsStreamProvider);

    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              'Total Patients',
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
                  color: Color(0xFF3F51B5),
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
              'Total Patients',
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
          final total = patients.length;
          final active = patients.where((p) => !p.isArchived).length;
          final now = DateTime.now();
          final startOfThisMonth = DateTime(now.year, now.month, 1);
          final newThisMonth = patients
              .where((p) => p.createdAt.isAfter(startOfThisMonth))
              .length;

          final ratio = total == 0 ? 0.0 : (active / total);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Patients',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      newThisMonth > 0
                          ? '+$newThisMonth this mo'
                          : '$active active',
                      style: const TextStyle(
                        color: Colors.blue,
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
                      text: '$total ',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: '$active active',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: total == 0 ? 0.0 : ratio,
                backgroundColor: const Color(0xFFE0E0E0),
                color: const Color(0xFF3F51B5),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. QUICK ACTIONS WIDGET
// -----------------------------------------------------------------------------

class QuickActionsWidget extends StatelessWidget {
  final VoidCallback? onAddPatient;
  final VoidCallback? onSchedule;
  final VoidCallback? onViewReports;
  final VoidCallback? onPrescribe;

  const QuickActionsWidget({
    super.key,
    this.onAddPatient,
    this.onSchedule,
    this.onViewReports,
    this.onPrescribe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onSurfaceColor = theme.colorScheme.onSurface;
    final borderColor = theme.colorScheme.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              color: onSurfaceColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Add Patient',
                color: primaryColor,
                onTap: onAddPatient,
              ),
              _ActionButton(
                icon: Icons.calendar_month_rounded,
                label: 'Schedule',
                color: primaryColor,
                onTap: onSchedule,
              ),
              _ActionButton(
                icon: Icons.assignment_rounded,
                label: 'View Reports',
                color: primaryColor,
                onTap: onViewReports,
              ),
              _ActionButton(
                icon: Icons.medication_rounded,
                label: 'Prescribe',
                color: primaryColor,
                onTap: onPrescribe,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. RECENT PATIENTS WIDGET
// -----------------------------------------------------------------------------

class RecentPatientsWidget extends ConsumerWidget {
  const RecentPatientsWidget({super.key});

  String _formatInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsStreamProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Patients',
                style: TextStyle(
                  color: _clrPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton.icon(
                onPressed: () => showAddPatientSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Patient'),
                style: TextButton.styleFrom(
                  foregroundColor: _clrBlue,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          patientsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _clrBlue,
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Could not load patients: $error',
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
            data: (patients) {
              if (patients.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 36,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No patients registered yet.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final sortedPatients = List<Patient>.from(patients)
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final recentList = sortedPatients.take(5).toList();

              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(3.5),
                  1: FlexColumnWidth(2.5),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(2),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.15),
                  ),
                ),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Patient Info',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Diagnosis',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        'Age / Gender',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        'Status',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        'Joined',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  ...recentList.map((patient) {
                    final diagnosisText =
                        patient.diagnosisDisplay.trim().isNotEmpty
                        ? patient.diagnosisDisplay
                        : 'General';
                    final genderText = patient.gender.trim().isNotEmpty
                        ? patient.gender
                        : '—';
                    final ageText = patient.age > 0 ? '${patient.age}y' : '';
                    final ageGender = [
                      genderText,
                      if (ageText.isNotEmpty) ageText,
                    ].join(' • ');
                    final joinedDate = DateFormat(
                      'dd MMM yyyy',
                    ).format(patient.createdAt);

                    return TableRow(
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DesktopPatientDetailsScreen(
                                  patient: patient,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: _clrBlueTint,
                                  child: Text(
                                    _formatInitials(patient.fullName),
                                    style: const TextStyle(
                                      color: _clrBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: _clrTextDark,
                                      ),
                                    ),
                                    if (patient.phone.trim().isNotEmpty)
                                      Text(
                                        patient.phone,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _clrBlueTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                diagnosisText,
                                style: const TextStyle(
                                  color: _clrBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ageGender,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusBadge(
                            text: patient.isArchived ? 'Archived' : 'Active',
                            color: patient.isArchived
                                ? _clrTextMedium
                                : _clrGreen,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            joinedDate,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 5. ACTIVITY LOGS WIDGET
// -----------------------------------------------------------------------------

class ActivityLogsWidget extends ConsumerWidget {
  const ActivityLogsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(recentActivityProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Activity Logs',
                style: TextStyle(
                  color: _clrPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              activityAsync.whenOrNull(
                    data: (items) => items.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _clrBlueTint,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _clrBlue.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              '${items.length} events',
                              style: const TextStyle(
                                color: _clrBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                  ) ??
                  const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 12),
          activityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _clrBlue,
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Could not load activity logs.',
                style: TextStyle(color: _clrTextMedium, fontSize: 13),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'No recent activity recorded.',
                    style: TextStyle(color: _clrTextMedium, fontSize: 13),
                  ),
                );
              }

              final displayItems = items.take(5).toList();

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayItems.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 16, color: _clrCardBorder),
                itemBuilder: (context, index) {
                  return _LogItem(item: displayItems[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final ActivityItem item;

  const _LogItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _clrBlueTint,
            shape: BoxShape.circle,
          ),
          child: Icon(item.icon, size: 14, color: _clrBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.text,
            style: const TextStyle(
              color: _clrTextDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.relativeTime,
          style: TextStyle(
            color: _clrTextMedium,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 6. UPCOMING APPOINTMENTS WIDGET
// -----------------------------------------------------------------------------

class UpcomingAppointmentsWidget extends ConsumerWidget {
  const UpcomingAppointmentsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: visitsAsync.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(count: null),
            const SizedBox(height: 20),
            const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: _clrBlue,
                  strokeWidth: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        error: (error, stack) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(count: null),
            const SizedBox(height: 16),
            Text(
              'Unable to load appointments.',
              style: TextStyle(
                color: _clrRed,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        data: (visits) {
          final resolved = visits.where((v) => v.patient != null).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(count: resolved.length),
              const SizedBox(height: 12),
              if (resolved.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'No appointments scheduled for today.',
                    style: TextStyle(color: _clrTextMedium, fontSize: 13),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: resolved.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = resolved[index];
                    return _AppointmentItem(
                      item: item,
                      onTap: () => showSessionDetailsSheet(context, item),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader({required int? count}) {
    final label = (count == null || count == 0) ? 'Today' : '$count Today';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Your Appointments',
          style: TextStyle(
            color: _clrPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _clrBlueTint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _clrBlue.withValues(alpha: 0.2)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _clrBlue,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppointmentItem extends StatelessWidget {
  final VisitWithPatient item;
  final VoidCallback onTap;

  const _AppointmentItem({required this.item, required this.onTap});

  String _formatInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final patient = item.patient;
    final visit = item.visit;
    final patientName = patient?.fullName.trim().isNotEmpty == true
        ? patient!.fullName
        : 'Unknown Patient';

    final startTime = DateFormat('h:mm a').format(visit.scheduledStart);
    final endTime = DateFormat('h:mm a').format(visit.scheduledEnd);
    final timeRange = '$startTime - $endTime';

    final typeLabel = visit.visitType == VisitType.home ? 'Home' : 'Clinic';
    final typeColor = visit.visitType == VisitType.home ? _clrAmber : _clrGreen;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _clrBlueTint,
                child: Text(
                  _formatInitials(patientName),
                  style: const TextStyle(
                    color: _clrBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        color: _clrTextDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeRange,
                      style: TextStyle(color: _clrTextMedium, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

// -----------------------------------------------------------------------------
// 7. UPCOMING VISITS WIDGET
// -----------------------------------------------------------------------------

class UpcomingVisitsWidget extends ConsumerWidget {
  const UpcomingVisitsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(visitsWithPatientsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: visitsAsync.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Upcoming Visits',
              style: TextStyle(
                color: _clrPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 20),
            Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _clrBlue,
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
              'Upcoming Visits',
              style: TextStyle(
                color: _clrPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to load upcoming visits.',
              style: TextStyle(color: _clrTextMedium, fontSize: 13),
            ),
          ],
        ),
        data: (visits) {
          final resolved = visits.where((v) => v.patient != null).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Visits',
                    style: TextStyle(
                      color: _clrPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (resolved.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _clrBlueTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _clrBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        '${resolved.length}',
                        style: const TextStyle(
                          color: _clrBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (resolved.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No upcoming visits scheduled.',
                    style: TextStyle(color: _clrTextMedium, fontSize: 13),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: resolved.length,
                  itemBuilder: (context, index) {
                    final item = resolved[index];
                    final isLast = index == resolved.length - 1;
                    return _VisitTimelineRow(
                      item: item,
                      isLast: isLast,
                      onTap: () => showSessionDetailsSheet(context, item),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VisitTimelineRow extends StatelessWidget {
  final VisitWithPatient item;
  final bool isLast;
  final VoidCallback onTap;

  const _VisitTimelineRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final isTomorrow =
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day + 1;

    final timeStr = DateFormat('hh:mm a').format(date);
    if (isToday) {
      return timeStr;
    } else if (isTomorrow) {
      return 'Tom $timeStr';
    } else {
      return '${DateFormat('MMM d').format(date)}\n$timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = item.visit;
    final patient = item.patient;
    final patientName = patient?.fullName.trim().isNotEmpty == true
        ? patient!.fullName
        : 'Unknown Patient';

    final title = visit.treatmentType?.trim().isNotEmpty == true
        ? visit.treatmentType!
        : (visit.visitType == VisitType.home
              ? 'Home Visitation'
              : 'Clinic Appointment');

    final dotColor = visit.visitType == VisitType.home ? _clrAmber : _clrBlue;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    _formatTime(visit.scheduledStart),
                    style: TextStyle(
                      color: _clrTextMedium,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: Colors.grey.shade200,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _clrTextDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          patientName,
                          style: TextStyle(color: _clrTextMedium, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

// -----------------------------------------------------------------------------
// 8. AI INSIGHT WIDGET
// -----------------------------------------------------------------------------

class AiInsightWidget extends StatelessWidget {
  const AiInsightWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF6366F1),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'AI Smart Insights',
                style: TextStyle(
                  fontFamily: AppColors.headingFontFamily,
                  color: _kTextDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _InsightItem(
            icon: Icons.trending_up_rounded,
            text:
                'Patient influx is 15% higher this week. Consider preparing extra examination slots.',
          ),
          const SizedBox(height: 8),
          const _InsightItem(
            icon: Icons.tips_and_updates_rounded,
            text:
                '3 follow-up lab investigations are pending review for today’s morning visits.',
          ),
          const SizedBox(height: 8),
          const _InsightItem(
            icon: Icons.notifications_active_rounded,
            text:
                'Preventative immunization reminder dispatch scheduled for this Thursday.',
          ),
        ],
      ),
    );
  }
}

class _InsightItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InsightItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: _kTextDark,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 9. PENDING TASKS SUGGESTIONS WIDGET
// -----------------------------------------------------------------------------

class PendingTasksSuggestionsWidget extends StatelessWidget {
  const PendingTasksSuggestionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _clrCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Tasks',
                style: TextStyle(
                  color: _clrPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _clrBlueTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _clrBlue.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  '2/8',
                  style: TextStyle(
                    color: _clrBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _TaskCheckItem(
            title: 'Interview',
            subtitle: 'Sep 15, 08:30',
            isComplete: true,
          ),
          const Divider(height: 8, color: _clrCardBorder),
          const _TaskCheckItem(
            title: 'Team Meeting',
            subtitle: 'Sep 15, 10:30',
            isComplete: true,
          ),
          const Divider(height: 8, color: _clrCardBorder),
          const _TaskCheckItem(
            title: 'Project Update',
            subtitle: 'Sep 15, 13:00',
            isComplete: false,
          ),
          const Divider(height: 8, color: _clrCardBorder),
          const _TaskCheckItem(
            title: 'AI Follow-up: Schedule review',
            subtitle: 'Sep 16, 09:00',
            isComplete: false,
          ),
        ],
      ),
    );
  }
}

class _TaskCheckItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isComplete;

  const _TaskCheckItem({
    required this.title,
    required this.subtitle,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: isComplete,
          onChanged: (val) {},
          activeColor: _clrBlue,
          checkColor: Colors.white,
          shape: const CircleBorder(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _clrTextDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  decoration: isComplete
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: _clrTextMedium, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, color: _clrIcon, size: 20),
          onPressed: () {},
        ),
      ],
    );
  }
}
