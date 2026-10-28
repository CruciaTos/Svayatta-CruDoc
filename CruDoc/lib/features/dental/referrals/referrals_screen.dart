import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_pdf.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_share_flows.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _ReferralTab { sent, received, completed }

/// Sidebar screen for managing all dental referrals.
class ReferralsScreen extends ConsumerStatefulWidget {
  const ReferralsScreen({super.key});

  @override
  ConsumerState<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends ConsumerState<ReferralsScreen> {
  _ReferralTab _tab = _ReferralTab.sent;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final referrals = ref.watch(allReferralsProvider);
    final sharesError = ref.watch(referralSharesErrorProvider);
    final patients =
        ref.watch(patientsStreamProvider).value ?? const <Patient>[];

    // Compute glance metrics
    final openSent = referrals
        .where((r) => r.direction == ReferralDirection.out && r.status.isOpen)
        .length;
    final waitingReply = referrals
        .where(
          (r) =>
              r.direction == ReferralDirection.out &&
              (r.status == ReferralStatus.sent ||
                  r.status == ReferralStatus.acknowledged),
        )
        .length;
    final receivedToSee = referrals
        .where(
          (r) => r.direction == ReferralDirection.inbound && r.status.isOpen,
        )
        .length;

    final now = DateTime.now();
    final completedThisMonth = referrals
        .where(
          (r) =>
              r.status == ReferralStatus.completed &&
              r.recordedAt.year == now.year &&
              r.recordedAt.month == now.month,
        )
        .length;

    final totalOpen = referrals.where((r) => r.status.isOpen).length;
    final urgentOpen = referrals
        .where((r) => r.status.isOpen && r.urgency == ReferralUrgency.urgent)
        .length;
    final subtitle = [
      '$totalOpen open',
      if (urgentOpen > 0) '$urgentOpen urgent',
    ].join(' · ');

    // Filter referrals by tab and search
    final query = _search.text.trim().toLowerCase();
    final filtered = referrals.where((r) {
      if (_tab == _ReferralTab.sent &&
          (r.direction != ReferralDirection.out || !r.status.isOpen)) {
        return false;
      }
      if (_tab == _ReferralTab.received &&
          (r.direction != ReferralDirection.inbound || !r.status.isOpen)) {
        return false;
      }
      if (_tab == _ReferralTab.completed && r.status.isOpen) return false;

      if (query.isNotEmpty) {
        final p = patients.where((p) => p.id == r.patientId).firstOrNull;
        final patientName = (p?.fullName ?? r.share?.patientName ?? '')
            .toLowerCase();
        final reason = r.reason.toLowerCase();
        final contact = r.contactName.toLowerCase();
        if (!patientName.contains(query) &&
            !reason.contains(query) &&
            !contact.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    Widget cell(String label, String value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value),
        GlanceCaption(caption),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: cruIsPhone(context)
            ? EdgeInsets.zero
            : desktopPagePadding(context).copyWith(bottom: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (with the page gutter on a phone)
            Padding(
              padding: cruIsPhone(context)
                  ? const EdgeInsets.fromLTRB(16, 8, 16, 0)
                  : EdgeInsets.zero,
              child: DentalPageHeader(
                title: 'Referrals',
                subtitle: subtitle.isNotEmpty
                    ? subtitle
                    : 'Track referrals sent to and received from other doctors',
                actions: [
                  CruButton(
                    label: 'Contacts',
                    icon: CruIcons.userPlus,
                    kind: CruButtonKind.secondary,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ContactDirectoryDialog(),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruButton(
                    label: 'New referral',
                    icon: CruIcons.plus,
                    kind: CruButtonKind.primary,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ReferralEditDialog(),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: cruIsPhone(context)
                    ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
                    : EdgeInsets.only(
                        top: CruSpace.cardGap,
                        bottom: desktopPagePadding(context).bottom,
                      ),
                children: [
                  // Glance strip
                  GlanceStrip(
                    semanticLabel: 'Referrals at a glance',
                    cells: [
                      cell(
                        'Open sent',
                        '$openSent',
                        const Text('Active sent referrals'),
                      ),
                      cell(
                        'Waiting for reply',
                        '$waitingReply',
                        const Text('Sent or acknowledged'),
                      ),
                      cell(
                        'Received to see',
                        '$receivedToSee',
                        const Text('Incoming referrals'),
                      ),
                      cell(
                        'Completed this month',
                        '$completedThisMonth',
                        const Text('This calendar month'),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s20),

                  // Controls row: Segments & Search
                  DentalFilterBar(
                    filters: [
                      CruSegmentedControl<_ReferralTab>(
                        semanticLabel: 'Filter referrals by status',
                        segments: const [
                          CruSegment(_ReferralTab.sent, 'Sent'),
                          CruSegment(_ReferralTab.received, 'Received'),
                          CruSegment(_ReferralTab.completed, 'Completed'),
                        ],
                        selected: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ],
                    search: DentalSearchField(
                      hint: 'Search patient, doctor, reason…',
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: CruSpace.cardGap),

                  // Referrals from other doctors couldn't be loaded: say so,
                  // rather than look like there are none.
                  if (sharesError != null) ...[
                    _SharesErrorCard(
                      message: sharesError,
                      onRetry: () {
                        ref.invalidate(incomingSharesProvider);
                        ref.invalidate(outgoingSharesProvider);
                      },
                    ),
                    const SizedBox(height: CruSpace.cardGap),
                  ],

                  // List or empty state
                  if (filtered.isEmpty)
                    desktopEmptyCard(
                      context,
                      DentalEmptyState(
                        icon: CruIcons.arrowUpRight,
                        title: query.isNotEmpty
                            ? 'No matching referrals'
                            : 'No referrals here',
                        body: query.isNotEmpty
                            ? 'Try changing your search terms or filters.'
                            : 'Refer a patient to a specialist or record an incoming referral.',
                        actions: query.isEmpty
                            ? [
                                CruButton(
                                  label: 'New referral',
                                  icon: CruIcons.plus,
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => const ReferralEditDialog(),
                                  ),
                                ),
                              ]
                            : const [],
                      ),
                    )
                  else
                    CruCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            if (i > 0) const CruSeparator(),
                            _ReferralListRow(
                              referral: filtered[i],
                              patient: patients
                                  .where((p) => p.id == filtered[i].patientId)
                                  .firstOrNull,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferralListRow extends ConsumerWidget {
  const _ReferralListRow({required this.referral, required this.patient});

  final DentalReferral referral;
  final Patient? patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final r = referral;
    final isOut = r.direction == ReferralDirection.out;

    final targetName = r.contactName.isNotEmpty
        ? r.contactName
        : (isOut ? 'Specialist' : 'Referring Doctor');
    final phone = cruIsPhone(context);
    final name = referralPatientLabel(r, patient);
    final shared = r.isShared;

    return DentalListRow(
      semanticLabel: '${r.reason} - $name',
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => shared
            ? SharedReferralDialog(referral: r)
            : ReferralEditDialog(initialReferral: r, initialPatient: patient),
      ),
      minHeight: 56,
      child: Row(
        children: [
          // Direction indicator icon
          CruIconTile(
            icon: isOut ? CruIcons.arrowUpRight : CruIcons.chevronLeft,
            tone: CruTileTone.neutral,
          ),
          const SizedBox(width: CruSpace.s12),

          // Phone: patient over "To / From · reason", then the status.
          if (phone) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  Text(
                    '${isOut ? 'To' : 'From'} $targetName · ${r.reason}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tint(c.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
          ] else ...[
            // Date
            SizedBox(
              width: 80,
              child: Text(
                DentalFormat.date(r.recordedAt),
                style: CruType.caption.tabular.tint(c.label2),
              ),
            ),

            // Patient name
            SizedBox(
              width: 140,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.callout.w600.tint(c.label),
              ),
            ),
            const SizedBox(width: CruSpace.s12),

            // To or from contact
            SizedBox(
              width: 160,
              child: Text(
                '${isOut ? 'To: ' : 'From: '}$targetName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.note.tint(c.label2),
              ),
            ),
            const SizedBox(width: CruSpace.s12),

            // Reason
            Expanded(
              child: Text(
                r.reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.callout.tint(c.label),
              ),
            ),
            const SizedBox(width: CruSpace.s8),

            // Urgency pill (urgent is amber; red is strictly reserved for safety/allergies)
            if (r.urgency == ReferralUrgency.urgent)
              CruPill(
                text: 'Urgent',
                background: c.amberTint,
                foreground: c.amberText,
              )
            else if (r.urgency == ReferralUrgency.soon)
              CruPill(text: 'Soon', background: c.inset, foreground: c.label2),
            const SizedBox(width: CruSpace.s8),
          ],

          if (shared) ...[
            CruPill(
              text: 'CruDoc',
              background: c.accentTint,
              foreground: c.accent,
            ),
            const SizedBox(width: CruSpace.s8),
          ],

          // Status pill
          CruPill(
            text: r.status.label,
            background: r.status == ReferralStatus.completed
                ? c.greenTint
                : (r.status == ReferralStatus.sent ||
                          r.status == ReferralStatus.seen
                      ? c.accentTint
                      : c.inset),
            foreground: r.status == ReferralStatus.completed
                ? c.greenText
                : (r.status == ReferralStatus.sent ||
                          r.status == ReferralStatus.seen
                      ? c.accent
                      : c.label2),
          ),
          const SizedBox(width: CruSpace.s8),

          // WhatsApp Capsule button (in the menu on a phone)
          if (patient != null && !phone && !shared)
            CruCapsuleButton(
              label: 'WhatsApp',
              icon: CruIcons.phone,
              onPressed: () => sendReferralWhatsApp(context, ref, r, patient!),
            ),
          const SizedBox(width: CruSpace.s4),

          // Menu button
          PopupMenuButton<String>(
            tooltip: 'Actions',
            icon: CruIcon(CruIcons.more, size: 18, color: c.label2),
            itemBuilder: (ctx) => [
              if (shared) ...[
                const PopupMenuItem(value: 'open', child: Text('Open')),
                if (!isOut &&
                    r.isUnfiledShare &&
                    r.status != ReferralStatus.withdrawn)
                  const PopupMenuItem(
                    value: 'file',
                    child: Text('Add to my patients'),
                  ),
                if (!isOut && patient != null)
                  const PopupMenuItem(
                    value: 'bookVisit',
                    child: Text('Book visit'),
                  ),
                if (isOut && r.status.isOpen)
                  const PopupMenuItem(
                    value: 'withdraw',
                    child: Text('Withdraw'),
                  ),
                if (patient != null)
                  PopupMenuItem(
                    value: 'pdf',
                    child: Text(isOut ? 'Letter (PDF)' : 'Summary (PDF)'),
                  ),
                if (!r.isUnfiledShare)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete from my records'),
                  ),
              ] else ...[
                if (isOut &&
                    r.status == ReferralStatus.draft &&
                    patient != null) ...[
                  const PopupMenuItem(value: 'send', child: Text('Send…')),
                  const PopupMenuDivider(),
                ],
                if (phone && patient != null) ...[
                  const PopupMenuItem(
                    value: 'whatsapp',
                    child: Text('Send on WhatsApp'),
                  ),
                  const PopupMenuDivider(),
                ],
                if (isOut) ...[
                  if (r.status != ReferralStatus.acknowledged)
                    const PopupMenuItem(
                      value: 'acknowledged',
                      child: Text('Mark acknowledged'),
                    ),
                  if (r.status != ReferralStatus.seen)
                    const PopupMenuItem(
                      value: 'seen',
                      child: Text('Mark seen'),
                    ),
                  if (r.status != ReferralStatus.completed)
                    const PopupMenuItem(
                      value: 'completed',
                      child: Text('Mark completed'),
                    ),
                  if (r.status != ReferralStatus.declined)
                    const PopupMenuItem(
                      value: 'declined',
                      child: Text('Declined'),
                    ),
                  const PopupMenuItem(
                    value: 'pdf',
                    child: Text('Letter (PDF)'),
                  ),
                ] else ...[
                  if (patient != null)
                    const PopupMenuItem(
                      value: 'bookVisit',
                      child: Text('Book visit'),
                    ),
                  const PopupMenuItem(
                    value: 'reply',
                    child: Text('Write reply'),
                  ),
                  if (r.status != ReferralStatus.completed)
                    const PopupMenuItem(
                      value: 'completed',
                      child: Text('Mark completed'),
                    ),
                  const PopupMenuItem(
                    value: 'pdf',
                    child: Text('Summary (PDF)'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete referral'),
                ),
              ],
            ],
            onSelected: (action) async {
              switch (action) {
                case 'open':
                  await showDialog<void>(
                    context: context,
                    builder: (_) => SharedReferralDialog(referral: r),
                  );
                  break;
                case 'file':
                  await fileSharedReferral(context, ref, r);
                  break;
                case 'withdraw':
                  final ok = await confirmDental(
                    context,
                    title: 'Withdraw this referral?',
                    body:
                        '${drName(targetName)} will no longer see the patient\'s details or files.',
                    action: 'Withdraw',
                  );
                  if (ok && context.mounted) {
                    await runShareStep(
                      context,
                      r,
                      ShareStep.withdraw,
                      done: 'Referral withdrawn',
                    );
                  }
                  break;
                case 'send':
                  if (patient != null) {
                    await sendDraftReferral(context, ref, r, patient!);
                  }
                  break;
                case 'whatsapp':
                  if (patient != null) {
                    await sendReferralWhatsApp(context, ref, r, patient!);
                  }
                  break;
                case 'acknowledged':
                  await updateReferralStatus(
                    ref,
                    r,
                    ReferralStatus.acknowledged,
                  );
                  break;
                case 'seen':
                  await updateReferralStatus(ref, r, ReferralStatus.seen);
                  break;
                case 'completed':
                  await updateReferralStatus(ref, r, ReferralStatus.completed);
                  break;
                case 'declined':
                  await updateReferralStatus(ref, r, ReferralStatus.declined);
                  break;
                case 'reply':
                  await showDialog<void>(
                    context: context,
                    builder: (_) => WriteReplyDialog(referral: r),
                  );
                  break;
                case 'bookVisit':
                  if (patient != null) {
                    await PatientActions.newVisit(context, ref, patient!);
                  }
                  break;
                case 'pdf':
                  if (patient != null) {
                    await ReferralPdfService.printOrPreview(
                      context: context,
                      ref: ref,
                      referral: r,
                      patient: patient!,
                      isReply: !isOut,
                    );
                  }
                  break;
                case 'delete':
                  final withdraws = shared && isOut && r.status.isOpen;
                  final ok = await confirmDental(
                    context,
                    title: 'Delete referral?',
                    body: withdraws
                        ? 'This withdraws it from ${drName(targetName)} and removes it from your records.'
                        : 'This will remove the referral for $name from your records.',
                    action: 'Delete',
                  );
                  if (ok && context.mounted) {
                    if (withdraws &&
                        !await runShareStep(context, r, ShareStep.withdraw)) {
                      break;
                    }
                    await deleteDentalRecord(ref, r.record);
                    if (context.mounted) recToast(context, 'Referral deleted');
                  }
                  break;
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Referrals sent to or from other doctors in CruDoc couldn't be loaded:
/// why, and Retry.
class _SharesErrorCard extends StatelessWidget {
  const _SharesErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: "Couldn't load referrals from other doctors",
      child: Row(
        children: [
          CruIcon(CruIcons.warning, size: 18, color: c.label2),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't load referrals from other doctors",
                  style: CruType.callout.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(message, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

/// The patient a referral is about: this clinic's patient, or the name the
/// referring doctor sent for one not filed here yet.
String referralPatientLabel(DentalReferral r, Patient? patient) {
  if (patient != null) return patient.fullName;
  final shared = r.share?.patientName ?? '';
  if (shared.trim().isNotEmpty) return shared;
  if (r.status == ReferralStatus.withdrawn) return 'Withdrawn referral';
  return r.patientId.length >= 4
      ? 'Patient #${r.patientId.substring(0, 4)}'
      : 'Patient';
}

/// Sends a saved draft: in CruDoc (after the patient's consent) when the
/// contact is on CruDoc, else by WhatsApp, email or an invitation.
Future<void> sendDraftReferral(
  BuildContext context,
  WidgetRef ref,
  DentalReferral referral,
  Patient patient,
) async {
  final contact = ref
      .read(referralContactsProvider)
      .where((c) => c.id == referral.contactId)
      .firstOrNull;
  if (contact == null) {
    recToast(context, 'Pick who to refer to first: open the referral to edit');
    return;
  }
  if (!contact.onCruDoc) {
    await showDialog<void>(
      context: context,
      builder: (_) => ReferralSendOptionsDialog(
        referral: referral,
        patient: patient,
        contact: contact,
      ),
    );
    return;
  }
  final ok = await confirmDental(
    context,
    title: 'Send to ${drName(contact.crudocName)} in CruDoc?',
    body:
        'Only if ${patient.fullName} agreed: their name, contact details, '
        'findings and files go to this doctor, who gets a notification.',
    action: 'Patient agreed, send',
  );
  if (!ok || !context.mounted) return;
  try {
    await sendReferralInCruDoc(
      ref,
      referral: referral,
      patient: patient,
      contact: contact,
    );
    if (context.mounted) {
      recToast(context, 'Sent to ${drName(contact.crudocName)}');
    }
  } on ReferralNetworkException catch (e) {
    if (context.mounted) recToast(context, e.message);
  }
}
