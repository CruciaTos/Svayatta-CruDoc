import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/campaigns/data/providers/campaign_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/messaging/data/providers/clinic_gmail_providers.dart';
import 'package:doctor_management_app/features/messaging/data/providers/reminder_settings_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Automatic reminders and recalls, inside Campaigns.
///
/// The server sends them (6 pm the day before, recalls at 10 am), so they go
/// out with every device off. Here the clinic chooses what is on, which
/// channel goes first, connects its Gmail and words the email. WhatsApp
/// wording is Meta-approved and fixed.
///
/// Used by the desktop and phone Campaigns screens; the caller supplies the
/// scrolling and the outer padding.
class RemindersPanel extends ConsumerWidget {
  const RemindersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const gap = SizedBox(height: CruSpace.s16);
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitchesCard(),
        gap,
        _ChannelsCard(),
        gap,
        _WordingCard(),
        gap,
        _ActivityCard(),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: CruType.headline.tint(c.label)),
          if (description != null) ...[
            const SizedBox(height: CruSpace.s4),
            Text(description!, style: CruType.text.tint(c.label2)),
          ],
          const SizedBox(height: CruSpace.s20),
          child,
        ],
      ),
    );
  }
}

/// A label, a caption and an Off/On switch.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.caption,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: CruType.row.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(caption, style: CruType.caption.tint(c.label2)),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s16),
        CruSegmentedControl<bool>(
          semanticLabel: label,
          segments: const [CruSegment(false, 'Off'), CruSegment(true, 'On')],
          selected: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SwitchesCard extends ConsumerWidget {
  const _SwitchesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      title: 'Automatic messages',
      description:
          'Sent by CruDoc from our servers, so they go out even when every '
          'device is off. Nothing about treatment is included.',
      child: Column(
        children: [
          _SwitchRow(
            label: 'Appointment reminders',
            caption: 'At 6:00 pm the day before, and a catch-up at 8:00 am.',
            value: ref.watch(whatsAppRemindersEnabledProvider),
            onChanged: setWhatsAppRemindersEnabled,
          ),
          const SizedBox(height: CruSpace.s16),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s16),
          _SwitchRow(
            label: 'Recalls',
            caption:
                'At 10:00 am on the day a patient\'s recall is due, '
                'up to 200 a day.',
            value: ref.watch(recallsEnabledProvider),
            onChanged: setRecallsEnabled,
          ),
        ],
      ),
    );
  }
}

class _ChannelsCard extends ConsumerStatefulWidget {
  const _ChannelsCard();

  @override
  ConsumerState<_ChannelsCard> createState() => _ChannelsCardState();
}

