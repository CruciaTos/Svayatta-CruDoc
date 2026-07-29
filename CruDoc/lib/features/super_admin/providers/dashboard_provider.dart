import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashboard_stats_model.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';

/// State for the Super Admin dashboard.
class DashboardState {
  final DashboardStatsModel stats;
  final List<ChartDataPoint> doctorGrowth;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastRefreshed;

  DashboardState({
    DashboardStatsModel? stats,
    this.doctorGrowth = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastRefreshed,
  }) : stats = stats ?? DashboardStatsModel();

  DashboardState copyWith({
    DashboardStatsModel? stats,
    List<ChartDataPoint>? doctorGrowth,
    bool? isLoading,
    String? errorMessage,
    DateTime? lastRefreshed,
    bool clearError = false,
  }) {
    return DashboardState(
      stats: stats ?? this.stats,
      doctorGrowth: doctorGrowth ?? this.doctorGrowth,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    );
  }
}

/// Provider for dashboard data.
class DashboardNotifier extends Notifier<DashboardState> {
  late final SuperAdminAnalyticsService _service;

  @override
  DashboardState build() {
    _service = SuperAdminAnalyticsService();
    return DashboardState();
  }

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true);

    try {
      final results = await Future.wait([
        _service.getDashboardStats(),
        _service.getDoctorGrowthData(),
      ]);

      state = state.copyWith(
        stats: results[0] as DashboardStatsModel,
        doctorGrowth: results[1] as List<ChartDataPoint>,
        isLoading: false,
        lastRefreshed: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> refresh() async {
    await loadDashboard();
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);