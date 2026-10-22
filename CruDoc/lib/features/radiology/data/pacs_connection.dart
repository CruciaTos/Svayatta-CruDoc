import 'dart:async';
import 'dart:io';

import 'package:dicom_net/dicom_net.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';

// ───────────────────────────── PACS (DICOMweb) ─────────────────────────────

/// PACS passwords and tokens live in this device's keychain, never in the
/// synced radiology records.
abstract final class RadPacsSecrets {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _key(String serverId) => 'rad_pacs_secret_$serverId';

  static Future<String> read(String serverId) async {
    try {
      return await _storage.read(key: _key(serverId)) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> write(String serverId, String secret) => secret.isEmpty
      ? _storage.delete(key: _key(serverId))
      : _storage.write(key: _key(serverId), value: secret);

  static Future<void> delete(String serverId) =>
      _storage.delete(key: _key(serverId));
}

DicomWebAuth _auth(String a) => switch (a) {
  'basic' => DicomWebAuth.basic,
  'bearer' => DicomWebAuth.bearer,
  _ => DicomWebAuth.none,
};

/// A client for [s]; [secret] overrides the saved one (for testing an
/// unsaved form).
Future<DicomWebClient> radPacsClient(RadPacsServer s, {String? secret}) async =>
    DicomWebClient(
      s.baseUrl,
      auth: _auth(s.auth),
      username: s.username,
      secret: secret ?? await RadPacsSecrets.read(s.id),
    );

/// Downloads a study into a new temporary folder and returns its path,
/// ready for the import flow.
Future<String> radDownloadPacsStudy(
  RadPacsServer server,
  String studyUid, {
  void Function(int received, int? total)? onProgress,
}) async {
  final client = await radPacsClient(server);
  final files = await client.retrieveStudy(studyUid, onProgress: onProgress);
  if (files.isEmpty) {
    throw DicomWebException('The PACS sent no images for this study.');
  }
  final temp = await getTemporaryDirectory();
  final dir = Directory(
    p.join(temp.path, 'crudoc_pacs_${DateTime.now().millisecondsSinceEpoch}'),
  );
  await dir.create(recursive: true);
  for (var i = 0; i < files.length; i++) {
    await File(
      p.join(dir.path, 'img_${i.toString().padLeft(4, '0')}.dcm'),
    ).writeAsBytes(files[i]);
  }
  return dir.path;
}

/// What sending a study to a PACS did.
class RadPacsSendResult {
  const RadPacsSendResult({
    required this.sent,
    required this.failed,
    required this.skipped,
  });

  final int sent;
  final int failed;

  /// Pictures (JPG, PNG…) a PACS can't take.
  final int skipped;
}

/// Uploads [study]'s DICOM images to [server] (STOW-RS).
Future<RadPacsSendResult> radSendStudyToPacs(
  RadiologyController ctrl,
  RadStudy study,
  RadPacsServer server,
) async {
  final files = <Uint8List>[];
  var skipped = 0;
  for (final img in study.images) {
    if (img.kind != RadFileKind.dicom) {
      skipped++;
      continue;
    }
    final f = await ctrl.fileOf(study, img.path);
    if (!await f.exists()) {
      skipped++;
      continue;
    }
    final bytes = await f.readAsBytes();
    if (DicomInstance.looksLikeDicom(bytes)) {
      files.add(bytes);
    } else {
      skipped++;
    }
  }
  if (files.isEmpty) {
    return RadPacsSendResult(sent: 0, failed: 0, skipped: skipped);
  }
  final r = await (await radPacsClient(server)).store(files);
  await ctrl.log(
    'Sent to PACS',
    targetKind: 'study',
    targetId: study.id,
    detail: '${server.name} · ${r.stored} images',
  );
  return RadPacsSendResult(sent: r.stored, failed: r.failed, skipped: skipped);
}

// ───────────────────────────── Receiver (C-STORE) ─────────────────────────────

/// The scanner receiver's state.
class RadReceiverState {
  const RadReceiverState({
    this.on = false,
    this.listening = false,
    this.error,
    this.received = const [],
    this.lastFrom = '',
  });

  /// Switched on in settings.
  final bool on;
  final bool listening;
  final String? error;

  /// Received files waiting to be added to the worklist.
  final List<String> received;

  /// "PACSSIM (192.168.1.8)".
  final String lastFrom;

  RadReceiverState copyWith({
    bool? listening,
    String? error,
    bool clearError = false,
    List<String>? received,
    String? lastFrom,
  }) => RadReceiverState(
    on: on,
    listening: listening ?? this.listening,
    error: clearError ? null : (error ?? this.error),
    received: received ?? this.received,
    lastFrom: lastFrom ?? this.lastFrom,
  );
}

/// Listens for scanners and PACS sending studies ("Send to CruDoc",
/// DICOM C-STORE) while switched on in Radiology settings. Received files
/// wait in an inbox until they are added to the worklist.
final radReceiverProvider =
    NotifierProvider<RadReceiverNotifier, RadReceiverState>(
      RadReceiverNotifier.new,
    );

class RadReceiverNotifier extends Notifier<RadReceiverState> {
  DimseServer? _server;

  static Future<Directory> inbox() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'rad_inbox'),
  );

