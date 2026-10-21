import 'dart:io';

import 'package:dicom_net/dicom_net.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/pacs_connection.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/rad_import_flow.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A one-line result: green check when it worked, otherwise a notice.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.ok, required this.title, this.body = ''});

  final bool ok;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (!ok) return RadNotConnected(title: title, body: body);
    return Row(
      children: [
        CruIcon(CruIcons.check, size: 16, strokeWidth: 2, color: c.greenText),
        const SizedBox(width: CruSpace.s8),
        Expanded(
          child: Text(title, style: CruType.subhead.w500.tint(c.greenText)),
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        SizedBox(
          width: CruSpace.s16,
          height: CruSpace.s16,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
        ),
        const SizedBox(width: CruSpace.s10),
        Text(text, style: CruType.subhead.tint(c.label2)),
      ],
    );
  }
}

// ============================================================ query

/// Search a PACS for a patient's studies and download one.
Future<void> showRadPacsQueryDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _PacsQueryDialog(),
);

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
  bool _searching = false;
  String? _error;
  String _errorTitle = '';
  List<DicomStudySummary>? _results;

  /// The study being downloaded, and how far along.
  String? _downloading;
  String _progress = '';

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _accession.dispose();
    super.dispose();
  }

  Future<void> _search(RadPacsServer server) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final client = await radPacsClient(server);
      final r = await client.searchStudies(
        patientName: _name.text,
        patientId: _id.text,
        accession: _accession.text,
        from: _from,
        to: _to,
        modalities: _modalities,
      );
      r.sort(
        (a, b) => (b.studyDate ?? DateTime(0)).compareTo(
          a.studyDate ?? DateTime(0),
        ),
      );
      if (mounted) setState(() => _results = r);
    } on DicomWebException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorTitle = 'Couldn\'t search the PACS';
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(RadPacsServer server, DicomStudySummary s) async {
    setState(() {
      _downloading = s.studyUid;
      _progress = '';
      _error = null;
    });
    String? dir;
    try {
      dir = await radDownloadPacsStudy(
        server,
        s.studyUid,
        onProgress: (got, total) {
          if (!mounted) return;
          setState(
            () => _progress = total == null || total == 0
                ? RadFormat.bytes(got)
                : '${(got * 100 / total).round()}%',
          );
        },
      );
      await ref
          .read(radiologyProvider)
          .log(
            'Downloaded from PACS',
            detail: '${server.name} · ${s.displayName}',
          );
      if (!mounted) return;
      setState(() => _downloading = null);
      final added = await runRadImport(context, ref, paths: [dir]);
      if (added > 0 && mounted) Navigator.of(context).pop();
    } on DicomWebException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorTitle = 'Couldn\'t download the study';
        });
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
      if (dir != null) {
        try {
          await Directory(dir).delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final servers =
        ref.watch(radPacsServersProvider).value ?? const <RadPacsServer>[];
    final server =
        servers.where((s) => s.id == _serverId).firstOrNull ??
        servers.where((s) => s.isDefault).firstOrNull ??
        servers.firstOrNull;
    final results = _results;

    return DentalPanelDialog(
      title: 'Search PACS',
      subtitle: server == null
          ? 'No PACS added yet'
          : '${server.name} · ${server.baseUrl}',
      leading: const CruIconTile(
        icon: RadIcons.server,
        tone: CruTileTone.accent,
      ),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s8,
          vertical: CruSpace.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (servers.isEmpty)
              DentalEmptyState(
                icon: RadIcons.server,
                title: 'Add your PACS first',
                body:
                    'Enter the DICOMweb address of the practice or hospital PACS '
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
                    onTap: (s) => setState(() {
                      _serverId = s.id;
                      _results = null;
                      _error = null;
                    }),
                  ),
                ),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Patient name',
                    controller: _name,
                    optional: true,
                    onSubmitted: (_) => _search(server!),
                  ),
                  CruTextField(
                    label: 'Patient ID',
                    controller: _id,
                    optional: true,
                    onSubmitted: (_) => _search(server!),
                  ),
                  CruTextField(
                    label: 'Accession',
                    controller: _accession,
                    optional: true,
                    onSubmitted: (_) => _search(server!),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              CruFieldRow(
                children: [
                  CruPickerField(
                    label: 'From',
                    optional: true,
                    icon: CruIcons.calendar,
                    value: _from == null ? null : RadFormat.date(_from!),
                    placeholder: 'Any date',
                    onTap: () async {
                      final d = await pickDentalDate(
                        context,
                        initial: _from ?? DateTime.now(),
                        last: DateTime.now(),
                      );
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
                      final d = await pickDentalDate(
                        context,
                        initial: _to ?? DateTime.now(),
                        last: DateTime.now(),
                      );
                      if (d != null) setState(() => _to = d);
                    },
                  ),
                ],
              ),
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
                    () => _modalities.contains(m)
                        ? _modalities.remove(m)
                        : _modalities.add(m),
                  ),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              if (_error != null) ...[
                RadNotConnected(title: _errorTitle, body: _error!),
                const SizedBox(height: CruSpace.s12),
              ],
              if (_searching)
                const _Busy('Searching…')
              else if (results == null)
                Text(
                  'Results appear here with each study\'s date, type and image count; '
                  'download one to add it to the worklist.',
                  style: CruType.caption.tint(c.label2),
                )
              else if (results.isEmpty)
                Text(
                  'No studies match. Try fewer filters.',
                  style: CruType.subhead.tint(c.label2),
                )
              else ...[
                DentalGroupLabel(
                  'Results',
                  trailing: results.length == 1
                      ? '1 study'
                      : '${results.length} studies',
                ),
                for (var i = 0; i < results.length; i++) ...[
                  if (i > 0) const CruSeparator(),
                  _ResultRow(
                    study: results[i],
                    downloading: _downloading == results[i].studyUid,
                    progress: _progress,
                    enabled: _downloading == null,
                    onDownload: () => _download(server!, results[i]),
                  ),
                ],
              ],
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
              label: _searching ? 'Searching…' : 'Search',
              icon: CruIcons.search,
              onPressed: _searching || _downloading != null
                  ? null
                  : () => _search(server!),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.study,
    required this.downloading,
    required this.progress,
    required this.enabled,
    required this.onDownload,
  });

  final DicomStudySummary study;
  final bool downloading;
  final String progress;
  final bool enabled;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final detail = [
      if (study.studyDate != null) RadFormat.date(study.studyDate!),
      if (study.modalities.isNotEmpty) study.modalities.join(', '),
      if (study.description.isNotEmpty) study.description,
      if (study.instanceCount > 0) RadFormat.images(study.instanceCount),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s4,
        vertical: CruSpace.s10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    study.displayName.isEmpty
                        ? 'Unnamed patient'
                        : study.displayName,
                    if (study.patientId.isNotEmpty) study.patientId,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruButton(
            label: downloading
                ? (progress.isEmpty ? 'Downloading…' : 'Downloading $progress')
                : 'Download',
            kind: CruButtonKind.inset,
            onPressed: enabled ? onDownload : null,
          ),
        ],
      ),
    );
  }
}

