import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_dialogs.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_pdf.dart';
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
    final c = context.cru;
    final referrals = ref.watch(allReferralsProvider);
    final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];

    // Compute glance metrics
    final openSent = referrals.where((r) => r.direction == ReferralDirection.out && r.status.isOpen).length;
    final waitingReply = referrals.where((r) =>
        r.direction == ReferralDirection.out &&
        (r.status == ReferralStatus.sent || r.status == ReferralStatus.acknowledged)).length;
    final receivedToSee = referrals.where((r) => r.direction == ReferralDirection.inbound && r.status.isOpen).length;

    final now = DateTime.now();
    final completedThisMonth = referrals.where((r) =>
        r.status == ReferralStatus.completed &&
        r.recordedAt.year == now.year &&
        r.recordedAt.month == now.month).length;

    final totalOpen = referrals.where((r) => r.status.isOpen).length;
    final urgentOpen = referrals.where((r) => r.status.isOpen && r.urgency == ReferralUrgency.urgent).length;
    final subtitle = [
      '$totalOpen open',
      if (urgentOpen > 0) '$urgentOpen urgent',
    ].join(' · ');

    // Filter referrals by tab and search
    final query = _search.text.trim().toLowerCase();
    final filtered = referrals.where((r) {
      if (_tab == _ReferralTab.sent && (r.direction != ReferralDirection.out || !r.status.isOpen)) return false;
      if (_tab == _ReferralTab.received && (r.direction != ReferralDirection.inbound || !r.status.isOpen)) return false;
      if (_tab == _ReferralTab.completed && r.status.isOpen) return false;

      if (query.isNotEmpty) {
        final p = patients.where((p) => p.id == r.patientId).firstOrNull;
        final patientName = p?.fullName.toLowerCase() ?? '';
        final reason = r.reason.toLowerCase();
        final contact = r.contactName.toLowerCase();
        if (!patientName.contains(query) && !reason.contains(query) && !contact.contains(query)) {
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
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          DentalPageHeader(
            title: 'Referrals',
            subtitle: subtitle.isNotEmpty ? subtitle : 'Track referrals sent to and received from other doctors',
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

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s24),
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
                Row(
                  children: [
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
                    const Spacer(),
                    SizedBox(
                      width: 280,
                      child: DentalSearchField(
                        hint: 'Search patient, doctor, reason…',
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s16),

                // List or empty state
                if (filtered.isEmpty)
                  DentalEmptyState(
                    icon: CruIcons.arrowUpRight,
                    title: query.isNotEmpty ? 'No matching referrals' : 'No referrals here',
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
                            patient: patients.where((p) => p.id == filtered[i].patientId).firstOrNull,
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
    );
  }
}

class _ReferralListRow extends ConsumerWidget {
  const _ReferralListRow({
    required this.referral,
    required this.patient,
  });

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

    return DentalListRow(
      semanticLabel: '${r.reason} - ${patient?.fullName ?? 'Patient'}',
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => ReferralEditDialog(
          initialReferral: r,
          initialPatient: patient,
        ),
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
              patient?.fullName ?? 'Patient #${r.patientId.substring(0, 4)}',
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
            CruPill(
              text: 'Soon',
              background: c.inset,
              foreground: c.label2,
            ),
          const SizedBox(width: CruSpace.s8),

          // Status pill
          CruPill(
            text: r.status.label,
            background: r.status == ReferralStatus.completed
                ? c.greenTint
                : (r.status == ReferralStatus.sent || r.status == ReferralStatus.seen
                    ? c.accentTint
                    : c.inset),
            foreground: r.status == ReferralStatus.completed
                ? c.greenText
                : (r.status == ReferralStatus.sent || r.status == ReferralStatus.seen
                    ? c.accent
                    : c.label2),
          ),
          const SizedBox(width: CruSpace.s8),

          // WhatsApp Capsule button
          if (patient != null)
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
            onSelected: (action) async {
              switch (action) {
                case 'acknowledged':
                  await updateReferralStatus(ref, r, ReferralStatus.acknowledged);
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
                  final ok = await confirmDental(
                    context,
                    title: 'Delete referral?',
                    body: 'This will remove the referral for ${patient?.fullName ?? 'this patient'}.',
                    action: 'Delete',
                  );
                  if (ok) {
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
