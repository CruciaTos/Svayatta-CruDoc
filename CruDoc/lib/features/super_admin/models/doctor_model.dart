import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/enums.dart';

/// Model for doctor accounts visible in Super Admin panel.
/// Contains ONLY metadata accessible to Super Admin — no patient data.
class DoctorModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String specialization;
  final String clinicName;
  final String country;
  final String timeZone;
  final SubscriptionPlan subscriptionPlan;
  final DoctorStatus status;
  final DateTime accountCreated;
  final DateTime? lastLogin;
  final double storageUsedGB;
  final double storageLimitGB;
  final int patientCount;
  final int appointmentCount;
  final int activeDeviceCount;
  final int ocrRequestsThisMonth;
  final List<String> enabledModules;
  final int totalSessions;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? notes;
  final bool allowMultiDevice;

  DoctorModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.specialization,
    required this.clinicName,
    required this.country,
    required this.timeZone,
    required this.subscriptionPlan,
    this.status = DoctorStatus.pending,
    DateTime? accountCreated,
    this.lastLogin,
    this.storageUsedGB = 0.0,
    double? storageLimitGB,
    this.patientCount = 0,
    this.appointmentCount = 0,
    this.activeDeviceCount = 0,
    this.ocrRequestsThisMonth = 0,
    List<String>? enabledModules,
    this.totalSessions = 0,
    this.isDeleted = false,
    this.deletedAt,
    this.notes,
    this.allowMultiDevice = false,
  })  : accountCreated = accountCreated ?? DateTime.now(),
        storageLimitGB = storageLimitGB ?? subscriptionPlan.storageLimitGB,
        enabledModules = enabledModules ?? subscriptionPlan.includedModules;

  factory DoctorModel.fromJson(Map<String, dynamic> json, String id) {
    final planStr = json['subscriptionPlan'] as String? ?? 'starter';
    return DoctorModel(
      id: id,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      specialization: json['specialization'] as String? ?? '',
      clinicName: json['clinicName'] as String? ?? '',
      country: json['country'] as String? ?? '',
      timeZone: json['timeZone'] as String? ?? '',
      subscriptionPlan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == planStr,
        orElse: () => SubscriptionPlan.starter,
      ),
      status: DoctorStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DoctorStatus.pending,
      ),
      accountCreated: (json['accountCreated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (json['lastLogin'] as Timestamp?)?.toDate(),
      storageUsedGB: (json['storageUsedGB'] as num?)?.toDouble() ?? 0.0,
      storageLimitGB: (json['storageLimitGB'] as num?)?.toDouble(),
      patientCount: json['patientCount'] as int? ?? 0,
      appointmentCount: json['appointmentCount'] as int? ?? 0,
      activeDeviceCount: json['activeDeviceCount'] as int? ?? 0,
      ocrRequestsThisMonth: json['ocrRequestsThisMonth'] as int? ?? 0,
      enabledModules: (json['enabledModules'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      totalSessions: json['totalSessions'] as int? ?? 0,
      isDeleted: json['isDeleted'] as bool? ?? false,
      deletedAt: (json['deletedAt'] as Timestamp?)?.toDate(),
      notes: json['notes'] as String?,
      allowMultiDevice: json['allowMultiDevice'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'specialization': specialization,
      'clinicName': clinicName,
      'country': country,
      'timeZone': timeZone,
      'subscriptionPlan': subscriptionPlan.name,
      'status': status.name,
      'accountCreated': Timestamp.fromDate(accountCreated),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'storageUsedGB': storageUsedGB,
      'storageLimitGB': storageLimitGB,
      'patientCount': patientCount,
      'appointmentCount': appointmentCount,
      'activeDeviceCount': activeDeviceCount,
      'ocrRequestsThisMonth': ocrRequestsThisMonth,
      'enabledModules': enabledModules,
      'totalSessions': totalSessions,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'notes': notes,
      'allowMultiDevice': allowMultiDevice,
    };
  }

  DoctorModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? specialization,
    String? clinicName,
    String? country,
    String? timeZone,
    SubscriptionPlan? subscriptionPlan,
    DoctorStatus? status,
    DateTime? accountCreated,
    DateTime? lastLogin,
    double? storageUsedGB,
    double? storageLimitGB,
    int? patientCount,
    int? appointmentCount,
    int? activeDeviceCount,
    int? ocrRequestsThisMonth,
    List<String>? enabledModules,
    int? totalSessions,
    bool? isDeleted,
    DateTime? deletedAt,
    String? notes,
    bool? allowMultiDevice,
  }) {
    return DoctorModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      specialization: specialization ?? this.specialization,
      clinicName: clinicName ?? this.clinicName,
      country: country ?? this.country,
      timeZone: timeZone ?? this.timeZone,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      status: status ?? this.status,
      accountCreated: accountCreated ?? this.accountCreated,
      lastLogin: lastLogin ?? this.lastLogin,
      storageUsedGB: storageUsedGB ?? this.storageUsedGB,
      storageLimitGB: storageLimitGB ?? this.storageLimitGB,
      patientCount: patientCount ?? this.patientCount,
      appointmentCount: appointmentCount ?? this.appointmentCount,
      activeDeviceCount: activeDeviceCount ?? this.activeDeviceCount,
      ocrRequestsThisMonth: ocrRequestsThisMonth ?? this.ocrRequestsThisMonth,
      enabledModules: enabledModules ?? this.enabledModules,
      totalSessions: totalSessions ?? this.totalSessions,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      notes: notes ?? this.notes,
      allowMultiDevice: allowMultiDevice ?? this.allowMultiDevice,
    );
  }

  double get storageUsagePercent =>
      storageLimitGB > 0 ? (storageUsedGB / storageLimitGB) * 100 : 0;

  @override
  String toString() {
    return 'DoctorModel(id: $id, name: $name, email: $email, plan: $subscriptionPlan, status: $status)';
  }
}