// ============================================================ servers

/// The saved PACS servers: add, edit, make default.
Future<void> showRadPacsServersDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _PacsServersDialog(),
);

class _PacsServersDialog extends ConsumerWidget {
  const _PacsServersDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final servers =
        ref.watch(radPacsServersProvider).value ?? const <RadPacsServer>[];
    return DentalPanelDialog(
      title: 'PACS servers',
      subtitle: 'DICOMweb addresses you can search and send to',
      leading: const CruIconTile(
        icon: RadIcons.server,
        tone: CruTileTone.neutral,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (servers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Text(
                'None added yet.',
                style: CruType.subhead.tint(c.label2),
              ),
            ),
          for (final s in servers)
            DentalListRow(
              semanticLabel: s.name,
              onTap: () => showRadPacsServerDialog(context, existing: s),
              child: Row(
                children: [
                  const CruIconTile(
                    icon: RadIcons.server,
                    tone: CruTileTone.neutral,
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: CruType.callout.tint(c.label)),
                        Text(
                          s.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  if (s.isDefault)
                    CruPill(
                      text: 'Default',
                      background: c.inset,
                      foreground: c.label2,
                    ),
                ],
              ),
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
          CruButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Add or edit one PACS server.
Future<void> showRadPacsServerDialog(
  BuildContext context, {
  RadPacsServer? existing,
}) => showDialog<void>(
  context: context,
  builder: (_) => _PacsServerDialog(existing: existing),
);

class _PacsServerDialog extends ConsumerStatefulWidget {
  const _PacsServerDialog({this.existing});

  final RadPacsServer? existing;

  @override
  ConsumerState<_PacsServerDialog> createState() => _PacsServerDialogState();
}

enum _Test { idle, testing, ok, failed }

class _PacsServerDialogState extends ConsumerState<_PacsServerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final _user = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  final _secret = TextEditingController();
  late final String _id = widget.existing?.id ?? radId('pacs_');
  late String _auth = widget.existing?.auth ?? 'none';
  late bool _default = widget.existing?.isDefault ?? false;
  _Test _test = _Test.idle;
  String _testMessage = '';
  bool _dirty = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      RadPacsSecrets.read(_id).then((s) {
        if (mounted && _secret.text.isEmpty) _secret.text = s;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _edited() {
    setState(() {
      _dirty = true;
      _test = _Test.idle;
    });
  }

  RadPacsServer _fromForm({bool? isDefault}) => RadPacsServer(
    id: _id,
    name: _name.text.trim(),
    baseUrl: _url.text.trim(),
    auth: _auth,
    username: _auth == 'basic' ? _user.text.trim() : '',
    isDefault: isDefault ?? _default,
  );

  Future<void> _runTest() async {
    final u = Uri.tryParse(_url.text.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      setState(() {
        _test = _Test.failed;
        _testMessage = 'Enter the full DICOMweb address first.';
      });
      return;
    }
    setState(() => _test = _Test.testing);
    try {
      final client = await radPacsClient(
        _fromForm(),
        secret: _auth == 'none' ? '' : _secret.text,
      );
      await client.ping();
      if (mounted) setState(() => _test = _Test.ok);
    } on DicomWebException catch (e) {
      if (mounted) {
        setState(() {
          _test = _Test.failed;
          _testMessage = e.message;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(radiologyProvider);
    final s = _fromForm();
    if (_default) {
      // Only one default.
      for (final o
          in ref.read(radPacsServersProvider).value ??
              const <RadPacsServer>[]) {
        if (o.id != s.id && o.isDefault) {
          await ctrl.savePacsServer(
            RadPacsServer(
              id: o.id,
              name: o.name,
              baseUrl: o.baseUrl,
              auth: o.auth,
              username: o.username,
            ),
          );
        }
      }
    }
    await RadPacsSecrets.write(s.id, _auth == 'none' ? '' : _secret.text);
    await ctrl.savePacsServer(s);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDental(
      context,
      title: 'Remove ${e.name}?',
      body: 'Only the saved address is removed.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await RadPacsSecrets.delete(e.id);
    await ref.read(radiologyProvider).deletePacsServer(e);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.existing == null ? 'Add PACS' : 'Edit PACS',
      subtitle: 'A DICOMweb server',
      leading: const CruIconTile(
        icon: RadIcons.server,
        tone: CruTileTone.accent,
      ),
      submitLabel: widget.existing == null ? 'Add PACS' : 'Save changes',
      onSubmit: _save,
      dirty: _dirty,
      body: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Server',
              description:
                  'Ask whoever runs the PACS for its DICOMweb address.',
              children: [
                CruTextField(
                  label: 'Name',
                  controller: _name,
                  autofocus: widget.existing == null,
                  hint: 'City Hospital PACS',
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
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
                CruFieldRow(
                  children: [
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
                            _auth = a;
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
                  ],
                ),
                if (_auth != 'none')
                  CruTextField(
                    label: _auth == 'basic' ? 'Password' : 'Token',
                    controller: _secret,
                    obscureText: true,
                    help:
                        'Kept in this device\'s secure storage and never synced; '
                        'enter it again on each computer.',
                    onChanged: (_) => _edited(),
                  ),
                DentalChoiceChip(
                  label: 'Use as default',
                  selected: _default,
                  onTap: () {
                    _default = !_default;
                    _edited();
                  },
                ),
              ],
            ),
            CruFormSection(
              title: 'Connection',
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruButton(
                    label: _test == _Test.testing
                        ? 'Testing…'
                        : 'Test connection',
                    kind: CruButtonKind.secondary,
                    icon: RadIcons.server,
                    onPressed: _test == _Test.testing ? null : _runTest,
                  ),
                ),
                if (_test == _Test.ok)
                  const _Outcome(
                    ok: true,
                    title: 'Connected — the PACS answered a search.',
                  )
                else if (_test == _Test.failed)
                  _Outcome(
                    ok: false,
                    title: 'Couldn\'t connect',
                    body: _testMessage,
                  ),
                if (widget.existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Remove this PACS',
                      onPressed: _delete,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ send

/// Uploads [study] to the default PACS (or the only one).
Future<void> sendRadStudyToPacs(
  BuildContext context,
  WidgetRef ref,
  RadStudy study,
) async {
  final servers = await ref.read(radPacsServersProvider.future);
  final server =
      servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
  if (server == null) {
    if (context.mounted) await showRadPacsServerDialog(context);
    return;
  }
  if (!context.mounted) return;
  radToast(context, 'Sending to ${server.name}…');
  try {
    final r = await radSendStudyToPacs(
      ref.read(radiologyProvider),
      study,
      server,
    );
    if (!context.mounted) return;
    radToast(
      context,
      r.sent == 0 && r.failed == 0
          ? 'Nothing to send: only DICOM images can go to a PACS.'
          : [
              'Sent ${RadFormat.images(r.sent)} to ${server.name}',
              if (r.failed > 0) '${r.failed} refused',
              if (r.skipped > 0) '${r.skipped} pictures skipped (not DICOM)',
            ].join(' · '),
    );
  } on DicomWebException catch (e) {
    if (context.mounted) radToast(context, 'Couldn\'t send: ${e.message}');
  }
}

// ============================================================ receiver

/// Adds the scans received from scanners to the worklist.
Future<void> importRadReceived(BuildContext context, WidgetRef ref) async {
  final paths = List.of(ref.read(radReceiverProvider).received);
  if (paths.isEmpty) return;
  final added = await runRadImport(context, ref, paths: paths);
  if (added > 0) await ref.read(radReceiverProvider.notifier).clear(paths);
}

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
  bool? _on;
  List<String> _addresses = const [];

  @override
  void initState() {
    super.initState();
    radLocalAddresses().then((a) {
      if (mounted) setState(() => _addresses = a);
    });
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
    await ref
        .read(radiologyProvider)
        .saveSettings(
          s.copyWith(
            aeTitle: ae.isEmpty ? 'CRUDOC' : ae,
            dicomPort: port.clamp(1, 65535),
            dicomReceiverOn: _on ?? s.dicomReceiverOn,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = ref.watch(radSettingsProvider).value;
    final rx = ref.watch(radReceiverProvider);
    if (s != null) {
      _ae ??= TextEditingController(text: s.aeTitle);
      _port ??= TextEditingController(text: '${s.dicomPort}');
      _on ??= s.dicomReceiverOn;
    }
    final changed =
        s != null &&
        (_on != s.dicomReceiverOn ||
            _ae!.text.trim().toUpperCase() != s.aeTitle ||
            _port!.text.trim() != '${s.dicomPort}');
    return DentalPanelDialog(
      title: 'Receive from scanners',
      subtitle: 'Scanners and PACS "Send to CruDoc" (DICOM C-STORE)',
      leading: const CruIconTile(
        icon: RadIcons.cube,
        tone: CruTileTone.neutral,
      ),
      body: s == null
          ? const SizedBox(height: 120)
          : Padding(
              padding: const EdgeInsets.all(CruSpace.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CruFieldFrame(
                    label: 'Receiving',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CruSegmentedControl<bool>(
                        semanticLabel: 'Receiving',
                        segments: const [
                          CruSegment(false, 'Off'),
                          CruSegment(true, 'On'),
                        ],
                        selected: _on!,
                        onChanged: (v) => setState(() => _on = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s12),
                  CruFieldRow(
                    children: [
                      CruTextField(
                        label: 'AE title',
                        controller: _ae!,
                        help: 'Up to 16 letters, the name scanners send to.',
                        onChanged: (_) => setState(() {}),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(16),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]'),
                          ),
                        ],
                      ),
                      CruTextField(
                        label: 'Port',
                        controller: _port!,
                        tabular: true,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s16),
                  Text(
                    'Set up on the scanner',
                    style: CruType.subhead.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s6),
                  Text(
                    'Add a DICOM destination with AE title ${_ae?.text ?? s.aeTitle}, port '
                    '${_port?.text ?? s.dicomPort} and this computer\'s address'
                    '${_addresses.isEmpty ? '' : ' (${_addresses.join(', ')})'}.',
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s16),
                  if (changed)
                    Text(
                      'Save to apply.',
                      style: CruType.caption.tint(c.label2),
                    )
                  else if (!s.dicomReceiverOn)
                    Text(
                      'Switched off: scans sent here are refused.',
                      style: CruType.caption.tint(c.label2),
                    )
                  else if (rx.error != null)
                    RadNotConnected(
                      title: 'Not listening',
                      body: rx.error!,
                    )
                  else if (rx.listening)
                    _Outcome(
                      ok: true,
                      title:
                          'Listening on port ${s.dicomPort} while CruDoc is open.',
                    )
                  else
                    const _Busy('Starting…'),
                  if (rx.received.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${RadFormat.images(rx.received.length)} received'
                            '${rx.lastFrom.isEmpty ? '' : ' from ${rx.lastFrom}'}',
                            style: CruType.subhead.tabular.tint(c.label),
                          ),
                        ),
                        CruButton(
                          label: 'Add to worklist',
                          kind: CruButtonKind.inset,
                          onPressed: () => importRadReceived(context, ref),
                        ),
                      ],
                    ),
                  ],
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
          CruButton(
            label: 'Save',
            onPressed: s == null ? null : () => _save(s),
          ),
        ],
      ),
    );
  }
}
