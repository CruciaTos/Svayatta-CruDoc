import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/support/data/support_repository.dart';
import 'package:doctor_management_app/features/support/data/support_ticket.dart';
import 'package:doctor_management_app/features/support/presentation/new_ticket_dialog.dart';
import 'package:doctor_management_app/features/support/presentation/ticket_thread_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → Help & feedback. Doctors report problems, request features
/// and share feedback; each becomes a ticket in the Super Admin's Support
/// Desk, and the team's replies and decisions show up here.
class SupportSection extends ConsumerWidget {
  const SupportSection({super.key});

  Future<void> _start(
    BuildContext context,
    SupportCategory category,
  ) async {
    final sent = await showNewTicketDialog(context, category: category);
    if (!sent || !context.mounted) return;
    final c = context.cru;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          category == SupportCategory.featureRequest
              ? 'Request sent. We\'ll let you know here once it\'s reviewed.'
              : 'Sent. The CruDoc team will reply here.',
          style: CruType.text.tint(c.surface),
        ),
        backgroundColor: c.label,
        behavior: SnackBarBehavior.floating,
        shape: cruShape(CruRadius.control),
        margin: const EdgeInsets.all(CruSpace.s16),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final tickets = ref.watch(myTicketsProvider);
    final phone = cruIsPhone(context);

    final actions = [
      for (final cat in const [
        SupportCategory.bug,
        SupportCategory.featureRequest,
        SupportCategory.feedback,
      ])
        CruButton(
          label: cat.action,
          kind: cat == SupportCategory.featureRequest
              ? CruButtonKind.primary
              : CruButtonKind.secondary,
          icon: cat == SupportCategory.featureRequest
              ? CruIcons.sparkle
              : null,
          expand: phone,
          onPressed: () => _start(context, cat),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruCard(
          semanticLabel: 'Contact CruDoc',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Contact CruDoc', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Tell us what isn\'t working, ask for a feature your clinic '
                'needs, or share feedback. The CruDoc team reviews every '
                'request and replies here.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s20),
              if (phone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: CruSpace.s8),
                      actions[i],
                    ],
                  ],
                )
              else
                Wrap(
                  spacing: CruSpace.s10,
                  runSpacing: CruSpace.s10,
                  children: actions,
                ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),
        CruCard(
          semanticLabel: 'Your requests',
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s20,
                  CruSpace.s12,
                  CruSpace.s20,
                  CruSpace.s8,
                ),
                child: Text(
                  'Your requests',
                  style: CruType.headline.tint(c.label),
                ),
              ),
              ...tickets.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(CruSpace.s24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  _Empty(
                    'Couldn\'t load your requests. Check your connection.',
                  ),
                ],
                data: (list) => list.isEmpty
                    ? const [
                        _Empty(
                          'Nothing yet. Requests you send show here with '
                          'the CruDoc team\'s replies.',
                        ),
                      ]
                    : [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            const CruSeparator(
                              indent: CruSpace.s20,
                              endIndent: CruSpace.s20,
                            ),
                          _TicketRow(ticket: list[i]),
                        ],
                      ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CruSpace.s20,
      CruSpace.s4,
      CruSpace.s20,
      CruSpace.s16,
    ),
    child: Text(text, style: CruType.subhead.tint(context.cru.label2)),
  );
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final last = ticket.messages.isEmpty ? null : ticket.messages.last;
    final preview = last == null
        ? ticket.description
        : '${last.fromDoctor ? 'You' : 'CruDoc'}: ${last.content}';
    return CruPressable(
      onTap: () => showTicketThreadDialog(context, ticket.id),
      semanticLabel: ticket.subject,
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        color: hovered ? c.hoverFill : null,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s20,
          vertical: CruSpace.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (ticket.doctorUnread) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: ShapeDecoration(
                            color: c.accent,
                            shape: const CircleBorder(),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s6),
                      ],
                      Flexible(
                        child: Text(
                          ticket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (ticket.doctorUnread
                                  ? CruType.callout.w600
                                  : CruType.callout)
                              .tint(c.label),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    '${ticket.category.label} · '
                    '${DateFormat('d MMM yyyy').format(ticket.createdAt)}',
                    style: CruType.caption.tabular.tint(c.label3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            TicketStatusPill(ticket: ticket),
          ],
        ),
      ),
    );
  }
}
