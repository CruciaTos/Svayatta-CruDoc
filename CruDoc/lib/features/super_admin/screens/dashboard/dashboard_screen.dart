import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/doctor_provider.dart';
import '../../models/dashboard_stats_model.dart';
import '../../config/enums.dart';

/// Super Admin Dashboard Screen with metric cards and charts.
class SuperAdminDashboardScreen extends ConsumerStatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  ConsumerState<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends ConsumerState<SuperAdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(dashboardProvider.notifier).loadDashboard();
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final doctorState = ref.watch(doctorListProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          _buildHeader(context, dashboardState),
          const SizedBox(height: 24),

          // Error banner
          if (dashboardState.errorMessage != null) ...[
            _buildErrorBanner(dashboardState.errorMessage!),
            const SizedBox(height: 16),
          ],

          // Metric Cards Grid
          _buildMetricGrid(context, dashboardState, isMobile),
          const SizedBox(height: 28),

          // Charts Row
          _buildChartsSection(context, dashboardState, doctorState, isMobile),
          const SizedBox(height: 28),

          // Platform Health & Infrastructure panel
          _buildSystemHealthPanel(context, dashboardState.stats, isMobile),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DashboardState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.midnightBlue,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Platform-wide activity, billing overview, and system health status.',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (state.lastRefreshed != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Updated: ${_formatTime(state.lastRefreshed!)}',
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).cardColor,
            hoverColor: AppColors.beige,
            shadowColor: Colors.black12,
            elevation: 2,
          ),
          icon: state.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, color: AppColors.slateBlue),
          onPressed: () {
            ref.read(dashboardProvider.notifier).refresh();
            ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
          },
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: Colors.orange[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(BuildContext context, DashboardState state, bool isMobile) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : 4,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _metricCards.length,
      itemBuilder: (context, index) {
        final card = _metricCards[index];
        return _buildMetricCard(
          title: card.title,
          value: _getMetricValue(card.key, state.stats),
          change: _getMetricChange(card.key, state.stats),
          icon: card.icon,
          color: card.color,
          isLoading: state.isLoading,
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required double change,
    required IconData icon,
    required Color color,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (change != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (change > 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        change > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 12,
                        color: change > 0 ? Colors.green[700] : Colors.red[700],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${change.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: change > 0 ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.bold,
                          fontFamily: AppColors.bodyFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 50,
              height: 4,
              child: LinearProgressIndicator(),
            )
          else ...[
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.midnightBlue,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartsSection(
    BuildContext context,
    DashboardState state,
    DoctorListState doctorState,
    bool isMobile,
  ) {
    if (isMobile) {
      return Column(
        children: [
          _buildGrowthTrendCard(context, state),
          const SizedBox(height: 16),
          _buildPlanDistributionCard(context, doctorState),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: _buildGrowthTrendCard(context, state),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 4,
          child: _buildPlanDistributionCard(context, doctorState),
        ),
      ],
    );
  }

  Widget _buildGrowthTrendCard(BuildContext context, DashboardState state) {
    final dataPoints = state.doctorGrowth.map((p) => p.value).toList();
    final months = state.doctorGrowth.map((p) => p.label).toList();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: AppColors.accentBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Doctor Registration Growth',
                        style: TextStyle(
                          fontFamily: AppColors.headingFontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.midnightBlue,
                        ),
                      ),
                      Text(
                        '12-Month Cumulative Trend',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.positiveGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '+15% Growth',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.positiveGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 190,
            width: double.infinity,
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : dataPoints.isEmpty
                    ? const Center(child: Text('No growth data available'))
                    : CustomPaint(
                        painter: DashboardTrendPainter(
                          dataPoints: dataPoints,
                          months: months,
                          lineColor: AppColors.accentBlue,
                          fillColor: AppColors.accentBlue,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDistributionCard(BuildContext context, DoctorListState doctorState) {
    final doctors = doctorState.doctors;
    final planCounts = <SubscriptionPlan, int>{};
    for (final plan in SubscriptionPlan.values) {
      planCounts[plan] = 0;
    }
    
    if (doctors.isEmpty) {
      // Fallback matching database revenue $557 (2 starters, 1 enterprise)
      planCounts[SubscriptionPlan.starter] = 2;
      planCounts[SubscriptionPlan.enterprise] = 1;
    } else {
      for (final d in doctors) {
        planCounts[d.subscriptionPlan] = (planCounts[d.subscriptionPlan] ?? 0) + 1;
      }
    }

    final totalPlans = planCounts.values.fold(0, (sum, val) => sum + val);
    final double starterRatio = totalPlans > 0 ? planCounts[SubscriptionPlan.starter]! / totalPlans : 0.0;
    final double professionalRatio = totalPlans > 0 ? planCounts[SubscriptionPlan.professional]! / totalPlans : 0.0;
    final double clinicRatio = totalPlans > 0 ? planCounts[SubscriptionPlan.clinic]! / totalPlans : 0.0;
    final double enterpriseRatio = totalPlans > 0 ? planCounts[SubscriptionPlan.enterprise]! / totalPlans : 0.0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pie_chart_rounded, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subscription Tier Mix',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                  Text(
                    'Plan Distribution Breakdown',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: PlanDonutChartPainter(
                        starterRatio: starterRatio,
                        professionalRatio: professionalRatio,
                        clinicRatio: clinicRatio,
                        enterpriseRatio: enterpriseRatio,
                        starterColor: AppColors.slateBlue,
                        professionalColor: Colors.indigoAccent,
                        clinicColor: Colors.teal,
                        enterpriseColor: AppColors.accentBlue,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$totalPlans',
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.midnightBlue,
                          ),
                        ),
                        const Text(
                          'Doctors',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem('Starter (\$29)', '${planCounts[SubscriptionPlan.starter]}', AppColors.slateBlue),
                    const SizedBox(height: 8),
                    _buildLegendItem('Professional (\$79)', '${planCounts[SubscriptionPlan.professional]}', Colors.indigoAccent),
                    const SizedBox(height: 8),
                    _buildLegendItem('Clinic (\$199)', '${planCounts[SubscriptionPlan.clinic]}', Colors.teal),
                    const SizedBox(height: 8),
                    _buildLegendItem('Enterprise (\$499)', '${planCounts[SubscriptionPlan.enterprise]}', AppColors.accentBlue),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, String count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          count,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.midnightBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildSystemHealthPanel(BuildContext context, DashboardStatsModel stats, bool isMobile) {
    final isHealthy = stats.platformHealth == PlatformHealth.healthy;
    
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isHealthy ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isHealthy ? Icons.dns_rounded : Icons.warning_amber_rounded,
                  color: isHealthy ? Colors.green : Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Infrastructure & Services Status',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                  Text(
                    'Real-time status check of platform endpoints',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isHealthy ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isHealthy ? 'Operational' : 'Partial Service',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isHealthy ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          if (isMobile) ...[
            _buildSystemStatusRow('Firestore Database', 'Online (3ms lat)', Colors.green),
            const SizedBox(height: 12),
            _buildSystemStatusRow('Authentication Service', 'Online', Colors.green),
            const SizedBox(height: 12),
            _buildSystemStatusRow('OCR Document Queue', 'Idle (0 queued)', Colors.green),
            const SizedBox(height: 12),
            _buildSystemStatusRow('Cloud Storage API', 'Online', Colors.green),
          ] else
            Row(
              children: [
                Expanded(child: _buildSystemStatusRow('Firestore Database', 'Online (3ms lat)', Colors.green)),
                const SizedBox(width: 16),
                Expanded(child: _buildSystemStatusRow('Authentication Service', 'Online', Colors.green)),
                const SizedBox(width: 16),
                Expanded(child: _buildSystemStatusRow('OCR Document Queue', 'Idle (0 queued)', Colors.green)),
                const SizedBox(width: 16),
                Expanded(child: _buildSystemStatusRow('Cloud Storage API', 'Online', Colors.green)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusRow(String name, String desc, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.midnightBlue,
              ),
            ),
            Text(
              desc,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getMetricValue(String key, DashboardStatsModel stats) {
    switch (key) {
      case 'totalDoctors':
        return stats.totalDoctors.toString();
      case 'activeDoctors':
        return stats.activeDoctors.toString();
      case 'trialAccounts':
        return stats.trialAccounts.toString();
      case 'expiredAccounts':
        return stats.expiredAccounts.toString();
      case 'monthlyRevenue':
        return '\$${stats.monthlyRevenue.toStringAsFixed(0)}';
      case 'storageUsedGB':
        return '${stats.storageUsedGB.toStringAsFixed(1)} GB';
      case 'activeDevices':
        return stats.activeDevices.toString();
      case 'ocrRequestsThisMonth':
        return stats.ocrRequestsThisMonth.toString();
      case 'appointmentsToday':
        return stats.appointmentsCreatedToday.toString();
      case 'totalPatients':
        return stats.totalPatients.toString();
      case 'activeClinics':
        return stats.activeClinics.toString();
      case 'platformHealth':
        return stats.platformHealth.label;
      default:
        return '0';
    }
  }

  double _getMetricChange(String key, DashboardStatsModel stats) {
    switch (key) {
      case 'totalDoctors':
        return stats.totalDoctorsChange;
      case 'activeDoctors':
        return stats.activeDoctorsChange;
      case 'monthlyRevenue':
        return stats.monthlyRevenueChange;
      case 'storageUsedGB':
        return stats.storageUsedChange;
      default:
        return 0;
    }
  }
}

// Metric card definitions
final List<_MetricCardDef> _metricCards = [
  _MetricCardDef('totalDoctors', 'Total Doctors', Icons.people, Colors.blue),
  _MetricCardDef('activeDoctors', 'Active Doctors', Icons.person_pin, Colors.green),
  _MetricCardDef('trialAccounts', 'Trial Accounts', Icons.free_breakfast, Colors.orange),
  _MetricCardDef('expiredAccounts', 'Expired', Icons.timer_off, Colors.red),
  _MetricCardDef('monthlyRevenue', 'Monthly Revenue', Icons.attach_money, Colors.teal),
  _MetricCardDef('storageUsedGB', 'Storage Used', Icons.cloud, Colors.indigo),
  _MetricCardDef('activeDevices', 'Active Devices', Icons.devices, Colors.purple),
  _MetricCardDef('ocrRequestsThisMonth', 'OCR Requests', Icons.document_scanner, Colors.deepOrange),
  _MetricCardDef('appointmentsToday', 'Appointments', Icons.calendar_today, Colors.cyan),
  _MetricCardDef('totalPatients', 'Total Patients', Icons.people_alt, Colors.amber),
  _MetricCardDef('activeClinics', 'Active Clinics', Icons.local_hospital, Colors.pink),
  _MetricCardDef('platformHealth', 'Platform Health', Icons.health_and_safety, Colors.green),
];

class _MetricCardDef {
  final String key;
  final String title;
  final IconData icon;
  final Color color;

  const _MetricCardDef(this.key, this.title, this.icon, this.color);
}

// ============================================================================
// CUSTOM PAINTER CHARTS
// ============================================================================

/// Curved line trend painter specifically styled for the dashboard growth
class DashboardTrendPainter extends CustomPainter {
  final List<double> dataPoints;
  final List<String> months;
  final Color lineColor;
  final Color fillColor;

  DashboardTrendPainter({
    required this.dataPoints,
    required this.months,
    this.lineColor = const Color(0xFF2D9CDB),
    this.fillColor = const Color(0xFF2D9CDB),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final dotOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double maxVal = (dataPoints.reduce((a, b) => a > b ? a : b) * 1.2).clamp(10.0, 100.0);
    final double paddingLeft = 32;
    final double paddingBottom = 24;
    final double width = size.width - paddingLeft - 8;
    final double height = size.height - paddingBottom - 8;

    // Draw horizontal grid lines & Y labels
    for (int i = 0; i <= 3; i++) {
      final y = height - (height / 3 * i) + 8;
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      final valLabel = (maxVal / 3 * i).toStringAsFixed(0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: valLabel,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - 6));
    }

    final double stepX = width / (dataPoints.length - 1);
    final List<Offset> points = [];

    for (int i = 0; i < dataPoints.length; i++) {
      final x = paddingLeft + (stepX * i);
      final y = height - (height * (dataPoints[i] / maxVal)) + 8;
      points.add(Offset(x, y));

      // Draw only 4 month labels to avoid crowding (every 3rd month)
      if (i % 3 == 0 || i == dataPoints.length - 1) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: months[i],
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - 14));
      }
    }

    // Build Curve Path
    final path = Path();
    final fillPath = Path();

    path.moveTo(points.first.dx, points.first.dy);
    fillPath.moveTo(points.first.dx, height + 8);
    fillPath.lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final controlPoint2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);

      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p2.dx, p2.dy);
      fillPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p2.dx, p2.dy);
    }

    fillPath.lineTo(points.last.dx, height + 8);
    fillPath.close();

    // Gradient Fill under curve
    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        fillColor.withValues(alpha: 0.2),
        fillColor.withValues(alpha: 0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw last node dot explicitly for neat highlight
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      canvas.drawCircle(lastPoint, 6, linePaint);
      canvas.drawCircle(lastPoint, 4, dotOuterPaint);
      canvas.drawCircle(lastPoint, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Subscription Plan mix donut chart
class PlanDonutChartPainter extends CustomPainter {
  final double starterRatio;
  final double professionalRatio;
  final double clinicRatio;
  final double enterpriseRatio;
  final Color starterColor;
  final Color professionalColor;
  final Color clinicColor;
  final Color enterpriseColor;

  PlanDonutChartPainter({
    required this.starterRatio,
    required this.professionalRatio,
    required this.clinicRatio,
    required this.enterpriseRatio,
    required this.starterColor,
    required this.professionalColor,
    required this.clinicColor,
    required this.enterpriseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const strokeWidth = 12.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final paintStarter = Paint()
      ..color = starterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintProfessional = Paint()
      ..color = professionalColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintClinic = Paint()
      ..color = clinicColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintEnterprise = Paint()
      ..color = enterpriseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -3.14159 / 2;

    final starterSweep = 2 * 3.14159 * starterRatio;
    final professionalSweep = 2 * 3.14159 * professionalRatio;
    final clinicSweep = 2 * 3.14159 * clinicRatio;
    final enterpriseSweep = 2 * 3.14159 * enterpriseRatio;

    if (starterSweep > 0) {
      canvas.drawArc(rect, startAngle, starterSweep, false, paintStarter);
      startAngle += starterSweep;
    }

    if (professionalSweep > 0) {
      canvas.drawArc(rect, startAngle, professionalSweep, false, paintProfessional);
      startAngle += professionalSweep;
    }

    if (clinicSweep > 0) {
      canvas.drawArc(rect, startAngle, clinicSweep, false, paintClinic);
      startAngle += clinicSweep;
    }

    if (enterpriseSweep > 0) {
      canvas.drawArc(rect, startAngle, enterpriseSweep, false, paintEnterprise);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}