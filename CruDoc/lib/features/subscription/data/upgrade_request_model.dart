import 'package:cloud_firestore/cloud_firestore.dart';

/// Status lifecycle of an upgrade request.
enum UpgradeRequestStatus {
  pending,
  approved,
  rejected;

  String get value => name;

  String get label {
    switch (this) {
      case UpgradeRequestStatus.pending:
        return 'Pending';
      case UpgradeRequestStatus.approved:
        return 'Approved';
      case UpgradeRequestStatus.rejected:
        return 'Rejected';
    }
  }

  static UpgradeRequestStatus fromValue(String? raw) {
    return UpgradeRequestStatus.values.firstWhere(
      (s) => s.value == raw,
      orElse: () => UpgradeRequestStatus.pending,
    );
  }
}

/// Model for a doctor's feature upgrade request.
///
/// Created by the doctor from the mobile app when they want to
/// upgrade/renew their subscription. Stored in Firestore collection
/// `upgrade_requests`. The Super Admin reviews, and upon offline payment
/// confirmation, approves the request — which enables the requested
/// modules and extends `expiresDate` on the doctor's `users` document.
class UpgradeRequest {
  final String id;
  final String doctorId;
  final String doctorName;
  final String doctorEmail;
  final List<String> requestedModules;
  final double totalMonthlyPrice;
  final String currentPlan;
  final UpgradeRequestStatus status;
  final String? adminNotes;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? processedBy;

  const UpgradeRequest({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.doctorEmail,
    required this.requestedModules,
    required this.totalMonthlyPrice,
    required this.currentPlan,
    this.status = UpgradeRequestStatus.pending,
    this.adminNotes,
    this.rejectionReason,
    required this.createdAt,
    this.processedAt,
    this.processedBy,
  });

  factory UpgradeRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return UpgradeRequest.fromMap(data, id: doc.id);
  }

  factory UpgradeRequest.fromMap(Map<String, dynamic> map, {required String id}) {
    return UpgradeRequest(
      id: id,
      doctorId: map['doctorId'] as String? ?? '',
      doctorName: map['doctorName'] as String? ?? '',
      doctorEmail: map['doctorEmail'] as String? ?? '',
      requestedModules: (map['requestedModules'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      totalMonthlyPrice:
          (map['totalMonthlyPrice'] as num?)?.toDouble() ?? 0.0,
      currentPlan: map['currentPlan'] as String? ?? 'starter',
      status: UpgradeRequestStatus.fromValue(map['status'] as String?),
      adminNotes: map['adminNotes'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      createdAt: _timestampToDate(map['createdAt']),
      processedAt: map['processedAt'] != null
          ? _timestampToDate(map['processedAt'])
          : null,
      processedBy: map['processedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'doctorId': doctorId,
      'doctorName': doctorName,
      'doctorEmail': doctorEmail,
      'requestedModules': requestedModules,
      'totalMonthlyPrice': totalMonthlyPrice,
      'currentPlan': currentPlan,
      'status': status.value,
      'adminNotes': adminNotes,
      'rejectionReason': rejectionReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'processedAt':
          processedAt != null ? Timestamp.fromDate(processedAt!) : null,
      'processedBy': processedBy,
    };
  }

  UpgradeRequest copyWith({
    UpgradeRequestStatus? status,
    String? adminNotes,
    String? rejectionReason,
    DateTime? processedAt,
    String? processedBy,
  }) {
    return UpgradeRequest(
      id: id,
      doctorId: doctorId,
      doctorName: doctorName,
      doctorEmail: doctorEmail,
      requestedModules: requestedModules,
      totalMonthlyPrice: totalMonthlyPrice,
      currentPlan: currentPlan,
      status: status ?? this.status,
      adminNotes: adminNotes ?? this.adminNotes,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt,
      processedAt: processedAt ?? this.processedAt,
      processedBy: processedBy ?? this.processedBy,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
