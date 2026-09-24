import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/pacs_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ai/ai_panels.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → Radiology (radiologists only): the report signature,
/// turnaround times, fees, PACS, the scanner receiver, AI switches,
/// storage and the audit log.
class RadSettingsSection extends ConsumerWidget {
  const RadSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(radSettingsProvider).value;
    final fees = ref.watch(radFeesProvider).value ?? const <RadFee>[];
    final servers = ref.watch(radPacsServersProvider).value ?? const <RadPacsServer>[];
    if (settings == null) return const SizedBox(height: 200);

    final gap = const SizedBox(height: CruSpace.cardGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SignatureCard(settings: settings),
        gap,
        _TurnaroundCard(settings: settings),
        gap,
        _Card(
          title: 'Work',
          description: 'What you charge, where scans come from.',
          child: Column(
            children: [
              _ActionRow(
                title: 'Reading fees',
                detail: fees.isEmpty
                    ? 'None set'
                    : '${fees.length} study types · from ${RadFormat.rupees(fees.map((f) => f.amount).reduce((a, b) => a < b ? a : b))}',
                action: 'Edit fees',
                onTap: () => showRadFeesDialog(context),
              ),
              const CruSeparator(),
              _ActionRow(
                title: 'PACS',
                detail: servers.isEmpty
                    ? 'None added · not connected yet'
                    : '${servers.map((s) => s.name).join(', ')} · not connected yet',
                action: 'Manage',
                onTap: () => showRadPacsServersDialog(context),
              ),
              const CruSeparator(),
              _ActionRow(
                title: 'Receive from scanners',
                detail: 'AE title ${settings.aeTitle} · port ${settings.dicomPort} · not connected yet',
                action: 'Set up',
                onTap: () => showRadDicomReceiverDialog(context),
              ),
            ],
          ),
        ),
        gap,
        const _Card(
          title: 'AI assistance',
          description: 'Suggestions you confirm or reject; never a diagnosis on its own.',
          child: RadAiSwitches(),
        ),
        gap,
        const _StorageCard(),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.tint(c.label)),
                Text(detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tabular.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          CruButton(label: action, kind: CruButtonKind.inset, onPressed: onTap),
        ],
      ),
    );
  }
}

// ============================================================ signature

class _SignatureCard extends ConsumerStatefulWidget {
  const _SignatureCard({required this.settings});

  final RadSettings settings;

  @override
  ConsumerState<_SignatureCard> createState() => _SignatureCardState();
}

class _SignatureCardState extends ConsumerState<_SignatureCard> {
  late final _name = TextEditingController(text: widget.settings.signatureName);
  late final _qual = TextEditingController(text: widget.settings.qualification);
  late final _reg = TextEditingController(text: widget.settings.regNo);
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _qual.dispose();
    _reg.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final s = await ref.read(radSettingsProvider.future);
    await ref.read(radiologyProvider).saveSettings(s.copyWith(
          signatureName: _name.text.trim(),
          qualification: _qual.text.trim(),
          regNo: _reg.text.trim(),
        ));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    radToast(context, 'Signature saved');
  }

  @override
  Widget build(BuildContext context) {
    void edited(String _) {
      if (!_dirty) setState(() => _dirty = true);
    }

    return _Card(
      title: 'Report signature',
      description: 'Printed under every report you sign.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFieldRow(children: [
            CruTextField(
              label: 'Name',
              controller: _name,
              hint: 'Dr. Meera Kulkarni',
              textCapitalization: TextCapitalization.words,
              onChanged: edited,
            ),
            CruTextField(
              label: 'Registration no.',
              controller: _reg,
              onChanged: edited,
            ),
          ]),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Qualification',
            controller: _qual,
            hint: 'MDS (Oral Medicine & Radiology)',
            onChanged: edited,
          ),
          if (_dirty) ...[
            const SizedBox(height: CruSpace.s16),
            Align(
              alignment: Alignment.centerRight,
              child: CruButton(label: _saving ? 'Saving…' : 'Save', onPressed: _saving ? null : _save),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================ turnaround

class _TurnaroundCard extends ConsumerStatefulWidget {
  const _TurnaroundCard({required this.settings});

  final RadSettings settings;

  @override
  ConsumerState<_TurnaroundCard> createState() => _TurnaroundCardState();
}

class _TurnaroundCardState extends ConsumerState<_TurnaroundCard> {
  late final Map<RadPriority, TextEditingController> _hours = {
    for (final p in RadPriority.values)
      p: TextEditingController(text: '${widget.settings.turnaround(p).inHours}'),
  };
  bool _dirty = false;

  @override
  void dispose() {
    for (final c in _hours.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = await ref.read(radSettingsProvider.future);
    await ref.read(radiologyProvider).saveSettings(s.copyWith(tatHours: {
          for (final e in _hours.entries)
            e.key.name: (int.tryParse(e.value.text.trim()) ?? s.turnaround(e.key).inHours)
                .clamp(1, 24 * 30),
        }));
    if (!mounted) return;
    setState(() => _dirty = false);
    radToast(context, 'Turnaround times saved. New studies use them.');
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Turnaround times',
      description: 'When a report is due after the scan arrives. The worklist turns amber when a study is late.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruFieldRow(children: [
            for (final p in RadPriority.values)
              CruTextField(
                label: p.label,
                controller: _hours[p]!,
                tabular: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                trailing: Text('hours', style: CruType.subhead.tint(context.cru.label3)),
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
              ),
          ]),
          if (_dirty) ...[
            const SizedBox(height: CruSpace.s16),
            Align(
              alignment: Alignment.centerRight,
              child: CruButton(label: 'Save', onPressed: _save),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================ storage

class _StorageCard extends ConsumerStatefulWidget {
  const _StorageCard();

  @override
  ConsumerState<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends ConsumerState<_StorageCard> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    ref.read(radiologyProvider).storageBytes().then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final studies = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
    return _Card(
      title: 'Storage and records',
      description: 'Scans stay on this computer. Nothing is uploaded.',
      child: Column(
        children: [
          _ActionRow(
            title: 'Scans on this computer',
            detail: _bytes == null
                ? 'Adding up…'
                : '${RadFormat.bytes(_bytes!)} · ${studies.length} studies',
            action: 'Open folder',
            onTap: () async {
              final studyDir = await ref.read(radiologyProvider).studyDir('_');
              await launchUrl(Uri.directory(studyDir.parent.path));
            },
          ),
          const CruSeparator(),
          _ActionRow(
            title: 'Radiation dose log',
            detail: "Exposure values read from each scan's files",
            action: 'View',
            onTap: () => showRadDoseLogDialog(context),
          ),
          const CruSeparator(),
          _ActionRow(
            title: 'Audit log',
            detail: 'Who opened, changed, signed, exported or shared each study',
            action: 'View',
            onTap: () => showRadAuditDialog(context),
          ),
        ],
      ),
    );
  }
}
