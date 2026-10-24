import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/campaigns/data/models/campaign_enums.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_model.dart';
import 'package:doctor_management_app/features/campaigns/data/providers/campaign_providers.dart';
import 'package:doctor_management_app/features/campaigns/presentation/campaign_analytics_dialog.dart';
import 'package:doctor_management_app/features/campaigns/presentation/post_campaign_modal.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Campaigns on the desktop, laid out like the other pages: header with
/// the one filled button, the at-a-glance strip, filters and search, then
/// the campaigns in one card.
class DesktopCampaignsScreen extends ConsumerStatefulWidget {
  const DesktopCampaignsScreen({super.key});

  @override
  ConsumerState<DesktopCampaignsScreen> createState() =>
      _DesktopCampaignsScreenState();
}

class _DesktopCampaignsScreenState
    extends ConsumerState<DesktopCampaignsScreen> {
  final _search = TextEditingController();
  CampaignCategory? _category;
  CampaignStatus? _status;

  String get _doctorId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CampaignModel> _filter(List<CampaignModel> all) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final c in all)
        if ((q.isEmpty ||
                c.title.toLowerCase().contains(q) ||
                c.message.toLowerCase().contains(q) ||
                c.category.label.toLowerCase().contains(q)) &&
            (_category == null || c.category == _category) &&
            (_status == null || c.status == _status))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(campaignRepositoryProvider);
    return Padding(
      padding: desktopPagePadding(context),
      child: StreamBuilder<List<CampaignModel>>(
        stream: repo.watchDoctorCampaigns(_doctorId),
        builder: (context, snapshot) {
          final all = snapshot.data;
          final shown = all == null ? const <CampaignModel>[] : _filter(all);
          final filtering =
              _category != null ||
              _status != null ||
              _search.text.trim().isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DentalPageHeader(
                title: 'Campaigns',
                subtitle: all == null
                    ? ''
                    : all.isEmpty
                    ? 'Health notices to your patients by WhatsApp and email'
                    : _subtitle(all),
                actions: [
                  CruButton(
                    label: 'New campaign',
                    icon: CruIcons.plus,
                    onPressed: () => PostCampaignModal.show(context),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.cardGap),
              _Glance(campaigns: all ?? const []),
              const SizedBox(height: CruSpace.cardGap),
              DentalFilterBar(
                filters: [
                  _Menu<CampaignCategory>(
                    tooltip: 'Category',
                    allLabel: 'All categories',
                    value: _category,
                    values: CampaignCategory.values,
                    label: (c) => c.label,
                    onSelected: (c) => setState(() => _category = c),
                  ),
                  _Menu<CampaignStatus>(
                    tooltip: 'Status',
                    allLabel: 'All statuses',
                    value: _status,
                    values: CampaignStatus.values,
                    label: (s) => s.label,
                    onSelected: (s) => setState(() => _status = s),
                  ),
                  if (filtering)
                    CruLink(
                      label: 'Clear',
                      onPressed: () {
                        _search.clear();
                        setState(() {
                          _category = null;
                          _status = null;
                        });
                      },
                    ),
                ],
                search: DentalSearchField(
                  controller: _search,
                  hint: 'Search title, topic or message',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: CruSpace.cardGap),
              Expanded(
                child: all == null
                    ? const SizedBox.shrink()
                    : shown.isEmpty
                    // The empty card fills the list's space, like the
                    // other pages' lists do.
                    ? CruCard(
                        padding: const EdgeInsets.all(CruSpace.s12),
                        child: Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: CruIcons.megaphone,
                              title: all.isEmpty
                                  ? 'No campaigns yet'
                                  : 'No campaigns here',
                              body: all.isEmpty
                                  ? 'Send check-up drives, vaccine notices and '
                                        'health advisories to your patients.'
                                  : 'Try another filter or search.',
                              actions: [
                                if (all.isEmpty)
                                  CruButton(
                                    label: 'New campaign',
                                    icon: CruIcons.plus,
                                    onPressed: () =>
                                        PostCampaignModal.show(context),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : CruCard(
                        semanticLabel: 'Campaigns',
                        padding: const EdgeInsets.all(CruSpace.s12),
                        child: ListView.separated(
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => const CruSeparator(),
                          itemBuilder: (context, i) =>
                              _CampaignRow(campaign: shown[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _subtitle(List<CampaignModel> all) {
    final reached = all.fold<int>(0, (s, c) => s + c.totalRecipients);
    return [
      DashFormat.plural(all.length, 'campaign'),
      '${NumberFormat.decimalPattern('en_IN').format(reached)} patients reached',
    ].join(' · ');
  }
}

/// Campaigns, patients reached, delivery and messages sent.
class _Glance extends StatelessWidget {
  const _Glance({required this.campaigns});

  final List<CampaignModel> campaigns;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    var recipients = 0, emails = 0, whatsApp = 0, failed = 0;
    for (final x in campaigns) {
      recipients += x.totalRecipients;
      emails += x.emailsSent;
      whatsApp += x.whatsAppSent;
      failed += x.totalFailed;
    }
    final sent = emails + whatsApp;
    final attempts = sent + failed;
    final rate = attempts == 0 ? null : sent / attempts * 100;
    final number = NumberFormat.decimalPattern('en_IN');

    Widget cell(String label, String value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );

    return GlanceStrip(
      semanticLabel: 'Campaigns at a glance',
      cells: [
        cell(
          'Campaigns',
          '${campaigns.length}',
          Text(
            campaigns.isEmpty
                ? 'None sent yet'
                : '${campaigns.where((x) => x.status == CampaignStatus.completed).length} completed',
          ),
        ),
        cell(
          'Patients reached',
          number.format(recipients),
          const Text('Across all campaigns'),
        ),
        cell(
          'Delivered',
          rate == null ? '—' : '${rate.toStringAsFixed(0)}%',
          failed > 0
              ? Text(
                  '${number.format(failed)} not delivered',
                  style: TextStyle(color: c.amberText),
                )
              : Text(attempts == 0 ? 'Nothing sent yet' : 'All delivered'),
        ),
        cell(
          'Messages sent',
          number.format(sent),
          Text('$emails email · $whatsApp WhatsApp'),
        ),
      ],
    );
  }
}

/// An inset menu button ("All categories ⌄"), like the worklist's type.
class _Menu<T> extends StatelessWidget {
  const _Menu({
    required this.tooltip,
    required this.allLabel,
    required this.value,
    required this.values,
    required this.label,
    required this.onSelected,
  });

  final String tooltip;
  final String allLabel;
  final T? value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return PopupMenuButton<T?>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem<T?>(value: null, child: Text(allLabel)),
        for (final x in values)
          PopupMenuItem<T?>(value: x, child: Text(label(x))),
      ],
      child: IgnorePointer(
        child: CruButton(
          label: v == null ? allLabel : label(v),
          icon: CruIcons.chevronDown,
          kind: CruButtonKind.inset,
          onPressed: () {},
        ),
      ),
    );
  }
}

/// One campaign: what it was, to whom and when, how delivery went, and
/// its actions.
class _CampaignRow extends ConsumerWidget {
  const _CampaignRow({required this.campaign});

  final CampaignModel campaign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final x = campaign;
    final failed = x.totalFailed > 0;
    final (pillBg, pillFg) = switch (x.status) {
      CampaignStatus.completed => (c.greenTint, c.greenText),
      CampaignStatus.partiallyFailed ||
      CampaignStatus.failed => (c.amberTint, c.amberText),
      CampaignStatus.processing ||
      CampaignStatus.scheduled => (c.accentTint, c.accentText),
      CampaignStatus.draft => (c.inset, c.label2),
    };
    return DentalListRow(
      semanticLabel: x.title,
      onTap: () => CampaignAnalyticsDialog.show(context, campaign: x),
      minHeight: 64,
      child: Row(
        children: [
          CruIconTile(
            icon: x.channels == CampaignChannel.email
                ? CruIcons.megaphone
                : CruIcons.whatsapp,
            tone: CruTileTone.neutral,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  [
                    x.category.label,
                    x.channels.label,
                    x.audienceType.label,
                    DateFormat('d MMM, h:mm a').format(x.createdAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          SizedBox(
            width: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${x.emailsSent + x.whatsAppSent} of ${x.totalRecipients} sent',
                  style: CruType.callout.tabular.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  failed
                      ? '${x.totalFailed} not delivered'
                      : '${x.successRate.toStringAsFixed(0)}% delivered',
                  style: CruType.subhead.tabular.tint(
                    failed ? c.amberText : c.label2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          CruPill(text: x.status.label, background: pillBg, foreground: pillFg),
          const SizedBox(width: CruSpace.s4),
          _RowMenu(campaign: x),
        ],
      ),
    );
  }
}

/// Logs, retry and delete.
class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.campaign});

  final CampaignModel campaign;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this campaign?'),
        content: const Text(
          'Its record and the delivery log for each patient are removed.',
        ),
        actions: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CruButton(label: 'Delete', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(campaignRepositoryProvider)
          .deleteCampaign(campaign.doctorId, campaign.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = campaign.totalFailed > 0;
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) async {
        switch (v) {
          case 'logs':
            CampaignAnalyticsDialog.show(context, campaign: campaign);
          case 'retry':
            await ref
                .read(campaignDispatchServiceProvider)
                .retryFailedRecipients(
                  doctorId: campaign.doctorId,
                  campaignId: campaign.id,
                );
          case 'delete':
            if (context.mounted) await _delete(context, ref);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'logs', child: Text('Delivery log')),
        if (failed)
          const PopupMenuItem(
            value: 'retry',
            child: Text('Retry failed sends'),
          ),
        const PopupMenuItem(value: 'delete', child: Text('Delete campaign')),
      ],
      child: const IgnorePointer(
        child: CruIconButton(
          icon: CruIcons.more,
          semanticLabel: 'More',
          onPressed: null,
        ),
      ),
    );
  }
}