class _ChannelsCardState extends ConsumerState<_ChannelsCard> {
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(clinicGmailLinkProvider).connect();
    } on ClinicGmailException catch (e) {
      if (mounted && !e.cancelled) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(clinicGmailLinkProvider).disconnect();
    } on ClinicGmailException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final order = ref.watch(reminderChannelOrderProvider);
    final gmail = ref.watch(clinicGmailStatusProvider).value;
    final whatsApp = ref.watch(whatsAppConnectionProvider).value;
    final whatsAppReady = whatsApp?.canSend ?? false;

    final gmailLine = gmail == null
        ? ''
        : gmail.connected
        ? 'Sending as ${gmail.address ?? 'your Gmail'}'
        : gmail.needsReconnect
        ? 'Gmail needs to be connected again'
        : 'Not connected';

    return _Card(
      title: 'Channels',
      description:
          'Each patient gets one message, on the first channel that can '
          'reach them. If neither can, it shows as skipped below.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruSegmentedControl<ReminderChannel>(
            semanticLabel: 'Channel order',
            expand: true,
            segments: [
              CruSegment(
                order.first,
                '${order.first.label} first',
              ),
              CruSegment(
                order.last,
                '${order.last.label} first',
              ),
            ],
            selected: order.first,
            onChanged: (first) => setReminderChannelOrder([
              first,
              for (final ch in ReminderChannel.values)
                if (ch != first) ch,
            ]),
          ),
          const SizedBox(height: CruSpace.s20),
          _ChannelRow(
            icon: CruIcons.whatsapp,
            name: 'WhatsApp',
            status: whatsAppReady
                ? 'Sending from ${whatsApp?.displayPhoneNumber ?? 'your number'}'
                : 'Waiting for WhatsApp connection',
            waiting: !whatsAppReady,
          ),
          const SizedBox(height: CruSpace.s16),
          _ChannelRow(
            icon: CruIcons.megaphone,
            name: 'Email',
            status: gmailLine,
            waiting: gmail != null && !gmail.connected,
            action: gmail == null
                ? null
                : gmail.connected
                ? CruButton(
                    label: 'Disconnect',
                    kind: CruButtonKind.inset,
                    onPressed: _busy ? null : _disconnect,
                  )
                : CruButton(
                    label: gmail.needsReconnect
                        ? 'Connect again'
                        : 'Connect Gmail',
                    onPressed: _busy ? null : _connect,
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: CruSpace.s12),
            Text(_error!, style: CruType.caption.tint(c.label2)),
          ],
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.name,
    required this.status,
    required this.waiting,
    this.action,
  });

  final CruIconData icon;
  final String name;
  final String status;
  final bool waiting;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        CruIconTile(
          icon: icon,
          tone: waiting ? CruTileTone.amber : CruTileTone.green,
        ),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: CruType.row.tint(c.label)),
              if (status.isNotEmpty)
                Text(
                  status,
                  style: CruType.caption.tint(
                    waiting ? c.amberText : c.label2,
                  ),
                ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: CruSpace.s12),
          action!,
        ],
      ],
    );
  }
}

class _WordingCard extends ConsumerStatefulWidget {
  const _WordingCard();

  @override
  ConsumerState<_WordingCard> createState() => _WordingCardState();
}

class _WordingCardState extends ConsumerState<_WordingCard> {
  ReminderKind _kind = ReminderKind.reminder;
  late final _subject = TextEditingController();
  late final _body = TextEditingController();
  final _subjectFocus = FocusNode();
  final _bodyFocus = FocusNode();
  late TextEditingController _target = _body;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(ref.read(reminderEmailTemplateProvider(_kind)));
    _subjectFocus.addListener(() {
      if (_subjectFocus.hasFocus) _target = _subject;
    });
    _bodyFocus.addListener(() {
      if (_bodyFocus.hasFocus) _target = _body;
    });
    _subject.addListener(_changed);
    _body.addListener(_changed);
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _subjectFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _load(({String subject, String body}) t) {
    _subject.text = t.subject;
    _body.text = t.body;
  }

  bool _isDirty(({String subject, String body}) saved) =>
      _subject.text.trim() != saved.subject.trim() ||
      _body.text.trim() != saved.body.trim();

