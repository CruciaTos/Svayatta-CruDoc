import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dicom_net/dicom_net.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogKind { request, upload, send, error, info }

class LogEntry {
  LogEntry(this.kind, this.text, {this.detail = ''}) : at = DateTime.now();
  final DateTime at;
  final LogKind kind;
  final String text;
  final String detail;
}

/// Settings kept between runs.
class SimSettings {
  int port = 8042;
  DicomWebAuth auth = DicomWebAuth.none;
  String username = 'crudoc';
  String secret = '';
  String crudocHost = '';
  int crudocPort = 11112;
  String crudocAe = 'CRUDOC';
  String ourAe = 'PACSSIM';

  Map<String, Object> toJson() => {
    'port': port,
    'auth': auth.name,
    'username': username,
    'secret': secret,
    'crudocHost': crudocHost,
    'crudocPort': crudocPort,
    'crudocAe': crudocAe,
    'ourAe': ourAe,
  };

  void read(Map<String, dynamic> j) {
    port = j['port'] as int? ?? port;
    auth = DicomWebAuth.values.firstWhere(
      (a) => a.name == j['auth'],
      orElse: () => DicomWebAuth.none,
    );
    username = j['username'] as String? ?? username;
    secret = j['secret'] as String? ?? secret;
    crudocHost = j['crudocHost'] as String? ?? crudocHost;
    crudocPort = j['crudocPort'] as int? ?? crudocPort;
    crudocAe = j['crudocAe'] as String? ?? crudocAe;
    ourAe = j['ourAe'] as String? ?? ourAe;
  }
}

/// The simulated PACS: a DICOMweb server over a folder of studies, plus
/// a DICOM sender that pushes studies to CruDoc's receiver.
class Simulator extends ChangeNotifier {
  final settings = SimSettings();
  late final FolderPacsStore store;
  late final File _settingsFile;

  DicomWebServer? _server;
  StreamSubscription<DicomWebEvent>? _sub;
  String? serverError;
  List<String> addresses = const [];
  final log = <LogEntry>[];
  bool ready = false;

  /// Study UIDs being sent to CruDoc, with progress text.
  final sending = <String, String>{};
  bool busy = false;

  bool get running => _server?.running ?? false;

