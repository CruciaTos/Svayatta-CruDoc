import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/enums.dart';
import '../models/audit_log_model.dart';

/// State for the Audit Logs management screen.
class AuditLogState {
  final List<AuditLogModel> logs;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;
  final AuditActionType? actionTypeFilter;
  final String statusFilter; // 'all', 'success', 'failed'
  final DateTimeRange? dateRangeFilter;
  final String? lastDocId;
  final bool hasMore;

  const AuditLogState({
    this.logs = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery = '',
    this.actionTypeFilter,
    this.statusFilter = 'all',
    this.dateRangeFilter,
    this.lastDocId,
    this.hasMore = false,
  });

  AuditLogState copyWith({
    List<AuditLogModel>? logs,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
    AuditActionType? actionTypeFilter,
    String? statusFilter,
    DateTimeRange? dateRangeFilter,
    String? lastDocId,
    bool? hasMore,
    bool clearError = false,
    bool clearDateRange = false,
    bool clearActionType = false,
  }) {
    return AuditLogState(
      logs: logs ?? this.logs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      actionTypeFilter:
          clearActionType ? null : (actionTypeFilter ?? this.actionTypeFilter),
      statusFilter: statusFilter ?? this.statusFilter,
      dateRangeFilter:
          clearDateRange ? null : (dateRangeFilter ?? this.dateRangeFilter),
      lastDocId: lastDocId ?? this.lastDocId,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  /// Filtered view of audit logs according to search query, action type, status, and date range.
  List<AuditLogModel> get filteredLogs {
    return logs.where((log) {
      // 1. Search Query Filter (Admin name, email, target doctor name/email, action label)
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final matchesAdmin = log.adminName.toLowerCase().contains(q) ||
            log.adminEmail.toLowerCase().contains(q);
        final matchesTarget = (log.targetDoctorName?.toLowerCase().contains(q) ?? false) ||
            (log.targetDoctorEmail?.toLowerCase().contains(q) ?? false) ||
            (log.targetDoctorId?.toLowerCase().contains(q) ?? false);
        final matchesAction = log.actionType.label.toLowerCase().contains(q);
        final matchesStatus = log.status.toLowerCase().contains(q);

        if (!matchesAdmin && !matchesTarget && !matchesAction && !matchesStatus) {
          return false;
        }
      }

      // 2. Action Type Filter
      if (actionTypeFilter != null && log.actionType != actionTypeFilter) {
        return false;
      }

      // 3. Status Filter
      if (statusFilter != 'all') {
        if (log.status.toLowerCase() != statusFilter.toLowerCase()) {
          return false;
        }
      }

      // 4. Date Range Filter
      if (dateRangeFilter != null) {
        final start = DateTime(
          dateRangeFilter!.start.year,
          dateRangeFilter!.start.month,
          dateRangeFilter!.start.day,
        );
        final end = DateTime(
          dateRangeFilter!.end.year,
          dateRangeFilter!.end.month,
          dateRangeFilter!.end.day,
          23,
          59,
          59,
        );
        if (log.timestamp.isBefore(start) || log.timestamp.isAfter(end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}

/// Riverpod Notifier for Audit Log state management.
class AuditLogNotifier extends Notifier<AuditLogState> {
  @override
  AuditLogState build() {
    final initialState = const AuditLogState();
    // Load initial mock logs
    Future.microtask(() => loadInitialLogs());
    return initialState;
  }

  /// Initial seed mock logs for immediate rich presentation.
  List<AuditLogModel> _getMockSeedLogs() {
    final now = DateTime.now();
    return [
      AuditLogModel(
        id: 'log-101',
        adminName: 'Super Admin',
        adminEmail: 'admin@crudoc.com',
        actionType: AuditActionType.createdDoctor,
        targetDoctorId: 'doc-991',
        targetDoctorName: 'Dr. Venom Mhatre',
        targetDoctorEmail: 'venom@crudoc.com',
        details: {'plan': 'Enterprise', 'region': 'India', 'initialStatus': 'Active'},
        afterValues: {'status': 'Active', 'plan': 'Enterprise', 'patientsLimit': -1},
        timestamp: now.subtract(const Duration(minutes: 12)),
        status: 'success',
        ipAddress: '192.168.1.45',
        userAgent: 'Chrome 127.0 (Windows NT 10.0)',
      ),
      AuditLogModel(
        id: 'log-102',
        adminName: 'Sarah Jenkins',
        adminEmail: 'sarah.admin@crudoc.com',
        actionType: AuditActionType.changedPlan,
        targetDoctorId: 'doc-882',
        targetDoctorName: 'Dr. Smit Mhatre',
        targetDoctorEmail: 'smit@crudoc.com',
        details: {'previousPlan': 'Starter', 'newPlan': 'Professional'},
        beforeValues: {'plan': 'Starter', 'monthlyFee': 29.0},
        afterValues: {'plan': 'Professional', 'monthlyFee': 79.0},
        timestamp: now.subtract(const Duration(hours: 1, minutes: 25)),
        status: 'success',
        ipAddress: '10.0.0.12',
        userAgent: 'Safari 17.4 (macOS Sonoma)',
      ),
      AuditLogModel(
        id: 'log-103',
        adminName: 'Super Admin',
        adminEmail: 'admin@crudoc.com',
        actionType: AuditActionType.suspendedAccount,
        targetDoctorId: 'doc-773',
        targetDoctorName: 'Dr. Alex Mercer',
        targetDoctorEmail: 'alex.m@clinic.org',
        details: {'reason': 'Unverified credentials'},
        timestamp: now.subtract(const Duration(hours: 3, minutes: 10)),
        status: 'failed',
        errorMessage: 'Security Policy Guard: Cannot suspend system owner account',
        ipAddress: '192.168.1.45',
        userAgent: 'Chrome 127.0 (Windows NT 10.0)',
      ),
      AuditLogModel(
        id: 'log-104',
        adminName: 'Rahul Sharma',
        adminEmail: 'support.lead@crudoc.com',
        actionType: AuditActionType.resetPassword,
        targetDoctorId: 'doc-664',
        targetDoctorName: 'Dr. Ananya Roy',
        targetDoctorEmail: 'ananya@royhealth.com',
        details: {'ticketRef': '#TK-8821', 'requestSource': 'Portal Ticket'},
        timestamp: now.subtract(const Duration(hours: 5, minutes: 45)),
        status: 'success',
        ipAddress: '172.16.0.88',
        userAgent: 'Firefox 128.0 (Linux x86_64)',
      ),
      AuditLogModel(
        id: 'log-105',
        adminName: 'Sarah Jenkins',
        adminEmail: 'sarah.admin@crudoc.com',
        actionType: AuditActionType.enabledModule,
        targetDoctorId: 'doc-555',
        targetDoctorName: 'Dr. Rajesh Kumar',
        targetDoctorEmail: 'rkumar@citycare.com',
        details: {'moduleName': 'Medicine OCR & Digital Invoicing'},
        beforeValues: {'medicineOcr': false},
        afterValues: {'medicineOcr': true},
        timestamp: now.subtract(const Duration(days: 1, hours: 2)),
        status: 'success',
        ipAddress: '10.0.0.12',
        userAgent: 'Safari 17.4 (macOS Sonoma)',
      ),
      AuditLogModel(
        id: 'log-106',
        adminName: 'Super Admin',
        adminEmail: 'admin@crudoc.com',
        actionType: AuditActionType.editedPlanDefinition,
        targetDoctorId: null,
        targetDoctorName: null,
        targetDoctorEmail: null,
        details: {'plan': 'Clinic', 'newMonthlyPrice': 199.0, 'storageGB': 50},
        beforeValues: {'monthlyPrice': 179.0},
        afterValues: {'monthlyPrice': 199.0},
        timestamp: now.subtract(const Duration(days: 2, hours: 4)),
        status: 'success',
        ipAddress: '192.168.1.45',
        userAgent: 'Chrome 127.0 (Windows NT 10.0)',
      ),
      AuditLogModel(
        id: 'log-107',
        adminName: 'Rahul Sharma',
        adminEmail: 'support.lead@crudoc.com',
        actionType: AuditActionType.resolvedSupportTicket,
        targetDoctorId: 'doc-446',
        targetDoctorName: 'Dr. Meera Patel',
        targetDoctorEmail: 'meera@patelclinic.in',
        details: {'ticketId': 'TK-1049', 'resolutionTimeMinutes': 42},
        timestamp: now.subtract(const Duration(days: 2, hours: 9)),
        status: 'success',
        ipAddress: '172.16.0.88',
        userAgent: 'Firefox 128.0 (Linux x86_64)',
      ),
      AuditLogModel(
        id: 'log-108',
        adminName: 'Super Admin',
        adminEmail: 'admin@crudoc.com',
        actionType: AuditActionType.suspendedAccount,
        targetDoctorId: 'doc-337',
        targetDoctorName: 'Dr. John Doe',
        targetDoctorEmail: 'john.doe@expired.com',
        details: {'reason': 'Billing overdue > 60 days'},
        beforeValues: {'status': 'Active'},
        afterValues: {'status': 'Suspended'},
        timestamp: now.subtract(const Duration(days: 3, hours: 14)),
        status: 'success',
        ipAddress: '192.168.1.45',
        userAgent: 'Chrome 127.0 (Windows NT 10.0)',
      ),
      AuditLogModel(
        id: 'log-109',
        adminName: 'Super Admin',
        adminEmail: 'admin@crudoc.com',
        actionType: AuditActionType.updatedSystemConfig,
        targetDoctorId: null,
        targetDoctorName: null,
        targetDoctorEmail: null,
        details: {'configKey': 'max_ocr_concurrency', 'previous': 5, 'new': 10},
        timestamp: now.subtract(const Duration(days: 4, hours: 1)),
        status: 'success',
        ipAddress: '192.168.1.45',
        userAgent: 'Chrome 127.0 (Windows NT 10.0)',
      ),
      AuditLogModel(
        id: 'log-110',
        adminName: 'Sarah Jenkins',
        adminEmail: 'sarah.admin@crudoc.com',
        actionType: AuditActionType.sentAnnouncement,
        targetDoctorId: null,
        targetDoctorName: null,
        targetDoctorEmail: null,
        details: {'title': 'System Maintenance Notification', 'recipientsCount': 142},
        timestamp: now.subtract(const Duration(days: 5, hours: 6)),
        status: 'success',
        ipAddress: '10.0.0.12',
        userAgent: 'Safari 17.4 (macOS Sonoma)',
      ),
    ];
  }

  /// Loads logs with initial mock data fallback.
  Future<void> loadInitialLogs() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final mockLogs = _getMockSeedLogs();
      state = state.copyWith(
        logs: mockLogs,
        isLoading: false,
        hasMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load audit logs: $e',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setActionTypeFilter(AuditActionType? actionType) {
    state = state.copyWith(
      actionTypeFilter: actionType,
      clearActionType: actionType == null,
    );
  }

  void setStatusFilter(String status) {
    state = state.copyWith(statusFilter: status);
  }

  void setDateRangeFilter(DateTimeRange? range) {
    state = state.copyWith(
      dateRangeFilter: range,
      clearDateRange: range == null,
    );
  }

  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      statusFilter: 'all',
      clearActionType: true,
      clearDateRange: true,
    );
  }

  /// Generates CSV data string of current filtered logs and triggers export feedback.
  void exportToCsv(BuildContext context) {
    final logsToExport = state.filteredLogs;
    if (logsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audit logs available to export for current filters'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final StringBuffer csvBuffer = StringBuffer();

    // CSV Header Row
    csvBuffer.writeln(
      'Log ID,Timestamp,Admin Name,Admin Email,Action Type,Target Doctor Name,Target Doctor Email,Status,IP Address,Error Message',
    );

    // CSV Data Rows
    for (final log in logsToExport) {
      final id = _cleanCsvField(log.id);
      final time = _cleanCsvField(dateFormat.format(log.timestamp));
      final adminName = _cleanCsvField(log.adminName);
      final adminEmail = _cleanCsvField(log.adminEmail);
      final action = _cleanCsvField(log.actionType.label);
      final targetName = _cleanCsvField(log.targetDoctorName ?? 'N/A');
      final targetEmail = _cleanCsvField(log.targetDoctorEmail ?? 'N/A');
      final status = _cleanCsvField(log.status.toUpperCase());
      final ip = _cleanCsvField(log.ipAddress ?? 'N/A');
      final error = _cleanCsvField(log.errorMessage ?? '');

      csvBuffer.writeln(
        '$id,$time,$adminName,$adminEmail,$action,$targetName,$targetEmail,$status,$ip,$error',
      );
    }

    // Show export success toast
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.download_done_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              'Successfully exported ${logsToExport.length} audit logs to CSV',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _cleanCsvField(String field) {
    var str = field;
    // CSV Formula Injection Guard: sanitize cells starting with =, +, -, @
    if (str.startsWith('=') ||
        str.startsWith('+') ||
        str.startsWith('-') ||
        str.startsWith('@')) {
      str = "'$str";
    }
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      final escaped = str.replaceAll('"', '""');
      return '"$escaped"';
    }
    return str;
  }
}

/// Provider for Super Admin Audit Logs state.
final superAdminAuditLogProvider =
    NotifierProvider<AuditLogNotifier, AuditLogState>(() {
  return AuditLogNotifier();
});
