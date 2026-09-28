import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/enums.dart';
import '../../models/audit_log_model.dart';
import '../../providers/audit_log_provider.dart';

/// Super Admin Audit Logs Management Screen redesigned into the CruDoc Calm Clinical design system.
/// Tracks administrative changes, security anomalies, doctor modifications, and data access.
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
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          _buildHeaderBar(context, notifier, filteredLogs.length, auditState.isLoading),

          const SizedBox(height: CruSpace.s20),

          // 2. Metrics Summary Row
          _buildMetricsRow(context, isMobile, totalLogs, todayLogs, failedLogs, activeAdminsCount),

          const SizedBox(height: CruSpace.s24),

          // 3. Search & Filter Bar
          _buildSearchAndFilters(context, auditState, notifier),

          const SizedBox(height: CruSpace.s20),

          // 4. Audit Logs Table Card
          _buildLogsTableCard(context, auditState, filteredLogs, isMobile),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER BAR
  // ===========================================================================
  Widget _buildHeaderBar(
    BuildContext context,
    AuditLogNotifier notifier,
    int filteredCount,
    bool isLoading,
  ) {
    final c = context.cru;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Security & Audit Logs', style: CruType.largeTitle.tint(c.label)),
                  const SizedBox(width: CruSpace.s12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: ShapeDecoration(
                      color: c.accentTint,
                      shape: cruShape(CruRadius.full),
                    ),
                    child: Text(
                      '$filteredCount Recorded',
                      style: CruType.caption.w600.tabular.tint(c.accentText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Tamper-evident chronological audit trail for administrative mutations, PACS access, and auth events.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        CruButton(
          label: 'Export CSV',
          kind: CruButtonKind.secondary,
          icon: CruIcons.download,
          onPressed: () => notifier.exportToCsv(context),
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(
          label: 'Refresh',
          kind: CruButtonKind.secondary,
          icon: CruIcons.sparkle,
          onPressed: isLoading ? null : () => notifier.loadInitialLogs(),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. METRICS ROW
  // ===========================================================================
  Widget _buildMetricsRow(
    BuildContext context,
    bool isMobile,
    int totalLogs,
    int todayLogs,
    int failedLogs,
    int activeAdmins,
  ) {
    final c = context.cru;

    final cards = [
      _AuditMetric(title: 'Total Logged Actions', value: '$totalLogs', icon: CruIcons.clock),
      _AuditMetric(title: 'Actions Today', value: '$todayLogs', icon: CruIcons.calendar),
      _AuditMetric(title: 'Failed / Denied Ops', value: '$failedLogs', icon: CruIcons.warning),
      _AuditMetric(title: 'Active Root Admins', value: '$activeAdmins', icon: CruIcons.user),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s12),
                  child: _buildMetricTile(c, m),
                ))
            .toList(),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s16),
          Expanded(child: _buildMetricTile(c, cards[i])),
        ],
      ],
    );
  }

  Widget _buildMetricTile(CruColors c, _AuditMetric m) {
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: CruIcon(m.icon, size: 16, color: c.accentText),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          Text(m.value, style: CruType.metric.tint(c.label)),
          const SizedBox(height: CruSpace.s2),
          Text(m.title, style: CruType.caption.tint(c.label3)),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. SEARCH & FILTERS
  // ===========================================================================
  Widget _buildSearchAndFilters(
    BuildContext context,
    AuditLogState state,
    AuditLogNotifier notifier,
  ) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => notifier.setSearchQuery(val),
              style: CruType.text.tint(c.label),
              decoration: InputDecoration(
                hintText: 'Search audit records by admin email, action name, or target doctor...',
                hintStyle: CruType.text.tint(c.label3),
                filled: true,
                fillColor: c.inset,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CruIcon(CruIcons.search, size: 16, color: c.label3),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: CruIcon(CruIcons.close, size: 14, color: c.label3),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Action Type:', style: CruType.caption.w600.tint(c.label3)),
              _buildFilterPill(
                label: 'All Actions',
                selected: state.actionTypeFilter == null,
                onTap: () => notifier.setActionTypeFilter(null),
              ),
              for (final type in AuditActionType.values)
                _buildFilterPill(
                  label: type.label,
                  selected: state.actionTypeFilter == type,
                  onTap: () => notifier.setActionTypeFilter(type),
                ),
              if (_searchController.text.isNotEmpty || state.actionTypeFilter != null) ...[
                const SizedBox(width: CruSpace.s8),
                CruPressable(
                  onTap: () {
                    _searchController.clear();
                    notifier.clearFilters();
                  },
                  builder: (ctx, hovered) => Text('Reset', style: CruType.caption.w600.tint(c.accentText)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      builder: (ctx, hovered) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: ShapeDecoration(
            color: selected
                ? c.accent
                : hovered
                    ? c.hoverFill
                    : c.inset,
            shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
          ),
          child: Text(
            label,
            style: CruType.caption
                .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500)
                .tint(selected ? CruBrand.white : c.label2),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 4. LOGS TABLE CARD
  // ===========================================================================
  Widget _buildLogsTableCard(
    BuildContext context,
    AuditLogState state,
    List<AuditLogModel> logs,
    bool isMobile,
  ) {
    final c = context.cru;

    return CruCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (!isMobile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: c.inset,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(CruRadius.card)),
                border: Border(bottom: BorderSide(color: c.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('ACTION & EVENT', style: CruType.groupLabel.tint(c.label3))),
                  Expanded(flex: 3, child: Text('ADMIN / ACTOR', style: CruType.groupLabel.tint(c.label3))),
                  Expanded(flex: 3, child: Text('TARGET RESOURCE', style: CruType.groupLabel.tint(c.label3))),
                  Expanded(flex: 2, child: Text('TIMESTAMP', style: CruType.groupLabel.tint(c.label3))),
                  Expanded(flex: 1, child: Text('STATUS', style: CruType.groupLabel.tint(c.label3))),
                ],
              ),
            ),
          if (state.isLoading && logs.isEmpty)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    CruIcon(CruIcons.clock, size: 40, color: c.label3),
                    const SizedBox(height: CruSpace.s12),
                    Text('No audit records match filters', style: CruType.headline.tint(c.label)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.hairline),
              itemBuilder: (ctx, index) {
                final log = logs[index];
                return CruPressable(
                  onTap: () => _showLogDetailsDialog(context, log),
                  builder: (ctx, hovered) {
                    return Container(
                      color: hovered ? c.hoverFill : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                CruStatusDot(
                                  log.status.toLowerCase() == 'success' ? CruDotKind.done : CruDotKind.inactive,
                                  size: 8,
                                ),
                                const SizedBox(width: CruSpace.s10),
                                Expanded(
                                  child: Text(
                                    log.actionType.label,
                                    style: CruType.row.tint(c.label),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                CruMonogram(name: log.adminEmail, size: 26, background: c.track),
                                const SizedBox(width: CruSpace.s8),
                                Expanded(
                                  child: Text(
                                    log.adminEmail,
                                    style: CruType.caption.tint(c.label2),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              log.targetDoctorName ?? (log.details != null ? log.details.toString() : 'System Action'),
                              style: CruType.caption.tint(c.label),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              DateFormat('dd MMM, HH:mm:ss').format(log.timestamp),
                              style: CruType.caption.tabular.tint(c.label3),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: ShapeDecoration(
                                  color: log.status.toLowerCase() == 'success' ? c.greenTint : c.redTint,
                                  shape: cruShape(CruRadius.full),
                                ),
                                child: Text(
                                  log.status.toUpperCase(),
                                  style: CruType.caption.w600.tint(
                                    log.status.toLowerCase() == 'success' ? c.greenText : c.redText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  void _showLogDetailsDialog(BuildContext context, AuditLogModel log) {
    final c = context.cru;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: cruShape(CruRadius.card),
        title: Row(
          children: [
            CruIcon(CruIcons.clock, size: 20, color: c.accent),
            const SizedBox(width: CruSpace.s10),
            Text('Audit Record Details', style: CruType.title.tint(c.label)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(c, 'Action Event', log.actionType.label),
              _detailRow(c, 'Initiator Admin', log.adminEmail),
              _detailRow(c, 'Target Doctor', log.targetDoctorName ?? 'N/A'),
              _detailRow(c, 'IP Address', log.ipAddress ?? 'N/A'),
              _detailRow(c, 'Timestamp', DateFormat('dd MMMM yyyy, hh:mm:ss a').format(log.timestamp)),
              _detailRow(c, 'Status', log.status.toUpperCase()),
              const SizedBox(height: CruSpace.s12),
              Text('Description / Payload Details:', style: CruType.caption.w600.tint(c.label3)),
              const SizedBox(height: CruSpace.s4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.control),
                ),
                child: Text(
                  log.details != null && log.details!.isNotEmpty
                      ? log.details.toString()
                      : 'No payload details recorded for this operation.',
                  style: CruType.text.tint(c.label),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CruButton(
            label: 'Close',
            kind: CruButtonKind.primary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(CruColors c, String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(key, style: CruType.caption.tint(c.label3)),
          ),
          Expanded(
            child: Text(value, style: CruType.caption.w600.tint(c.label)),
          ),
        ],
      ),
    );
  }
}

class _AuditMetric {
  final String title;
  final String value;
  final CruIconData icon;

  const _AuditMetric({
    required this.title,
    required this.value,
    required this.icon,
  });
}
