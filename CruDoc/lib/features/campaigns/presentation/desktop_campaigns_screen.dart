import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_enums.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_dispatch_service.dart';
import 'post_campaign_modal.dart';
import 'campaign_analytics_dialog.dart';

// =============================================================================
// DESIGN TOKENS (Matching desktop consistency system)
// =============================================================================
const _kPrimaryAccent = Color(0xFF2563EB); // Royal cobalt blue
const _kAccentTint    = Color(0xFFEFF6FF);
const _kSuccessGreen  = Color(0xFF10B981);
const _kSuccessTint   = Color(0xFFECFDF5);
const _kDangerRose    = Color(0xFFF43F5E);
const _kDangerTint    = Color(0xFFFFF1F2);
const _kWarningAmber  = Color(0xFFF59E0B);
const _kWarningTint   = Color(0xFFFFFBEB);
const _kTextDark      = Color(0xFF0F172A);
const _kTextMedium    = Color(0xFF334155);
const _kTextMuted     = Color(0xFF64748B);
const _kBorderLight   = Color(0xFFE2E8F0);
const _kCardBg        = Colors.white;

/// Full desktop Campaign Management Hub screen.
class DesktopCampaignsScreen extends StatefulWidget {
  const DesktopCampaignsScreen({super.key});

  @override
  State<DesktopCampaignsScreen> createState() => _DesktopCampaignsScreenState();
}

class _DesktopCampaignsScreenState extends State<DesktopCampaignsScreen> {
  final CampaignRepository _campaignRepository = CampaignRepository();
  final CampaignDispatchService _dispatchService = CampaignDispatchService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  CampaignCategory? _selectedCategoryFilter;
  CampaignStatus? _selectedStatusFilter;

