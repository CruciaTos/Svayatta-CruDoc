import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/analytics_model.dart';
import '../models/dashboard_stats_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for fetching analytics data (metadata only, no patient data).
class SuperAdminAnalyticsService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Fetch dashboard statistics (aggregated).
  Future<DashboardStatsModel> getDashboardStats() async {
    try {
      // Try to get today's cached analytics first
      final todayKey = _dateKey(DateTime.now());
      final cachedDoc = await _fb.analyticsCollection.doc(todayKey).get();

      if (cachedDoc.exists) {
        return DashboardStatsModel.fromJson(
            cachedDoc.data() as Map<String, dynamic>);
      }

      // Calculate live stats if no cached data
      return await _calculateLiveStats();
    } catch (e) {
      // Fallback to live calculation
      return await _calculateLiveStats();
    }
  }

  /// Calculate live stats from the database.
  Future<DashboardStatsModel> _calculateLiveStats() async {
    try {
      final doctorsSnapshot = await _fb.usersCollection
          .where('role', isEqualTo: 'doctor')
          .where('isDeleted', isEqualTo: false)
          .get();

      int totalDoctors = 0;
      int activeDoctors = 0;
      int trialAccounts = 0;
      int expiredAccounts = 0;
      double storageUsedGB = 0.0;
      int totalPatients = 0;
      int ocrRequests = 0;
      int totalAppointments = 0;

      for (final doc in doctorsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalDoctors++;
        activeDoctors += data['status'] == DoctorStatus.active.name ? 1 : 0;
        trialAccounts += data['subscriptionPlan'] == 'trial' ? 1 : 0;
        expiredAccounts += data['status'] == DoctorStatus.expired.name ? 1 : 0;
        storageUsedGB += (data['storageUsedGB'] as num?)?.toDouble() ?? 0.0;
        totalPatients += data['patientCount'] as int? ?? 0;
        ocrRequests += data['ocrRequestsThisMonth'] as int? ?? 0;
        totalAppointments += data['appointmentCount'] as int? ?? 0;
      }

      return DashboardStatsModel(
        totalDoctors: totalDoctors,
        activeDoctors: activeDoctors,
        trialAccounts: trialAccounts,
        expiredAccounts: expiredAccounts,
        storageUsedGB: storageUsedGB,
        ocrRequestsThisMonth: ocrRequests,
        totalPatients: totalPatients,
        appointmentsCreatedToday: totalAppointments, // approximate
        activeDevices: doctorsSnapshot.docs.length, // approximate
        activeClinics: doctorsSnapshot.docs.length, // approximate
        monthlyRevenue: _estimateMonthlyRevenue(doctorsSnapshot),
        platformHealth: PlatformHealth.healthy,
      );
    } catch (e) {
      return DashboardStatsModel();
    }
  }

  double _estimateMonthlyRevenue(QuerySnapshot snapshot) {
    double revenue = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final planStr = data['subscriptionPlan'] as String? ?? 'starter';
      final plan = SubscriptionPlan.values.firstWhere(
        (e) => e.name == planStr,
        orElse: () => SubscriptionPlan.starter,
      );
      revenue += plan.monthlyPrice;
    }
    return revenue;
  }

  /// Get analytics history for charts (last N days).
  Future<List<AnalyticsModel>> getAnalyticsHistory(int days) async {
    try {
      final startDate = DateTime.now().subtract(Duration(days: days));
      final startKey = _dateKey(startDate);

      final snapshot = await _fb.analyticsCollection
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .orderBy(FieldPath.documentId, descending: false)
          .limit(days)
          .get();

      return snapshot.docs.map((doc) {
        return AnalyticsModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get per-doctor analytics (metadata only).
  Future<List<DoctorAnalyticsModel>> getDoctorAnalytics(String doctorId) async {
    try {
      final doc = await _fb.usersCollection.doc(doctorId).get();
      if (!doc.exists) return [];

      final data = doc.data() as Map<String, dynamic>;
      final analytics = DoctorAnalyticsModel(
        doctorId: doctorId,
        doctorName: data['name'] as String? ?? '',
        storageUsedGB: (data['storageUsedGB'] as num?)?.toDouble() ?? 0.0,
        storageLimitGB: (data['storageLimitGB'] as num?)?.toDouble() ?? 0.0,
        patientCount: data['patientCount'] as int? ?? 0,
        appointmentCount: data['appointmentCount'] as int? ?? 0,
        ocrRequestsThisMonth: data['ocrRequestsThisMonth'] as int? ?? 0,
        activeDeviceCount: data['activeDeviceCount'] as int? ?? 0,
        lastLogin: (data['lastLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
        totalSessions: data['totalSessions'] as int? ?? 0,
      );

      return [analytics];
    } catch (e) {
      return [];
    }
  }

  /// Get doctor growth data for charts (monthly for past 12 months).
  Future<List<ChartDataPoint>> getDoctorGrowthData() async {
    final points = <ChartDataPoint>[];
    final now = DateTime.now();

    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';

      try {
        final doc = await _fb.analyticsCollection.doc('growth_$key').get();
        final count = (doc.data() as Map<String, dynamic>?)?['totalDoctors'] as int? ?? 0;
        points.add(ChartDataPoint(
          label: _monthAbbr(month.month),
          value: count.toDouble(),
        ));
      } catch (_) {
        points.add(ChartDataPoint(
          label: _monthAbbr(month.month),
          value: 0,
        ));
      }
    }

    return points;
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _monthAbbr(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}