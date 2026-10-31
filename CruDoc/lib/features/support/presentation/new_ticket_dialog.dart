import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/support/data/support_repository.dart';
import 'package:doctor_management_app/features/support/data/support_ticket.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the form that raises a ticket. True when one was sent.
Future<bool> showNewTicketDialog(
  BuildContext context, {
  SupportCategory category = SupportCategory.bug,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NewTicketDialog(initial: category),
  );
  return sent ?? false;
}

class _NewTicketDialog extends ConsumerStatefulWidget {
  const _NewTicketDialog({required this.initial});

  final SupportCategory initial;

  @override
  ConsumerState<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends ConsumerState<_NewTicketDialog> {
  late SupportCategory _category = widget.initial;
  final _subject = TextEditingController();
  final _details = TextEditingController();
  bool _blocking = false;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _subject.dispose();
    _details.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _subject.text.trim().isNotEmpty || _details.text.trim().isNotEmpty;

  (String subject, String details) get _hints => switch (_category) {
    SupportCategory.bug => (
      'e.g. Prescriptions won\'t print',
      'What happened, and what did you expect? Steps to make it happen '
          'again help us fix it faster.',
    ),
    SupportCategory.featureRequest => (
      'e.g. Send lab reports to patients on WhatsApp',
      'What would you like CruDoc to do, and how would it help your clinic?',
    ),
    SupportCategory.feedback => (
      'e.g. The new schedule view',
      'What\'s working well, and what could be better?',
    ),
    SupportCategory.complaint => (
      'e.g. Billing was charged twice',
      'Tell us what went wrong. We read every complaint.',
    ),
  };

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final details = _details.text.trim();
    if (subject.isEmpty || details.isEmpty) {
      setState(() => _notice = 'Add a title and a few details.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final sender = supportSender(ref);
    try {
      await ref
          .read(supportRepositoryProvider)
          .create(
            category: _category,
            subject: subject,
            description: details,
            doctorName: sender.name,
            clinicName: sender.clinic,
            phone: sender.phone,
            blocking: _category == SupportCategory.bug && _blocking,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Couldn\'t send it. Check your connection and try again.';
      });
      debugPrint('Support: create failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (subjectHint, detailsHint) = _hints;
    return CruFormDialog(
      title: _category.action,
      subtitle: 'The CruDoc team replies here, usually within a working day.',
      leading: CruIconTile(
        icon: _category == SupportCategory.featureRequest
            ? CruIcons.sparkle
            : CruIcons.whatsapp,
        tone: CruTileTone.accent,
      ),
      submitLabel: 'Send',
      busy: _busy,
      dirty: _dirty,
      notice: _notice,
      onSubmit: _submit,
      body: CruFormSection(
        title: 'Details',
        first: true,
        children: [
          CruDropdownField<SupportCategory>(
            label: 'About',
            value: _category,
            items: SupportCategory.values,
            itemLabel: (c) => c.label,
            onChanged: _busy ? null : (v) => setState(() => _category = v),
          ),
          CruTextField(
            label: 'Title',
            controller: _subject,
            hint: subjectHint,
            autofocus: true,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          CruTextField(
            label: _category == SupportCategory.featureRequest
                ? 'What it should do'
                : 'Details',
            controller: _details,
            hint: detailsHint,
            maxLines: 6,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          if (_category == SupportCategory.bug)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Is this stopping you from working?',
                    style: CruType.callout.tint(c.label),
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                CruSegmentedControl<bool>(
                  semanticLabel: 'Is this stopping you from working?',
                  segments: const [
                    CruSegment(false, 'No'),
                    CruSegment(true, 'Yes'),
                  ],
                  selected: _blocking,
                  onChanged: (v) => setState(() => _blocking = v),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
