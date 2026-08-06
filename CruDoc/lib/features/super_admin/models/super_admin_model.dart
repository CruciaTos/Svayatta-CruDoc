import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/enums.dart';

/// Model for the Super Admin user account.
class SuperAdminModel {
  final String id;
  final String email;
  final String name;
  final String? profilePictureUrl;
  final UserRole role;
  final bool isTwoFAEnabled;
  final bool isTwoFAVerified;
  final String? twoFASecret;
  final DateTime accountCreated;
  final DateTime lastLogin;
  final bool isActive;
  final int failedLoginAttempts;
  final DateTime? lockedUntil;

  SuperAdminModel({
    required this.id,
    required this.email,
    required this.name,
    this.profilePictureUrl,
    this.role = UserRole.superAdmin,
    this.isTwoFAEnabled = false,
    this.isTwoFAVerified = false,
    this.twoFASecret,
    DateTime? accountCreated,
    DateTime? lastLogin,
    this.isActive = true,
    this.failedLoginAttempts = 0,
    this.lockedUntil,
  })  : accountCreated = accountCreated ?? DateTime.now(),
        lastLogin = lastLogin ?? DateTime.now();

  factory SuperAdminModel.fromJson(Map<String, dynamic> json, String id) {
    return SuperAdminModel(
      id: id,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      profilePictureUrl: json['profilePictureUrl'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.doctor, // Default to least privilege
      ),
      isTwoFAEnabled: json['isTwoFAEnabled'] as bool? ?? false,
      isTwoFAVerified: json['isTwoFAVerified'] as bool? ?? false,
      twoFASecret: json['twoFASecret'] as String?,
      accountCreated: (json['accountCreated'] as Timestamp?)?.toDate(),
      lastLogin: (json['lastLogin'] as Timestamp?)?.toDate(),
      isActive: json['isActive'] as bool? ?? true,
      failedLoginAttempts: json['failedLoginAttempts'] as int? ?? 0,
      lockedUntil: (json['lockedUntil'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'name': name,
      'profilePictureUrl': profilePictureUrl,
      'role': role.name,
      'isTwoFAEnabled': isTwoFAEnabled,
      'isTwoFAVerified': isTwoFAVerified,
      'twoFASecret': twoFASecret,
      'accountCreated': Timestamp.fromDate(accountCreated),
      'lastLogin': Timestamp.fromDate(lastLogin),
      'isActive': isActive,
      'failedLoginAttempts': failedLoginAttempts,
      'lockedUntil': lockedUntil != null ? Timestamp.fromDate(lockedUntil!) : null,
    };
  }

  SuperAdminModel copyWith({
    String? id,
    String? email,
    String? name,
    String? profilePictureUrl,
    UserRole? role,
    bool? isTwoFAEnabled,
    bool? isTwoFAVerified,
    String? twoFASecret,
    DateTime? accountCreated,
    DateTime? lastLogin,
    bool? isActive,
    int? failedLoginAttempts,
    DateTime? lockedUntil,
  }) {
    return SuperAdminModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      role: role ?? this.role,
      isTwoFAEnabled: isTwoFAEnabled ?? this.isTwoFAEnabled,
      isTwoFAVerified: isTwoFAVerified ?? this.isTwoFAVerified,
      twoFASecret: twoFASecret ?? this.twoFASecret,
      accountCreated: accountCreated ?? this.accountCreated,
      lastLogin: lastLogin ?? this.lastLogin,
      isActive: isActive ?? this.isActive,
      failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
    );
  }

  @override
  String toString() {
    return 'SuperAdminModel(id: $id, email: $email, name: $name, role: $role)';
  }
}