import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/dashboard_stats_model.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              if (dashboardState.lastRefreshed != null)
                Text(
                  'Last updated: ${_formatTime(dashboardState.lastRefreshed!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: dashboardState.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(dashboardProvider.notifier).refresh(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Dashboard error
          if (dashboardState.errorMessage != null) ...[
            Container(
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
                  Expanded(child: Text(dashboardState.errorMessage!)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Metric cards
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isMobile ? 2 : 4,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _metricCards.length,
              itemBuilder: (context, index) {
                final card = _metricCards[index];
                return _buildMetricCard(
                  title: card.title,
                  value: _getMetricValue(card.key, dashboardState.stats),
                  change: _getMetricChange(card.key, dashboardState.stats),
                  icon: card.icon,
                  color: card.color,
                  isLoading: dashboardState.isLoading,
                );
              },
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color.withValues(alpha: 1.0), size: 20),
              ),
              const Spacer(),
              if (change != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (change > 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        change > 0 ? Icons.trending_up : Icons.trending_down,
                        size: 14,
                        color: change > 0 ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${change.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: change > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
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
              width: 60,
              height: 12,
              child: LinearProgressIndicator(),
            )
          else ...[
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
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