import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'dataset.dart';
import 'uid.dart';

/// A DICOM network failure, said plainly.
class DimseException implements Exception {
  DimseException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ───────────────────────────── PDUs ─────────────────────────────

class _Pdu {
  _Pdu(this.type, this.body);
  final int type;
  final Uint8List body;
}

/// Splits a socket's bytes into PDUs.
class _PduReader {
  _PduReader(Stream<Uint8List> input) {
    _sub = input.listen(
      (chunk) {
        _buf.add(chunk);
        _drain();
      },
      onError: (Object e) => _fail(e),
      onDone: () => _fail(DimseException('The other side closed the connection.')),
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final _buf = BytesBuilder(copy: false);
  final _ready = Queue<_Pdu>();
  final _waiting = Queue<Completer<_Pdu>>();
  Object? _error;

  void _drain() {
    var bytes = _buf.takeBytes();
    var off = 0;
    while (bytes.length - off >= 6) {
      final len = ByteData.sublistView(bytes, off + 2, off + 6).getUint32(0);
      if (bytes.length - off < 6 + len) break;
      final pdu = _Pdu(
        bytes[off],
        Uint8List.fromList(Uint8List.sublistView(bytes, off + 6, off + 6 + len)),
      );
      off += 6 + len;
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete(pdu);
      } else {
        _ready.add(pdu);
      }
    }
    if (off < bytes.length) _buf.add(Uint8List.sublistView(bytes, off));
  }

  void _fail(Object e) {
    _error ??= e;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(e);
    }
  }

  Future<_Pdu> next([Duration timeout = const Duration(seconds: 60)]) {
    if (_ready.isNotEmpty) return Future.value(_ready.removeFirst());
    if (_error != null) return Future.error(_error!);
    final c = Completer<_Pdu>();
    _waiting.add(c);
    return c.future.timeout(
      timeout,
      onTimeout: () => throw DimseException('No answer in ${timeout.inSeconds} seconds.'),
    );
  }

  Future<void> cancel() => _sub.cancel();
}

Uint8List _pdu(int type, List<int> body) {
  final h = ByteData(6)
    ..setUint8(0, type)
    ..setUint32(2, body.length);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...body]);
}

List<int> _item(int type, List<int> body) {
  final h = ByteData(4)
    ..setUint8(0, type)
    ..setUint16(2, body.length);
  return [...h.buffer.asUint8List(), ...body];
}

List<int> _ae(String ae) {
  final s = ae.trim().toUpperCase();
  return ascii.encode(s.padRight(16).substring(0, 16));
}

String _readAe(Uint8List b, int off) =>
    ascii.decode(b.sublist(off, off + 16), allowInvalid: true).trim();

String _uidOf(Uint8List b) =>
    ascii.decode(b, allowInvalid: true).replaceAll('\u0000', '').trim();

/// One proposed presentation context.
class _Pc {
  _Pc(this.id, this.abstractSyntax, this.transferSyntaxes);
  final int id;
  final String abstractSyntax;
  final List<String> transferSyntaxes;
  int result = 0;
  String accepted = '';
}

/// Variable items of an A-ASSOCIATE-RQ/AC.
class _AssocItems {
  final contexts = <_Pc>[];
  int maxLength = 0;
}

_AssocItems _parseAssoc(Uint8List body, {required bool request}) {
  final out = _AssocItems();
  final d = ByteData.sublistView(body);
  var off = 68;
  while (off + 4 <= body.length) {
    final type = body[off];
    final len = d.getUint16(off + 2);
    final start = off + 4;
    final end = start + len;
    if (type == 0x20 || type == 0x21) {
      final id = body[start];
      final result = body[start + 2];
      var o = start + 4;
      var abstract = '';
      final ts = <String>[];
      while (o + 4 <= end) {
        final t = body[o];
        final l = d.getUint16(o + 2);
        final v = _uidOf(Uint8List.sublistView(body, o + 4, o + 4 + l));
        if (t == 0x30) abstract = v;
        if (t == 0x40) ts.add(v);
        o += 4 + l;
      }
      final pc = _Pc(id, abstract, ts)..result = request ? 0 : result;
      if (!request && ts.isNotEmpty) pc.accepted = ts.first;
      out.contexts.add(pc);
    } else if (type == 0x50) {
      var o = start;
      while (o + 4 <= end) {
        final t = body[o];
        final l = d.getUint16(o + 2);
        if (t == 0x51 && l == 4) out.maxLength = d.getUint32(o + 4);
        o += 4 + l;
      }
    }
    off = end;
  }
  return out;
}

