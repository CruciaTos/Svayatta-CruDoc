import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/support/data/support_ticket_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens "Report a bug or send feedback". What is sent goes to the CruDoc
/// team (the Super Admin console), not to anyone in the clinic.
Future<void> showFeedbackDialog(
  BuildContext context, {
  SupportTicketKind initial = SupportTicketKind.bug,
  SupportTicketService? service,
}) async {
  final root = Navigator.of(context, rootNavigator: true).context;
  final messenger = ScaffoldMessenger.maybeOf(root);
  final outcome = await showDialog<SupportTicketOutcome>(
    context: root,
    builder: (_) => FeedbackDialog(initial: initial, service: service),
  );
  if (outcome == null) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          outcome == SupportTicketOutcome.sent
              ? 'Thank you. The CruDoc team has it.'
              : "You're offline. It will be sent when you're back online.",
        ),
      ),
    );
}

class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({
    super.key,
    this.initial = SupportTicketKind.bug,
    this.service,
  });

  final SupportTicketKind initial;
  final SupportTicketService? service;

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  late SupportTicketKind _kind = widget.initial;
  final _message = TextEditingController();
  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _bug => _kind == SupportTicketKind.bug;

  Future<void> _send() async {
    if (_busy) return;
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(
        () => _notice = _bug
            ? 'Tell us what went wrong.'
            : 'Write a few words first.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final identity = ref.read(doctorIdentityProvider);
    final access = ref.read(clinicAccessProvider).value;
    try {
      final outcome = await (widget.service ?? SupportTicketService()).submit(
        kind: _kind,
        message: text,
        sender: SupportTicketSender(
          name: identity.fullName,
          clinicId: access?.clinicId,
          clinicName: identity.clinicName,
          role: access?.roleName,
        ),
      );
      if (mounted) Navigator.of(context).pop(outcome);
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = "Couldn't send it: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Watched so they are loaded by the time Send is pressed.
    ref.watch(doctorIdentityProvider);
    ref.watch(clinicAccessProvider);
    final left = SupportTicketService.maxMessage - _message.text.length;
    return CruFormDialog(
      title: 'Report a bug or send feedback',
      subtitle: 'Goes straight to the CruDoc team',
      submitLabel: 'Send',
      onSubmit: _send,
      busy: _busy,
      dirty: _message.text.trim().isNotEmpty,
      notice: _notice,
      footerHint: 'Your app version and device are sent with it.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CruSegmentedControl<SupportTicketKind>(
            semanticLabel: 'What are you sending?',
            segments: [
              for (final k in SupportTicketKind.values) CruSegment(k, k.label),
            ],
            selected: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _notice = null;
            }),
          ),
          const SizedBox(height: CruSpace.s16),
          CruTextField(
            label: _bug ? 'What went wrong?' : 'Your feedback',
            controller: _message,
            autofocus: true,
            enabled: !_busy,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            hint: _bug
                ? 'What you did, what happened, and what you expected'
                : 'What would make CruDoc better for you?',
            help: 'Please leave out patient names and details.',
          ),
          if (left < 200) ...[
            const SizedBox(height: CruSpace.s6),
            Text(
              left >= 0
                  ? '$left characters left'
                  : '${-left} characters over the limit',
              style: CruType.caption.tabular.tint(
                left >= 0 ? c.label3 : c.amberText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
