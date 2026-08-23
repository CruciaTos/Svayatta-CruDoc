import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_recipient_log.dart';
import '../data/models/campaign_enums.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_dispatch_service.dart';
import 'mobile_post_campaign_sheet.dart';

/// CruDoc Mobile Campaign Management Screen.
/// Seamlessly matches the app's clean typography, card surfaces, and color palette.
class MobileCampaignsScreen extends StatefulWidget {
  const MobileCampaignsScreen({super.key});

  @override
  State<MobileCampaignsScreen> createState() => _MobileCampaignsScreenState();
}

class _MobileCampaignsScreenState extends State<MobileCampaignsScreen> {
  final CampaignRepository _campaignRepository = CampaignRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();

  String _searchQuery = '';
  CampaignCategory? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => MobilePostCampaignSheet.show(context),
        backgroundColor: AppColors.chartBarLight,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.campaign_rounded, size: 20),
        label: const Text(
          'Post Campaign',
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------ Top Header Row ------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Patient Campaigns',
                    style: AppColors.pageHeading,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Health alerts & updates across Email & WhatsApp',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ------ Search & Category Filter Bar ------
              _buildSearchBar(),
              const SizedBox(height: 10),
              _buildCategoryChips(),
              const SizedBox(height: 12),

              // ------ Campaigns Stream List with Overview KPI ------
              Expanded(
                child: StreamBuilder<List<CampaignModel>>(
                  stream: _campaignRepository.watchDoctorCampaigns(_currentDoctorId),
                  builder: (context, snapshot) {
                    final allCampaigns = snapshot.data ?? [];
                    final filtered = allCampaigns.where((c) {
                      if (_searchQuery.isNotEmpty && !c.title.toLowerCase().contains(_searchQuery)) {
                        return false;
                      }
                      if (_selectedCategory != null && c.category != _selectedCategory) {
                        return false;
                      }
                      return true;
                    }).toList();

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.chartBarLight),
                      );
                    }

                    return CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // Section Heading
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedCategory == null
                                      ? 'All Broadcasts (${filtered.length})'
                                      : '${_selectedCategory!.label} (${filtered.length})',
                                  style: AppColors.pageHeading.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (allCampaigns.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.positiveGreen.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${allCampaigns.where((c) => c.status == CampaignStatus.completed).length} delivered',
                                      style: const TextStyle(
                                        fontFamily: AppColors.bodyFontFamily,
                                        fontSize: 11.5,
                                        color: AppColors.positiveGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Empty State or Campaign Cards
                        if (filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(allCampaigns.isEmpty),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.only(bottom: 80),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final campaign = filtered[index];
                                  return _buildCampaignCard(campaign);
                                },
                                childCount: filtered.length,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SEARCH BAR (Matching CruDoc SearchBar style)
  // ===========================================================================
  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (q) => setState(() => _searchQuery = q.trim().toLowerCase()),
        style: AppColors.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search campaigns by title...',
          hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.slateBlue),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
    );
  }

  // ===========================================================================
  // CATEGORY FILTER CHIPS (High-Contrast & Highly Visible)
  // ===========================================================================
  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildChip(
            label: 'All Categories',
            icon: Icons.grid_view_rounded,
            color: AppColors.chartBarLight,
            isSelected: _selectedCategory == null,
            onTap: () => setState(() => _selectedCategory = null),
          ),
          ...CampaignCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            return _buildChip(
              label: cat.label,
              icon: cat.icon,
              color: cat.color,
              isSelected: isSelected,
              onTap: () {
                setState(() => _selectedCategory = isSelected ? null : cat);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? color
                  : color.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withValues(alpha: 0.28)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: isSelected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CAMPAIGN CARD (Complementing CruDoc Card Style)
  // ===========================================================================
  Widget _buildCampaignCard(CampaignModel campaign) {
    final cat = campaign.category;
    final successRate = campaign.successRate;
    final hasFailures = campaign.totalFailed > 0;
    final formattedDate = DateFormat('d MMM yyyy • h:mm a').format(campaign.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showRecipientLogsSheet(campaign),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Pill & Status Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cat.color.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.icon, size: 14, color: cat.color),
                          const SizedBox(width: 5),
                          Text(
                            cat.label,
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cat.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: campaign.status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: campaign.status.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            campaign.status.label,
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: campaign.status.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                Text(
                  campaign.title,
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),

                // Message Preview Snippet
                Text(
                  campaign.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),

                // Delivery Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: successRate / 100.0,
                    minHeight: 5,
                    backgroundColor: AppColors.inputBackground,
                    valueColor: AlwaysStoppedAnimation(
                      hasFailures ? const Color(0xFFF59E0B) : AppColors.chartBarLight,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Footer Row: Channels, Metrics, and Inspect Prompt
                Row(
                  children: [
                    if (campaign.channels.includesEmail)
                      _buildChannelPill(
                        'Email: ${campaign.emailsSent}',
                        Icons.email_outlined,
                        const Color(0xFF2563EB),
                      ),
                    if (campaign.channels.includesEmail && campaign.channels.includesWhatsApp)
                      const SizedBox(width: 6),
                    if (campaign.channels.includesWhatsApp)
                      _buildChannelPill(
                        'WA: ${campaign.whatsAppSent}',
                        Icons.chat_bubble_outline_rounded,
                        const Color(0xFF10B981),
                      ),
                    if (hasFailures) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${campaign.totalFailed} failed',
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Inspect Logs',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.chartBarLight,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.chartBarLight),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Timestamp Subtext
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
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

  Widget _buildChannelPill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // RECIPIENT LOGS SHEET (Matching CruDoc Sheet Style)
  // ===========================================================================
  void _showRecipientLogsSheet(CampaignModel campaign) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RecipientLogsModalContent(
        campaign: campaign,
        campaignRepository: _campaignRepository,
        dispatchService: _dispatchService,
      ),
    );
  }

  // ===========================================================================
  // EMPTY STATE
  // ===========================================================================
  Widget _buildEmptyState(bool isAllEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.chartBarLight.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_outlined, size: 48, color: AppColors.chartBarLight),
            ),
            const SizedBox(height: 16),
            Text(
              isAllEmpty ? 'No Campaigns Yet' : 'No matching campaigns',
              style: const TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isAllEmpty
                  ? 'Broadcast health advisories, vaccination drives, and checkup camps to your patients via Email & WhatsApp.'
                  : 'Try clearing your search term or category filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (isAllEmpty) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => MobilePostCampaignSheet.show(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Post Your First Campaign'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.chartBarLight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RECIPIENT LOGS MODAL CONTENT WIDGET
// =============================================================================
class _RecipientLogsModalContent extends StatefulWidget {
  const _RecipientLogsModalContent({
    required this.campaign,
    required this.campaignRepository,
    required this.dispatchService,
  });

  final CampaignModel campaign;
  final CampaignRepository campaignRepository;
  final CampaignDispatchService dispatchService;

  @override
  State<_RecipientLogsModalContent> createState() => _RecipientLogsModalContentState();
}

class _RecipientLogsModalContentState extends State<_RecipientLogsModalContent> {
  String _filter = 'all'; // 'all', 'failed', 'delivered'
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.silver.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.title,
                        style: const TextStyle(
                          fontFamily: AppColors.headingFontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${campaign.totalRecipients} targeted • ${campaign.successRate.toStringAsFixed(0)}% delivered',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Filter Segmented Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildFilterTab('All (${campaign.totalRecipients})', 'all'),
                const SizedBox(width: 8),
                _buildFilterTab('Failed (${campaign.totalFailed})', 'failed'),
                const SizedBox(width: 8),
                _buildFilterTab('Delivered (${campaign.totalSent})', 'delivered'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),

          // Stream of Recipient Delivery Logs
          Expanded(
            child: StreamBuilder<List<CampaignRecipientLog>>(
              stream: widget.campaignRepository.watchRecipientLogs(campaign.doctorId, campaign.id),
              builder: (context, snap) {
                final logs = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.chartBarLight),
                  );
                }

                final filteredLogs = logs.where((log) {
                  if (_filter == 'failed') {
                    return log.hasFailed;
                  } else if (_filter == 'delivered') {
                    return log.isSuccessful;
                  }
                  return true;
                }).toList();

                if (filteredLogs.isEmpty) {
                  return Center(
                    child: Text(
                      _filter == 'failed' ? 'No failed recipients!' : 'No recipients found.',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredLogs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (context, i) {
                    final log = filteredLogs[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.chartBarLight.withValues(alpha: 0.1),
                            child: Text(
                              log.patientName.isNotEmpty ? log.patientName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontFamily: AppColors.headingFontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.chartBarLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log.patientName,
                                  style: const TextStyle(
                                    fontFamily: AppColors.bodyFontFamily,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${log.phone.isNotEmpty ? log.phone : 'No Phone'} • ${log.email.isNotEmpty ? log.email : 'No Email'}',
                                  style: const TextStyle(
                                    fontFamily: AppColors.bodyFontFamily,
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (log.hasFailed) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    log.emailError ?? log.whatsAppError ?? 'Delivery failed',
                                    style: const TextStyle(
                                      fontFamily: AppColors.bodyFontFamily,
                                      fontSize: 10,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (campaign.channels.includesEmail)
                            _buildDeliveryBadge(log.emailStatus.label, log.emailStatus.color),
                          const SizedBox(width: 4),
                          if (campaign.channels.includesWhatsApp)
                            _buildDeliveryBadge(log.whatsAppStatus.label, log.whatsAppStatus.color),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Bottom Retry Action (if any failures exist)
          if (campaign.totalFailed > 0) ...[
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isRetrying
                      ? null
                      : () async {
                          setState(() => _isRetrying = true);
                          try {
                            await widget.dispatchService.retryFailedRecipients(
                              doctorId: campaign.doctorId,
                              campaignId: campaign.id,
                            );
                          } finally {
                            if (mounted) setState(() => _isRetrying = false);
                          }
                        },
                  icon: _isRetrying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.replay_rounded, size: 18),
                  label: Text(_isRetrying
                      ? 'Retrying Dispatches...'
                      : 'Retry Failed Recipients (${campaign.totalFailed})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.chartBarLight.withValues(alpha: 0.12) : AppColors.inputBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.chartBarLight : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.chartBarLight : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
