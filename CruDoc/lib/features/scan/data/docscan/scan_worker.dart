import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'geometry.dart';
import 'page_render.dart';
import 'pixels.dart';
import 'scan_engine.dart';

/// What the scanner screen hears back for each frame it sent.
class WorkerUpdate {
  const WorkerUpdate({
    required this.phase,
    required this.hint,
    this.quad,
    this.progress = 0,
    this.page,
    this.focusAt,
  });

  final ScanPhase phase;
  final ScanHint hint;
  final Quad? quad;
  final double progress;
  final CapturedPage? page;
  final Pt? focusAt;
}

/// Runs the [ScanEngine] on its own isolate so the camera preview never
/// stutters. Frames are offered, not queued: while the worker is busy the
/// camera's frames are simply skipped, so there is never a backlog, and
/// every frame sent gets exactly one reply. Candidate frames stay in the
/// worker's memory and are dropped once a page is chosen.
class ScanWorker {
  ScanWorker._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final _updates = StreamController<WorkerUpdate>.broadcast();
  bool _busy = false;
  bool _closed = false;

  Stream<WorkerUpdate> get updates => _updates.stream;
  bool get busy => _busy;

  static Future<ScanWorker> start({bool autoCapture = true}) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, [
      port.sendPort,
      autoCapture,
    ], debugName: 'document-scanner');
    final completer = Completer<SendPort>();
    late final ScanWorker worker;
    port.listen((msg) {
      if (!completer.isCompleted && msg is SendPort) {
        completer.complete(msg);
        return;
      }
      worker._onMessage(msg);
    });
    worker = ScanWorker._(isolate, await completer.future, port);
    return worker;
  }

  /// Hands [image] over unless the last frame is still being looked at.
  /// [rotation] turns the sensor image upright; [quarterTurns] turns the
  /// finished page the way the phone is held.
  bool offer(
    CameraImage image, {
    required int rotation,
    required int quarterTurns,
    required bool fullRange,
  }) {
    if (_busy || _closed) return false;
    final msg = _encodeFrame(image, rotation, quarterTurns, fullRange);
    if (msg == null) return false;
    _busy = true;
    _toWorker.send(msg);
    return true;
  }

  void captureNow() => _toWorker.send(const ['capture']);
  void setAutoCapture(bool on) => _toWorker.send(['auto', on]);
  void reset() => _toWorker.send(const ['reset']);

  void _onMessage(Object? msg) {
    if (msg is! List || msg.isEmpty) return;
    _busy = false;
    if (_closed) return;
    if (msg[0] == 'error') {
      debugPrint('[Scanner] frame failed: ${msg[1]}');
      return;
    }
    final quad = (msg[3] as List?)?.cast<double>();
    final pageMsg = msg[5] as List?;
    final focus = (msg[6] as List?)?.cast<double>();
    _updates.add(
      WorkerUpdate(
        phase: ScanPhase.values[msg[1] as int],
        hint: ScanHint.values[msg[2] as int],
        quad: quad == null ? null : Quad.fromList(quad),
        progress: msg[4] as double,
        page: pageMsg == null
            ? null
            : CapturedPage(
                jpeg: (pageMsg[0] as TransferableTypedData)
                    .materialize()
                    .asUint8List(),
                thumb: (pageMsg[1] as TransferableTypedData)
                    .materialize()
                    .asUint8List(),
                width: pageMsg[2] as int,
                height: pageMsg[3] as int,
              ),
        focusAt: focus == null ? null : Pt(focus[0], focus[1]),
      ),
    );
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _fromWorker.close();
    await _updates.close();
  }

  /// Copies the camera's planes (they are only valid during the callback)
  /// into transferable buffers.
  static List<Object?>? _encodeFrame(
    CameraImage image,
    int rotation,
    int quarterTurns,
    bool fullRange,
  ) {
    final planes = image.planes;
    if (planes.isEmpty) return null;
    TransferableTypedData t(Uint8List b) => TransferableTypedData.fromList([b]);
    final w = image.width, h = image.height;
    final p0 = planes[0];
    // [width, height, rotation, turns, fullRange, yRow, uOff, uRow, uPix,
    //  vOff, vRow, vPix, layout] + buffers.
    if (planes.length >= 3) {
      final u = planes[1], v = planes[2];
      return [
        'frame',
        [
          w,
          h,
          rotation,
          quarterTurns,
          fullRange ? 1 : 0,
          p0.bytesPerRow,
          0,
          u.bytesPerRow,
          u.bytesPerPixel ?? 1,
          0,
          v.bytesPerRow,
          v.bytesPerPixel ?? 1,
          3,
        ],
        t(p0.bytes),
        t(u.bytes),
        t(v.bytes),
      ];
    }
    if (planes.length == 2) {
      // NV12 (iOS): one interleaved Cb/Cr plane.
      final uv = planes[1];
      final pix = uv.bytesPerPixel ?? 2;
      return [
        'frame',
        [
          w,
          h,
          rotation,
          quarterTurns,
          fullRange ? 1 : 0,
          p0.bytesPerRow,
          0,
          uv.bytesPerRow,
          pix,
          1,
          uv.bytesPerRow,
          pix,
          2,
        ],
        t(p0.bytes),
        t(uv.bytes),
        null,
      ];
    }
    // NV21 in one buffer: Y, then interleaved Cr/Cb.
    return [
      'frame',
      [
        w,
        h,
        rotation,
        quarterTurns,
        fullRange ? 1 : 0,
        w,
        w * h + 1,
        w,
        2,
        w * h,
        w,
        2,
        1,
      ],
      t(p0.bytes),
      null,
      null,
    ];
  }
}