  String get _currentDoctorId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                width: 0.75,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C000000),
                  blurRadius: 20,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: StreamBuilder<List<CampaignModel>>(
              stream: _campaignRepository.watchDoctorCampaigns(_currentDoctorId),
              builder: (context, snapshot) {
                final allCampaigns = snapshot.data ?? [];
                final filteredCampaigns = _filterCampaigns(allCampaigns);

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header Bar
                      _buildHeaderSection(context),
                      const SizedBox(height: 18),

                      // 2. Summary KPI Metric Row (Clean no-icon value boxes)
                      _buildSummaryKpiRow(allCampaigns),
                      const SizedBox(height: 18),

                      // 3. Search & Filter Bar
                      _buildSearchAndFilters(),
                      const SizedBox(height: 16),

                      // 4. Campaign Cards List / Table
                      Expanded(
                        child: snapshot.connectionState == ConnectionState.waiting
                            ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kPrimaryAccent,
                                ),
                              )
                            : filteredCampaigns.isEmpty
                                ? _buildEmptyState(allCampaigns.isEmpty)
                                : _buildCampaignsList(filteredCampaigns),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER SECTION
  // ===========================================================================
  Widget _buildHeaderSection(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Campaigns & Broadcasts',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Publish health advisories, vaccination drives, and camp notices via Email & WhatsApp',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: _kTextMuted,
              ),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => PostCampaignModal.show(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Post Campaign'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimaryAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            elevation: 1,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. KPI SUMMARY ROW (Matching Financial Overview & Invoice Management)
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
    final successRate = totalAttempts > 0
        ? (totalSent / totalAttempts) * 100.0
        : 100.0;

    final isHealthy = successRate >= 90;
    final isModerate = successRate >= 70;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = (constraints.maxWidth - (16 * 3)) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _CampaignMetricCard(
              title: 'Total Campaigns',
              amount: '${campaigns.length}',
              subtitle: 'Broadcast campaigns',
              badgeText: 'Published',
              badgeColor: _kPrimaryAccent,
              badgeBg: _kAccentTint,
              width: width,
            ),
            _CampaignMetricCard(
              title: 'Patients Reached',
              amount: NumberFormat.compact().format(totalRecipients),
              subtitle: '$totalRecipients total targeted',
              badgeText: 'Audience',
              badgeColor: _kSuccessGreen,
              badgeBg: _kSuccessTint,
              width: width,
            ),
            _CampaignMetricCard(
              title: 'Delivery Rate',
              amount: '${successRate.toStringAsFixed(1)}%',
              subtitle: '$totalSent sent • $totalFailed failed',
              badgeText: isHealthy
                  ? 'Healthy'
                  : (isModerate ? 'Moderate' : 'Errors'),
              badgeColor: isHealthy
                  ? _kSuccessGreen
                  : (isModerate ? _kWarningAmber : _kDangerRose),
              badgeBg: isHealthy
                  ? _kSuccessTint
                  : (isModerate ? _kWarningTint : _kDangerTint),
              width: width,
            ),
            _CampaignMetricCard(
              title: 'Messages Dispatched',
              amount: '$totalSent',
              subtitle: '$totalEmails email • $totalWhatsApp WhatsApp',
              badgeText: 'Omnichannel',
              badgeColor: const Color(0xFF0284C7),
              badgeBg: const Color(0xFFF0F9FF),
              width: width,
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // 3. SEARCH & FILTERS BAR
  // ===========================================================================
  Widget _buildSearchAndFilters() {
    final bool hasActiveFilter =
        _selectedCategoryFilter != null || _selectedStatusFilter != null || _searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (q) =>
                    setState(() => _searchQuery = q.trim().toLowerCase()),
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  color: _kTextDark,
                ),
                decoration: InputDecoration(
                  hintText: 'Search campaigns by title, topic, or message...',
                  hintStyle: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 13,
                    color: _kTextMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: _kTextMuted,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16, color: _kTextMuted),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kPrimaryAccent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Category Dropdown Filter
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorderLight),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CampaignCategory?>(
                value: _selectedCategoryFilter,
                hint: const Text(
                  'All Categories',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12.5,
                    color: _kTextMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _kTextMuted),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All Categories'),
                  ),
                  ...CampaignCategory.values.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c.label)),
                  ),
                ],
                onChanged: (cat) => setState(() => _selectedCategoryFilter = cat),
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12.5,
                  color: _kTextDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Status Dropdown Filter
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorderLight),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CampaignStatus?>(
                value: _selectedStatusFilter,
                hint: const Text(
                  'All Statuses',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12.5,
                    color: _kTextMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _kTextMuted),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Statuses')),
                  ...CampaignStatus.values.map(
                    (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                  ),
                ],
                onChanged: (s) => setState(() => _selectedStatusFilter = s),
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12.5,
                  color: _kTextDark,
                ),
              ),
            ),
          ),

          if (hasActiveFilter) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategoryFilter = null;
                  _selectedStatusFilter = null;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kDangerTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kDangerRose.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.filter_alt_off_rounded, size: 15, color: _kDangerRose),
                    SizedBox(width: 4),
                    Text(
                      'Reset',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kDangerRose,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<CampaignModel> _filterCampaigns(List<CampaignModel> all) {
    return all.where((c) {
      if (_searchQuery.isNotEmpty &&
          !c.title.toLowerCase().contains(_searchQuery) &&
          !c.message.toLowerCase().contains(_searchQuery) &&
          !c.category.label.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      if (_selectedCategoryFilter != null &&
          c.category != _selectedCategoryFilter) {
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
      physics: const BouncingScrollPhysics(),
      itemCount: campaigns.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Icon Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cat.color.withValues(alpha: 0.2)),
            ),
            child: Icon(cat.icon, color: cat.color, size: 22),
          ),
          const SizedBox(width: 16),

          // Main Campaign Details
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cat.label,
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cat.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Channel Badge
                    _buildChannelBadge(campaign.channels),
                    const SizedBox(width: 6),

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: campaign.status.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        campaign.status.label,
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: campaign.status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  campaign.title,
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  campaign.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 13,
                    color: _kTextMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: _kTextMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Published ${campaign.formattedCreatedAt}',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11.5,
                        color: _kTextMuted,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.people_outline_rounded,
                      size: 14,
                      color: _kTextMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Audience: ${campaign.audienceType.label}',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11.5,
                        color: _kTextMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // Delivery Health Progress Indicator
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Delivery Rate',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kTextMuted,
                      ),
                    ),
                    Text(
                      '${successRate.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: successRate >= 90
                            ? _kSuccessGreen
                            : (successRate > 50
                                ? _kWarningAmber
                                : _kDangerRose),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: successRate / 100.0,
                    minHeight: 6,
                    backgroundColor: _kBorderLight,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      successRate >= 90
                          ? _kSuccessGreen
                          : (successRate > 50 ? _kPrimaryAccent : _kDangerRose),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${campaign.emailsSent} Email • ${campaign.whatsAppSent} WhatsApp',
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _kTextMedium,
                  ),
                ),
                if (hasFailures)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${campaign.totalFailed} delivery error${campaign.totalFailed > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kDangerRose,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Action Buttons
          Column(
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    CampaignAnalyticsDialog.show(context, campaign: campaign),
                icon: const Icon(Icons.insights_rounded, size: 15),
                label: const Text('Logs'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kTextDark,
                  side: const BorderSide(color: _kBorderLight),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Delete Campaign?'),
                        content: const Text(
                          'This will delete the campaign record and its recipient delivery logs.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kDangerRose,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _campaignRepository.deleteCampaign(
                        campaign.doctorId,
                        campaign.id,
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (hasFailures)
                    const PopupMenuItem(
                      value: 'retry',
                      child: Row(
                        children: [
                          Icon(Icons.refresh_rounded, size: 16, color: _kPrimaryAccent),
                          SizedBox(width: 8),
                          Text('Retry Failed Recipients'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: _kDangerRose),
                        SizedBox(width: 8),
                        Text(
                          'Delete Campaign',
                          style: TextStyle(color: _kDangerRose),
                        ),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: _kTextMuted,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBadge(CampaignChannel channel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.6),
      ),
      child: Text(
        channel.label,
        style: const TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isCompletelyEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccentTint,
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 48,
                color: _kPrimaryAccent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCompletelyEmpty
                  ? 'No Campaigns Created Yet'
                  : 'No Campaigns Match Your Filters',
              style: const TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isCompletelyEmpty
                  ? 'Engage your patients with health checkup drives, vaccine notices, and health advisories.'
                  : 'Try clearing your search query or selecting "All Categories".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                color: _kTextMuted,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => PostCampaignModal.show(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Post First Campaign'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// REUSABLE METRIC VALUE BOX (Identical to Financial Overview & Invoice Management)
// =============================================================================
class _CampaignMetricCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final Color badgeBg;
  final double width;

  const _CampaignMetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.clamp(230.0, double.infinity),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderLight, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Metric title
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: _kTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Big bold number
          Text(
            amount,
            style: const TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _kTextDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Bottom row: Subtitle & status pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: _kTextMuted,
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
