import 'package:dicom_net/dicom_net.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'simulator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PacsSimulatorApp());
}

class PacsSimulatorApp extends StatefulWidget {
  const PacsSimulatorApp({super.key});

  @override
  State<PacsSimulatorApp> createState() => _PacsSimulatorAppState();
}

class _PacsSimulatorAppState extends State<PacsSimulatorApp> {
  final sim = Simulator();

  @override
  void initState() {
    super.initState();
    sim.init();
  }

  @override
  void dispose() {
    sim.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorSchemeSeed: const Color(0xFF2F54EB),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PACS Simulator',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: ListenableBuilder(
      listenable: sim,
      builder: (context, _) => sim.ready
          ? HomeScreen(sim: sim)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.sim});
  final Simulator sim;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final sim = widget.sim;
    final pages = [
      ServerPage(sim: sim),
      StudiesPage(sim: sim, goToSend: () => setState(() => _tab = 2)),
      SendPage(sim: sim),
      ActivityPage(sim: sim),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('PACS Simulator'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StatusChip(running: sim.running),
          ),
        ],
      ),
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dns_outlined), label: 'Server'),
          NavigationDestination(
            icon: Badge.count(
              count: sim.store.byStudy().length,
              isLabelVisible: sim.store.instances.isNotEmpty,
              child: const Icon(Icons.folder_open_outlined),
            ),
            label: 'Studies',
          ),
          const NavigationDestination(icon: Icon(Icons.send_outlined), label: 'Send'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Activity'),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    final color = running ? Colors.green : Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(running ? 'Running' : 'Stopped'),
      ],
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: t.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Server ─────────────────────────────