void _workerMain(List<Object?> args) {
  final toMain = args[0] as SendPort;
  final engine = ScanEngine(autoCapture: args[1] as bool);
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final clock = Stopwatch()..start();
  inbox.listen((msg) {
    if (msg is! List || msg.isEmpty) return;
    switch (msg[0]) {
      case 'capture':
        engine.captureNow();
      case 'auto':
        engine.autoCapture = msg[1] as bool;
      case 'reset':
        engine.reset();
      case 'frame':
        try {
          final frame = _decodeFrame(msg);
          final meta = msg[1] as List;
          final u = engine.process(
            frame,
            nowMs: clock.elapsedMilliseconds,
            quarterTurns: meta[3] as int,
          );
          final page = u.page;
          toMain.send([
            'update',
            u.phase.index,
            u.hint.index,
            u.quad?.toList(),
            u.progress,
            page == null
                ? null
                : [
                    TransferableTypedData.fromList([page.jpeg]),
                    TransferableTypedData.fromList([page.thumb]),
                    page.width,
                    page.height,
                  ],
            u.focusAt == null ? null : [u.focusAt!.x, u.focusAt!.y],
          ]);
        } catch (e, st) {
          toMain.send(['error', '$e\n$st']);
        }
    }
  });
}

YuvFrame _decodeFrame(List msg) {
  final m = (msg[1] as List).cast<int>();
  final y = (msg[2] as TransferableTypedData).materialize().asUint8List();
  final layout = m[12];
  final Uint8List u, v;
  if (layout == 3) {
    u = (msg[3] as TransferableTypedData).materialize().asUint8List();
    v = (msg[4] as TransferableTypedData).materialize().asUint8List();
  } else if (layout == 2) {
    u = v = (msg[3] as TransferableTypedData).materialize().asUint8List();
  } else {
    u = v = y;
  }
  return YuvFrame(
    sensorWidth: m[0],
    sensorHeight: m[1],
    rotation: m[2],
    fullRange: m[4] == 1,
    y: y,
    yRowStride: m[5],
    u: u,
    uOffset: m[6],
    uRowStride: m[7],
    uPixelStride: m[8],
    v: v,
    vOffset: m[9],
    vRowStride: m[10],
    vPixelStride: m[11],
  );
}

/// Gallery photos: found, straightened and encoded off the UI thread.
Future<CapturedPage?> processStillPhoto(Uint8List bytes) =>
    compute(PageRender.still, bytes);
