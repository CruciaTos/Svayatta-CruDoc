import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

// Import all the widgets we created
import '../widgets/ai_insight_widget.dart';
import '../widgets/upcoming_appointments_widget.dart';
import '../widgets/upcoming_visits_widget.dart';
import '../widgets/consultations_stats_widget.dart';
import '../widgets/total_patients_widget.dart';
import '../widgets/quick_actions_widget.dart';
import '../widgets/recent_patients_widget.dart';
import '../widgets/activity_logs_widget.dart';
import '../widgets/pending_tasks_suggestions_widget.dart';

/// Desktop version of the Dashboard tab.
/// 
/// Features a responsive 2-column grid layout containing stats, 
/// patient lists, AI insights, appointments, and task tracking.
class DesktopDashboardScreen extends StatelessWidget {
  const DesktopDashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    // We wrap the content in a transparent Scaffold to match your Shell's design.
    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header --
            const _DashboardHeader(),
            const SizedBox(height: 24),

            // -- Top Stats Row --
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: const [
                ConsultationsStatsWidget(),
                TotalPatientsWidget(),
              ],
            ),
            const SizedBox(height: 24),

            // -- Main Body Grid --
            LayoutBuilder(
              builder: (context, constraints) {
                // Desktop: Two columns (2/3 stats & 1/3 side panel)
                // Mobile/Tablet: Stacked vertically
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
                    children: const [
                      QuickActionsWidget(),
                      SizedBox(height: 16),
                      UpcomingAppointmentsWidget(),
                      SizedBox(height: 16),
                      RecentPatientsWidget(),
                      SizedBox(height: 16),
                      AiInsightWidget(),
                      SizedBox(height: 16),
                      PendingTasksSuggestionsWidget(),
                      SizedBox(height: 16),
                      ActivityLogsWidget(),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// HEADER WIDGET (Kept inside the main file as it's specific to this screen)
// ==============================================================================

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: DoctorProfileHelper.watchDoctorProfile(user),
      builder: (context, snapshot) {
        final doctorName = DoctorProfileHelper.formatDoctorName(user, snapshot.data);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey, $doctorName!',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const Text(
                  "Let's get to work",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('Search...', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.12),
                  radius: 20,
                  child: Text(
                    doctorName.isNotEmpty ? doctorName[0].toUpperCase() : 'Dr',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
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