import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/support/data/support_repository.dart';
import 'package:doctor_management_app/features/support/data/support_ticket.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens one ticket: what the doctor wrote, the CruDoc team's decision
/// and replies, and a box to answer.
Future<void> showTicketThreadDialog(BuildContext context, String ticketId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _TicketThreadDialog(ticketId: ticketId),
    );

class _TicketThreadDialog extends ConsumerStatefulWidget {
  const _TicketThreadDialog({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_TicketThreadDialog> createState() =>
      _TicketThreadDialogState();
}

class _TicketThreadDialogState extends ConsumerState<_TicketThreadDialog> {
  final _reply = TextEditingController();
  bool _sending = false;
  String? _error;
  int? _markedReadAt;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(SupportTicket ticket) async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(supportRepositoryProvider)
          .reply(ticket, content: text, senderName: supportSender(ref).name);
      _reply.clear();
    } catch (e) {
      _error = 'Couldn\'t send. Check your connection and try again.';
      debugPrint('Support: reply failed: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _withdraw(SupportTicket ticket) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.cru;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: cruShape(CruRadius.card),
          title: Text(
            'Withdraw this request?',
            style: CruType.headline.tint(c.label),
          ),
          content: Text(
            'The CruDoc team will stop working on it. You can still read it here.',
            style: CruType.text.tint(c.label2),
          ),
          actions: [
            CruButton(
              label: 'Keep',
              kind: CruButtonKind.inset,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            CruButton(
              label: 'Withdraw',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(supportRepositoryProvider).withdraw(ticket);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t withdraw it: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final tickets = ref.watch(myTicketsProvider).value ?? const [];
    final ticket = tickets.where((t) => t.id == widget.ticketId).firstOrNull;
    if (ticket != null &&
        ticket.doctorUnread &&
        _markedReadAt != ticket.messages.length) {
      // Opening it is reading it. Once per new reply, not every rebuild.
      _markedReadAt = ticket.messages.length;
      ref.read(supportRepositoryProvider).markRead(ticket);
    }
    final phone = cruIsPhone(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      insetPadding: phone
          ? const EdgeInsets.all(CruSpace.s8)
          : const EdgeInsets.all(CruSpace.s32),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: size.height),
        child: ticket == null
            ? const Padding(
                padding: EdgeInsets.all(CruSpace.s32),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, ticket),
                  const CruSeparator(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(CruSpace.s20),
                      children: [
                        _Bubble(
                          name: 'You',
                          text: ticket.description,
                          time: ticket.createdAt,
                          mine: true,
                        ),
                        if (ticket.approval != null) ...[
                          const SizedBox(height: CruSpace.s12),
                          _ApprovalBanner(ticket: ticket),
                        ],
                        for (final m in ticket.messages) ...[
                          const SizedBox(height: CruSpace.s12),
                          _Bubble(
                            name: m.fromDoctor ? 'You' : 'CruDoc team',
                            text: m.content,
                            time: m.timestamp,
                            mine: m.fromDoctor,
                          ),
                        ],
                        if (ticket.status == SupportStatus.resolved) ...[
                          const SizedBox(height: CruSpace.s12),
                          _Banner(
                            icon: CruIcons.check,
                            fg: c.greenText,
                            bg: c.greenTint,
                            title: 'Resolved',
                            body:
                                ticket.resolution ??
                                'Reply below if it isn\'t fixed and we\'ll reopen it.',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) CruFormNotice(_error!),
                  const CruSeparator(),
                  _composer(context, ticket),
                ],
              ),
      ),
    );
  }

  Widget _header(BuildContext context, SupportTicket ticket) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s16,
        CruSpace.s8,
        CruSpace.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.subject, style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s6),
                Wrap(
                  spacing: CruSpace.s6,
                  runSpacing: CruSpace.s6,
                  children: [
                    CruPill(
                      text: ticket.category.label,
                      background: c.inset,
                      foreground: c.label2,
                    ),
                    TicketStatusPill(ticket: ticket),
                  ],
                ),
              ],
            ),
          ),
          if (ticket.status.isActive)
            CruButton(
              label: 'Withdraw',
              kind: CruButtonKind.inset,
              onPressed: () => _withdraw(ticket),
            ),
          CruIconButton(
            icon: CruIcons.close,
            semanticLabel: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, SupportTicket ticket) {
    final c = context.cru;
    if (ticket.status == SupportStatus.closed) {
      return Padding(
        padding: const EdgeInsets.all(CruSpace.s20),
        child: Text(
          'This request is closed. Raise a new one if you need anything else.',
          style: CruType.subhead.tint(c.label2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _reply,
              minLines: 1,
              maxLines: 5,
              enabled: !_sending,
              textCapitalization: TextCapitalization.sentences,
              style: CruType.text.tint(c.label),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: ticket.status == SupportStatus.resolved
                    ? 'Still a problem? Reply to reopen'
                    : 'Write a reply',
                hintStyle: CruType.text.tint(c.label3),
                filled: true,
                fillColor: c.inset,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s12,
                  vertical: CruSpace.s10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          CruButton(
            label: _sending ? 'Sending…' : 'Send',
            onPressed: _sending || _reply.text.trim().isEmpty
                ? null
                : () => _send(ticket),
          ),
        ],
      ),
    );
  }
}

/// Where a ticket stands, in one pill: the decision for a feature
/// request still waiting on it, the status otherwise.
class TicketStatusPill extends StatelessWidget {
  const TicketStatusPill({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final approval = ticket.approval;
    if (approval != null && ticket.status != SupportStatus.resolved) {
      final (bg, fg) = switch (approval) {
        SupportApproval.pending => (c.amberTint, c.amberText),
        SupportApproval.approved => (c.greenTint, c.greenText),
        SupportApproval.declined => (c.inset, c.label2),
      };
      return CruPill(text: approval.label, background: bg, foreground: fg);
    }
    final (bg, fg) = switch (ticket.status) {
      SupportStatus.open => (c.amberTint, c.amberText),
      SupportStatus.inProgress => (c.accentTint, c.accentText),
      SupportStatus.resolved => (c.greenTint, c.greenText),
      SupportStatus.closed => (c.inset, c.label3),
    };
    return CruPill(text: ticket.status.label, background: bg, foreground: fg);
  }
}

class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final note = ticket.approvalNote;
    return switch (ticket.approval!) {
      SupportApproval.pending => _Banner(
        icon: CruIcons.clock,
        fg: c.amberText,
        bg: c.amberTint,
        title: 'Under review',
        body: 'The CruDoc team will look at this request and let you know here.',
      ),
      SupportApproval.approved => _Banner(
        icon: CruIcons.sparkle,
        fg: c.greenText,
        bg: c.greenTint,
        title: 'Approved',
        body: note ?? 'We\'re adding this to CruDoc. We\'ll tell you here when it ships.',
      ),
      SupportApproval.declined => _Banner(
        icon: CruIcons.close,
        fg: c.label2,
        bg: c.inset,
        title: 'Not planned',
        body: note ?? 'We won\'t be building this for now. Thank you for the idea.',
      ),
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.fg,
    required this.bg,
    required this.title,
    required this.body,
  });

  final CruIconData icon;
  final Color fg;
  final Color bg;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: ShapeDecoration(color: bg, shape: cruShape(CruRadius.control)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, size: 16, color: fg),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.subhead.w600.tint(fg)),
                const SizedBox(height: CruSpace.s2),
                Text(body, style: CruType.subhead.tint(fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.name,
    required this.text,
    required this.time,
    required this.mine,
  });

  final String name;
  final String text;
  final DateTime time;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              '$name · ${DateFormat('d MMM, h:mm a').format(time)}',
              style: CruType.caption.tabular.tint(c.label3),
            ),
            const SizedBox(height: CruSpace.s4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CruSpace.s12,
                vertical: CruSpace.s10,
              ),
              decoration: ShapeDecoration(
                color: mine ? c.accentTint : c.inset,
                shape: cruShape(CruRadius.control),
              ),
              child: SelectableText(
                text,
                style: CruType.text.tint(mine ? c.accentText : c.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
