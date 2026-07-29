import '../config/enums.dart';

/// Lightweight model for dashboard statistics display cards.
class DashboardStatsModel {
  final int totalDoctors;
  final int activeDoctors;
  final int trialAccounts;
  final int expiredAccounts;
  final double monthlyRevenue;
  final double storageUsedGB;
  final int activeDevices;
  final int ocrRequestsThisMonth;
  final int appointmentsCreatedToday;
  final int totalPatients; // count only, no patient data
  final int activeClinics;
  final PlatformHealth platformHealth;
  final double totalDoctorsChange;
  final double activeDoctorsChange;
  final double monthlyRevenueChange;
  final double storageUsedChange;

  DashboardStatsModel({
    this.totalDoctors = 0,
    this.activeDoctors = 0,
    this.trialAccounts = 0,
    this.expiredAccounts = 0,
    this.monthlyRevenue = 0.0,
    this.storageUsedGB = 0.0,
    this.activeDevices = 0,
    this.ocrRequestsThisMonth = 0,
    this.appointmentsCreatedToday = 0,
    this.totalPatients = 0,
    this.activeClinics = 0,
    this.platformHealth = PlatformHealth.healthy,
    this.totalDoctorsChange = 0.0,
    this.activeDoctorsChange = 0.0,
    this.monthlyRevenueChange = 0.0,
    this.storageUsedChange = 0.0,
  });

  factory DashboardStatsModel.fromJson(Map<String, dynamic> json) {
    return DashboardStatsModel(
      totalDoctors: json['totalDoctors'] as int? ?? 0,
      activeDoctors: json['activeDoctors'] as int? ?? 0,
      trialAccounts: json['trialAccounts'] as int? ?? 0,
      expiredAccounts: json['expiredAccounts'] as int? ?? 0,
      monthlyRevenue: (json['monthlyRevenue'] as num?)?.toDouble() ?? 0.0,
      storageUsedGB: (json['storageUsedGB'] as num?)?.toDouble() ?? 0.0,
      activeDevices: json['activeDevices'] as int? ?? 0,
      ocrRequestsThisMonth: json['ocrRequestsThisMonth'] as int? ?? 0,
      appointmentsCreatedToday: json['appointmentsCreatedToday'] as int? ?? 0,
      totalPatients: json['totalPatients'] as int? ?? 0,
      activeClinics: json['activeClinics'] as int? ?? 0,
      platformHealth: PlatformHealth.values.firstWhere(
        (e) => e.name == json['platformHealth'],
        orElse: () => PlatformHealth.healthy,
      ),
      totalDoctorsChange: (json['totalDoctorsChange'] as num?)?.toDouble() ?? 0.0,
      activeDoctorsChange: (json['activeDoctorsChange'] as num?)?.toDouble() ?? 0.0,
      monthlyRevenueChange: (json['monthlyRevenueChange'] as num?)?.toDouble() ?? 0.0,
      storageUsedChange: (json['storageUsedChange'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalDoctors': totalDoctors,
      'activeDoctors': activeDoctors,
      'trialAccounts': trialAccounts,
      'expiredAccounts': expiredAccounts,
      'monthlyRevenue': monthlyRevenue,
      'storageUsedGB': storageUsedGB,
      'activeDevices': activeDevices,
      'ocrRequestsThisMonth': ocrRequestsThisMonth,
      'appointmentsCreatedToday': appointmentsCreatedToday,
      'totalPatients': totalPatients,
      'activeClinics': activeClinics,
      'platformHealth': platformHealth.name,
      'totalDoctorsChange': totalDoctorsChange,
      'activeDoctorsChange': activeDoctorsChange,
      'monthlyRevenueChange': monthlyRevenueChange,
      'storageUsedChange': storageUsedChange,
    };
  }
}

/// Model for the system configuration document.
class SystemConfigModel {
  final String platformName;
  final String supportEmail;
  final String helpCenterUrl;
  final String privacyPolicyUrl;
  final String termsOfServiceUrl;
  final String contactPhone;
  final bool allowNewDoctorRegistrations;
  final String maintenanceMessage;
  final bool isUnderMaintenance;
  final int apiRateLimitPerMinute;
  final int sessionTimeoutMinutes;
  final int maxLoginAttempts;

  SystemConfigModel({
    this.platformName = 'CruDoc',
    this.supportEmail = 'support@crudoc.com',
    this.helpCenterUrl = '',
    this.privacyPolicyUrl = '',
    this.termsOfServiceUrl = '',
    this.contactPhone = '',
    this.allowNewDoctorRegistrations = true,
    this.maintenanceMessage = '',
    this.isUnderMaintenance = false,
    this.apiRateLimitPerMinute = 60,
    this.sessionTimeoutMinutes = 15,
    this.maxLoginAttempts = 5,
  });

  factory SystemConfigModel.fromJson(Map<String, dynamic> json) {
    return SystemConfigModel(
      platformName: json['platformName'] as String? ?? 'CruDoc',
      supportEmail: json['supportEmail'] as String? ?? 'support@crudoc.com',
      helpCenterUrl: json['helpCenterUrl'] as String? ?? '',
      privacyPolicyUrl: json['privacyPolicyUrl'] as String? ?? '',
      termsOfServiceUrl: json['termsOfServiceUrl'] as String? ?? '',
      contactPhone: json['contactPhone'] as String? ?? '',
      allowNewDoctorRegistrations: json['allowNewDoctorRegistrations'] as bool? ?? true,
      maintenanceMessage: json['maintenanceMessage'] as String? ?? '',
      isUnderMaintenance: json['isUnderMaintenance'] as bool? ?? false,
      apiRateLimitPerMinute: json['apiRateLimitPerMinute'] as int? ?? 60,
      sessionTimeoutMinutes: json['sessionTimeoutMinutes'] as int? ?? 15,
      maxLoginAttempts: json['maxLoginAttempts'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'platformName': platformName,
      'supportEmail': supportEmail,
      'helpCenterUrl': helpCenterUrl,
      'privacyPolicyUrl': privacyPolicyUrl,
      'termsOfServiceUrl': termsOfServiceUrl,
      'contactPhone': contactPhone,
      'allowNewDoctorRegistrations': allowNewDoctorRegistrations,
      'maintenanceMessage': maintenanceMessage,
      'isUnderMaintenance': isUnderMaintenance,
      'apiRateLimitPerMinute': apiRateLimitPerMinute,
      'sessionTimeoutMinutes': sessionTimeoutMinutes,
      'maxLoginAttempts': maxLoginAttempts,
    };
  }
}