class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.sim});
  final Simulator sim;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final _port = TextEditingController(text: '${widget.sim.settings.port}');
  late final _user = TextEditingController(text: widget.sim.settings.username);
  late final _secret = TextEditingController(text: widget.sim.settings.secret);
  late DicomWebAuth _auth = widget.sim.settings.auth;

  @override
  void dispose() {
    _port.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    widget.sim.settings
      ..port = int.tryParse(_port.text.trim())?.clamp(1, 65535) ?? 8042
      ..auth = _auth
      ..username = _user.text.trim()
      ..secret = _secret.text;
    await widget.sim.saveSettings();
    await widget.sim.startServer();
    if (mounted) _toast(context, widget.sim.running ? 'Restarted with the new settings' : 'Couldn\'t start');
  }

  @override
  Widget build(BuildContext context) {
    final sim = widget.sim;
    final t = Theme.of(context).textTheme;
    final urls = [
      for (final a in sim.addresses) 'http://$a:${sim.settings.port}${sim.dicomWebPath}',
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _Section(
          title: 'This phone is a PACS',
          subtitle:
              'CruDoc can search it, download studies from it and send studies to it '
              'over DICOMweb — the same way it talks to Orthanc or dcm4chee.',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(sim.running ? 'Running' : 'Stopped'),
              subtitle: Text(
                sim.serverError ??
                    '${sim.store.byStudy().length} studies · ${sim.store.instances.length} images',
              ),
              value: sim.running,
              onChanged: (on) => on ? sim.startServer() : sim.stopServer(),
            ),
          ],
        ),
        _Section(
          title: 'Add it in CruDoc',
          subtitle:
              'Radiology → PACS → Add PACS. Put this phone and the CruDoc computer on the '
              'same Wi-Fi, then enter one of these as the DICOMweb address:',
          children: [
            if (urls.isEmpty)
              const Text('No network found. Connect to Wi-Fi, then tap refresh.'),
            for (final u in urls)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(u, style: t.titleSmall?.copyWith(fontFamily: 'monospace'))),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: u));
                        _toast(context, 'Copied');
                      },
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: sim.refreshAddresses,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh addresses'),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Settings',
          subtitle: 'Turn on sign-in to check that CruDoc sends the password or token.',
          children: [
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            SegmentedButton<DicomWebAuth>(
              segments: const [
                ButtonSegment(value: DicomWebAuth.none, label: Text('None')),
                ButtonSegment(value: DicomWebAuth.basic, label: Text('Password')),
                ButtonSegment(value: DicomWebAuth.bearer, label: Text('Token')),
              ],
              selected: {_auth},
              onSelectionChanged: (s) => setState(() => _auth = s.first),
            ),
            if (_auth == DicomWebAuth.basic) ...[
              const SizedBox(height: 12),
              TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
            ],
            if (_auth != DicomWebAuth.none) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _secret,
                decoration: InputDecoration(
                  labelText: _auth == DicomWebAuth.basic ? 'Password' : 'Token',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _apply, child: const Text('Save and restart')),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────── Studies ─────────────────────────────

class StudiesPage extends StatelessWidget {
  const StudiesPage({super.key, required this.sim, required this.goToSend});
  final Simulator sim;
  final VoidCallback goToSend;

  Future<void> _import(BuildContext context) async {
    final r = await FilePicker.pickFiles(dialogTitle: 'Pick DICOM files');
    final paths = r.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    await sim.importFiles(paths);
  }

  Future<void> _send(BuildContext context, String uid) async {
    if (sim.settings.crudocHost.trim().isEmpty) {
      _toast(context, 'Set up CruDoc\'s address first.');
      goToSend();
      return;
    }
    final msg = await sim.sendStudy(uid);
    if (context.mounted) _toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final studies = sim.store.byStudy();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: sim.busy ? null : () => sim.addSamples(3),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Add 3 samples'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sim.busy ? null : () => _import(context),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import .dcm'),
                ),
              ),
            ],
          ),
        ),
        if (sim.busy) const LinearProgressIndicator(),
        Expanded(
          child: studies.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No studies yet. Add samples (a panoramic, two intraoral '
                      'images and a 40-slice CBCT for made-up TEST patients) or import real '
                      '.dcm files.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: studies.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final uid = studies.keys.elementAt(i);
                    final list = studies[uid]!;
                    final f = list.first;
                    final mods = {for (final x in list) x[DicomAttr.modality]}..remove('');
                    final date = parseDicomDate(f[DicomAttr.studyDate], f[DicomAttr.studyTime]);
                    final sending = sim.sending[uid];
                    final fromCrudoc = list.any((x) => x.source.startsWith('Received'));
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.secondaryContainer,
                        child: Text(
                          mods.isEmpty ? '?' : mods.first,
                          style: t.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
                        ),
                      ),
                      title: Text(
                        f[DicomAttr.patientName].replaceAll('^', ' ').trim().isEmpty
                            ? 'No name'
                            : f[DicomAttr.patientName].replaceAll('^', ' '),
                      ),
                      subtitle: Text(
                        [
                          if (date != null) '${date.day}/${date.month}/${date.year}',
                          if (f[DicomAttr.studyDescription].isNotEmpty) f[DicomAttr.studyDescription],
                          '${list.length} image${list.length == 1 ? '' : 's'}',
                          if (fromCrudoc) 'from CruDoc',
                          ?sending,
                        ].join(' · '),
                      ),
                      trailing: sending != null
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : PopupMenuButton<String>(
                              onSelected: (a) async {
                                if (a == 'send') await _send(context, uid);
                                if (a == 'delete') await sim.deleteStudy(uid);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'send', child: Text('Send to CruDoc')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                      onTap: sending != null ? null : () => _send(context, uid),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Send ─────────────────────────────

class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.sim});
  final Simulator sim;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late final s = widget.sim.settings;
  late final _host = TextEditingController(text: s.crudocHost);
  late final _port = TextEditingController(text: '${s.crudocPort}');
  late final _ae = TextEditingController(text: s.crudocAe);
  late final _ours = TextEditingController(text: s.ourAe);
  String? _result;
  bool _testing = false;
  bool _sendingAll = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _ae.dispose();
    _ours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    s
      ..crudocHost = _host.text.trim()
      ..crudocPort = int.tryParse(_port.text.trim())?.clamp(1, 65535) ?? 11112
      ..crudocAe = _ae.text.trim().toUpperCase()
      ..ourAe = _ours.text.trim().toUpperCase();
    await widget.sim.saveSettings();
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _result = null;
    });
    final r = await widget.sim.echoCrudoc();
    if (mounted) {
      setState(() {
        _testing = false;
        _result = r;
      });
    }
  }

  Future<void> _sendAll() async {
    await _save();
    setState(() => _sendingAll = true);
    var last = '';
    for (final uid in widget.sim.store.byStudy().keys.toList()) {
      last = await widget.sim.sendStudy(uid);
    }
    if (mounted) {
      setState(() {
        _sendingAll = false;
        _result = last.isEmpty ? 'No studies to send.' : 'Done. See Activity for each study.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ae = [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')), LengthLimitingTextInputFormatter(16)];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _Section(
          title: 'Send to CruDoc',
          subtitle:
              'Like a scanner or PACS pushing images (DICOM C-STORE). In CruDoc open '
              'Radiology → Import scans → Straight from the scanner, switch receiving on, '
              'and copy its address, AE title and port here.',
          children: [
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'CruDoc computer address', hintText: '192.168.1.5'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ae,
                    decoration: const InputDecoration(labelText: 'CruDoc AE title'),
                    inputFormatters: ae,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ours,
              decoration: const InputDecoration(labelText: 'This PACS\'s AE title', helperText: 'What CruDoc sees as the sender'),
              inputFormatters: ae,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing || _sendingAll ? null : _test,
                  icon: const Icon(Icons.network_ping, size: 18),
                  label: Text(_testing ? 'Testing…' : 'Test (echo)'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _testing || _sendingAll || widget.sim.store.instances.isEmpty ? null : _sendAll,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(_sendingAll ? 'Sending…' : 'Send all studies'),
                ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!),
            ],
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────── Activity ─────────────────────────────

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.sim});
  final Simulator sim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sim.log.isEmpty) {
      return const Center(child: Text('Requests from CruDoc show up here.'));
    }
    return ListView.builder(
      itemCount: sim.log.length,
      itemBuilder: (context, i) {
        final e = sim.log[i];
        final (icon, color) = switch (e.kind) {
          LogKind.request => (Icons.download_outlined, scheme.primary),
          LogKind.upload => (Icons.upload_outlined, Colors.green),
          LogKind.send => (Icons.send_outlined, Colors.green),
          LogKind.error => (Icons.error_outline, scheme.error),
          LogKind.info => (Icons.info_outline, scheme.outline),
        };
        final time =
            '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}:${e.at.second.toString().padLeft(2, '0')}';
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text(e.text),
          subtitle: e.detail.isEmpty ? null : Text(e.detail, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: Text(time, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        );
      },
    );
  }
}
