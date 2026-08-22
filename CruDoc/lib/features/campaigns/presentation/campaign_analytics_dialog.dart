import 'package:flutter/material.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_recipient_log.dart';
import '../data/models/campaign_enums.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_dispatch_service.dart';

/// Detailed inspection dialog displaying real-time delivery logs, channel breakdowns,
/// error diagnostics, and a 1-click retry option for failed recipients.
class CampaignAnalyticsDialog extends StatefulWidget {
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
  State<CampaignAnalyticsDialog> createState() => _CampaignAnalyticsDialogState();
}

class _CampaignAnalyticsDialogState extends State<CampaignAnalyticsDialog> {
  final CampaignRepository _campaignRepository = CampaignRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();

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
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRetrying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retry failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Modal Header
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Top KPI Stat Tiles
            _buildKpiRow(),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

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
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return _buildLogsTable(filteredLogs);
                },
              ),
            ),

            // Modal Footer
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
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
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cat.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
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
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _currentCampaign.status.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _currentCampaign.status.color.withOpacity(0.3)),
                      ),
                      child: Text(
                        _currentCampaign.status.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _currentCampaign.status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Created: ${_currentCampaign.formattedCreatedAt} • Category: ${cat.label}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    final successRate = _currentCampaign.successRate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        children: [
          _buildKpiCard('Total Targeted', '${_currentCampaign.totalRecipients}', const Color(0xFF0F172A)),
          _buildKpiCard('Success Rate', '${successRate.toStringAsFixed(1)}%', const Color(0xFF16A34A)),
          _buildKpiCard('📧 Emails Sent', '${_currentCampaign.emailsSent}', const Color(0xFF2563EB),
              failedCount: _currentCampaign.emailsFailed),
          _buildKpiCard('💬 WhatsApp Sent', '${_currentCampaign.whatsAppSent}', const Color(0xFF059669),
              failedCount: _currentCampaign.whatsAppFailed),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color, {int failedCount = 0}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                if (failedCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '($failedCount failed)',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
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
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (q) => setState(() => _searchQuery = q.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search recipients by patient name, phone, or email...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
      selectedColor: const Color(0xFF2563EB),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: isSelected ? Colors.white : const Color(0xFF334155),
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0)),
      ),
    );
  }

  List<CampaignRecipientLog> _applyFilters(List<CampaignRecipientLog> logs) {
    return logs.where((log) {
      // Search
      if (_searchQuery.isNotEmpty) {
        final match = log.patientName.toLowerCase().contains(_searchQuery) ||
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
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final log = logs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Patient Initials Avatar
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFEFF6FF),
                child: Text(
                  log.patientName.isNotEmpty ? log.patientName[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2563EB)),
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
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      '${log.phone}  •  ${log.email.isNotEmpty ? log.email : "No Email"}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                      const Icon(Icons.email_outlined, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      _buildStatusBadge(log.emailStatus, log.emailError),
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
                      const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      _buildStatusBadge(log.whatsAppStatus, log.whatsAppError),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(RecipientDeliveryStatus status, String? error) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: status.color),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status.color),
          ),
        ],
      ),
    );

    if (error != null && error.isNotEmpty) {
      return Tooltip(
        message: 'Reason: $error',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge,
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, size: 14, color: Color(0xFFDC2626)),
          ],
        ),
      );
    }

    return badge;
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
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.replay_rounded, size: 16),
              label: Text(_isRetrying ? 'Retrying...' : 'Retry Failed Dispatches (${_currentCampaign.totalFailed})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
