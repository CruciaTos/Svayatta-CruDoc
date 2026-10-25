import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_recipient_log.dart';
import '../data/models/campaign_enums.dart';
import '../data/providers/campaign_providers.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_dispatch_service.dart';

/// Detailed inspection dialog displaying real-time delivery logs, channel breakdowns,
/// error diagnostics, and a 1-click retry option for failed recipients.
class CampaignAnalyticsDialog extends ConsumerStatefulWidget {
  const CampaignAnalyticsDialog({
    super.key,
    required this.campaign,
    this.onCampaignUpdated,
  });

  final CampaignModel campaign;
  final VoidCallback? onCampaignUpdated;

  static Future<void> show(
    BuildContext context, {
    required CampaignModel campaign,
    VoidCallback? onCampaignUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
          child: CampaignAnalyticsDialog(
            campaign: campaign,
            onCampaignUpdated: onCampaignUpdated,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<CampaignAnalyticsDialog> createState() =>
      _CampaignAnalyticsDialogState();
}

class _CampaignAnalyticsDialogState
    extends ConsumerState<CampaignAnalyticsDialog> {
  CampaignRepository get _campaignRepository =>
      ref.read(campaignRepositoryProvider);
  CampaignDispatchService get _dispatchService =>
      ref.read(campaignDispatchServiceProvider);

  late CampaignModel _currentCampaign;
  String _filter = 'all'; // 'all', 'delivered', 'failed', 'email', 'whatsapp'
  String _searchQuery = '';
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _currentCampaign = widget.campaign;
  }

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);
    try {
      final updated = await _dispatchService.retryFailedRecipients(
        doctorId: _currentCampaign.doctorId,
        campaignId: _currentCampaign.id,
      );
      if (mounted) {
        setState(() {
          _currentCampaign = updated;
          _isRetrying = false;
        });
        widget.onCampaignUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Retry process completed for failed recipients.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRetrying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Retry failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        boxShadow: const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CruRadius.card),
        child: Column(
          children: [
            // Modal Header
            _buildHeader(),
            const Divider(height: 1),

            // Top KPI Stat Tiles
            _buildKpiRow(),
            const Divider(height: 1),

            // Filter Bar
            _buildFilterBar(),

            // Recipient Stream Table
            Expanded(
              child: StreamBuilder<List<CampaignRecipientLog>>(
                stream: _campaignRepository.watchRecipientLogs(
                  _currentCampaign.doctorId,
                  _currentCampaign.id,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allLogs = snapshot.data ?? [];
                  final filteredLogs = _applyFilters(allLogs);

                  if (allLogs.isEmpty) {
                    return const Center(
                      child: Text('No recipient delivery logs recorded yet.'),
                    );
                  }

                  if (filteredLogs.isEmpty) {
                    return Center(
                      child: Text(
                        'No recipients match the selected filter "$_filter"',
                        style: TextStyle(color: context.cru.label2),
                      ),
                    );
                  }

                  return _buildLogsTable(filteredLogs);
                },
              ),
            ),

            // Modal Footer
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cat = _currentCampaign.category;
    return Container(
      padding: const EdgeInsets.all(20),
      color: context.cru.inset,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CruRadius.control),
            ),
            child: Icon(cat.icon, color: cat.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _currentCampaign.title,
                        style: CruType.headline.w700.tint(context.cru.label),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _currentCampaign.status.color.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _currentCampaign.status.color.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Text(
                        _currentCampaign.status.label,
                        style: CruType.micro.w700.tint(
                          _currentCampaign.status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Created: ${_currentCampaign.formattedCreatedAt} • Category: ${cat.label}',
                  style: CruType.caption.tint(context.cru.label2),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: context.cru.label2),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    final successRate = _currentCampaign.successRate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: context.cru.surface,
      child: Row(
        children: [
          _buildKpiCard(
            'Total Targeted',
            '${_currentCampaign.totalRecipients}',
            context.cru.label,
          ),
          _buildKpiCard(
            'Success Rate',
            '${successRate.toStringAsFixed(1)}%',
            context.cru.greenText,
          ),
          _buildKpiCard(
            '📧 Emails Sent',
            '${_currentCampaign.emailsSent}',
            context.cru.accent,
            failedCount: _currentCampaign.emailsFailed,
          ),
          _buildKpiCard(
            '💬 WhatsApp Sent',
            '${_currentCampaign.whatsAppSent}',
            context.cru.greenText,
            failedCount: _currentCampaign.whatsAppFailed,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    String label,
    String value,
    Color color, {
    int failedCount = 0,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: CruType.micro.w600.tint(context.cru.label2)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(value, style: CruType.headline.w700.tint(color)),
                if (failedCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '($failedCount failed)',
                    style: CruType.micro.w600.tint(context.cru.label2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: context.cru.inset,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (q) =>
                    setState(() => _searchQuery = q.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText:
                      'Search recipients by patient name, phone, or email...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  filled: true,
                  fillColor: context.cru.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 6),
          _buildFilterChip('Delivered', 'delivered'),
          const SizedBox(width: 6),
          _buildFilterChip('Failed', 'failed'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _filter = value),
      showCheckmark: false,
      selectedColor: context.cru.accentTint,
      labelStyle: CruType.micro.w600.tint(
        isSelected ? context.cru.accentText : context.cru.label,
      ),
      backgroundColor: context.cru.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CruRadius.control),
        side: BorderSide(
          color: isSelected ? context.cru.accent : context.cru.cardBorder,
        ),
      ),
    );
  }

  List<CampaignRecipientLog> _applyFilters(List<CampaignRecipientLog> logs) {
    return logs.where((log) {
      // Search
      if (_searchQuery.isNotEmpty) {
        final match =
            log.patientName.toLowerCase().contains(_searchQuery) ||
            log.phone.contains(_searchQuery) ||
            log.email.toLowerCase().contains(_searchQuery);
        if (!match) return false;
      }

      // Filter
      if (_filter == 'delivered') {
        return log.isSuccessful;
      } else if (_filter == 'failed') {
        return log.hasFailed;
      }
      return true;
    }).toList();
  }

  Widget _buildLogsTable(List<CampaignRecipientLog> logs) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: logs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final log = logs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Patient Initials Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: context.cru.accentWash,
                child: Text(
                  log.patientName.isNotEmpty
                      ? log.patientName[0].toUpperCase()
                      : '?',
                  style: CruType.caption.w700.tint(context.cru.accent),
                ),
              ),
              const SizedBox(width: 12),

              // Patient Name & Contacts
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.patientName,
                      style: CruType.subhead.w700.tint(context.cru.label),
                    ),
                    Text(
                      '${log.phone}  •  ${log.email.isNotEmpty ? log.email : "No Email"}',
                      style: CruType.micro.tint(context.cru.label2),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Email Status Badge
              if (_currentCampaign.channels.includesEmail) ...[
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 14,
                        color: context.cru.label2,
                      ),
                      const SizedBox(width: 4),
                      _buildStatusBadge(
                        log.emailStatus,
                        log.emailError,
                        simulated: log.emailSimulated,
                      ),
                    ],
                  ),
                ),
              ],

              // WhatsApp Status Badge
              if (_currentCampaign.channels.includesWhatsApp) ...[
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: context.cru.label2,
                      ),
                      const SizedBox(width: 4),
                      _buildStatusBadge(
                        log.whatsAppStatus,
                        log.whatsAppError,
                        simulated: log.whatsAppSimulated,
                      ),
                    ],
                  ),
                ),
              ],

              // Time
              SizedBox(
                width: 90,
                child: Text(
                  log.formattedDispatchedAt,
                  textAlign: TextAlign.right,
                  style: CruType.micro.tint(context.cru.label3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(
    RecipientDeliveryStatus status,
    String? error, {
    bool simulated = false,
  }) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status.color,
            ),
          ),
          const SizedBox(width: 6),
          Text(status.label, style: CruType.micro.w700.tint(status.color)),
        ],
      ),
    );

    final children = <Widget>[badge];

    if (simulated) {
      children.add(const SizedBox(width: 4));
      children.add(
        Tooltip(
          message:
              'Simulated in a test build — this message was NOT actually sent.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: context.cru.amberText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'SIMULATED',
              style: CruType.micro.w700
                  .tint(context.cru.amberText)
                  .copyWith(letterSpacing: 0.4),
            ),
          ),
        ),
      );
    }

    if (error != null && error.isNotEmpty) {
      children.add(const SizedBox(width: 4));
      children.add(
        Tooltip(
          message: 'Reason: $error',
          child: Icon(Icons.info_outline, size: 14, color: context.cru.label2),
        ),
      );
    }

    if (children.length == 1) return badge;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildFooter() {
    final hasFailures = _currentCampaign.totalFailed > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (hasFailures) ...[
            ElevatedButton.icon(
              onPressed: _isRetrying ? null : _handleRetry,
              icon: _isRetrying
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.cru.label,
                      ),
                    )
                  : const Icon(Icons.replay_rounded, size: 16),
              label: Text(
                _isRetrying
                    ? 'Retrying...'
                    : 'Retry Failed Dispatches (${_currentCampaign.totalFailed})',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.cru.inset,
                foregroundColor: context.cru.label,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
