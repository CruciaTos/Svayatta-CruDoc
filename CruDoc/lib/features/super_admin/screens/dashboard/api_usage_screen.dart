import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:doctor_management_app/core/theme/app_colors.dart';
import '../../models/api_key_model.dart';
import '../../providers/api_key_provider.dart';

/// Super Admin API Keys and Usage Screen.
class SuperAdminApiUsageScreen extends ConsumerStatefulWidget {
  const SuperAdminApiUsageScreen({super.key});

  @override
  ConsumerState<SuperAdminApiUsageScreen> createState() =>
      _SuperAdminApiUsageScreenState();
}

class _SuperAdminApiUsageScreenState
    extends ConsumerState<SuperAdminApiUsageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _systemKeyControllers = {};
  final Map<String, bool> _obscureText = {};

  void _syncControllers(Map<String, String> keys) {
    for (final entry in keys.entries) {
      final key = entry.key;
      final val = entry.value;
      if (!_systemKeyControllers.containsKey(key)) {
        _systemKeyControllers[key] = TextEditingController(text: val);
        _obscureText[key] = true;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    Future.microtask(() {
      ref.read(apiKeysProvider.notifier).loadKeysAndLogs();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    for (final controller in _systemKeyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeysProvider);
    final notifier = ref.read(apiKeysProvider.notifier);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(135),
        child: Container(
          padding: EdgeInsets.only(
            left: isMobile ? 16 : 24,
            right: isMobile ? 16 : 24,
            top: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'API Gateway & Usage',
                          style: TextStyle(
                            fontFamily: AppColors.headingFontFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage credentials and monitor third-party voice assistant & integration traffic.',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: state.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.slateBlue,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        onPressed: () => notifier.loadKeysAndLogs(),
                        tooltip: 'Refresh Data',
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showGenerateKeyDialog(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Generate Key'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).primaryColor,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'API Credentials'),
                  Tab(text: 'Access Logs'),
                  Tab(text: 'Third-Party Integrations'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(context, state, isMobile),
          _buildCredentialsTab(context, state, notifier, isMobile),
          _buildLogsTab(context, state, notifier, isMobile),
          _buildThirdPartyTab(context, state, notifier, isMobile),
        ],
      ),
    );
  }

  // ============================================================
  // OVERVIEW TAB
  // ============================================================

  Widget _buildOverviewTab(BuildContext context, ApiKeyState state, bool isMobile) {
    if (state.isLoading && state.apiKeys.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final dailyCounts = state.dailyRequestCounts.values.toList();
    final dailyDays = state.dailyRequestCounts.keys
        .map((d) => DateFormat('E').format(d))
        .toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI summary grid
          _buildMetricsGrid(context, state, isMobile),
          const SizedBox(height: 24),

          // Chart Section
          if (isMobile) ...[
            _buildUsageChartCard(context, dailyCounts, dailyDays),
            const SizedBox(height: 16),
            _buildEndpointsBreakdownCard(context, state),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildUsageChartCard(context, dailyCounts, dailyDays),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 2,
                  child: _buildEndpointsBreakdownCard(context, state),
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context, ApiKeyState state, bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = isMobile
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKPICard(
              width: cardWidth,
              title: 'Active API Keys',
              value: '${state.activeKeysCount}',
              subtitle: 'Out of ${state.apiKeys.length} total',
              icon: Icons.key_rounded,
              iconColor: Theme.of(context).primaryColor,
            ),
            _buildKPICard(
              width: cardWidth,
              title: 'Total Requests',
              value: '${state.totalRequestCount}',
              subtitle: 'Last 7 days',
              icon: Icons.cloud_queue_rounded,
              iconColor: Colors.blueAccent,
            ),
            _buildKPICard(
              width: cardWidth,
              title: 'Success Rate',
              value: '${state.successRate.toStringAsFixed(1)}%',
              subtitle: 'Status 2xx traffic',
              icon: Icons.check_circle_outline_rounded,
              iconColor: AppColors.positiveGreen,
            ),
            _buildKPICard(
              width: cardWidth,
              title: 'Avg Latency',
              value: '${state.averageLatency.toStringAsFixed(0)}ms',
              subtitle: 'Response gateway delay',
              icon: Icons.speed_rounded,
              iconColor: Colors.amber,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard({
    required double width,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageChartCard(
    BuildContext context,
    List<int> dailyCounts,
    List<String> dailyDays,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart_rounded, color: AppColors.slateBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'API REQUEST VOLUME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.slateBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.positiveGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Daily requests (Last 7 days)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.positiveGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: ApiUsageTrendPainter(
                dataPoints: dailyCounts.map((e) => e.toDouble()).toList(),
                labels: dailyDays,
                lineColor: Theme.of(context).primaryColor,
                fillColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointsBreakdownCard(BuildContext context, ApiKeyState state) {
    final Map<String, int> counts = state.endpointUsageCounts;
    final int total = counts.values.fold(0, (sum, c) => sum + c);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, color: AppColors.slateBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'ENDPOINT DISTRIBUTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slateBlue,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (counts.isEmpty)
            const SizedBox(
              height: 160,
              child: Center(
                child: Text('No request data logged yet',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Column(
              children: counts.entries.map((entry) {
                final percent = total > 0 ? (entry.value / total) * 100 : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${entry.value} (${percent.toStringAsFixed(1)}%)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? entry.value / total : 0.0,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getEndpointColor(entry.key),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Color _getEndpointColor(String endpoint) {
    if (endpoint.contains('voice')) return Colors.teal;
    if (endpoint.contains('patients')) return Colors.indigo;
    if (endpoint.contains('appointments')) return Colors.blue;
    if (endpoint.contains('inventory')) return Colors.orange;
    return Colors.grey;
  }

  // ============================================================
  // CREDENTIALS TAB
  // ============================================================

  Widget _buildCredentialsTab(
    BuildContext context,
    ApiKeyState state,
    ApiKeyNotifier notifier,
    bool isMobile,
  ) {
    final filteredKeys = state.apiKeys.where((key) {
      if (state.searchQuery.isEmpty) return true;
      return key.name.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
          key.maskedKey.toLowerCase().contains(state.searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search filter row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by API key name or identifier...',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                  onChanged: (val) => notifier.setSearchQuery(val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Keys Table Card
          Expanded(
            child: Card(
              color: AppColors.cardSurface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: filteredKeys.isEmpty
                  ? const Center(
                      child: Text(
                        'No API keys found. Click "Generate Key" to create one.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredKeys.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final key = filteredKeys[index];
                        return _buildKeyListRow(context, key, notifier, isMobile);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyListRow(
    BuildContext context,
    ApiKeyModel key,
    ApiKeyNotifier notifier,
    bool isMobile,
  ) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      title: Row(
        children: [
          Text(
            key.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          _buildStatusBadge(key.isActive),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.vpn_key_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  key.maskedKey,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Created: ${dateFormat.format(key.createdAt)}'),
              ],
            ),
            if (key.expiresAt != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Expires: ${dateFormat.format(key.expiresAt!)}'),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Limit: ${key.rateLimit} req/min'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_alt_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Calls: ${key.totalRequests}'),
              ],
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit Key Settings',
            onPressed: () => _showEditKeyDialog(context, key),
          ),
          if (key.isActive)
            IconButton(
              icon: const Icon(Icons.block_outlined, size: 20, color: Colors.redAccent),
              tooltip: 'Revoke API Key',
              onPressed: () => _showRevokeConfirmation(context, key, notifier),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.positiveGreen.withValues(alpha: 0.12)
            : Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Revoked',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isActive ? AppColors.positiveGreen : Colors.redAccent,
        ),
      ),
    );
  }

  // ============================================================
  // ACCESS LOGS TAB
  // ============================================================

  Widget _buildLogsTab(
    BuildContext context,
    ApiKeyState state,
    ApiKeyNotifier notifier,
    bool isMobile,
  ) {
    final filteredLogs = state.apiLogs.where((log) {
      if (state.searchQuery.isEmpty) return true;
      return log.apiKeyName.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
          log.endpoint.toLowerCase().contains(state.searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search logs by endpoint or key name...',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                  onChanged: (val) => notifier.setSearchQuery(val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              color: AppColors.cardSurface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: filteredLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'No request logs found.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filteredLogs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        return _buildLogListRow(context, log, isMobile);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogListRow(BuildContext context, ApiLogModel log, bool isMobile) {
    final timeStr = DateFormat('MMM dd, yyyy HH:mm:ss').format(log.timestamp);
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: _buildMethodBadge(log.method),
      title: Text(
        log.endpoint,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'monospace'),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          children: [
            Text(
              log.apiKeyName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const SizedBox(width: 12),
            Text(
              timeStr,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${log.latencyMs} ms',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          _buildStatusCodeBadge(log.statusCode),
        ],
      ),
    );
  }

  Widget _buildMethodBadge(String method) {
    Color bg = Colors.grey[200]!;
    Color text = Colors.grey[700]!;
    if (method == 'GET') {
      bg = Colors.green[50]!;
      text = Colors.green[800]!;
    } else if (method == 'POST') {
      bg = Colors.blue[50]!;
      text = Colors.blue[800]!;
    } else if (method == 'PUT') {
      bg = Colors.amber[50]!;
      text = Colors.amber[800]!;
    }

    return Container(
      width: 55,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  Widget _buildStatusCodeBadge(int code) {
    Color bg = Colors.green[50]!;
    Color text = Colors.green[800]!;
    if (code >= 400 && code < 500) {
      bg = Colors.orange[50]!;
      text = Colors.orange[800]!;
    } else if (code >= 500) {
      bg = Colors.red[50]!;
      text = Colors.red[800]!;
    }

    return Container(
      width: 40,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$code',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  // ============================================================
  // DIALOGS & ACTIONS
  // ============================================================

  void _showGenerateKeyDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _GenerateKeyDialog(),
    );
  }

  void _showEditKeyDialog(BuildContext context, ApiKeyModel key) {
    showDialog(
      context: context,
      builder: (context) => _EditKeyDialog(apiKey: key),
    );
  }

  void _showRevokeConfirmation(
    BuildContext context,
    ApiKeyModel key,
    ApiKeyNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            const Text('Revoke API Key'),
          ],
        ),
        content: Text(
          'Are you sure you want to revoke "${key.name}"? '
          'Any integrations currently using this key will immediately be denied access. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notifier.revokeApiKey(key.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('API Key "${key.name}" revoked'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Revoke Key'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SYSTEM INTEGRATIONS WIDGETS
  // ============================================================

  Widget _buildThirdPartyTab(
    BuildContext context,
    ApiKeyState state,
    ApiKeyNotifier notifier,
    bool isMobile,
  ) {
    _syncControllers(state.systemKeys);

    if (state.isLoading && state.systemKeys.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border.all(color: Colors.blue[100]!),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue[800], size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Third-Party Integration Keys',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Centralized management of third-party API configurations (Google Maps, Twilio telephony, Gemini chatbot, voice receptionist, and WhatsApp notifications). Modify these values to update credentials platform-wide.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (isMobile) ...[
            _buildGroupCard(
              title: 'Google & AI Credentials',
              icon: Icons.language_rounded,
              iconColor: Colors.deepPurple,
              fields: [
                _buildSystemField('googleMapsApiKey', 'Google Maps API Key', 'Used for address geocoding and Static Map previews.'),
                _buildSystemField('chatbotGeminiApiKey', 'Gemini Chatbot API Key', 'LLM key used to power the CruDoc practice AI Assistant.'),
                _buildSystemField('voiceGeminiApiKey', 'Voice Gemini API Key', 'LLM key used by the telephony voice receptionist.'),
                _buildSystemField('sarvamApiKey', 'Sarvam AI Speech API Key', 'TTS/STT key used for speech translation in voice receptionist.'),
              ],
            ),
            const SizedBox(height: 16),
            _buildGroupCard(
              title: 'Twilio Telephony & Routing',
              icon: Icons.phone_callback_rounded,
              iconColor: Colors.redAccent,
              fields: [
                _buildSystemField('twilioAccountSid', 'Twilio Account SID', 'Your Twilio Account identifier.'),
                _buildSystemField('twilioAuthToken', 'Twilio Auth Token', 'Twilio Auth Token used to sign websocket connections.'),
                _buildSystemField('twilioPhoneNumber', 'Twilio Phone Number', 'Dial-in number callers use to contact the bot.'),
                _buildSystemField('receptionistNumber', 'Receptionist Transfer Number', 'Number callers are forwarded to for human support.'),
              ],
            ),
            const SizedBox(height: 16),
            _buildGroupCard(
              title: 'Meta WhatsApp Notifications',
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: AppColors.positiveGreen,
              fields: [
                _buildSystemField('whatsappAccessToken', 'WhatsApp Access Token', 'Meta System User token for sending template notifications.'),
                _buildSystemField('whatsappVerifyToken', 'WhatsApp Webhook Verify Token', 'Verification token matched against Meta webhook requests.'),
              ],
            ),
            const SizedBox(height: 16),
            _buildGroupCard(
              title: 'Voice Bot API Secret',
              icon: Icons.security_rounded,
              iconColor: Colors.amber,
              fields: [
                _buildSystemField('voiceBotApiKey', 'Voice Bot API Secret', 'Shared secret checked by Appointments API Cloud Function.'),
              ],
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildGroupCard(
                        title: 'Google & AI Credentials',
                        icon: Icons.language_rounded,
                        iconColor: Colors.deepPurple,
                        fields: [
                          _buildSystemField('googleMapsApiKey', 'Google Maps API Key', 'Used for address geocoding and Static Map previews.'),
                          _buildSystemField('chatbotGeminiApiKey', 'Gemini Chatbot API Key', 'LLM key used to power the CruDoc practice AI Assistant.'),
                          _buildSystemField('voiceGeminiApiKey', 'Voice Gemini API Key', 'LLM key used by the telephony voice receptionist.'),
                          _buildSystemField('sarvamApiKey', 'Sarvam AI Speech API Key', 'TTS/STT key used for speech translation in voice receptionist.'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildGroupCard(
                        title: 'Voice Bot API Secret',
                        icon: Icons.security_rounded,
                        iconColor: Colors.amber,
                        fields: [
                          _buildSystemField('voiceBotApiKey', 'Voice Bot API Secret', 'Shared secret checked by Appointments API Cloud Function.'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _buildGroupCard(
                        title: 'Twilio Telephony & Routing',
                        icon: Icons.phone_callback_rounded,
                        iconColor: Colors.redAccent,
                        fields: [
                          _buildSystemField('twilioAccountSid', 'Twilio Account SID', 'Your Twilio Account identifier.'),
                          _buildSystemField('twilioAuthToken', 'Twilio Auth Token', 'Twilio Auth Token used to sign websocket connections.'),
                          _buildSystemField('twilioPhoneNumber', 'Twilio Phone Number', 'Dial-in number callers use to contact the bot.'),
                          _buildSystemField('receptionistNumber', 'Receptionist Transfer Number', 'Number callers are forwarded to for human support.'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildGroupCard(
                        title: 'Meta WhatsApp Notifications',
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: AppColors.positiveGreen,
                        fields: [
                          _buildSystemField('whatsappAccessToken', 'WhatsApp Access Token', 'Meta System User token for sending template notifications.'),
                          _buildSystemField('whatsappVerifyToken', 'WhatsApp Webhook Verify Token', 'Verification token matched against Meta webhook requests.'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),

          Center(
            child: ElevatedButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () async {
                      final keys = _systemKeyControllers.map((key, ctrl) {
                        return MapEntry(key, ctrl.text.trim());
                      });
                      await notifier.saveSystemKeys(keys);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('System integration keys saved successfully'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              icon: state.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Save Integration Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildGroupCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> fields,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: iconColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...fields,
        ],
      ),
    );
  }

  Widget _buildSystemField(String configKey, String label, String description) {
    final controller = _systemKeyControllers[configKey];
    if (controller == null) return const SizedBox.shrink();
    final isObscured = _obscureText[configKey] ?? true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: isObscured,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText[configKey] = !isObscured;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GENERATE DIALOG WIDGET
// ============================================================

class _GenerateKeyDialog extends ConsumerStatefulWidget {
  const _GenerateKeyDialog();

  @override
  ConsumerState<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends ConsumerState<_GenerateKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _rateLimit = 60;
  String _expiryOption = 'never';
  final List<String> _selectedScopes = ['patients:read', 'appointments:read'];

  final List<Map<String, String>> _availableScopes = [
    {'value': 'patients:read', 'label': 'Read Patient Files'},
    {'value': 'patients:write', 'label': 'Create/Edit Patients'},
    {'value': 'appointments:read', 'label': 'Read Appointments'},
    {'value': 'appointments:write', 'label': 'Create/Edit Appointments'},
    {'value': 'inventory:read', 'label': 'View Inventory items'},
    {'value': 'voice:read', 'label': 'Read Voice receptionist Logs'},
    {'value': 'voice:write', 'label': 'Write Voice call Webhooks'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeysProvider);
    final notifier = ref.read(apiKeysProvider.notifier);

    // If key has just been generated, show screen with plain key copy button
    if (state.lastGeneratedKey != null) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.positiveGreen, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'API Key Generated',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Please copy this API key now. For security reasons, '
                'you will not be able to see it again once you close this dialog.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Plain key box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.lastGeneratedKey!,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: state.lastGeneratedKey!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('API Key copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      tooltip: 'Copy to Clipboard',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Danger notice banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.amber[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keep this key secret. Anyone with access to this key can perform '
                        'actions on behalf of this workspace corresponding to the scopes granted.',
                        style: TextStyle(fontSize: 11, color: Colors.amber[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      notifier.clearGeneratedKey();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Default key setup form
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Generate New API Key',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name field
                const Text('Key Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Voice Agent Client, Stripe Webhook',
                    hintStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a name for the key';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Expiry Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Expiration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _expiryOption,
                            isDense: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: '7', child: Text('7 Days', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: '30', child: Text('30 Days', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: '90', child: Text('90 Days', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'never', child: Text('Never Expires', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _expiryOption = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rate Limit: $_rateLimit req/min',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          Slider(
                            value: _rateLimit.toDouble(),
                            min: 10,
                            max: 300,
                            divisions: 29,
                            activeColor: Theme.of(context).primaryColor,
                            label: '$_rateLimit req/min',
                            onChanged: (val) {
                              setState(() {
                                _rateLimit = val.toInt();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Scopes Select
                const Text('Permissions / Scopes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: _availableScopes.map((scope) {
                      final isSelected = _selectedScopes.contains(scope['value']);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(scope['label']!, style: const TextStyle(fontSize: 12)),
                        subtitle: Text(scope['value']!, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'monospace')),
                        dense: true,
                        activeColor: Theme.of(context).primaryColor,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedScopes.add(scope['value']!);
                            } else {
                              _selectedScopes.remove(scope['value']!);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: state.isLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                DateTime? exp;
                                if (_expiryOption != 'never') {
                                  final days = int.parse(_expiryOption);
                                  exp = DateTime.now().add(Duration(days: days));
                                }
                                notifier.createApiKey(
                                  name: _nameController.text.trim(),
                                  expiresAt: exp,
                                  rateLimit: _rateLimit,
                                  scopes: _selectedScopes,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: state.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Generate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EDIT DIALOG WIDGET
// ============================================================

class _EditKeyDialog extends ConsumerStatefulWidget {
  final ApiKeyModel apiKey;
  const _EditKeyDialog({required this.apiKey});

  @override
  ConsumerState<_EditKeyDialog> createState() => _EditKeyDialogState();
}

class _EditKeyDialogState extends ConsumerState<_EditKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late int _rateLimit;
  late bool _isActive;
  late List<String> _selectedScopes;

  final List<Map<String, String>> _availableScopes = [
    {'value': 'patients:read', 'label': 'Read Patient Files'},
    {'value': 'patients:write', 'label': 'Create/Edit Patients'},
    {'value': 'appointments:read', 'label': 'Read Appointments'},
    {'value': 'appointments:write', 'label': 'Create/Edit Appointments'},
    {'value': 'inventory:read', 'label': 'View Inventory items'},
    {'value': 'voice:read', 'label': 'Read Voice receptionist Logs'},
    {'value': 'voice:write', 'label': 'Write Voice call Webhooks'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.apiKey.name);
    _rateLimit = widget.apiKey.rateLimit;
    _isActive = widget.apiKey.isActive;
    _selectedScopes = List<String>.from(widget.apiKey.scopes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(apiKeysProvider);
    final notifier = ref.read(apiKeysProvider.notifier);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit API Key Configuration',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name field
                const Text('Key Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a name for the key';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Status Switch
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Key Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          SwitchListTile(
                            title: Text(_isActive ? 'Active (Traffic allowed)' : 'Inactive (Traffic blocked)', style: const TextStyle(fontSize: 13)),
                            value: _isActive,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: AppColors.positiveGreen,
                            onChanged: (val) {
                              setState(() {
                                _isActive = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rate Limit: $_rateLimit req/min',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          Slider(
                            value: _rateLimit.toDouble(),
                            min: 10,
                            max: 300,
                            divisions: 29,
                            activeColor: Theme.of(context).primaryColor,
                            label: '$_rateLimit req/min',
                            onChanged: (val) {
                              setState(() {
                                _rateLimit = val.toInt();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Scopes Select
                const Text('Permissions / Scopes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: _availableScopes.map((scope) {
                      final isSelected = _selectedScopes.contains(scope['value']);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(scope['label']!, style: const TextStyle(fontSize: 12)),
                        subtitle: Text(scope['value']!, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontFamily: 'monospace')),
                        dense: true,
                        activeColor: Theme.of(context).primaryColor,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedScopes.add(scope['value']!);
                            } else {
                              _selectedScopes.remove(scope['value']!);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: state.isLoading
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                await notifier.updateApiKey(
                                  id: widget.apiKey.id,
                                  name: _nameController.text.trim(),
                                  rateLimit: _rateLimit,
                                  isActive: _isActive,
                                  scopes: _selectedScopes,
                                );
                                if (mounted) {
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('API Key updated successfully'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: state.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CUSTOM TREND PAINTER
// ============================================================

class ApiUsageTrendPainter extends CustomPainter {
  final List<double> dataPoints;
  final List<String> labels;
  final Color lineColor;
  final Color fillColor;

  ApiUsageTrendPainter({
    required this.dataPoints,
    required this.labels,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Determine max value for Y scaling
    final double maxVal = (dataPoints.reduce((a, b) => a > b ? a : b) * 1.25).clamp(10.0, 100000.0);
    const double paddingLeft = 40.0;
    const double paddingBottom = 30.0;
    final double width = size.width - paddingLeft - 10.0;
    final double height = size.height - paddingBottom - 10.0;

    // Draw horizontal grid lines & Y labels
    for (int i = 0; i <= 4; i++) {
      final y = height - (height / 4 * i) + 10.0;
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      final valLabel = (maxVal / 4 * i).toStringAsFixed(0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: valLabel,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - 6));
    }

    final double stepX = width / (dataPoints.length > 1 ? dataPoints.length - 1 : 1);
    final List<Offset> points = [];

    for (int i = 0; i < dataPoints.length; i++) {
      final x = paddingLeft + (stepX * i);
      final y = height - (height * (dataPoints[i] / maxVal)) + 10.0;
      points.add(Offset(x, y));

      // Day Label
      if (i < labels.length) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - 18));
      }
    }

    // Build Curve Path
    if (points.isNotEmpty) {
      final path = Path();
      final fillPath = Path();

      path.moveTo(points.first.dx, points.first.dy);
      fillPath.moveTo(points.first.dx, height + 10.0);
      fillPath.lineTo(points.first.dx, points.first.dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final controlPoint1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
        final controlPoint2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);

        path.cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          p2.dx,
          p2.dy,
        );
        fillPath.cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          p2.dx,
          p2.dy,
        );
      }

      fillPath.lineTo(points.last.dx, height + 10.0);
      fillPath.close();

      // Gradient Fill under curve
      final fillGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fillColor.withValues(alpha: 0.20),
          fillColor.withValues(alpha: 0.0),
        ],
      );

      final fillPaint = Paint()
        ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
