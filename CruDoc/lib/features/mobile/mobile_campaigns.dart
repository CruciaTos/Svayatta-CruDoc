import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/campaigns/data/models/campaign_enums.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_model.dart';
import 'package:doctor_management_app/features/campaigns/data/repo/campaign_repository.dart';
import 'package:doctor_management_app/features/campaigns/data/services/campaign_dispatch_service.dart';
import 'package:doctor_management_app/features/campaigns/presentation/campaign_analytics_dialog.dart';
import 'package:doctor_management_app/features/campaigns/presentation/mobile_post_campaign_sheet.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Campaigns on the phone: how many patients your messages reached, then
/// every campaign with its delivery. Tap one for its log, a retry of the
/// failed sends, or delete.
class MobileCampaignsPage extends StatefulWidget {
  const MobileCampaignsPage({super.key});

  @override
  State<MobileCampaignsPage> createState() => _MobileCampaignsPageState();
}

class _MobileCampaignsPageState extends State<MobileCampaignsPage> {
  final _repo = CampaignRepository();
  late final Stream<List<CampaignModel>> _stream = _repo.watchDoctorCampaigns(
    FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
  );

  CampaignStatus? _status;

  void _post() => MobilePostCampaignSheet.show(mobileRoot(context));

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return StreamBuilder<List<CampaignModel>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data;
        final reached = all?.fold<int>(0, (s, x) => s + x.totalRecipients) ?? 0;
        final sent = all?.fold<int>(0, (s, x) => s + x.totalSent) ?? 0;
        final failed = all?.fold<int>(0, (s, x) => s + x.totalFailed) ?? 0;
        final shown = all == null
            ? const <CampaignModel>[]
            : [
                for (final x in all)
                  if (_status == null || x.status == _status) x,
              ];
        final statuses = {for (final x in all ?? const []) x.status};

        return ListView(
          padding: EdgeInsets.only(
            bottom: MobileMetrics.navBottom(context) + CruSpace.s24,
          ),
          children: [
            MobileHeader(
              pushed: true,
              title: 'Campaigns',
              subtitle: 'Health notes to your patients on WhatsApp and email',
              trailing: MobileCircleButton(
                icon: CruIcons.plus,
                semanticLabel: 'Post a campaign',
                onPressed: _post,
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            if (all == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
                child: MobileCard(child: MobileLoading('Loading campaigns…')),
              )
            else if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileEmpty(
                  icon: CruIcons.megaphone,
                  title: 'No campaigns yet',
                  body:
                      'Send a vaccination drive, a camp notice or a '
                      'seasonal health tip to your patients.',
                  action: 'Post a campaign',
                  onAction: _post,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                  child: Row(
                    children: [
                      _Figure('Campaigns', '${all.length}', c.label),
                      _Figure('Reached', '$reached', c.label),
                      _Figure(
                        'Failed',
                        '$failed',
                        failed > 0
                            ? mobileTone(c, MobileTone.amber).$2
                            : c.label,
                        caption: '$sent sent',
                      ),
                    ],
                  ),
                ),
              ),
              if (statuses.length > 1) ...[
                const SizedBox(height: CruSpace.s16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MobileMetrics.gutter,
                  ),
                  child: Row(
                    children: [
                      MobileChip(
                        label: 'All',
                        count: all.length,
                        selected: _status == null,
                        onTap: () => setState(() => _status = null),
                      ),
                      for (final s in CampaignStatus.values)
                        if (statuses.contains(s)) ...[
                          const SizedBox(width: CruSpace.s8),
                          MobileChip(
                            label: s.label,
                            count: all.where((x) => x.status == s).length,
                            selected: _status == s,
                            onTap: () => setState(() => _status = s),
                          ),
                        ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              MobileRowGroup(
                children: [for (final x in shown) _CampaignRow(campaign: x)],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, this.color, {this.caption});

  final String label;
  final String value;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: MobileType.caption.tint(c.label2)),
          const SizedBox(height: CruSpace.s4),
          Text(value, style: MobileType.title2.tabular.tint(color)),
          if (caption != null)
            Text(caption!, style: MobileType.micro.tint(c.label3)),
        ],
      ),
    );
  }
}

class _CampaignRow extends StatelessWidget {
  const _CampaignRow({required this.campaign});

  final CampaignModel campaign;

  String get _channel => switch (campaign.channels) {
    CampaignChannel.email => 'Email',
    CampaignChannel.whatsapp => 'WhatsApp',
    CampaignChannel.both => 'WhatsApp & email',
  };

  void _sheet(BuildContext context) {
    final x = campaign;
    showMobileActionSheet(
      context,
      title: x.title,
      subtitle:
          '${x.category.label} · ${DashFormat.plural(x.totalRecipients, 'patient')}',
      leading: const MobileIconTile(
        icon: CruIcons.megaphone,
        tone: MobileTone.blue,
      ),
      actions: [
        MobileSheetAction(
          label: 'Delivery log',
          detail: '${x.totalSent} sent · ${x.totalFailed} failed',
          icon: CruIcons.fileText,
          tone: MobileTone.blue,
          onTap: () =>
              CampaignAnalyticsDialog.show(mobileRoot(context), campaign: x),
        ),
        if (x.totalFailed > 0)
          MobileSheetAction(
            label: 'Retry the failed sends',
            icon: CruIcons.play,
            tone: MobileTone.amber,
            onTap: () => CampaignDispatchService().retryFailedRecipients(
              doctorId: x.doctorId,
              campaignId: x.id,
            ),
          ),
        MobileSheetAction(
          label: 'Delete campaign',
          icon: CruIcons.close,
          destructive: true,
          onTap: () => showMobileActionSheet(
            context,
            title: 'Delete this campaign?',
            subtitle: 'Its delivery log goes with it.',
            actions: [
              MobileSheetAction(
                label: 'Delete',
                icon: CruIcons.close,
                destructive: true,
                onTap: () =>
                    CampaignRepository().deleteCampaign(x.doctorId, x.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = campaign;
    final failed = x.totalFailed > 0;
    return MobileRow(
      leading: const MobileIconTile(
        icon: CruIcons.megaphone,
        tone: MobileTone.blue,
      ),
      title: x.title.isEmpty ? 'Untitled campaign' : x.title,
      subtitle:
          '$_channel · ${DashFormat.shortDate(x.createdAt)} · '
          '${DashFormat.plural(x.totalRecipients, 'patient')}',
      trailing: MobilePill(
        failed ? '${x.totalFailed} failed' : x.status.label,
        tone: failed ? MobileTone.amber : MobileTone.green,
      ),
      onTap: () => _sheet(context),
      onLongPress: () => _sheet(context),
    );
  }
}
