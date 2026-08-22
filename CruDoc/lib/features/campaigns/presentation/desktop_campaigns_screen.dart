import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_enums.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_dispatch_service.dart';
import 'post_campaign_modal.dart';
import 'campaign_analytics_dialog.dart';

/// Full desktop Campaign Management Hub screen.
class DesktopCampaignsScreen extends StatefulWidget {
  const DesktopCampaignsScreen({super.key});

  @override
  State<DesktopCampaignsScreen> createState() => _DesktopCampaignsScreenState();
}

class _DesktopCampaignsScreenState extends State<DesktopCampaignsScreen> {
  final CampaignRepository _campaignRepository = CampaignRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();

  String _searchQuery = '';
  CampaignCategory? _selectedCategoryFilter;
  CampaignStatus? _selectedStatusFilter;

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: StreamBuilder<List<CampaignModel>>(
          stream: _campaignRepository.watchDoctorCampaigns(_currentDoctorId),
          builder: (context, snapshot) {
            final allCampaigns = snapshot.data ?? [];
            final filteredCampaigns = _filterCampaigns(allCampaigns);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Header with "Post Campaign" Button
                _buildHeaderBar(context),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),

                // 2. Summary KPI Metric Tiles
                _buildSummaryKpiRow(allCampaigns),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),

                // 3. Search & Filter Bar
                _buildSearchAndFilters(),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),

                // 4. Campaign Cards List / Table
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : filteredCampaigns.isEmpty
                          ? _buildEmptyState(allCampaigns.isEmpty)
                          : _buildCampaignsList(filteredCampaigns),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER BAR
  // ===========================================================================
  Widget _buildHeaderBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Campaign Management & Patient Broadcasts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Publish health advisories, vaccination drives, and camp notices via Email & WhatsApp',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          // Prominent "Post Campaign" Button
          ElevatedButton.icon(
            onPressed: () => PostCampaignModal.show(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'Post Campaign',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. KPI SUMMARY ROW
  // ===========================================================================
  Widget _buildSummaryKpiRow(List<CampaignModel> campaigns) {
    int totalRecipients = 0;
    int totalEmails = 0;
    int totalWhatsApp = 0;
    int totalFailed = 0;

    for (final c in campaigns) {
      totalRecipients += c.totalRecipients;
      totalEmails += c.emailsSent;
      totalWhatsApp += c.whatsAppSent;
      totalFailed += c.totalFailed;
    }

    final totalSent = totalEmails + totalWhatsApp;
    final totalAttempts = totalSent + totalFailed;
    final successRate = totalAttempts > 0 ? (totalSent / totalAttempts) * 100.0 : 100.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          _buildKpiTile('Total Campaigns', '${campaigns.length}', Icons.auto_stories_rounded, const Color(0xFF0F172A)),
          _buildKpiTile('Patients Reached', '$totalRecipients', Icons.groups_rounded, const Color(0xFF2563EB)),
          _buildKpiTile('Overall Delivery Rate', '${successRate.toStringAsFixed(1)}%', Icons.check_circle_rounded, const Color(0xFF16A34A)),
          _buildKpiTile('Emails Sent', '$totalEmails', Icons.email_rounded, const Color(0xFF0284C7)),
          _buildKpiTile('WhatsApp Sent', '$totalWhatsApp', Icons.chat_rounded, const Color(0xFF059669)),
        ],
      ),
    );
  }

  Widget _buildKpiTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. SEARCH & FILTERS
  // ===========================================================================
  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                onChanged: (q) => setState(() => _searchQuery = q.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search campaigns by title or topic...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Category Dropdown
          DropdownButton<CampaignCategory?>(
            value: _selectedCategoryFilter,
            hint: const Text('All Categories', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Categories')),
              ...CampaignCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))),
            ],
            onChanged: (cat) => setState(() => _selectedCategoryFilter = cat),
          ),
          const SizedBox(width: 12),

          // Status Dropdown
          DropdownButton<CampaignStatus?>(
            value: _selectedStatusFilter,
            hint: const Text('All Statuses', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Statuses')),
              ...CampaignStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))),
            ],
            onChanged: (s) => setState(() => _selectedStatusFilter = s),
          ),
        ],
      ),
    );
  }

  List<CampaignModel> _filterCampaigns(List<CampaignModel> all) {
    return all.where((c) {
      if (_searchQuery.isNotEmpty && !c.title.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      if (_selectedCategoryFilter != null && c.category != _selectedCategoryFilter) {
        return false;
      }
      if (_selectedStatusFilter != null && c.status != _selectedStatusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  // ===========================================================================
  // 4. CAMPAIGNS LIST
  // ===========================================================================
  Widget _buildCampaignsList(List<CampaignModel> campaigns) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      itemCount: campaigns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final campaign = campaigns[index];
        return _buildCampaignCard(context, campaign);
      },
    );
  }

  Widget _buildCampaignCard(BuildContext context, CampaignModel campaign) {
    final cat = campaign.category;
    final successRate = campaign.successRate;
    final hasFailures = campaign.totalFailed > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cat.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(cat.icon, color: cat.color, size: 24),
          ),
          const SizedBox(width: 16),

          // Main Info
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cat.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cat.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cat.color),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildChannelBadge(campaign.channels),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: campaign.status.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        campaign.status.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: campaign.status.color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  campaign.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  campaign.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      'Published ${campaign.formattedCreatedAt}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.groups_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      'Audience: ${campaign.audienceType.label}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // Delivery Stats
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Delivery Rate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                    Text(
                      '${successRate.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: successRate >= 90 ? const Color(0xFF16A34A) : (successRate > 50 ? const Color(0xFFD97706) : const Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: successRate / 100.0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      successRate >= 90 ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '📧 ${campaign.emailsSent} sent • 💬 ${campaign.whatsAppSent} sent',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
                if (hasFailures)
                  Text(
                    '⚠️ ${campaign.totalFailed} delivery errors',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Actions
          Column(
            children: [
              OutlinedButton.icon(
                onPressed: () => CampaignAnalyticsDialog.show(context, campaign: campaign),
                icon: const Icon(Icons.insights_rounded, size: 16),
                label: const Text('View Logs'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 6),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'retry') {
                    await _dispatchService.retryFailedRecipients(
                      doctorId: campaign.doctorId,
                      campaignId: campaign.id,
                    );
                    setState(() {});
                  } else if (v == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Campaign?'),
                        content: const Text('This will delete the campaign record and its recipient delivery logs.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _campaignRepository.deleteCampaign(campaign.doctorId, campaign.id);
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (hasFailures)
                    const PopupMenuItem(value: 'retry', child: Text('Retry Failed Recipients')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Campaign', style: TextStyle(color: Colors.red))),
                ],
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBadge(CampaignChannel channel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        channel.label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
      ),
    );
  }

  Widget _buildEmptyState(bool isCompletelyEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEFF6FF),
              ),
              child: const Icon(Icons.campaign_outlined, size: 54, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 18),
            Text(
              isCompletelyEmpty ? 'No Campaigns Created Yet' : 'No Campaigns Match Your Filters',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            Text(
              isCompletelyEmpty
                  ? 'Engage your patients with health checkup drives, vaccine notices, and health advisories.'
                  : 'Try clearing your search query or selecting "All Categories".',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => PostCampaignModal.show(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Post First Campaign'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
