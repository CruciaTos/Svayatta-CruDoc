import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/enums.dart';

/// Model for audit log entries recording admin actions.
class AuditLogModel {
  final String id;
  final String adminEmail;
  final String adminName;
  final AuditActionType actionType;
  final String? targetDoctorId;
  final String? targetDoctorName;
  final String? targetDoctorEmail;
  final Map<String, dynamic>? details;
  final Map<String, dynamic>? beforeValues;
  final Map<String, dynamic>? afterValues;
  final DateTime timestamp;
  final String status; // 'success' or 'failed'
  final String? errorMessage;
  final String? ipAddress;
  final String? userAgent;

  AuditLogModel({
    required this.id,
    required this.adminEmail,
    required this.adminName,
    required this.actionType,
    this.targetDoctorId,
    this.targetDoctorName,
    this.targetDoctorEmail,
    this.details,
    this.beforeValues,
    this.afterValues,
    DateTime? timestamp,
    this.status = 'success',
    this.errorMessage,
    this.ipAddress,
    this.userAgent,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AuditLogModel.fromJson(Map<String, dynamic> json, String id) {
    return AuditLogModel(
      id: id,
      adminEmail: json['adminEmail'] as String? ?? '',
      adminName: json['adminName'] as String? ?? '',
      actionType: AuditActionType.values.firstWhere(
        (e) => e.name == json['actionType'],
        orElse: () => AuditActionType.updatedSystemConfig,
      ),
      targetDoctorId: json['targetDoctorId'] as String?,
      targetDoctorName: json['targetDoctorName'] as String?,
      targetDoctorEmail: json['targetDoctorEmail'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      beforeValues: json['beforeValues'] as Map<String, dynamic>?,
      afterValues: json['afterValues'] as Map<String, dynamic>?,
      timestamp: (json['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: json['status'] as String? ?? 'success',
      errorMessage: json['errorMessage'] as String?,
      ipAddress: json['ipAddress'] as String?,
      userAgent: json['userAgent'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'adminEmail': adminEmail,
      'adminName': adminName,
      'actionType': actionType.name,
      'targetDoctorId': targetDoctorId,
      'targetDoctorName': targetDoctorName,
      'targetDoctorEmail': targetDoctorEmail,
      'details': details,
      'beforeValues': beforeValues,
      'afterValues': afterValues,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      'errorMessage': errorMessage,
      'ipAddress': ipAddress,
      'userAgent': userAgent,
    };
  }

  String get actionDescription {
    final target = targetDoctorName ?? targetDoctorEmail ?? 'N/A';
    return '${actionType.label} - $target';
  }

  @override
  String toString() {
    return 'AuditLogModel(id: $id, admin: $adminEmail, action: ${actionType.label}, status: $status)';
  }
}