List<int> _userInfo(int maxLength) => _item(0x50, [
  ..._item(0x51, (ByteData(4)..setUint32(0, maxLength)).buffer.asUint8List()),
  ..._item(0x52, ascii.encode(DicomUid.implementationClass)),
  ..._item(0x55, ascii.encode(DicomUid.implementationVersion)),
]);

List<int> _assocHeader(String called, String calling) => [
  0, 1, 0, 0, //
  ..._ae(called),
  ..._ae(calling),
  ...List.filled(32, 0),
];

// ───────────────────────────── DIMSE commands ─────────────────────────────

/// Command sets are always implicit VR little endian.
Uint8List _command(Map<int, Object> fields) {
  final tags = fields.keys.toList()..sort();
  final body = BytesBuilder();
  for (final t in tags) {
    final v = fields[t]!;
    Uint8List value;
    if (v is int) {
      value = Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
    } else {
      final s = ascii.encode(v as String);
      value = Uint8List.fromList(s.length.isOdd ? [...s, 0] : s);
    }
    final h = ByteData(8)
      ..setUint16(0, 0x0000, Endian.little)
      ..setUint16(2, t, Endian.little)
      ..setUint32(4, value.length, Endian.little);
    body
      ..add(h.buffer.asUint8List())
      ..add(value);
  }
  final b = body.takeBytes();
  final gl = ByteData(12)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 0, Endian.little)
    ..setUint32(4, 4, Endian.little)
    ..setUint32(8, b.length, Endian.little);
  return Uint8List.fromList([...gl.buffer.asUint8List(), ...b]);
}

Map<int, Object> _parseCommand(Uint8List b) {
  final d = ByteData.sublistView(b);
  final out = <int, Object>{};
  var off = 0;
  while (off + 8 <= b.length) {
    final el = d.getUint16(off + 2, Endian.little);
    final len = d.getUint32(off + 4, Endian.little);
    final v = Uint8List.sublistView(b, off + 8, off + 8 + len);
    out[el] = switch (el) {
      0x0100 || 0x0110 || 0x0120 || 0x0700 || 0x0800 || 0x0900 =>
        len >= 2 ? ByteData.sublistView(v).getUint16(0, Endian.little) : 0,
      _ => _uidOf(v),
    };
    off += 8 + len;
  }
  return out;
}

const _cStoreRq = 0x0001, _cStoreRsp = 0x8001;
const _cEchoRq = 0x0030, _cEchoRsp = 0x8030;
const _noDataset = 0x0101;

/// Sends P-DATA-TF PDUs for one message part, fragmented to [maxPdu].
void _sendPdv(Socket s, int pcId, Uint8List data, {required bool command, required int maxPdu}) {
  final chunk = (maxPdu <= 0 ? 65536 : maxPdu) - 6;
  var off = 0;
  do {
    final end = (off + chunk).clamp(0, data.length);
    final last = end >= data.length;
    final control = (command ? 1 : 0) | (last ? 2 : 0);
    final len = ByteData(4)..setUint32(0, end - off + 2);
    s.add(
      _pdu(0x04, [
        ...len.buffer.asUint8List(),
        pcId,
        control,
        ...Uint8List.sublistView(data, off, end),
      ]),
    );
    off = end;
  } while (off < data.length);
}

/// One reassembled DIMSE message.
class _Message {
  _Message(this.pcId, this.command, this.dataset);
  final int pcId;
  final Map<int, Object> command;
  final Uint8List? dataset;
}

