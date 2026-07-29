import 'package:cloud_firestore/cloud_firestore.dart';

/// Aggregated analytics data for the Super Admin dashboard.
class AnalyticsModel {
  final String id; // YYYY-MM-DD format
  final DateTime date;
  final int totalDoctors;
  final int activeDoctors;
  final int trialAccounts;
  final int expiredAccounts;
  final int totalPatients;
  final int totalAppointments;
  final int activeDevices;
  final int ocrRequestsThisMonth;
  final double totalStorageUsedGB;
  final double totalStorageLimitGB;
  final double monthlyRevenue;
  final double annualRevenue;
  final int newDoctorsToday;
  final int newDoctorsThisWeek;
  final int newDoctorsThisMonth;
  final Map<String, int> doctorsByPlan;
  final Map<String, int> doctorsBySpecialization;
  final Map<String, int> doctorsByCountry;
  final Map<String, int> featureUsageCounts;
  final DateTime generatedAt;

  AnalyticsModel({
    required this.id,
    DateTime? date,
    this.totalDoctors = 0,
    this.activeDoctors = 0,
    this.trialAccounts = 0,
    this.expiredAccounts = 0,
    this.totalPatients = 0,
    this.totalAppointments = 0,
    this.activeDevices = 0,
    this.ocrRequestsThisMonth = 0,
    this.totalStorageUsedGB = 0.0,
    this.totalStorageLimitGB = 0.0,
    this.monthlyRevenue = 0.0,
    this.annualRevenue = 0.0,
    this.newDoctorsToday = 0,
    this.newDoctorsThisWeek = 0,
    this.newDoctorsThisMonth = 0,
    Map<String, int>? doctorsByPlan,
    Map<String, int>? doctorsBySpecialization,
    Map<String, int>? doctorsByCountry,
    Map<String, int>? featureUsageCounts,
    DateTime? generatedAt,
  })  : date = date ?? DateTime.now(),
        doctorsByPlan = doctorsByPlan ?? {},
        doctorsBySpecialization = doctorsBySpecialization ?? {},
        doctorsByCountry = doctorsByCountry ?? {},
        featureUsageCounts = featureUsageCounts ?? {},
        generatedAt = generatedAt ?? DateTime.now();

  factory AnalyticsModel.fromJson(Map<String, dynamic> json, String id) {
    return AnalyticsModel(
      id: id,
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalDoctors: json['totalDoctors'] as int? ?? 0,
      activeDoctors: json['activeDoctors'] as int? ?? 0,
      trialAccounts: json['trialAccounts'] as int? ?? 0,
      expiredAccounts: json['expiredAccounts'] as int? ?? 0,
      totalPatients: json['totalPatients'] as int? ?? 0,
      totalAppointments: json['totalAppointments'] as int? ?? 0,
      activeDevices: json['activeDevices'] as int? ?? 0,
      ocrRequestsThisMonth: json['ocrRequestsThisMonth'] as int? ?? 0,
      totalStorageUsedGB: (json['totalStorageUsedGB'] as num?)?.toDouble() ?? 0.0,
      totalStorageLimitGB: (json['totalStorageLimitGB'] as num?)?.toDouble() ?? 0.0,
      monthlyRevenue: (json['monthlyRevenue'] as num?)?.toDouble() ?? 0.0,
      annualRevenue: (json['annualRevenue'] as num?)?.toDouble() ?? 0.0,
      newDoctorsToday: json['newDoctorsToday'] as int? ?? 0,
      newDoctorsThisWeek: json['newDoctorsThisWeek'] as int? ?? 0,
      newDoctorsThisMonth: json['newDoctorsThisMonth'] as int? ?? 0,
      doctorsByPlan: (json['doctorsByPlan'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      doctorsBySpecialization: (json['doctorsBySpecialization'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      doctorsByCountry: (json['doctorsByCountry'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      featureUsageCounts: (json['featureUsageCounts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      generatedAt: (json['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': Timestamp.fromDate(date),
      'totalDoctors': totalDoctors,
      'activeDoctors': activeDoctors,
      'trialAccounts': trialAccounts,
      'expiredAccounts': expiredAccounts,
      'totalPatients': totalPatients,
      'totalAppointments': totalAppointments,
      'activeDevices': activeDevices,
      'ocrRequestsThisMonth': ocrRequestsThisMonth,
      'totalStorageUsedGB': totalStorageUsedGB,
      'totalStorageLimitGB': totalStorageLimitGB,
      'monthlyRevenue': monthlyRevenue,
      'annualRevenue': annualRevenue,
      'newDoctorsToday': newDoctorsToday,
      'newDoctorsThisWeek': newDoctorsThisWeek,
      'newDoctorsThisMonth': newDoctorsThisMonth,
      'doctorsByPlan': doctorsByPlan,
      'doctorsBySpecialization': doctorsBySpecialization,
      'doctorsByCountry': doctorsByCountry,
      'featureUsageCounts': featureUsageCounts,
      'generatedAt': Timestamp.fromDate(generatedAt),
    };
  }
}

/// Per-doctor analytics (metadata only, no patient data).
class DoctorAnalyticsModel {
  final String doctorId;
  final String doctorName;
  final double storageUsedGB;
  final double storageLimitGB;
  final int patientCount;
  final int appointmentCount;
  final int inventoryItemsCount;
  final int ocrRequestsThisMonth;
  final int activeDeviceCount;
  final DateTime lastLogin;
  final int totalSessions;
  final String appVersion;
  final String platform;
  final int crashCount;
  final Map<String, int> featureUsage;

  DoctorAnalyticsModel({
    required this.doctorId,
    required this.doctorName,
    this.storageUsedGB = 0.0,
    this.storageLimitGB = 0.0,
    this.patientCount = 0,
    this.appointmentCount = 0,
    this.inventoryItemsCount = 0,
    this.ocrRequestsThisMonth = 0,
    this.activeDeviceCount = 0,
    DateTime? lastLogin,
    this.totalSessions = 0,
    this.appVersion = '',
    this.platform = '',
    this.crashCount = 0,
    Map<String, int>? featureUsage,
  })  : lastLogin = lastLogin ?? DateTime.now(),
        featureUsage = featureUsage ?? {};

  factory DoctorAnalyticsModel.fromJson(Map<String, dynamic> json, String doctorId) {
    return DoctorAnalyticsModel(
      doctorId: doctorId,
      doctorName: json['doctorName'] as String? ?? '',
      storageUsedGB: (json['storageUsedGB'] as num?)?.toDouble() ?? 0.0,
      storageLimitGB: (json['storageLimitGB'] as num?)?.toDouble() ?? 0.0,
      patientCount: json['patientCount'] as int? ?? 0,
      appointmentCount: json['appointmentCount'] as int? ?? 0,
      inventoryItemsCount: json['inventoryItemsCount'] as int? ?? 0,
      ocrRequestsThisMonth: json['ocrRequestsThisMonth'] as int? ?? 0,
      activeDeviceCount: json['activeDeviceCount'] as int? ?? 0,
      lastLogin: (json['lastLogin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalSessions: json['totalSessions'] as int? ?? 0,
      appVersion: json['appVersion'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      crashCount: json['crashCount'] as int? ?? 0,
      featureUsage: (json['featureUsage'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
    );
  }
}

/// Chart data point for analytics visualizations.
class ChartDataPoint {
  final String label;
  final double value;
  final String? category;

  ChartDataPoint({
    required this.label,
    required this.value,
    this.category,
  });
}