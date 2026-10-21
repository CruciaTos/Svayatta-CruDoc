// Helpers for testing against other DICOM software.
//   dart run tool/interop.dart gen <dir>              write sample studies
//   dart run tool/interop.dart send <host> <port> <ae> <dir>   C-ECHO + C-STORE every .dcm
//   dart run tool/interop.dart receive <port> <ae> <dir> <seconds>
//   dart run tool/interop.dart dicomweb <baseUrl>     search + download the smallest study
import 'dart:io';

import 'package:dicom_net/dicom_net.dart';

Future<void> main(List<String> a) async {
  switch (a.first) {
    case 'gen':
      final dir = Directory(a[1])..createSync(recursive: true);
      final files = SyntheticStudies.generate(count: 3);
      for (var i = 0; i < files.length; i++) {
        File('${dir.path}/s$i.dcm').writeAsBytesSync(files[i]);
      }
      print('wrote ${files.length}');
    case 'send':
      final c = DimseClient(host: a[1], port: int.parse(a[2]), calledAe: a[3], callingAe: 'DICOMNET');
      print('echo ${(await c.echo()).inMilliseconds} ms');
      final files = [
        for (final f in Directory(a[4]).listSync().whereType<File>())
          if (f.path.endsWith('.dcm')) f.readAsBytesSync(),
      ];
      final r = await c.store(files);
      print('sent ${r.sent} failed ${r.failed} ${r.errors.take(3)}');
    case 'receive':
      final dir = Directory(a[3])..createSync(recursive: true);
      var n = 0;
      final s = DimseServer(
        aeTitle: a[2],
        onFile: (f) async {
          final d = DicomInstance.parse(f.bytes);
          File('${dir.path}/${d.sopInstanceUid}.dcm').writeAsBytesSync(f.bytes);
          n++;
        },
        onEvent: print,
      );
      await s.start(int.parse(a[1]));
      print('listening');
      await Future<void>.delayed(Duration(seconds: int.parse(a[4])));
      await s.stop();
      print('received $n');
    case 'dicomweb':
      // Test only: trust this one host even if its CA isn't in Dart's list.
      HttpOverrides.global = _TrustHost(Uri.parse(a[1]).host);
      final c = DicomWebClient(a[1], timeout: const Duration(seconds: 30));
      await c.ping();
      print('ping ok');
      final all = await c.searchStudies(limit: 20);
      print('studies ${all.length}: ${all.take(3).map((s) => '${s.displayName}/${s.modalities}/${s.instanceCount}').join(', ')}');
      final small = all.where((s) => s.instanceCount > 0).toList()
        ..sort((x, y) => x.instanceCount.compareTo(y.instanceCount));
      if (small.isEmpty) return;
      final pick = small.first;
      final files = await c.retrieveStudy(pick.studyUid);
      final d = DicomInstance.parse(files.first);
      print('downloaded ${files.length}/${pick.instanceCount} of ${pick.displayName}: '
          '${d.integer(DicomAttr.rows)}x${d.integer(DicomAttr.columns)} ${d.transferSyntax} pixels=${d.hasPixels}');
  }
}

class _TrustHost extends HttpOverrides {
  _TrustHost(this.host);
  final String host;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..badCertificateCallback = (_, h, _) => h == host;
}