/// Reads P-DATA until a whole message (command, plus dataset if one
/// follows) has arrived. Returns null on release; throws on abort.
Future<_Message?> _readMessage(_PduReader r, Socket s, {Duration? timeout}) async {
  final cmd = BytesBuilder(copy: false);
  final data = BytesBuilder(copy: false);
  Map<int, Object>? command;
  var pcId = 0;
  while (true) {
    final pdu = await r.next(timeout ?? const Duration(seconds: 60));
    switch (pdu.type) {
      case 0x05: // release request
        s.add(_pdu(0x06, [0, 0, 0, 0]));
        await s.flush();
        return null;
      case 0x07:
        throw DimseException('The other side aborted the connection.');
      case 0x04:
        final d = ByteData.sublistView(pdu.body);
        var off = 0;
        while (off + 6 <= pdu.body.length) {
          final len = d.getUint32(off);
          pcId = pdu.body[off + 4];
          final control = pdu.body[off + 5];
          final v = Uint8List.sublistView(pdu.body, off + 6, off + 4 + len);
          if (control & 1 == 1) {
            cmd.add(v);
            if (control & 2 == 2) {
              command = _parseCommand(cmd.takeBytes());
              if (command[0x0800] == _noDataset) {
                return _Message(pcId, command, null);
              }
            }
          } else {
            data.add(v);
            if (control & 2 == 2 && command != null) {
              return _Message(pcId, command, data.takeBytes());
            }
          }
          off += 4 + len;
        }
      default:
        throw DimseException('Unexpected message (type ${pdu.type}).');
    }
  }
}

// ───────────────────────────── SCU ─────────────────────────────

/// What a send did.
class StoreResult {
  const StoreResult({required this.sent, required this.failed, this.errors = const []});
  final int sent;
  final int failed;
  final List<String> errors;
}

/// Sends to a DICOM node (CruDoc's receiver, a PACS): C-ECHO and C-STORE.
class DimseClient {
  DimseClient({
    required this.host,
    required this.port,
    required this.calledAe,
    this.callingAe = 'DICOMNET',
    this.timeout = const Duration(seconds: 15),
  });

  final String host;
  final int port;

  /// The receiver's AE title.
  final String calledAe;

  /// Ours.
  final String callingAe;
  final Duration timeout;

