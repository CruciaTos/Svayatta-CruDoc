// Round trip of everything in the package: dart run tool/smoke.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dicom_net/dicom_net.dart';

void check(bool ok, String what) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what');
  if (!ok) exitCode = 1;
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('dicom_net_smoke');
  final store = FolderPacsStore(Directory('${tmp.path}/pacs'));
  await store.load();
  final files = SyntheticStudies.generate(count: 3);
  for (final f in files) {
    await store.add(f, source: 'sample');
  }
  check(store.byStudy().length == 3, '3 sample studies (${files.length} files)');

  // Reload from disk.
  final again = FolderPacsStore(store.dir);
  await again.load();
  check(again.instances.length == files.length, 'store reloads from disk');

  final server = DicomWebServer(
    again,
    auth: DicomWebAuth.basic,
    username: 'doc',
    secret: 'pw',
  );
  await server.start(0);
  final base = 'http://127.0.0.1:${server.port}/dicom-web';

  try {
    await DicomWebClient(base).ping();
    check(false, 'no sign-in is refused');
  } on DicomWebException catch (e) {
    check(e.status == 401, 'no sign-in is refused: $e');
  }
  final c = DicomWebClient(base, auth: DicomWebAuth.basic, username: 'doc', secret: 'pw');
  await c.ping();
  check(true, 'ping with sign-in');

  final all = await c.searchStudies();
  check(all.length == 3, 'search all → ${all.length}');
  final cbct = await c.searchStudies(modalities: {'CT'});
  check(cbct.length == 1 && cbct.first.instanceCount == 40, 'search CT → ${cbct.length}, ${cbct.firstOrNull?.instanceCount} images');
  final two = await c.searchStudies(modalities: {'CT', 'PX'});
  check(two.length == 2, 'search CT+PX → ${two.length}');
  final byName = await c.searchStudies(patientName: all.first.patientName.split('^').last.toLowerCase());
  check(byName.length == 1, 'search by part of name → ${byName.length}');
  final today = await c.searchStudies(from: DateTime.now().subtract(const Duration(hours: 12)));
  check(today.isNotEmpty, 'search by date → ${today.length}');
  final none = await c.searchStudies(patientId: 'NOPE');
  check(none.isEmpty, 'search no match → empty');

  final got = await c.retrieveStudy(cbct.first.studyUid);
  check(got.length == 40, 'download CBCT → ${got.length} files');
  final parsed = DicomInstance.parse(got.first);
  check(parsed.hasPixels && parsed.integer(DicomAttr.rows) == 96, 'downloaded file parses (${parsed.integer(DicomAttr.rows)} rows)');

  // STOW a fresh study.
  final fresh = SyntheticStudies.generate(count: 2).sublist(1); // intraoral ×2
  final stow = await c.store(fresh);
  check(stow.stored == 2 && stow.failed == 0, 'upload → ${stow.stored} stored');
  check((await c.searchStudies()).length == 4, 'uploaded study is searchable');

  try {
    await DicomWebClient('http://127.0.0.1:1/dicom-web', timeout: const Duration(seconds: 3)).ping();
  } on DicomWebException catch (e) {
    check(true, 'unreachable is explained: ${e.message.split('.').first}');
  }

  // DIMSE: receiver + sender.
  final received = <Uint8List>[];
  final events = <String>[];
  final scp = DimseServer(
    aeTitle: 'CRUDOC',
    onFile: (f) async => received.add(f.bytes),
    onEvent: events.add,
  );
  await scp.start(0);
  final scu = DimseClient(host: '127.0.0.1', port: scp.port!, calledAe: 'CRUDOC', callingAe: 'PACSSIM');
  final rtt = await scu.echo();
  check(true, 'C-ECHO ok in ${rtt.inMilliseconds} ms');
  final result = await scu.store(files);
  check(result.sent == files.length && result.failed == 0, 'C-STORE → ${result.sent}/${files.length} ${result.errors}');
  check(received.length == files.length, 'receiver got ${received.length}');
  final r0 = DicomInstance.parse(received.last);
  final o0 = DicomInstance.parse(files.last);
  check(
    r0.sopInstanceUid == o0.sopInstanceUid &&
        r0.string(DicomAttr.patientName) == o0.string(DicomAttr.patientName) &&
        r0.dataset.length == o0.dataset.length,
    'received file matches what was sent',
  );
  try {
    await DimseClient(host: '127.0.0.1', port: scp.port!, calledAe: 'WRONG').echo();
    check(false, 'wrong AE refused');
  } on DimseException catch (e) {
    check(e.message.contains('AE title'), 'wrong AE refused: $e');
  }
  stdout.writeln(events.join('\n'));

  await scp.stop();
  await server.stop();
  await tmp.delete(recursive: true);
}
