import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/audit_log_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for recording and querying audit logs.
class SuperAdminAuditLogService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Log an admin action.
  Future<void> logAction({
    required AuditActionType actionType,
    String? targetDoctorId,
    String? targetDoctorName,
    String? targetDoctorEmail,
    Map<String, dynamic>? details,
    Map<String, dynamic>? beforeValues,
    Map<String, dynamic>? afterValues,
    String? errorMessage,
    String status = 'success',
  }) async {
    try {
      final logEntry = <String, dynamic>{
        'adminEmail': _fb.currentUserEmail ?? 'unknown',
        'adminName': _fb.currentUser?.displayName ?? 'Unknown Admin',
        'actionType': actionType.name,
        'targetDoctorId': targetDoctorId,
        'targetDoctorName': targetDoctorName,
        'targetDoctorEmail': targetDoctorEmail,
        'details': details,
        'beforeValues': beforeValues,
        'afterValues': afterValues,
        'timestamp': FieldValue.serverTimestamp(),
        'status': status,
        'errorMessage': errorMessage,
      };

      await _fb.auditLogsCollection.add(logEntry);
    } catch (_) {
      // Audit logging should never throw - fail silently
    }
  }

  /// Query audit logs with filters and pagination.
  Future<List<AuditLogModel>> getAuditLogs({
    int limit = 50,
    String? lastDocId,
    AuditActionType? actionTypeFilter,
    String? adminEmailFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) async {
    try {
      Query query = _fb.auditLogsCollection
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (actionTypeFilter != null) {
        query = query.where('actionType', isEqualTo: actionTypeFilter.name);
      }
      if (adminEmailFilter != null && adminEmailFilter.isNotEmpty) {
        query = query.where('adminEmail', isEqualTo: adminEmailFilter);
      }
      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }
      if (lastDocId != null) {
        final lastDoc = await _fb.auditLogsCollection.doc(lastDocId).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      final snapshot = await query.get();
      var logs = snapshot.docs.map((doc) {
        return AuditLogModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      // Client-side search
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final queryLower = searchQuery.toLowerCase();
        logs = logs.where((log) {
          return log.adminEmail.toLowerCase().contains(queryLower) ||
              log.actionDescription.toLowerCase().contains(queryLower) ||
              (log.targetDoctorName?.toLowerCase().contains(queryLower) ?? false) ||
              (log.targetDoctorEmail?.toLowerCase().contains(queryLower) ?? false);
        }).toList();
      }

      return logs;
    } catch (e) {
      throw Exception('Failed to fetch audit logs: ${e.toString()}');
    }
  }

  /// Get audit log by ID.
  Future<AuditLogModel?> getAuditLogById(String logId) async {
    try {
      final doc = await _fb.auditLogsCollection.doc(logId).get();
      if (!doc.exists) return null;
      return AuditLogModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      return null;
    }
  }

  /// Export audit logs as CSV data.
  Future<String> exportAuditLogsCSV({
    DateTime? startDate,
    DateTime? endDate,
    AuditActionType? actionTypeFilter,
  }) async {
    try {
      Query query = _fb.auditLogsCollection.orderBy('timestamp', descending: false);

      if (actionTypeFilter != null) {
        query = query.where('actionType', isEqualTo: actionTypeFilter.name);
      }
      if (startDate != null) {
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.get();
      final buffer = StringBuffer();

      // Header
      buffer.writeln('Timestamp,Admin Email,Action Type,Target,Status');

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate().toIso8601String() ?? '';
        final admin = data['adminEmail'] ?? '';
        final action = data['actionType'] ?? '';
        final target = data['targetDoctorName'] ?? data['targetDoctorEmail'] ?? '';
        final status = data['status'] ?? '';
        buffer.writeln('"$timestamp","$admin","$action","$target","$status"');
      }

      return buffer.toString();
    } catch (e) {
      throw Exception('Failed to export audit logs: ${e.toString()}');
    }
  }
}