  Future<(Socket, _PduReader, _AssocItems)> _associate(List<_Pc> proposed) async {
    Socket s;
    try {
      s = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (e) {
      throw DimseException(
        'Can\'t reach $host:$port. Check the address and port, that the receiver is '
        'switched on and that a firewall isn\'t blocking it. (${e.osError?.message ?? e.message})',
      );
    }
    final r = _PduReader(s);
    final items = <int>[
      ..._item(0x10, ascii.encode(DicomUid.appContext)),
      for (final pc in proposed)
        ..._item(0x20, [
          pc.id, 0, 0, 0, //
          ..._item(0x30, ascii.encode(pc.abstractSyntax)),
          for (final ts in pc.transferSyntaxes) ..._item(0x40, ascii.encode(ts)),
        ]),
      ..._userInfo(65536),
    ];
    s.add(_pdu(0x01, [..._assocHeader(calledAe, callingAe), ...items]));
    await s.flush();
    final pdu = await r.next(timeout);
    if (pdu.type == 0x03) {
      final reason = pdu.body.length >= 4 ? pdu.body[3] : 0;
      final source = pdu.body.length >= 4 ? pdu.body[2] : 0;
      s.destroy();
      throw DimseException(
        source == 1 && reason == 7
            ? 'The receiver doesn\'t answer to AE title "$calledAe". Use the AE title set on the receiver.'
            : source == 1 && reason == 3
            ? 'The receiver doesn\'t accept our AE title "$callingAe".'
            : 'The receiver refused the connection (reason $reason).',
      );
    }
    if (pdu.type != 0x02) {
      s.destroy();
      throw DimseException('The receiver answered with something unexpected.');
    }
    final ac = _parseAssoc(pdu.body, request: false);
    for (final pc in proposed) {
      final got = ac.contexts.where((c) => c.id == pc.id).firstOrNull;
      pc.result = got?.result ?? 3;
      pc.accepted = got?.accepted ?? '';
    }
    return (s, r, ac);
  }

  Future<void> _release(Socket s, _PduReader r) async {
    try {
      s.add(_pdu(0x05, [0, 0, 0, 0]));
      await s.flush();
      await r.next(const Duration(seconds: 5));
    } catch (_) {
      // Closing anyway.
    } finally {
      await r.cancel();
      s.destroy();
    }
  }

  /// "Is it there?" Returns the round trip time.
  Future<Duration> echo() async {
    final sw = Stopwatch()..start();
    final pc = _Pc(1, DicomUid.verification, [DicomUid.implicitLittle]);
    final (s, r, ac) = await _associate([pc]);
    try {
      if (pc.result != 0) throw DimseException('The receiver doesn\'t accept echo.');
      _sendPdv(
        s,
        1,
        _command({
          0x0002: DicomUid.verification,
          0x0100: _cEchoRq,
          0x0110: 1,
          0x0800: _noDataset,
        }),
        command: true,
        maxPdu: ac.maxLength,
      );
      await s.flush();
      final msg = await _readMessage(r, s, timeout: timeout);
      if (msg == null || msg.command[0x0100] != _cEchoRsp) {
        throw DimseException('No echo answer.');
      }
      return sw.elapsed;
    } finally {
      await _release(s, r);
    }
  }

  /// C-STORE of Part 10 files, each in its own transfer syntax.
  Future<StoreResult> store(
    List<Uint8List> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    final parsed = <DicomInstance>[];
    final errors = <String>[];
    for (final f in files) {
      try {
        parsed.add(DicomInstance.parse(f));
      } catch (e) {
        errors.add('A file isn\'t DICOM: $e');
      }
    }
    if (parsed.isEmpty) {
      return StoreResult(sent: 0, failed: files.length, errors: errors);
    }
    final pcs = <String, _Pc>{};
    var id = 1;
    for (final d in parsed) {
      final key = '${d.sopClassUid}|${d.transferSyntax}';
      if (pcs.containsKey(key) || id > 255) continue;
      pcs[key] = _Pc(id, d.sopClassUid, [d.transferSyntax]);
      id += 2;
    }
    final (s, r, ac) = await _associate(pcs.values.toList());
    var sent = 0, failed = files.length - parsed.length, msgId = 1;
    try {
      for (final d in parsed) {
        final pc = pcs['${d.sopClassUid}|${d.transferSyntax}'];
        if (pc == null || pc.result != 0) {
          failed++;
          errors.add('The receiver won\'t take ${d.sopClassUid} in ${d.transferSyntax}.');
          continue;
        }
        _sendPdv(
          s,
          pc.id,
          _command({
            0x0002: d.sopClassUid,
            0x0100: _cStoreRq,
            0x0110: msgId++,
            0x0700: 0,
            0x0800: 0,
            0x1000: d.sopInstanceUid,
          }),
          command: true,
          maxPdu: ac.maxLength,
        );
        _sendPdv(s, pc.id, d.dataset, command: false, maxPdu: ac.maxLength);
        await s.flush();
        final msg = await _readMessage(r, s, timeout: timeout * 4);
        if (msg == null) throw DimseException('The receiver closed the connection.');
        final status = msg.command[0x0900] as int? ?? 0xFFFF;
        // 0x0000 success; 0xB000, 0xB006, 0xB007 stored with warnings.
        if (msg.command[0x0100] == _cStoreRsp &&
            (status == 0 || status == 0xB000 || status == 0xB006 || status == 0xB007)) {
          sent++;
        } else {
          failed++;
          errors.add('The receiver refused a file (status 0x${status.toRadixString(16)}).');
        }
        onProgress?.call(sent + failed, files.length);
      }
    } finally {
      await _release(s, r);
    }
    return StoreResult(sent: sent, failed: failed, errors: errors);
  }
}

// ───────────────────────────── SCP ─────────────────────────────

/// One file a [DimseServer] received.
class ReceivedFile {
  const ReceivedFile({required this.bytes, required this.callingAe, required this.remote});

  /// A Part 10 file.
  final Uint8List bytes;
  final String callingAe;
  final String remote;
}

/// Receives over DICOM: answers C-ECHO and takes C-STORE (what scanners
/// and PACS use to "send to" a workstation).
class DimseServer {
  DimseServer({required this.aeTitle, required this.onFile, this.onEvent});

  /// Ours; associations for any other called AE are refused.
  final String aeTitle;

  /// Store the file; throw to answer the sender with a failure.
  final Future<void> Function(ReceivedFile) onFile;