  String get dicomWebPath => DicomWebServer.prefix;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}${Platform.pathSeparator}pacs_simulator');
    store = FolderPacsStore(Directory('${root.path}${Platform.pathSeparator}archive'));
    _settingsFile = File('${root.path}${Platform.pathSeparator}settings.json');
    await root.create(recursive: true);
    if (await _settingsFile.exists()) {
      try {
        settings.read(jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    await store.load();
    await refreshAddresses();
    ready = true;
    notifyListeners();
    await startServer();
  }

  Future<void> saveSettings() async {
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      addresses = [
        for (final i in list)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      addresses = const [];
    }
    notifyListeners();
  }

  void _add(LogKind kind, String text, {String detail = ''}) {
    log.insert(0, LogEntry(kind, text, detail: detail));
    if (log.length > 400) log.removeLast();
    notifyListeners();
  }

  Future<void> startServer() async {
    await stopServer(quiet: true);
    final s = DicomWebServer(
      store,
      auth: settings.auth,
      username: settings.username,
      secret: settings.secret,
      onStored: (list) {
        final studies = {for (final i in list) i.studyUid}.length;
        _add(
          LogKind.upload,
          'CruDoc sent ${list.length} image${list.length == 1 ? '' : 's'} '
          '($studies stud${studies == 1 ? 'y' : 'ies'})',
          detail: list.first[DicomAttr.patientName].replaceAll('^', ' '),
        );
      },
    );
    try {
      await s.start(settings.port);
      _server = s;
      serverError = null;
      _sub = s.events.listen(
        (e) => _add(
          e.status >= 400 ? LogKind.error : LogKind.request,
          e.summary,
          detail: '${e.method} ${e.path} → ${e.status} · from ${e.remote}',
        ),
      );
      _add(LogKind.info, 'PACS started on port ${settings.port}');
    } on SocketException catch (e) {
      serverError = 'Port ${settings.port} is busy or blocked (${e.osError?.message ?? e.message}).';
      _add(LogKind.error, 'Couldn\'t start', detail: serverError!);
    }
    notifyListeners();
  }

  Future<void> stopServer({bool quiet = false}) async {
    await _sub?.cancel();
    _sub = null;
    final was = _server != null;
    await _server?.stop();
    _server = null;
    if (was && !quiet) _add(LogKind.info, 'PACS stopped');
    notifyListeners();
  }

  Future<void> addSamples(int count) async {
    busy = true;
    notifyListeners();
    try {
      final files = await compute(_generate, count);
      for (final f in files) {
        await store.add(f, source: 'Sample');
      }
      _add(LogKind.info, 'Added $count sample stud${count == 1 ? 'y' : 'ies'} (${files.length} images)');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> importFiles(List<String> paths) async {
    busy = true;
    notifyListeners();
    var ok = 0, bad = 0;
    try {
      for (final p in paths) {
        try {
          await store.add(await File(p).readAsBytes(), source: 'Imported');
          ok++;
        } catch (_) {
          bad++;
        }
      }
      _add(
        bad == 0 ? LogKind.info : LogKind.error,
        'Imported $ok file${ok == 1 ? '' : 's'}${bad > 0 ? ' · $bad weren\'t DICOM' : ''}',
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteStudy(String uid) async {
    await store.deleteStudy(uid);
    notifyListeners();
  }

  DimseClient _crudoc() => DimseClient(
    host: settings.crudocHost.trim(),
    port: settings.crudocPort,
    calledAe: settings.crudocAe,
    callingAe: settings.ourAe,
  );

  /// C-ECHO to CruDoc's receiver. Returns a message for the screen.
  Future<String> echoCrudoc() async {
    if (settings.crudocHost.trim().isEmpty) return 'Enter the address of the computer running CruDoc first.';
    try {
      final t = await _crudoc().echo();
      _add(LogKind.send, 'Echo to CruDoc answered in ${t.inMilliseconds} ms');
      return 'CruDoc answered in ${t.inMilliseconds} ms. Ready to send.';
    } on DimseException catch (e) {
      _add(LogKind.error, 'Echo to CruDoc failed', detail: e.message);
      return e.message;
    }
  }

  /// C-STORE of one study to CruDoc's receiver.
  Future<String> sendStudy(String studyUid) async {
    if (settings.crudocHost.trim().isEmpty) return 'Enter the address of the computer running CruDoc on the Send tab first.';
    final list = store.instances.where((i) => i.studyUid == studyUid).toList();
    if (list.isEmpty) return 'Nothing to send.';
    final name = list.first[DicomAttr.patientName].replaceAll('^', ' ');
    sending[studyUid] = 'Connecting…';
    notifyListeners();
    try {
      final files = [for (final i in list) await store.read(i)];
      final r = await _crudoc().store(
        files,
        onProgress: (done, total) {
          sending[studyUid] = '$done of $total';
          notifyListeners();
        },
      );
      final msg = r.failed == 0
          ? 'Sent ${r.sent} image${r.sent == 1 ? '' : 's'} of $name to CruDoc.'
          : 'Sent ${r.sent}, ${r.failed} failed: ${r.errors.first}';
      _add(r.failed == 0 ? LogKind.send : LogKind.error, msg);
      return msg;
    } on DimseException catch (e) {
      _add(LogKind.error, 'Send to CruDoc failed', detail: e.message);
      return e.message;
    } finally {
      sending.remove(studyUid);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopServer(quiet: true);
    super.dispose();
  }
}

// compute() needs a top-level function.
List<Uint8List> _generate(int count) => SyntheticStudies.generate(count: count);
