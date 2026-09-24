import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What connecting PACS will do, said once for every PACS screen.
const _pacsNotConnected =
    'Servers you add are saved. Searching and downloading studies over DICOMweb '
    '(QIDO-RS and WADO-RS) arrives with the connection update — until then, import '
    'from a folder, CD or ZIP.';

// ============================================================ query

/// Search a PACS for a patient's studies and download one.
Future<void> showRadPacsQueryDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PacsQueryDialog());

class _PacsQueryDialog extends ConsumerStatefulWidget {
  const _PacsQueryDialog();

  @override
  ConsumerState<_PacsQueryDialog> createState() => _PacsQueryDialogState();
}

class _PacsQueryDialogState extends ConsumerState<_PacsQueryDialog> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _accession = TextEditingController();
  String? _serverId;
  final Set<String> _modalities = {};
  DateTime? _from;
  DateTime? _to;
  bool _searched = false;

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _accession.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final servers = ref.watch(radPacsServersProvider).value ?? const <RadPacsServer>[];
    final server = servers.where((s) => s.id == _serverId).firstOrNull ??
        servers.where((s) => s.isDefault).firstOrNull ??
        servers.firstOrNull;

    return DentalPanelDialog(
      title: 'Search PACS',
      subtitle: server == null ? 'No PACS added yet' : '${server.name} · ${server.baseUrl}',
      leading: const CruIconTile(icon: RadIcons.server, tone: CruTileTone.accent),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (servers.isEmpty)
              DentalEmptyState(
                icon: RadIcons.server,
                title: 'Add your PACS first',
                body: 'Enter the DICOMweb address of the practice or hospital PACS '
                    '(Orthanc, dcm4chee, a cloud PACS).',
                actions: [
                  CruButton(
                    label: 'Add PACS',
                    icon: CruIcons.plus,
                    onPressed: () => showRadPacsServerDialog(context),
                  ),
                ],
              )
            else ...[
              if (servers.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s12),
                  child: DentalChipWrap<RadPacsServer>(
                    options: servers,
                    label: (s) => s.name,
                    isSelected: (s) => s.id == server?.id,
                    onTap: (s) => setState(() => _serverId = s.id),
                  ),
                ),
              CruFieldRow(children: [
                CruTextField(label: 'Patient name', controller: _name, optional: true),
                CruTextField(label: 'Patient ID', controller: _id, optional: true),
                CruTextField(label: 'Accession', controller: _accession, optional: true),
              ]),
              const SizedBox(height: CruSpace.s12),
              CruFieldRow(children: [
                CruPickerField(
                  label: 'From',
                  optional: true,
                  icon: CruIcons.calendar,
                  value: _from == null ? null : RadFormat.date(_from!),
                  placeholder: 'Any date',
                  onTap: () async {
                    final d = await pickDentalDate(context,
                        initial: _from ?? DateTime.now(), last: DateTime.now());
                    if (d != null) setState(() => _from = d);
                  },
                ),
                CruPickerField(
                  label: 'To',
                  optional: true,
                  icon: CruIcons.calendar,
                  value: _to == null ? null : RadFormat.date(_to!),
                  placeholder: 'Any date',
                  onTap: () async {
                    final d = await pickDentalDate(context,
                        initial: _to ?? DateTime.now(), last: DateTime.now());
                    if (d != null) setState(() => _to = d);
                  },
                ),
              ]),
              const SizedBox(height: CruSpace.s12),
              CruFieldFrame(
                label: 'Modality',
                optional: true,
                child: DentalChipWrap<String>(
                  options: const ['CT', 'PX', 'IO', 'DX', 'CR'],
                  label: (m) => switch (m) {
                    'CT' => 'CBCT (CT)',
                    'PX' => 'Panoramic (PX)',
                    'IO' => 'Intraoral (IO)',
                    'DX' => 'X-ray (DX)',
                    _ => 'CR',
                  },
                  isSelected: _modalities.contains,
                  onTap: (m) => setState(
                      () => _modalities.contains(m) ? _modalities.remove(m) : _modalities.add(m)),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              if (_searched)
                const RadNotConnected(title: 'PACS isn\'t connected yet', body: _pacsNotConnected)
              else
                Text(
                  'Results appear here with each study\'s date, type and image count; '
                  'download one to add it to the worklist.',
                  style: CruType.caption.tint(c.label2),
                ),
            ],
          ],
        ),
      ),
      footer: Row(
        children: [
          CruButton(
            label: 'Manage PACS',
            icon: RadIcons.server,
            kind: CruButtonKind.secondary,
            onPressed: () => showRadPacsServersDialog(context),
          ),
          const Spacer(),
          if (servers.isNotEmpty)
            CruButton(
              label: 'Search',
              icon: CruIcons.search,
              onPressed: () => setState(() => _searched = true),
            ),
        ],
      ),
    );
  }
}