  /// "Echo from PACSSIM (192.168.1.8)" and the like.
  final void Function(String)? onEvent;

  ServerSocket? _server;
  int? get port => _server?.port;

  Future<void> start(int port) async {
    await stop();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen((s) => _serve(s).catchError((_) {}));
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _serve(Socket s) async {
    final r = _PduReader(s);
    final remote = s.remoteAddress.address;
    try {
      final rq = await r.next(const Duration(seconds: 30));
      if (rq.type != 0x01 || rq.body.length < 68) {
        s.destroy();
        return;
      }
      final called = _readAe(rq.body, 4);
      final calling = _readAe(rq.body, 20);
      if (called.toUpperCase() != aeTitle.trim().toUpperCase()) {
        // Rejected permanent, by the service user, called AE not recognised.
        s.add(_pdu(0x03, [0, 1, 1, 7]));
        await s.flush();
        onEvent?.call('Refused $calling ($remote): it called "$called", not "$aeTitle"');
        s.destroy();
        return;
      }
      final items = _parseAssoc(rq.body, request: true);
      final accepted = <int, (String, String)>{};
      final pcs = <int>[];
      for (final pc in items.contexts) {
        // Files are kept as they come, so any transfer syntax will do.
        final ts = pc.transferSyntaxes.isEmpty ? '' : pc.transferSyntaxes.first;
        final ok = pc.abstractSyntax.isNotEmpty && ts.isNotEmpty;
        if (ok) accepted[pc.id] = (pc.abstractSyntax, ts);
        pcs.addAll(
          _item(0x21, [
            pc.id, 0, ok ? 0 : 4, 0, //
            if (ok) ..._item(0x40, ascii.encode(ts)),
          ]),
        );
      }
      final rqHeader = rq.body.sublist(0, 68);
      s.add(
        _pdu(0x02, [
          ...rqHeader,
          ..._item(0x10, ascii.encode(DicomUid.appContext)),
          ...pcs,
          ..._userInfo(65536),
        ]),
      );
      await s.flush();

      var stored = 0;
      while (true) {
        final msg = await _readMessage(r, s, timeout: const Duration(minutes: 5));
        if (msg == null) break;
        final field = msg.command[0x0100];
        final msgId = msg.command[0x0110] as int? ?? 0;
        final sopClass = msg.command[0x0002] as String? ?? '';
        final max = items.maxLength;
        if (field == _cEchoRq) {
          _sendPdv(
            s,
            msg.pcId,
            _command({
              0x0002: sopClass,
              0x0100: _cEchoRsp,
              0x0120: msgId,
              0x0800: _noDataset,
              0x0900: 0,
            }),
            command: true,
            maxPdu: max,
          );
          await s.flush();
          onEvent?.call('Echo from $calling ($remote)');
        } else if (field == _cStoreRq) {
          final sop = msg.command[0x1000] as String? ?? '';
          var status = 0;
          try {
            final ts = accepted[msg.pcId]?.$2 ?? DicomUid.implicitLittle;
            await onFile(
              ReceivedFile(
                bytes: buildPart10(
                  sopClassUid: sopClass,
                  sopInstanceUid: sop,
                  transferSyntax: ts,
                  dataset: msg.dataset ?? Uint8List(0),
                  sourceAe: calling,
                ),
                callingAe: calling,
                remote: remote,
              ),
            );
            stored++;
          } catch (_) {
            status = 0xA700; // out of resources
          }
          _sendPdv(
            s,
            msg.pcId,
            _command({
              0x0002: sopClass,
              0x0100: _cStoreRsp,
              0x0120: msgId,
              0x0800: _noDataset,
              0x0900: status,
              0x1000: sop,
            }),
            command: true,
            maxPdu: max,
          );
          await s.flush();
        } else {
          // Not supported: abort.
          s.add(_pdu(0x07, [0, 0, 2, 0]));
          await s.flush();
          break;
        }
      }
      if (stored > 0) {
        onEvent?.call('Received $stored file${stored == 1 ? '' : 's'} from $calling ($remote)');
      }
    } catch (e) {
      onEvent?.call('Connection from $remote ended: $e');
    } finally {
      await r.cancel();
      s.destroy();
    }
  }
}
