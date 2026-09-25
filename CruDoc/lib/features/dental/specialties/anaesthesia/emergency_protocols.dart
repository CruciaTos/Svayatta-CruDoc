import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Protocols clinics usually keep; the steps and doses always come from
/// the clinic's own approved guideline, never from the app.
const _usual = [
  'Anaphylaxis',
  'Syncope',
  'Hypoglycaemia',
  'Asthma',
  'Seizure',
  'Chest pain',
  'Local anaesthetic toxicity',
  'Airway obstruction',
];

List<String> _lines(Object? raw) => raw is List
    ? [for (final l in raw) '$l'.trim()].where((l) => l.isNotEmpty).toList()
    : const [];

/// The clinic's emergency protocols in large text, with a count-up timer
/// at the top. The clinic enters its approved steps and doses.
class EmergencyProtocolsScreen extends ConsumerStatefulWidget {
  const EmergencyProtocolsScreen({super.key});

  @override
  ConsumerState<EmergencyProtocolsScreen> createState() =>
      _EmergencyProtocolsScreenState();
}

class _EmergencyProtocolsScreenState
    extends ConsumerState<EmergencyProtocolsScreen> {
  DateTime? _started;
  Duration _elapsed = Duration.zero;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _tick?.cancel();
    setState(() {
      _started = DateTime.now();
      _elapsed = Duration.zero;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _started == null) return;
      setState(() => _elapsed = DateTime.now().difference(_started!));
    });
  }

  void _stopTimer() {
    _tick?.cancel();
    setState(() => _started = null);
  }

  String get _clock {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final protocols = [
      ...(ref.watch(clinicRecordsProvider(RecKind.emergencyProtocol)).value ??
          const <DentalRecord>[]),
    ]..sort((a, b) => a.str('name').toLowerCase().compareTo(b.str('name').toLowerCase()));
    final padding = MediaQuery.sizeOf(context).width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;
    final running = _started != null;

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Emergency',
            subtitle: protocols.isEmpty
                ? 'Your clinic’s approved protocols, in large text'
                : '${protocols.length} protocol${protocols.length == 1 ? '' : 's'} · from your clinic’s guideline',
            actions: [
              if (running) ...[
                Text(_clock, style: CruType.metric.tabular.tint(c.label)),
                CruButton(
                  label: 'Stop timer',
                  kind: CruButtonKind.secondary,
                  onPressed: _stopTimer,
                ),
              ] else
                CruButton(
                  label: 'Start timer',
                  icon: CruIcons.clock,
                  kind: CruButtonKind.secondary,
                  onPressed: _startTimer,
                ),
              CruButton(
                label: 'Add protocol',
                icon: CruIcons.plus,
                onPressed: () => showProtocolDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (protocols.isEmpty)
            CruCard(
              child: DentalEmptyState(
                icon: CruIcons.warning,
                title: 'No protocols yet',
                body: 'Add your clinic’s approved emergency protocols: '
                    'the steps and drug doses exactly as your guideline gives '
                    'them (for example the Indian Resuscitation Council’s). '
                    'They show here in large text, ready at the chair.',
                actions: [
                  for (final name in _usual)
                    CruCapsuleButton(
                      label: name,
                      icon: CruIcons.plus,
                      onPressed: () => showProtocolDialog(context, name: name),
                    ),
                ],
              ),
            )
          else
            for (final p in protocols) ...[
              _ProtocolCard(record: p),
              const SizedBox(height: CruSpace.cardGap),
            ],
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.record});

  final DentalRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final steps = _lines(record.data['steps']);
    final drugs = _lines(record.data['drugs']);
    return CruCard(
      semanticLabel: record.str('name'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.str('name'),
                  style: CruType.title2.tint(c.label),
                ),
              ),
              CruCapsuleButton(
                label: 'Edit',
                onPressed: () => showProtocolDialog(context, existing: record),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${i + 1}.',
                      style: CruType.headline.tabular.tint(c.label2),
                    ),
                  ),
                  Expanded(
                    child: Text(steps[i], style: CruType.headline.tint(c.label)),
                  ),
                ],
              ),
            ),
          if (drugs.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s6),
            Text('Drugs and doses', style: CruType.groupLabel.tint(c.label3)),
            const SizedBox(height: CruSpace.s6),
            for (final d in drugs)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s6),
                child: Text(d, style: CruType.headline.w600.tabular.tint(c.label)),
              ),
          ],
          const SizedBox(height: CruSpace.s6),
          Text(
            'Updated ${DentalFormat.date(record.updatedAt)}',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ],
      ),
    );
  }
}

/// Adds or edits one of the clinic's protocols.
Future<void> showProtocolDialog(
  BuildContext context, {
  DentalRecord? existing,
  String? name,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ProtocolDialog(existing: existing, name: name),
    );

class _ProtocolDialog extends ConsumerStatefulWidget {
  const _ProtocolDialog({this.existing, this.name});

  final DentalRecord? existing;
  final String? name;

  @override
  ConsumerState<_ProtocolDialog> createState() => _ProtocolDialogState();
}

class _ProtocolDialogState extends ConsumerState<_ProtocolDialog> {
  late final _name = TextEditingController(
    text: widget.existing?.str('name') ?? widget.name ?? '',
  );
  late final _steps = TextEditingController(
    text: _lines(widget.existing?.data['steps']).join('\n'),
  );
  late final _drugs = TextEditingController(
    text: _lines(widget.existing?.data['drugs']).join('\n'),
  );
  bool _dirty = false;
  bool _saving = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _steps.dispose();
    _drugs.dispose();
    super.dispose();
  }

  List<String> _split(String t) =>
      t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _split(_steps.text).isEmpty) {
      setState(() => _notice = 'Give the protocol a name and at least one step.');
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    final data = {
      'name': _name.text.trim(),
      'steps': _split(_steps.text),
      'drugs': _split(_drugs.text),
    };
    final e = widget.existing;
    try {
      await saveDentalRecord(
        ref,
        e == null
            ? DentalRecord.create('', RecKind.emergencyProtocol, data)
            : e.copyWith(data: data),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the protocol. Try again.";
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this protocol?',
      body: '${e.str('name')} will be removed from the emergency page.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await deleteDentalRecord(ref, e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    void edited(String _) {
      if (!_dirty) setState(() => _dirty = true);
    }

    return CruFormDialog(
      title: widget.existing == null ? 'Add protocol' : 'Edit protocol',
      subtitle: 'Exactly as your clinic’s approved guideline gives it',
      submitLabel: 'Save protocol',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFormSection(
            first: true,
            title: 'Protocol',
            children: [
              CruTextField(
                label: 'Name',
                controller: _name,
                hint: 'Anaphylaxis',
                textCapitalization: TextCapitalization.sentences,
                onChanged: edited,
              ),
              CruTextField(
                label: 'Steps',
                controller: _steps,
                maxLines: 10,
                help: 'One step per line; they show numbered.',
                textCapitalization: TextCapitalization.sentences,
                onChanged: edited,
              ),
              CruTextField(
                label: 'Drugs and doses',
                optional: true,
                controller: _drugs,
                maxLines: 5,
                help: 'One per line, with dose and route.',
                onChanged: edited,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s16),
            child: Text(
              'A clinician should check the steps and doses against your '
              'guideline before this is used with patients.',
              style: CruType.caption.tint(c.label3),
            ),
          ),
          if (widget.existing != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CruLink(label: 'Delete protocol', onPressed: _delete),
            ),
        ],
      ),
    );
  }
}