  @override
  RadReceiverState build() {
    final cfg = ref.watch(
      radSettingsProvider.select(
        (a) => a.value == null
            ? null
            : (a.value!.dicomReceiverOn, a.value!.aeTitle, a.value!.dicomPort),
      ),
    );
    ref.onDispose(() {
      _server?.stop();
      _server = null;
    });
    if (kIsWeb || cfg == null || !cfg.$1) {
      _loadInbox(const RadReceiverState());
      return const RadReceiverState();
    }
    final (_, ae, port) = cfg;
    final server = DimseServer(
      aeTitle: ae,
      onFile: _store,
      onEvent: (e) => debugPrint('DICOM receiver: $e'),
    );
    _server = server;
    server.start(port).then(
      (_) {
        if (_server == server) {
          state = state.copyWith(listening: true, clearError: true);
        }
      },
      onError: (Object e) {
        if (_server != server) return;
        state = state.copyWith(
          listening: false,
          error: e is SocketException
              ? 'Port $port is in use by another program, or blocked. Pick another port.'
              : 'Couldn\'t start listening: $e',
        );
      },
    );
    const initial = RadReceiverState(on: true);
    _loadInbox(initial);
    return initial;
  }

  Future<void> _loadInbox(RadReceiverState base) async {
    final dir = await inbox();
    if (!await dir.exists()) return;
    final files = [
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.dcm')) e.path,
    ];
    if (files.isNotEmpty) state = state.copyWith(received: files);
  }

  Future<void> _store(ReceivedFile f) async {
    final dir = await inbox();
    await dir.create(recursive: true);
    final d = DicomInstance.parse(f.bytes);
    final name = d.sopInstanceUid.replaceAll(RegExp(r'[^0-9.]'), '_');
    final path = p.join(dir.path, '$name.dcm');
    await File(path).writeAsBytes(f.bytes, flush: true);
    state = state.copyWith(
      received: {...state.received, path}.toList(),
      lastFrom: '${f.callingAe} (${f.remote})',
    );
  }

  /// Removes files that were offered for import.
  Future<void> clear(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    state = state.copyWith(
      received: state.received.where((x) => !paths.contains(x)).toList(),
    );
  }
}

/// This computer's network addresses, for telling scanners where to send.
Future<List<String>> radLocalAddresses() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in list)
        for (final a in i.addresses)
          // 192.0.0.x is Android's internal IPv4-over-IPv6 link, not
          // an address a scanner can reach.
          if (!a.isLoopback && !a.address.startsWith('192.0.0.')) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
