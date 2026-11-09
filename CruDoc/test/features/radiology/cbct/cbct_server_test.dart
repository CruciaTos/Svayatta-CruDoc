import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doctor_management_app/features/radiology/cbct/cbct_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory pack;
  late CbctServer server;
  late CbctOpened opened;
  late HttpClient client;

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);

  setUp(() async {
    pack = Directory.systemTemp.createTempSync('cbct_server_test');
    File(p.join(pack.path, 'meta.json')).writeAsStringSync('{"a":1}');
    File(p.join(pack.path, 'full.i16')).writeAsBytesSync([1, 2, 3, 4]);
    File(p.join(pack.path, 'secret.txt')).writeAsStringSync('no');
    server = CbctServer(
      loadAsset: (key) async {
        if (key != 'assets/cbct_viewer/index.html') throw StateError('missing');
        return ByteData.sublistView(Uint8List.fromList(utf8.encode('<html></html>')));
      },
    );
    opened = await server.open(pack);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    pack.deleteSync(recursive: true);
  });

  Uri url(String path) => opened.page.replace(path: path, query: '');

  Future<({int status, List<int> body, HttpClientResponse res})> send(
    String method,
    String path, {
    List<int>? body,
  }) async {
    final req = await client.openUrl(method, url(path));
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (status: res.statusCode, body: bytes, res: res);
  }

  test('serves a bundled asset with exact headers', () async {
    final r = await send('GET', '/index.html');
    expect(r.status, 200);
    expect(utf8.decode(r.body), '<html></html>');
    expect(r.res.headers.value('x-content-type-options'), 'nosniff');
    expect(r.res.headers.value('cache-control'), 'no-store');
    expect(r.res.contentLength, 13);
    expect((await send('GET', '/nope.js')).status, 404);
  });

  test('serves pack files behind the token only', () async {
    final base = opened.base;
    final ok = await send('GET', '${base}full.i16');
    expect(ok.status, 200);
    expect(ok.body, [1, 2, 3, 4]);
    expect((await send('GET', '${base}secret.txt')).status, 404);
    expect((await send('GET', '/v/wrong/full.i16')).status, 404);
    expect((await send('GET', '$base%2e%2e/meta.json')).status, 404);
    expect((await send('GET', '${base}poster_axial.png')).status, 404);
    server.revoke(opened.token);
    expect((await send('GET', '${base}full.i16')).status, 404);
  });

  test('PUT accepts only state.json, posters and snapshots', () async {
    final base = opened.base;
    final state = await send('PUT', '${base}state.json', body: utf8.encode('{"version":1}'));
    expect(state.status, 204);
    expect(File(p.join(pack.path, 'state.json')).readAsStringSync(), '{"version":1}');
    expect((await send('GET', '${base}state.json')).status, 200);

    expect((await send('PUT', '${base}snap_3.png', body: png)).status, 204);
    expect(File(p.join(pack.path, 'snap_3.png')).readAsBytesSync(), png);
    expect((await send('PUT', '${base}poster_axial.png', body: png)).status, 204);
    final got = await send('GET', '${base}poster_axial.png');
    expect(got.res.headers.contentType?.mimeType, 'image/png');

    expect(
      (await send('PUT', '${base}poster_axial.png', body: utf8.encode('not a png'))).status,
      400,
    );
    expect((await send('PUT', '${base}state.json', body: utf8.encode('{broken'))).status, 400);
    expect((await send('PUT', '${base}meta.json', body: utf8.encode('{}'))).status, 404);
    expect((await send('PUT', '${base}full.i16', body: png)).status, 404);
    expect((await send('PUT', '${base}snap_x.png', body: png)).status, 404);
    expect((await send('PUT', '$base%2e%2e/evil.png', body: png)).status, 404);
    expect((await send('PUT', '/v/wrong/state.json', body: utf8.encode('{}'))).status, 404);
    expect((await send('PUT', '/index.html', body: utf8.encode('x'))).status, 404);
  });

  test('PUT over the size limit is refused', () async {
    final big = Uint8List(256 * 1024 + 1);
    expect((await send('PUT', '${opened.base}state.json', body: big)).status, 413);
    expect(File(p.join(pack.path, 'state.json')).existsSync(), isFalse);
  });

  test('listens on loopback only', () {
    expect(server.boundAddress, InternetAddress.loopbackIPv4);
  });
}