// ============================================================ servers

/// The saved PACS servers: add, edit, make default.
Future<void> showRadPacsServersDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PacsServersDialog());

class _PacsServersDialog extends ConsumerWidget {
  const _PacsServersDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final servers = ref.watch(radPacsServersProvider).value ?? const <RadPacsServer>[];
    return DentalPanelDialog(
      title: 'PACS servers',
      subtitle: 'DICOMweb addresses you can search and send to',
      leading: const CruIconTile(icon: RadIcons.server, tone: CruTileTone.neutral),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (servers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text('None added yet.', style: CruType.subhead.tint(c.label2)),
            ),
          for (final s in servers)
            DentalListRow(
              semanticLabel: s.name,
              onTap: () => showRadPacsServerDialog(context, existing: s),
              child: Row(
                children: [
                  const CruIconTile(icon: RadIcons.server, tone: CruTileTone.neutral),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: CruType.callout.tint(c.label)),
                        Text(s.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.caption.tint(c.label2)),
                      ],
                    ),
                  ),
                  if (s.isDefault) ...[
                    CruPill(text: 'Default', background: c.inset, foreground: c.label2),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  const RadNotConnected(title: 'Not connected yet', body: '', compact: true),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s12, CruSpace.s8, CruSpace.s4),
            child: RadNotConnected(title: 'PACS isn\'t connected yet', body: _pacsNotConnected),
          ),
        ],
      ),
      footer: Row(
        children: [
          CruButton(
            label: 'Add PACS',
            icon: CruIcons.plus,
            kind: CruButtonKind.secondary,
            onPressed: () => showRadPacsServerDialog(context),
          ),
          const Spacer(),
          CruButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// Add or edit one PACS server.
Future<void> showRadPacsServerDialog(BuildContext context, {RadPacsServer? existing}) =>
    showDialog<void>(context: context, builder: (_) => _PacsServerDialog(existing: existing));

class _PacsServerDialog extends ConsumerStatefulWidget {
  const _PacsServerDialog({this.existing});

  final RadPacsServer? existing;

  @override
  ConsumerState<_PacsServerDialog> createState() => _PacsServerDialogState();
}

class _PacsServerDialogState extends ConsumerState<_PacsServerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final _user = TextEditingController(text: widget.existing?.username ?? '');
  late String _auth = widget.existing?.auth ?? 'none';
  late bool _default = widget.existing?.isDefault ?? false;
  bool _tested = false;
  bool _dirty = false;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(radiologyProvider);
    final s = RadPacsServer(
      id: widget.existing?.id ?? radId('pacs_'),
      name: _name.text.trim(),
      baseUrl: _url.text.trim(),
      auth: _auth,
      username: _user.text.trim(),
      isDefault: _default,
    );
    if (_default) {
      // Only one default.
      for (final o in ref.read(radPacsServersProvider).value ?? const <RadPacsServer>[]) {
        if (o.id != s.id && o.isDefault) {
          await ctrl.savePacsServer(RadPacsServer(
            id: o.id,
            name: o.name,
            baseUrl: o.baseUrl,
            auth: o.auth,
            username: o.username,
          ));
        }
      }
    }
    await ctrl.savePacsServer(s);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(context,
        title: 'Remove ${e.name}?', body: 'Only the saved address is removed.', action: 'Remove');
    if (!ok || !mounted) return;
    await ref.read(radiologyProvider).deletePacsServer(e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.existing == null ? 'Add PACS' : 'Edit PACS',
      subtitle: 'A DICOMweb server',
      leading: const CruIconTile(icon: RadIcons.server, tone: CruTileTone.accent),
      submitLabel: widget.existing == null ? 'Add PACS' : 'Save changes',
      onSubmit: _save,
      dirty: _dirty,
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Server',
              description: 'Ask whoever runs the PACS for its DICOMweb address.',
              children: [
                CruTextField(
                  label: 'Name',
                  controller: _name,
                  autofocus: widget.existing == null,
                  hint: 'City Hospital PACS',
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
                  onChanged: (_) => _edited(),
                ),
                CruTextField(
                  label: 'DICOMweb address',
                  controller: _url,
                  hint: 'http://192.168.1.20:8042/dicom-web',
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    final u = Uri.tryParse((v ?? '').trim());
                    return u == null || !u.hasScheme || u.host.isEmpty
                        ? 'Enter a full address starting with http:// or https://.'
                        : null;
                  },
                  onChanged: (_) => _edited(),
                ),
                CruFieldRow(children: [
                  CruFieldFrame(
                    label: 'Sign-in',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CruSegmentedControl<String>(
                        semanticLabel: 'Sign-in',
                        segments: const [
                          CruSegment('none', 'None'),
                          CruSegment('basic', 'Password'),
                          CruSegment('bearer', 'Token'),
                        ],
                        selected: _auth,
                        onChanged: (a) {
                          setState(() => _auth = a);
                          _edited();
                        },
                      ),
                    ),
                  ),
                  if (_auth == 'basic')
                    CruTextField(
                      label: 'Username',
                      controller: _user,
                      onChanged: (_) => _edited(),
                    ),
                ]),
                if (_auth != 'none')
                  Text(
                    'The password or token is asked for when the connection is set up; '
                    'CruDoc doesn\'t store it here.',
                    style: CruType.caption.tint(context.cru.label2),
                  ),
                DentalChoiceChip(
                  label: 'Use as default',
                  selected: _default,
                  onTap: () {
                    setState(() => _default = !_default);
                    _edited();
                  },
                ),
              ],
            ),
            CruFormSection(
              title: 'Connection',
              children: [
                if (_tested)
                  const RadNotConnected(title: 'Not connected yet', body: _pacsNotConnected)
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruButton(
                      label: 'Test connection',
                      kind: CruButtonKind.secondary,
                      icon: RadIcons.server,
                      onPressed: () => setState(() => _tested = true),
                    ),
                  ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(label: 'Remove this PACS', onPressed: _delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ receiver

/// "Send to CruDoc" from a scanner: the DICOM receiver's name and port.
Future<void> showRadDicomReceiverDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ReceiverDialog());

class _ReceiverDialog extends ConsumerStatefulWidget {
  const _ReceiverDialog();

  @override
  ConsumerState<_ReceiverDialog> createState() => _ReceiverDialogState();
}

class _ReceiverDialogState extends ConsumerState<_ReceiverDialog> {
  TextEditingController? _ae;
  TextEditingController? _port;
  List<String> _addresses = const [];

  @override
  void initState() {
    super.initState();
    NetworkInterface.list(type: InternetAddressType.IPv4).then((list) {
      if (!mounted) return;
      setState(() => _addresses = [
            for (final i in list)
              for (final a in i.addresses)
                if (!a.isLoopback) a.address,
          ]);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ae?.dispose();
    _port?.dispose();
    super.dispose();
  }

  Future<void> _save(RadSettings s) async {
    final port = int.tryParse(_port!.text.trim()) ?? s.dicomPort;
    final ae = _ae!.text.trim().toUpperCase();
    await ref.read(radiologyProvider).saveSettings(s.copyWith(
          aeTitle: ae.isEmpty ? 'CRUDOC' : ae,
          dicomPort: port.clamp(1, 65535),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = ref.watch(radSettingsProvider).value;
    if (s != null) {
      _ae ??= TextEditingController(text: s.aeTitle);
      _port ??= TextEditingController(text: '${s.dicomPort}');
    }
    return DentalPanelDialog(
      title: 'Receive from scanners',
      subtitle: 'Scanners and PACS "Send to CruDoc" (DICOM C-STORE)',
      leading: const CruIconTile(icon: RadIcons.cube, tone: CruTileTone.neutral),
      body: s == null
          ? const SizedBox(height: 120)
          : Padding(
              padding: const EdgeInsets.all(CruSpace.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CruFieldRow(children: [
                    CruTextField(
                      label: 'AE title',
                      controller: _ae!,
                      help: 'Up to 16 letters, the name scanners send to.',
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(16),
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                      ],
                    ),
                    CruTextField(
                      label: 'Port',
                      controller: _port!,
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ]),
                  const SizedBox(height: CruSpace.s16),
                  Text('Set up on the scanner', style: CruType.subhead.w600.tint(c.label)),
                  const SizedBox(height: CruSpace.s6),
                  Text(
                    'Add a DICOM destination with AE title ${_ae?.text ?? s.aeTitle}, port '
                    '${_port?.text ?? s.dicomPort} and this computer\'s address'
                    '${_addresses.isEmpty ? '' : ' (${_addresses.join(', ')})'}.',
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s16),
                  const RadNotConnected(
                    title: 'The receiver isn\'t connected yet',
                    body: 'These settings are saved. CruDoc starts listening for scans on '
                        'this port with the connection update; until then, export from the '
                        'scanner to a folder or USB drive and import it.',
                  ),
                ],
              ),
            ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: CruSpace.s10),
          CruButton(label: 'Save', onPressed: s == null ? null : () => _save(s)),
        ],
      ),
    );
  }
}
