import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import '../data/models/campaign_model.dart';
import '../data/models/campaign_recipient_log.dart';
import '../data/models/campaign_enums.dart';
import '../data/repo/campaign_repository.dart';
import '../data/services/campaign_audience_helper.dart';
import '../data/services/campaign_dispatch_service.dart';
import 'mobile_post_campaign_sheet.dart';

/// Full mobile Campaign Management screen with KPI stats, search,
/// campaign status cards, and recipient delivery inspection.
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

  String get _currentDoctorId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Patient Campaigns',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF2563EB), size: 24),
            tooltip: 'Post Campaign',
            onPressed: () => MobilePostCampaignSheet.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => MobilePostCampaignSheet.show(context),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.campaign_rounded, size: 20),
        label: const Text('Post Campaign', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      body: StreamBuilder<List<CampaignModel>>(
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

          return CustomScrollView(
            slivers: [
              // Summary KPI Stats
              SliverToBoxAdapter(
                child: _buildSummaryKpi(allCampaigns),
              ),

              // Search & Filter Row
              SliverToBoxAdapter(
                child: _buildSearchAndFilter(),
              ),

              // Campaign Cards
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(allCampaigns.isEmpty),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final campaign = filtered[index];
                        return _buildMobileCampaignCard(campaign);
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryKpi(List<CampaignModel> campaigns) {
    int totalRecipients = 0;
    int totalEmails = 0;
    int totalWhatsApp = 0;
    for (final c in campaigns) {
      totalRecipients += c.totalRecipients;
      totalEmails += c.emailsSent;
      totalWhatsApp += c.whatsAppSent;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Broadcast Overview',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text(
                '${campaigns.length} Campaigns',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniKpi('Reached', '$totalRecipients', const Color(0xFF2563EB)),
              _buildMiniKpi('Emails', '$totalEmails', const Color(0xFF0284C7)),
              _buildMiniKpi('WhatsApp', '$totalWhatsApp', const Color(0xFF10B981)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniKpi(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          TextField(
            onChanged: (q) => setState(() => _searchQuery = q.trim().toLowerCase()),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search campaigns...',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.cardSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('All', style: TextStyle(fontSize: 11)),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                ),
                ...CampaignCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(cat.label, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategory = isSelected ? null : cat),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCampaignCard(CampaignModel campaign) {
    final cat = campaign.category;
    final successRate = campaign.successRate;
    final hasFailures = campaign.totalFailed > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRecipientLogsSheet(campaign),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Category & Status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 12, color: cat.color),
                        const SizedBox(width: 4),
                        Text(cat.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cat.color)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: campaign.status.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      campaign.status.label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: campaign.status.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                campaign.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                campaign.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
              ),
              const SizedBox(height: 12),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: successRate / 100.0,
                  minHeight: 5,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation(successRate >= 80 ? const Color(0xFF10B981) : const Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 8),

              // Stats & Tap Prompt
              Row(
                children: [
                  Text(
                    '📧 ${campaign.emailsSent} • 💬 ${campaign.whatsAppSent} sent',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  if (hasFailures) ...[
                    const SizedBox(width: 8),
                    Text('(${campaign.totalFailed} failed)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red)),
                  ],
                  const Spacer(),
                  const Text('Logs ➔', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecipientLogsSheet(CampaignModel campaign) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            // Sheet Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaign.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${campaign.totalRecipients} Recipients Targeted',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),

            // Logs Stream List
            Expanded(
              child: StreamBuilder<List<CampaignRecipientLog>>(
                stream: _campaignRepository.watchRecipientLogs(campaign.doctorId, campaign.id),
                builder: (context, snap) {
                  final logs = snap.data ?? [];
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (logs.isEmpty) {
                    return const Center(child: Text('No recipient logs found.', style: TextStyle(color: AppColors.textSecondary)));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
                              child: Text(
                                log.patientName.isNotEmpty ? log.patientName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(log.patientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                  Text('${log.phone} • ${log.email}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            if (campaign.channels.includesEmail)
                              _buildMiniBadge(log.emailStatus.label, log.emailStatus.color),
                            const SizedBox(width: 4),
                            if (campaign.channels.includesWhatsApp) ...[
                              _buildMiniBadge(log.whatsAppStatus.label, log.whatsAppStatus.color),
                              if (log.phone.trim().isNotEmpty) ...[
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => _openWhatsAppForRecipient(log, campaign),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.chat_rounded, size: 14, color: Color(0xFF10B981)),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            if (campaign.totalFailed > 0) ...[
              const Divider(height: 1, color: AppColors.divider),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _dispatchService.retryFailedRecipients(
                        doctorId: campaign.doctorId,
                        campaignId: campaign.id,
                      );
                      setState(() {});
                    },
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: Text('Retry Failed Recipients (${campaign.totalFailed})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openWhatsAppForRecipient(CampaignRecipientLog log, CampaignModel campaign) {
    final patient = Patient(
      id: log.patientId,
      firstName: log.patientName.split(' ').first,
      lastName: log.patientName.split(' ').length > 1
          ? log.patientName.split(' ').sublist(1).join(' ')
          : '',
      phone: log.phone,
      email: log.email,
      gender: '',
      dateOfBirth: DateTime.now(),
      diagnosis: const [],
      packageBalance: 0,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final waMessage = CampaignAudienceHelper.buildFormattedWhatsAppMessage(
      campaign.message,
      title: campaign.title,
      patient: patient,
      category: campaign.category,
      clinicName: 'CruDoc Healthcare',
      doctorName: 'Doctor',
      mediaUrl: campaign.mediaUrl,
    );

    final directUrl = WhatsAppTemplateService.buildWhatsAppDirectUrl(
      phone: log.phone,
      message: waMessage,
    );

    if (directUrl != null) {
      launchUrl(directUrl, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildEmptyState(bool isAllEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 54, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              isAllEmpty ? 'No Campaigns Yet' : 'No matching campaigns',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              isAllEmpty ? 'Post your first health advisory or checkup camp notice.' : 'Try changing your search term or filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (isAllEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => MobilePostCampaignSheet.show(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Post Campaign'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