  void _insert(String variable) {
    final ctl = _target;
    final text = ctl.text;
    final sel = ctl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final token = '{$variable}';
    ctl.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    (_target == _subject ? _subjectFocus : _bodyFocus).requestFocus();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveReminderEmailTemplate(
        _kind,
        subject: _subject.text,
        body: _body.text,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    await resetReminderEmailTemplate(_kind);
    _load(kDefaultEmailTemplates[_kind]!);
  }

  /// Variables the clinic knows now are filled in; the rest stay in square
  /// brackets so the preview never invents a patient or a time.
  String _preview(String text, {required String clinic, required String doctor}) {
    final known = <String, String>{
      'clinic': clinic.isEmpty ? '[clinic]' : clinic,
      'doctor': doctor.isEmpty ? '[doctor]' : doctor,
    };
    return text.replaceAllMapped(
      RegExp('\\{(patient|date|time|clinic|doctor)\\}'),
      (m) => known[m[1]!] ?? '[${m[1]}]',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final saved = ref.watch(reminderEmailTemplateProvider(_kind));
    final identity = ref.watch(doctorIdentityProvider);
    final clinic = identity.clinicName ?? '';
    final doctor = identity.fullName ?? '';
    final dirty = _isDirty(saved);
    final isDefault =
        saved == kDefaultEmailTemplates[_kind] && !dirty;

    return _Card(
      title: 'Email wording',
      description:
          'WhatsApp uses CruDoc\'s Meta-approved messages, which stay as '
          'they are. Emails are yours to word.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruSegmentedControl<ReminderKind>(
            semanticLabel: 'Message type',
            expand: true,
            segments: [
              for (final k in ReminderKind.values) CruSegment(k, k.label),
            ],
            selected: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _load(ref.read(reminderEmailTemplateProvider(k)));
            }),
          ),
          const SizedBox(height: CruSpace.s16),
          CruTextField(
            label: 'Subject',
            controller: _subject,
            focusNode: _subjectFocus,
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Message',
            controller: _body,
            focusNode: _bodyFocus,
            maxLines: 8,
          ),
          const SizedBox(height: CruSpace.s12),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final v in kReminderVariables)
                CruCapsuleButton(
                  label: '{$v}',
                  semanticLabel: 'Insert $v',
                  onPressed: () => _insert(v),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          Text('Preview', style: CruType.subhead.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _preview(_subject.text, clinic: clinic, doctor: doctor),
                  style: CruType.row.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s8),
                Text(
                  _preview(_body.text, clinic: clinic, doctor: doctor),
                  style: CruType.text.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s12),
                Text(
                  _preview(kEmailFooter, clinic: clinic, doctor: doctor),
                  style: CruType.caption.tint(c.label3),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isDefault) ...[
                CruButton(
                  label: 'Use default',
                  kind: CruButtonKind.inset,
                  onPressed: _saving ? null : _reset,
                ),
                const SizedBox(width: CruSpace.s8),
              ],
              CruButton(
                label: 'Save wording',
                onPressed: dirty && !_saving ? _save : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final log = ref.watch(reminderLogProvider).value;
    final names = <String, String>{
      for (final p in ref.watch(patientsStreamProvider).value ?? const [])
        p.id: p.fullName,
    };

    return _Card(
      title: 'Recent activity',
      description: 'The last 50 automatic messages and what happened.',
      child: log == null
          ? const SizedBox.shrink()
          : log.isEmpty
          ? Text(
              'Nothing sent yet. The first reminders go out at 6:00 pm.',
              style: CruType.text.tint(c.label2),
            )
          : Column(
              children: [
                for (var i = 0; i < log.length; i++) ...[
                  if (i > 0) const CruSeparator(),
                  _ActivityRow(entry: log[i], name: names[log[i].patientId]),
                ],
              ],
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, this.name});

  final ReminderLogEntry entry;
  final String? name;

  static String _reason(String? r) => switch (r) {
    'no_channel' => 'No way to reach them',
    'opted_out' => 'Opted out',
    'no_patient_name' => 'No name on file',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (label, bg, fg) = switch (entry.status) {
      'sent' => ('Sent', c.greenTint, c.greenText),
      'queued' => ('Queued', c.amberTint, c.amberText),
      'failed' => ('Failed', c.amberTint, c.amberText),
      'skipped' => ('Skipped', c.inset, c.label2),
      _ => ('Pending', c.inset, c.label2),
    };
    final detail = [
      entry.kind.label,
      if (entry.channel != null) entry.channel!.label,
      if (entry.status == 'skipped') _reason(entry.reason),
      DateFormat('d MMM, h:mm a').format(entry.at),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? entry.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.row.tint(c.label),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tint(c.label2).tabular,
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruPill(text: label, background: bg, foreground: fg),
        ],
      ),
    );
  }
}
