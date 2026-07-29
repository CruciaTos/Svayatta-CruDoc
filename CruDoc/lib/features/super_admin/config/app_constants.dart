/// Super Admin Panel constants
class SuperAdminConstants {
  SuperAdminConstants._();

  // App Info
  static const String appName = 'CruDoc Super Admin';
  static const String version = '1.0.0';

  // Pagination
  static const int defaultPageSize = 50;
  static const int maxPageSize = 100;

  // Session
  static const int sessionTimeoutMinutes = 15;
  static const int maxLoginAttempts = 5;
  static const int accountLockoutMinutes = 30;

  // 2FA
  static const int otpLength = 6;
  static const int otpResendCooldownSeconds = 30;
  static const int otpExpirySeconds = 300;

  // Analytics
  static const int dashboardRefreshIntervalSeconds = 60;
  static const int cacheTTLMinutes = 5;

  // Storage
  static const double defaultStorageLimitGB = 5.0;
  static const double maxStorageLimitGB = 100.0;

  // Audit
  static const int auditLogRetentionYears = 7;

  // API
  static const int requestTimeoutSeconds = 10;
  static const int maxRetryAttempts = 3;

  // Collections
  static const String collectionUsers = 'users';
  static const String collectionSubscriptions = 'subscriptions';
  static const String collectionFeatureFlags = 'feature_flags';
  static const String collectionPlans = 'plans';
  static const String collectionAuditLogs = 'audit_logs';
  static const String collectionDoctorSettings = 'doctor_settings';
  static const String collectionAnalytics = 'analytics';
  static const String collectionNotifications = 'notifications';
  static const String collectionSupportTickets = 'support_tickets';
  static const String collectionSystemConfig = 'system_config';
}