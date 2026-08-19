import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/enums.dart';
import '../../models/audit_log_model.dart';
import '../../providers/audit_log_provider.dart';

/// Super Admin Audit Logs Management Screen.
class SuperAdminAuditLogsScreen extends ConsumerStatefulWidget {
  const SuperAdminAuditLogsScreen({super.key});

  @override
  ConsumerState<SuperAdminAuditLogsScreen> createState() =>
      _SuperAdminAuditLogsScreenState();
}

class _SuperAdminAuditLogsScreenState
    extends ConsumerState<SuperAdminAuditLogsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditState = ref.watch(superAdminAuditLogProvider);
    final notifier = ref.read(superAdminAuditLogProvider.notifier);
    final isMobile = MediaQuery.of(context).size.width < 768;
    final filteredLogs = auditState.filteredLogs;

    // Metrics Calculation
    final totalLogs = auditState.logs.length;
    final now = DateTime.now();
    final todayLogs = auditState.logs.where((l) {
      return l.timestamp.year == now.year &&
          l.timestamp.month == now.month &&
          l.timestamp.day == now.day;
    }).length;
    final failedLogs =
        auditState.logs.where((l) => l.status.toLowerCase() == 'failed').length;
    final activeAdminsCount =
        auditState.logs.map((l) => l.adminEmail).toSet().length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          _buildHeaderBar(context, notifier, filteredLogs.length, auditState.isLoading),

          const SizedBox(height: 20),

          // 2. Metrics Summary Row
          _buildMetricsRow(
            context,
            isMobile: isMobile,
            totalLogs: totalLogs,
            todayLogs: todayLogs,
            failedLogs: failedLogs,
            activeAdmins: activeAdminsCount,
          ),

          const SizedBox(height: 24),

          // 3. Search & Filter Bar
          _buildSearchAndFilters(context, auditState, notifier, isMobile),

          const SizedBox(height: 20),

          // 4. Audit Logs List / Data Table Card
          _buildLogsTableCard(context, auditState, filteredLogs, isMobile),
        ],
      ),
    );
  }

  // ==================== 1. HEADER BAR ====================
  Widget _buildHeaderBar(
    BuildContext context,
    AuditLogNotifier notifier,
    int filteredCount,
    bool isLoading,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Audit Logs',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$filteredCount Records',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Track all administrative actions, system events, and security logs',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: isLoading ? null : () => notifier.loadInitialLogs(),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh Logs',
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => notifier.exportToCsv(context),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Export CSV'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 2. METRICS ROW ====================
  Widget _buildMetricsRow(
    BuildContext context, {
    required bool isMobile,
    required int totalLogs,
    required int todayLogs,
    required int failedLogs,
    required int activeAdmins,
  }) {
    final cards = [
      _buildMetricCard(
        context,
        title: 'Total Logged Actions',
        value: totalLogs.toString(),
        icon: Icons.history_rounded,
        color: const Color(0xFF2563EB),
        bg: const Color(0xFFEFF6FF),
      ),
      _buildMetricCard(
        context,
        title: 'Actions Today',
        value: todayLogs.toString(),
        icon: Icons.today_rounded,
        color: const Color(0xFF10B981),
        bg: const Color(0xFFECFDF5),
      ),
      _buildMetricCard(
        context,
        title: 'Failed Actions',
        value: failedLogs.toString(),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
        bg: const Color(0xFFFEF2F2),
      ),
      _buildMetricCard(
        context,
        title: 'Active Admins',
        value: activeAdmins.toString(),
        icon: Icons.admin_panel_settings_outlined,
        color: const Color(0xFF8B5CF6),
        bg: const Color(0xFFF5F3FF),
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: c,
                ))
            .toList(),
      );
    }

    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: c,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. SEARCH & FILTERS ====================
  Widget _buildSearchAndFilters(
    BuildContext context,
    AuditLogState state,
    AuditLogNotifier notifier,
    bool isMobile,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => notifier.setSearchQuery(val),
                  decoration: InputDecoration(
                    hintText: 'Search by admin, doctor, or action...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              notifier.setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Date Range Picker Trigger
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: state.dateRangeFilter,
                  );
                  if (picked != null) {
                    notifier.setDateRangeFilter(picked);
                  }
                },
                icon: Icon(
                  Icons.calendar_month_outlined,
                  size: 18,
                  color: state.dateRangeFilter != null
                      ? Theme.of(context).primaryColor
                      : Colors.grey[700],
                ),
                label: Text(
                  state.dateRangeFilter == null
                      ? 'Date Range'
                      : '${DateFormat('MMM d').format(state.dateRangeFilter!.start)} - ${DateFormat('MMM d').format(state.dateRangeFilter!.end)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: state.dateRangeFilter != null
                        ? Theme.of(context).primaryColor
                        : Colors.grey[800],
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filters Row: Action Type + Status Selector + Reset Button
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Action Type Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AuditActionType?>(
                    value: state.actionTypeFilter,
                    hint: const Text('All Action Types',
                        style: TextStyle(fontSize: 13)),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<AuditActionType?>(
                        value: null,
                        child: Text('All Action Types',
                            style: TextStyle(fontSize: 13)),
                      ),
                      ...AuditActionType.values.map(
                        (type) => DropdownMenuItem<AuditActionType?>(
                          value: type,
                          child: Text(type.label,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (val) => notifier.setActionTypeFilter(val),
                  ),
                ),
              ),

              // Status Selector (All / Success / Failed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusChip(context, notifier, 'all', 'All Status',
                      state.statusFilter == 'all'),
                  const SizedBox(width: 6),
                  _buildStatusChip(context, notifier, 'success', 'Success',
                      state.statusFilter == 'success'),
                  const SizedBox(width: 6),
                  _buildStatusChip(context, notifier, 'failed', 'Failed',
                      state.statusFilter == 'failed'),
                ],
              ),

              // Reset Filters Button if any filter active
              if (state.searchQuery.isNotEmpty ||
                  state.actionTypeFilter != null ||
                  state.statusFilter != 'all' ||
                  state.dateRangeFilter != null)
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    notifier.clearFilters();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Clear Filters',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    AuditLogNotifier notifier,
    String value,
    String label,
    bool isSelected,
  ) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey[700],
        ),
      ),
      selected: isSelected,
      onSelected: (_) => notifier.setStatusFilter(value),
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      showCheckmark: false,
    );
  }

  // ==================== 4. DATA TABLE / LIST CARD ====================
  Widget _buildLogsTableCard(
    BuildContext context,
    AuditLogState state,
    List<AuditLogModel> logs,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Headers for Desktop
          if (!isMobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('TIMESTAMP', style: _thStyle)),
                  Expanded(
                      flex: 4,
                      child: Text('ADMIN USER', style: _thStyle)),
                  Expanded(
                      flex: 4,
                      child: Text('ACTION TYPE', style: _thStyle)),
                  Expanded(
                      flex: 4,
                      child: Text('TARGET DOCTOR', style: _thStyle)),
                  Expanded(
                      flex: 2,
                      child: Text('STATUS', style: _thStyle)),
                  SizedBox(
                      width: 90,
                      child: Text('DETAILS',
                          style: _thStyle, textAlign: TextAlign.center)),
                ],
              ),
            ),

          if (!isMobile) const Divider(height: 1),

          // Content List
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No audit logs found matching criteria',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try expanding your search query or date range filters',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                return isMobile
                    ? _buildMobileLogRow(context, log)
                    : _buildDesktopLogRow(context, log);
              },
            ),
        ],
      ),
    );
  }

  // Desktop Data Row
  Widget _buildDesktopLogRow(BuildContext context, AuditLogModel log) {
    final dateFormat = DateFormat('MMM d, yyyy • hh:mm a');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Timestamp
          Expanded(
            flex: 3,
            child: Text(
              dateFormat.format(log.timestamp),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // Admin User
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  child: Text(
                    log.adminName.isNotEmpty
                        ? log.adminName[0].toUpperCase()
                        : 'A',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.adminName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        log.adminEmail,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action Type Chip
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildActionChip(log.actionType),
            ),
          ),

          // Target Doctor
          Expanded(
            flex: 4,
            child: Text(
              log.targetDoctorName ?? log.targetDoctorEmail ?? 'System Global',
              style: TextStyle(
                fontSize: 13,
                fontWeight: log.targetDoctorName != null
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: log.targetDoctorName != null
                    ? const Color(0xFF0F172A)
                    : Colors.grey[500],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Status Badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(log.status),
            ),
          ),

          // View Details Button
          SizedBox(
            width: 90,
            child: TextButton.icon(
              onPressed: () => _showLogDetailsDialog(context, log),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile Log Card
  Widget _buildMobileLogRow(BuildContext context, AuditLogModel log) {
    final dateFormat = DateFormat('MMM d, yyyy • hh:mm a');

    return InkWell(
      onTap: () => _showLogDetailsDialog(context, log),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildActionChip(log.actionType),
                _buildStatusBadge(log.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Admin: ${log.adminName} (${log.adminEmail})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (log.targetDoctorName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Target: ${log.targetDoctorName}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateFormat.format(log.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 5. ACTION CHIPS & BADGES ====================
  Widget _buildActionChip(AuditActionType type) {
    Color bg;
    Color fg;

    switch (type) {
      case AuditActionType.createdDoctor:
      case AuditActionType.activatedAccount:
      case AuditActionType.enabledModule:
      case AuditActionType.createdApiKey:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF10B981);
        break;
      case AuditActionType.changedPlan:
      case AuditActionType.updatedDoctor:
      case AuditActionType.editedPlanDefinition:
      case AuditActionType.updatedSystemConfig:
      case AuditActionType.updatedApiKey:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        break;
      case AuditActionType.resetPassword:
      case AuditActionType.sentAnnouncement:
      case AuditActionType.extendedTrial:
      case AuditActionType.assignedSupportTicket:
      case AuditActionType.resolvedSupportTicket:
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFD97706);
        break;
      case AuditActionType.suspendedAccount:
      case AuditActionType.deletedDoctor:
      case AuditActionType.disabledModule:
      case AuditActionType.revokedApiKey:
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFEF4444);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isSuccess = status.toLowerCase() == 'success';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSuccess ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSuccess ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 12,
            color: isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
          const SizedBox(width: 4),
          Text(
            isSuccess ? 'Success' : 'Failed',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isSuccess ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 6. LOG DETAILS MODAL DIALOG ====================
  void _showLogDetailsDialog(BuildContext context, AuditLogModel log) {
    final dateFormat = DateFormat('MMMM d, yyyy • hh:mm:ss a');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 600,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_rounded,
                            color: Color(0xFF2563EB), size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Audit Event #${log.id}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Scrollable Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Event Summary Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildActionChip(log.actionType),
                                  _buildStatusBadge(log.status),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 15, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateFormat.format(log.timestamp),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Failed Error Box (if any)
                        if (log.errorMessage != null &&
                            log.errorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFFEE2E2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Color(0xFFEF4444), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    log.errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB91C1C),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Section 1: Admin & System Details
                        _buildSectionHeader('ADMIN & SYSTEM CONTEXT'),
                        const SizedBox(height: 8),
                        _buildDetailRow('Admin Name', log.adminName),
                        _buildDetailRow('Admin Email', log.adminEmail),
                        _buildDetailRow('IP Address', log.ipAddress ?? 'N/A'),
                        _buildDetailRow('User Agent', log.userAgent ?? 'N/A'),

                        const SizedBox(height: 16),

                        // Section 2: Target Doctor Context
                        _buildSectionHeader('TARGET CONTEXT'),
                        const SizedBox(height: 8),
                        _buildDetailRow('Doctor Name',
                            log.targetDoctorName ?? 'System Global'),
                        _buildDetailRow(
                            'Doctor Email', log.targetDoctorEmail ?? 'N/A'),
                        _buildDetailRow(
                            'Doctor UID', log.targetDoctorId ?? 'N/A'),

                        // Section 3: Event Details & Diff
                        if (log.details != null && log.details!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildSectionHeader('EVENT METADATA'),
                          const SizedBox(height: 8),
                          _buildJsonView(log.details!),
                        ],

                        if (log.beforeValues != null || log.afterValues != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionHeader('VALUES DIFF'),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (log.beforeValues != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('BEFORE',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFEF4444))),
                                      const SizedBox(height: 4),
                                      _buildJsonView(log.beforeValues!),
                                    ],
                                  ),
                                ),
                              if (log.beforeValues != null && log.afterValues != null)
                                const SizedBox(width: 12),
                              if (log.afterValues != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('AFTER',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981))),
                                      const SizedBox(height: 4),
                                      _buildJsonView(log.afterValues!),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonView(Map<String, dynamic> map) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries.map((e) {
          return Text(
            '${e.key}: ${e.value}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF1E293B),
            ),
          );
        }).toList(),
      ),
    );
  }
}

const TextStyle _thStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  color: Color(0xFF64748B),
  letterSpacing: 0.5,
);
