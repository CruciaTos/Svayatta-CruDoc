import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/scan/data/camera_steady.dart';
import 'package:doctor_management_app/features/scan/data/docscan/corner_set.dart';
import 'package:doctor_management_app/features/scan/data/docscan/geometry.dart';
import 'package:doctor_management_app/features/scan/data/docscan/page_render.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_engine.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_worker.dart';
import 'package:doctor_management_app/features/scan/presentation/corner_editor.dart';
import 'package:doctor_management_app/features/scan/presentation/outline_motion.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// How the document camera ended.
class CameraScanResult {
  const CameraScanResult.pages(this.pages) : fallback = false, error = null;
  const CameraScanResult.fallback()
    : pages = const [],
      fallback = true,
      error = null;
  const CameraScanResult.error(this.error) : pages = const [], fallback = false;

  final List<CapturedPage> pages;

  /// The camera could not be opened here; use the system scanner instead.
  final bool fallback;

  /// Something to tell the person (camera permission refused).
  final String? error;
}

/// The live document camera: outlines the page as it is found, and saves
/// it on its own once it has been held still, in focus and well lit for a
/// moment. Several pages can be scanned in a row.
///
/// The corners can be corrected by finger while the camera runs: drag one,
/// or press and hold on a spot to make the corner sensed there one of the
/// four. Corners set that way are followed as the phone moves, and the page
/// is cut along them. A page already saved can be reopened to move its
/// corners on the still picture.
class DocumentCameraPage extends StatefulWidget {
  const DocumentCameraPage({super.key, this.maxPages = 10});

  final int maxPages;

  static Future<CameraScanResult> open(
    BuildContext context, {
    int maxPages = 10,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<CameraScanResult>(
        fullscreenDialog: true,
        builder: (_) => DocumentCameraPage(maxPages: maxPages),
      ),
    );
    return result ?? const CameraScanResult.pages([]);
  }

  @override
  State<DocumentCameraPage> createState() => _DocumentCameraPageState();
}

class _DocumentCameraPageState extends State<DocumentCameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _minFrameGapMs = 66; // at most ~15 analysed frames a second

  // Finger distances, in logical pixels.
  static const _grabReach = 44.0; // a drag this close to a corner takes it
  static const _onHandle = 20.0; // holding still here keeps the corner put
  static const _pressReach = 48.0; // a long press senses corners this far
  static const _settleReach = 16.0; // a dropped corner settles this far
  static const _magnetReach = 30.0; // a dragged corner is drawn from this far
  static const _magnetLetGo = 40.0; // and held until the finger is this far
  static const _slop = 8.0;
  static const _pressDelay = Duration(milliseconds: 350);
  static const _blurTurn = 0.22; // radians a second

  CameraController? _camera;
  ScanWorker? _worker;
  StreamSubscription<WorkerUpdate>? _updatesSub;
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  /// The phone is turning too fast for a sharp picture, and until when it
  /// still counts as such.
  bool _shaking = false;
  int _shookMs = 0;

  /// A long press has just found the whole page.
  bool _pageFound = false;
  bool _opening = false;
  bool _done = false;

  int _sensorRotation = 90;
  int _turns = 0; // how the phone is held, for the finished page
  int _lastOfferMs = 0;

  WorkerUpdate? _update;
  final List<CapturedPage> _pages = [];
  bool _auto = true;
  bool _torch = false;
  bool _manualPending = false;
  bool _finishing = false;
  bool _importing = false;
  Timer? _manualTimeout;

  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );

  /// The outline as drawn: carried to the present between the scanner's
  /// reports, every screen frame, while there is movement to show.
  final _motion = OutlineMotion();
  final ValueNotifier<int> _moved = ValueNotifier(0);
  late final Ticker _ticker = createTicker((_) {
    final more = _motion.tick(DateTime.now().millisecondsSinceEpoch);
    _moved.value++;
    if (!more) _ticker.stop();
  });

  /// Non-null while a saved page's corners are being moved.
  CornerEditor? _editor;
  bool _loadingPage = false;
  bool _cutting = false;
  bool _cutFailed = false;

  /// The saved picture eases from the camera's framing to its own.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );
  Size _view = Size.zero;
  EdgeInsets _safe = EdgeInsets.zero;

  /// [CornerFlag]s while the live corners are set by hand; null while the
  /// scanner finds them itself.
  List<int>? _flags;

  /// Corners sent to the worker and not yet answered. Until then the
  /// outline on screen stands, not the one from an older frame.
  int _awaiting = 0;

  /// The live corner being dragged, and where the finger has put it
  /// (fractions of the frame).
  int? _held;
  Pt _heldAt = const Pt(0, 0);
  Pt _dragFrom = const Pt(0, 0);

  /// The corner sensed near the finger, and whether the dragged corner is
  /// on it.
  Pt? _magnet;
  bool _caught = false;

  /// A question about the dragged corner is with the worker.
  bool _asking = false;

  /// The picture has been asked to hold steady.
  bool _steadied = false;

  /// The outline as the finger landed, and whether it was really found.
  Quad _start = const Quad(Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1));
  bool _startSure = false;

  // The one finger on the picture.
  int? _finger;
  Offset _anchor = Offset.zero;
  Offset _last = Offset.zero;
  Timer? _pressTimer;
  int? _near;
  int? _pressedCorner;
  bool _onNear = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The outline is drawn in portrait; keep the screen there.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _tiltSub = accelerometerEventStream().listen(_onTilt, onError: (_) {});
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onTurn, onError: (_) {});
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _manualTimeout?.cancel();
    _pressTimer?.cancel();
    _editor?.dispose();
    _settle.dispose();
    _ticker.dispose();
    _moved.dispose();
    _tiltSub?.cancel();
    _gyroSub?.cancel();
    _updatesSub?.cancel();
    _closeCamera();
    _worker?.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _closeCamera();
    } else if (state == AppLifecycleState.resumed && !_done && !_importing) {
      _open();
    }
  }

  // ---- Camera ----------------------------------------------------------

  Future<void> _open() async {
    if (_opening || _camera != null || _done) return;
    _opening = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return _leave(const CameraScanResult.fallback());
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      // Optional controls: not every camera has them.
      await _try(
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp),
      );
      await _try(() => ctrl.setFocusMode(FocusMode.auto));
      await _try(
        () => ctrl.setFlashMode(_torch ? FlashMode.torch : FlashMode.off),
      );
      _worker ??= await ScanWorker.start(autoCapture: _auto);
      _updatesSub ??= _worker!.updates.listen(_onUpdate);
      _sensorRotation = back.sensorOrientation;
      _steadied = false;
      if (!mounted || _done) {
        await ctrl.dispose();
        return;
      }
      await ctrl.startImageStream(_onFrame);
      setState(() => _camera = ctrl);
    } on CameraException catch (e) {
      const denied = {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      };
      if (denied.contains(e.code)) {
        _leave(
          const CameraScanResult.error(
            'CruDoc needs the camera to scan. Allow it in Settings and try again.',
          ),
        );
      } else if (e.code != 'CameraPermissionsRequestOngoing') {
        debugPrint('[Scanner] camera failed: ${e.code} ${e.description}');
        _leave(const CameraScanResult.fallback());
      }
    } catch (e) {
      debugPrint('[Scanner] camera failed: $e');
      _leave(const CameraScanResult.fallback());
    } finally {
      _opening = false;
    }
  }

  Future<void> _closeCamera() async {
    final ctrl = _camera;
    if (ctrl == null) return;
    _camera = null;
    // Hand-set corners belong to the view that is going away.
    _dropTouch();
    _worker?.releaseCorners();
    _flags = null;
    _motion.jump(null);
    if (mounted) setState(() {});
    await _try(() async {
      if (ctrl.value.isStreamingImages) await ctrl.stopImageStream();
    });
    await _try(ctrl.dispose);
  }

  static Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    final worker = _worker;
    if (worker == null || _done) return;
    // Once frames are flowing the camera is fully set up.
    final camera = _camera;
    if (!_steadied && camera != null) {
      _steadied = true;
      unawaited(steadyCamera(camera));
    }
    if (_editor != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // While hand-set corners are being followed, take every frame there is
    // time for.
    if (_flags == null && now - _lastOfferMs < _minFrameGapMs) return;
    // Sensors store frames landscape; turn them to match the portrait view.
    final rotation = image.width > image.height ? _sensorRotation : 0;
    if (worker.offer(
      image,
      rotation: rotation,
      quarterTurns: _turns,
      // Android hands over full-range YUV; iOS uses video range.
      fullRange: Platform.isAndroid,
      takenMs: now,
    )) {
      _lastOfferMs = now;
    }
  }

  /// Which way up the phone is held, from gravity. Lying flat over the page
  /// tells nothing, so the last clear reading is kept.
  void _onTilt(AccelerometerEvent e) {
    final x = e.x, y = e.y;
    if (math.sqrt(x * x + y * y) < 3.5) return; // about flat
    final int turns;
    if (y.abs() > 1.5 * x.abs()) {
      turns = y > 0 ? 0 : 2;
    } else if (x.abs() > 1.5 * y.abs()) {
      // Top of the phone to the left: the page's top is at the screen's
      // right, so the picture turns three quarters clockwise.
      turns = x > 0 ? 3 : 1;
    } else {
      return;
    }
    _turns = turns;
  }

  /// A hand never holds quite still; past [_blurTurn] the picture smears.
  void _onTurn(GyroscopeEvent e) {
    final rate = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (rate > _blurTurn || (_shaking && rate > _blurTurn / 2)) {
      _shookMs = now;
    }
    final shaking = now - _shookMs < 200;
    if (shaking != _shaking) {
      _shaking = shaking;
      _worker?.shaking(shaking);
    }
  }

  // ---- Worker updates --------------------------------------------------

  void _onUpdate(WorkerUpdate u) {
    if (!mounted) return;
    if (_editor != null) {
      // The picture is held; only a page already on its way still counts.
      if (u.page != null) _addPage(u.page!);
      return;
    }
    if (u.focusAt != null) {
      // The page is near the middle; refocusing there is orientation-safe.
      _try(
        () => _camera?.setFocusPoint(const Offset(0.5, 0.5)) ?? Future.value(),
      );
    }
    if (u.page != null) _addPage(u.page!);
    if (_awaiting == 0) {
      _flags = u.corners;
      final next = u.quad;
      if (next != null) {
        _motion.observe(
          next,
          takenMs: u.takenMs,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          // Both kinds of outline are followed as one sheet.
          rigid: true,
        );
        if (!_ticker.isActive) _ticker.start();
      } else {
        _motion.jump(null);
      }
    }
    // The page moves under a still finger: so does the magnet.
    final held = _held, flags = u.corners, quad = u.quad;
    if (held != null && flags != null && quad != null) {
      _attract(
        flags[held] & CornerFlag.sensed != 0 ? quad.corners[held] : null,
      );
    }
    setState(() => _update = u);
    if (_finishing && u.phase != ScanPhase.capturing) _finish();
  }

  Quad? get _currentQuad => _motion.shown;

  void _addPage(CapturedPage page) {
    _manualPending = false;
    _manualTimeout?.cancel();
    final redo = page.redo && _pages.isNotEmpty;
    if (!redo && _pages.length >= widget.maxPages) return;
    setState(() => redo ? _pages.last = page : _pages.add(page));
    HapticFeedback.mediumImpact();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _flash.forward(from: 0);
    }
    _finishIfFull();
  }

  void _finishIfFull() {
    if (_pages.length >= widget.maxPages &&
        _editor == null &&
        _finger == null) {
      _finish();
    }
  }

  // ---- Correcting the corners --------------------------------------------

  /// The camera's picture, upright.
  Size? get _previewSize {
    final s = _camera?.value.previewSize;
    if (s == null) return null;
    return Size(math.min(s.width, s.height), math.max(s.width, s.height));
  }

  double get _settled => CruMotion.curve.transform(_settle.value);

  Rect _rect(Size picture) => pictureRect(picture, _view, _safe, _settled);

  Pt _toPicture(Offset at, Size picture) {
    final rect = _rect(picture);
    final p = (at - rect.topLeft) * (picture.width / rect.width);
    return Pt(p.dx, p.dy);
  }

  /// Screen pixels per picture pixel.
  double _scale(Size picture) => _rect(picture).width / picture.width;

  bool get _canTouch =>
      !_done &&
      !_finishing &&
      !_importing &&
      !_loadingPage &&
      !_cutting &&
      !_manualPending &&
      (_editor != null || _camera != null);

  /// The outline on screen, in fractions of the frame: the latest one, with
  /// a dragged corner where the finger has it.
  Quad? get _outline {
    final q = _currentQuad, held = _held;
    if (q == null || held == null) return q;
    return CornerSet(q.corners).move(held, _heldShown).quad;
  }

  /// The magnet, while the finger is still close enough to it.
  Pt? get _pulling {
    final magnet = _magnet, size = _previewSize;
    if (magnet == null || size == null) return null;
    final rect = _rect(size);
    final away = Offset(
      (magnet.x - _heldAt.x) * rect.width,
      (magnet.y - _heldAt.y) * rect.height,
    );
    return away.distance <= _magnetLetGo ? magnet : null;
  }

  /// Where the dragged corner is drawn: on the magnet, or under the finger.
  Pt get _heldShown => _pulling ?? _heldAt;

  void _attract(Pt? magnet) {
    _magnet = magnet;
    _feel();
  }

  /// A tick as the dragged corner catches.
  void _feel() {
    final caught = _pulling != null;
    if (caught && !_caught) MobileHaptics.select();
    _caught = caught;
  }

  /// Moves the dragged corner with the finger.
  void _dragLive(Pt to) {
    setState(() => _heldAt = to);
    _feel();
    unawaited(_askMagnet());
  }

  /// Asks the worker what lies near the finger: one question at a time,
  /// always about the latest place.
  Future<void> _askMagnet() async {
    final worker = _worker, size = _previewSize;
    final held = _held, shown = _outline;
    if (_asking || worker == null || size == null) return;
    if (held == null || shown == null) return;
    _asking = true;
    final asked = _heldAt;
    final reply = await worker.setCorner(
      start: shown,
      sure: _startSure,
      index: held,
      at: asked,
      reach: _magnetReach / _rect(size).width,
      holding: true,
    );
    _asking = false;
    if (!mounted || _held != held || reply == null) return;
    setState(() {
      _flags = reply.flags;
      _attract(reply.sensed(held) ? reply.at : null);
    });
    if (_heldAt.x != asked.x || _heldAt.y != asked.y) unawaited(_askMagnet());
  }

  Pt _fraction(Offset at, Size picture) {
    final p = _toPicture(at, picture);
    return Pt(p.x / picture.width, p.y / picture.height);
  }

  void _touchDown(PointerDownEvent e) {
    if (_finger != null || !_canTouch) return;
    final editor = _editor;
    final size = editor?.size ?? _previewSize;
    if (size == null) return;
    final at = e.localPosition;
    _finger = e.pointer;
    _anchor = _last = at;
    _near = _pressedCorner = null;
    _onNear = _dragging = _pageFound = false;

    final List<Pt>? corners;
    if (editor == null) {
      _worker?.hold(true);
      final shown = _outline;
      _startSure = shown != null;
      // With no outline to start from, a box well inside the screen.
      final a = _fraction(
        Offset(_view.width * 0.14, _view.height * 0.24),
        size,
      );
      final b = _fraction(
        Offset(_view.width * 0.86, _view.height * 0.72),
        size,
      );
      _start = shown ?? Quad(a, Pt(b.x, a.y), b, Pt(a.x, b.y));
      corners = shown?.scale(size.width, size.height).corners;
    } else {
      corners = editor.corners.points;
    }
    if (corners != null) {
      final point = _toPicture(at, size);
      final near = CornerSet(
        corners,
      ).nearest(point, within: _grabReach / _scale(size));
      _near = near;
      _onNear =
          near != null &&
          corners[near].distanceTo(point) * _scale(size) <= _onHandle;
      if (editor != null && near != null) {
        MobileHaptics.select();
        editor.grab(near, at);
      }
    }
    _pressTimer = Timer(_pressDelay, _longPress);
  }

  void _longPress() {
    if (!mounted || _finger == null || _dragging) return;
    _anchor = _last;
    final editor = _editor;
    if (editor != null) {
      if (_onNear) {
        // Already on a corner: take hold of it without moving it.
        editor.grab(_near!, _last);
        MobileHaptics.tap();
        return;
      }
      final sensed = editor.press(
        _last,
        _toPicture(_last, editor.size),
        _pressReach / _scale(editor.size),
      );
      sensed ? MobileHaptics.commit() : MobileHaptics.tap();
      return;
    }
    final size = _previewSize;
    if (size == null) return;
    final point = _fraction(_last, size);
    Pt pixels(Pt p) => Pt(p.x * size.width, p.y * size.height);
    final index = _onNear
        ? _near!
        : CornerSet(
            [for (final p in (_outline ?? _start).corners) pixels(p)],
            [
              for (var i = 0; i < 4; i++)
                (_flags?[i] ?? 0) & CornerFlag.sensed != 0,
            ],
          ).indexFor(pixels(point));
    MobileHaptics.tap();
    _caught = false;
    unawaited(_pressLive(index, point));
  }

  /// A long press on the live picture: the camera says whether a corner or
  /// the whole page was meant.
  Future<void> _pressLive(int index, Pt at) async {
    final worker = _worker, size = _previewSize;
    if (worker == null || size == null) return;
    final start = _outline ?? _start;
    final finger = _finger;
    _awaiting++;
    final reply = await worker.press(
      start: start,
      sure: _startSure,
      index: index,
      at: at,
      reach: _pressReach / _rect(size).width,
    );
    _awaiting--;
    if (!mounted || reply == null) return;
    final page = reply.page;
    setState(() {
      _flags = reply.flags;
      if (page != null) {
        _pageFound = finger != null && _finger == finger;
        _motion.jump(page);
        MobileHaptics.commit();
      } else {
        // The same finger may now drag the corner it set.
        if (_finger == finger) _pressedCorner = index;
        _motion.jump(
          CornerSet((_outline ?? start).corners).move(index, reply.at).quad,
        );
        if (reply.sensed(index)) MobileHaptics.commit();
      }
    });
  }

  void _touchMove(PointerMoveEvent e) {
    if (e.pointer != _finger) return;
    final at = _last = e.localPosition;
    final editor = _editor;
    final size = editor?.size ?? _previewSize;
    if (size == null) return;
    if (!_dragging) {
      if ((at - _anchor).distance < _slop) return;
      _pressTimer?.cancel();
      if (editor != null) {
        if (editor.active == null) {
          if (_near == null) return; // a swipe over nothing
          editor.grab(_near!, at);
        }
      } else {
        final index = _pressedCorner ?? _near;
        final shown = _outline;
        if (index == null || shown == null) return;
        _held = index;
        _heldAt = _dragFrom = shown.corners[index];
        _magnet = null;
        _caught = false;
        MobileHaptics.select();
      }
      _dragging = true;
    }
    if (editor != null) {
      final scale = _scale(size);
      if (editor.drag(at, (at - _anchor) / scale, _magnetReach / scale)) {
        MobileHaptics.select();
      }
      return;
    }
    if (_held == null) return;
    final rect = _rect(size);
    final by = at - _anchor;
    _dragLive(
      Pt(
        (_dragFrom.x + by.dx / rect.width).clamp(0.0, 1.0),
        (_dragFrom.y + by.dy / rect.height).clamp(0.0, 1.0),
      ),
    );
  }

  void _touchEnd(PointerEvent e) {
    if (e.pointer != _finger) return;
    _pressTimer?.cancel();
    _finger = null;
    _pressedCorner = null;
    _pageFound = false;
    final editor = _editor;
    if (editor != null) {
      final sensed = editor.release(
        reach: _dragging ? _settleReach / _scale(editor.size) : 0,
      );
      if (sensed) MobileHaptics.select();
      _settleIfReady();
      return;
    }
    final held = _held;
    if (held != null) {
      // Let go: it stays where it is drawn, or settles onto a corner right
      // beside it.
      unawaited(_setCorner(held, _heldShown, reach: _settleReach));
    }
    _worker?.hold(false);
    setState(() {});
    _finishIfFull();
  }

  void _dropTouch() {
    _pressTimer?.cancel();
    _finger = null;
    _held = _pressedCorner = null;
    _magnet = null;
    _dragging = _caught = false;
  }

  /// Puts live corner [index] at [at] (fractions of the frame). The outline
  /// on screen takes it at once; the camera keeps running and follows it
  /// from there. With a [reach] (screen pixels) it settles onto a corner
  /// sensed that close.
  Future<void> _setCorner(int index, Pt at, {required double reach}) async {
    final worker = _worker;
    final size = _previewSize;
    if (worker == null || size == null) return;
    final before = _outline ?? _start;
    final after = CornerSet(before.corners).move(index, at).quad;
    setState(() {
      _held = null;
      _motion.jump(after);
      _flags = [
        for (var i = 0; i < 4; i++)
          i == index
              ? CornerFlag.placed |
                    ((_flags?[i] ?? 0) & (_caught ? CornerFlag.sensed : 0))
              : _flags?[i] ?? (_startSure ? CornerFlag.placed : 0),
      ];
    });
    _awaiting++;
    final reply = await worker.setCorner(
      start: before,
      sure: _startSure,
      index: index,
      at: at,
      reach: reach / _rect(size).width,
      holding: false,
    );
    _awaiting--;
    final shown = _currentQuad;
    if (!mounted || reply == null || _awaiting > 0) return;
    // Unless the finger has already taken it somewhere else.
    if (_held != index && shown != null) {
      if (!_caught && reply.sensed(index)) MobileHaptics.commit();
      setState(() {
        _flags = reply.flags;
        _motion.jump(CornerSet(shown.corners).move(index, reply.at).quad);
      });
    }
  }

  /// Back to the scanner finding the corners itself.
  void _resetCorners() {
    MobileHaptics.select();
    _worker?.releaseCorners();
    setState(() {
      _flags = null;
      _motion.jump(null);
    });
  }

  void _settleIfReady() {
    if (_finger != null || _editor == null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _settle.value = 1;
    } else {
      _settle.forward();
    }
  }

  /// Reopens a kept page to move its corners.
  Future<void> _adjustPage(int index) async {
    final source = _pages[index].source;
    if (source == null || _editor != null || _loadingPage) return;
    MobileHaptics.select();
    _worker?.hold(true);
    setState(() => _loadingPage = true);
    try {
      final picture = await compute(PageRender.editable, source);
      if (picture == null) throw StateError('unreadable picture');
      final image = await CornerEditor.decode(picture);
      if (!mounted || _done) {
        image.dispose();
        return;
      }
      final w = picture.frame.width.toDouble();
      final h = picture.frame.height.toDouble();
      final editor = CornerEditor(
        source: source,
        picture: picture,
        image: image,
        corners: CornerSet.of(
          source.quad ??
              Quad(
                Pt(w * 0.04, h * 0.04),
                Pt(w * 0.96, h * 0.04),
                Pt(w * 0.96, h * 0.96),
                Pt(w * 0.04, h * 0.96),
              ),
        ),
        replaces: index,
      );
      _settle.value = 0;
      setState(() {
        _editor = editor;
        _cutFailed = false;
      });
      _settleIfReady();
    } catch (e) {
      debugPrint('[Scanner] could not reopen the page: $e');
      _worker?.hold(false);
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  Future<void> _useCorners() async {
    final editor = _editor;
    if (editor == null || !editor.corners.valid || _cutting) return;
    MobileHaptics.commit();
    setState(() {
      _cutting = true;
      _cutFailed = false;
    });
    final source = editor.source.withQuad(editor.corners.quad);
    CapturedPage? page;
    try {
      page = await compute(PageRender.fromSource, source);
    } catch (e) {
      debugPrint('[Scanner] could not cut the page: $e');
    }
    if (!mounted || _editor != editor) return;
    final cut = page;
    if (cut == null) {
      setState(() {
        _cutting = false;
        _cutFailed = true;
      });
      return;
    }
    _pages[editor.replaces] = cut;
    _worker?.pageTaken(source);
    _closeEditor();
  }

  /// Back to the live camera.
  void _closeEditor() {
    final editor = _editor;
    if (editor == null) return;
    _dropTouch();
    setState(() {
      _editor = null;
      _cutting = false;
      _cutFailed = false;
      _update = null;
      _motion.jump(null);
    });
    _settle.value = 0;
    // The painters let go of it with the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => editor.dispose());
    _worker?.hold(false);
    _finishIfFull();
  }

  // ---- Actions -----------------------------------------------------------

  void _shutter() {
    final worker = _worker;
    if (worker == null || _manualPending || _camera == null) return;
    MobileHaptics.commit();
    setState(() => _manualPending = true);
    worker.captureNow();
    _manualTimeout = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _manualPending = false);
    });
  }

  void _toggleAuto() {
    MobileHaptics.select();
    setState(() => _auto = !_auto);
    _worker?.setAutoCapture(_auto);
  }

  Future<void> _toggleTorch() async {
    MobileHaptics.select();
    setState(() => _torch = !_torch);
    await _try(
      () =>
          _camera?.setFlashMode(_torch ? FlashMode.torch : FlashMode.off) ??
          Future.value(),
    );
  }

  Future<void> _importPhotos() async {
    if (_importing) return;
    setState(() => _importing = true);
    await _closeCamera();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      for (final f in result?.files ?? const <PlatformFile>[]) {
        if (_pages.length >= widget.maxPages) break;
        final bytes =
            f.bytes ??
            (f.path == null ? null : await File(f.path!).readAsBytes());
        if (bytes == null) continue;
        final page = await processStillPhoto(bytes);
        if (page != null && mounted) setState(() => _pages.add(page));
      }
    } catch (e) {
      debugPrint('[Scanner] import failed: $e');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        if (_pages.length >= widget.maxPages) {
          _finish();
        } else {
          _open();
        }
      }
    }
  }

  /// Done. A capture already under way is allowed to land first.
  void _finish() {
    if (_done) return;
    if (_update?.phase == ScanPhase.capturing && !_finishing) {
      setState(() => _finishing = true);
      Timer(const Duration(seconds: 2), _finish);
      return;
    }
    _leave(CameraScanResult.pages(List.of(_pages)));
  }

  void _leave(CameraScanResult result) {
    if (_done) return;
    _done = true;
    _closeCamera();
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _close() async {
    if (_editor != null) return _closeEditor();
    if (_pages.isEmpty) return _leave(const CameraScanResult.pages([]));
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard the scan?'),
        content: Text(
          _pages.length == 1
              ? 'The page you scanned will not be kept.'
              : 'The ${_pages.length} pages you scanned will not be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scanning'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) _leave(const CameraScanResult.pages([]));
  }

  // ---- UI ----------------------------------------------------------------

  String get _guidance {
    final editor = _editor;
    if (editor != null) {
      if (_cutting) return 'Straightening the page…';
      if (_cutFailed) return "Couldn't cut the page — try again";
      if (editor.found.contains(editor.active)) return 'Corner found';
      if (!editor.corners.valid) return 'Uncross the sides of the page';
      return 'Drag a corner, or press and hold on one';
    }
    if (_loadingPage) return 'Opening the page…';
    if (_importing) return 'Reading the photos…';
    if (_finishing) return 'Finishing the page…';
    if (_camera == null) return 'Opening the camera…';
    if (_manualPending) return 'Capturing…';
    if (_pageFound) return 'Page found';
    final pressed = _pressedCorner;
    if (_held != null
        ? _caught
        : pressed != null && (_flags?[pressed] ?? 0) & CornerFlag.sensed != 0) {
      return 'Corner found';
    }
    final u = _update;
    if (u == null) return 'Point the camera at a page';
    return switch (u.hint) {
      ScanHint.findPage => 'Point the camera at a page',
      ScanHint.fitPage => 'Fit the whole page in view',
      ScanHint.moveCloser => 'Move closer to the page',
      ScanHint.holdSteady => 'Hold steady',
      ScanHint.focusing => 'Focusing — hold steady',
      ScanHint.tooDark => 'Too dark — find more light',
      ScanHint.glare => 'Glare on the page — tilt the phone a little',
      ScanHint.shadow => 'Shadow on the page — hold steady',
      ScanHint.capturing => 'Capturing — hold still',
      ScanHint.saved =>
        _pages.isEmpty
            ? 'Saved'
            : 'Page ${_pages.length} saved — show the next page',
      ScanHint.manual => 'Tap the shutter to capture',
      ScanHint.setCorners => 'Press and hold on the other corners',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final u = _update;
    final phase = u?.phase ?? ScanPhase.searching;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(
            builder: (context, constraints) {
              _view = constraints.biggest;
              _safe = MediaQuery.paddingOf(context);
              // The same children in the same places throughout, so a drag
              // begun on the live view carries on over the held picture.
              return Stack(
                fit: StackFit.expand,
                children: [
                  _preview(c, phase),
                  _heldPicture(c),
                  IgnorePointer(
                    child: FadeTransition(
                      opacity: ReverseAnimation(_flash),
                      child: AnimatedBuilder(
                        animation: _flash,
                        builder: (context, _) => _flash.isAnimating
                            ? ColoredBox(
                                color: Colors.white.withValues(alpha: 0.6),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  Listener(
                    key: const ValueKey('scan-touch'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _touchDown,
                    onPointerMove: _touchMove,
                    onPointerUp: _touchEnd,
                    onPointerCancel: _touchEnd,
                    child: const SizedBox.expand(),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        Visibility(
                          visible: _editor == null,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _topBar(),
                        ),
                        const SizedBox(height: CruSpace.s12),
                        ListenableBuilder(
                          listenable: _editor ?? _settle,
                          builder: (context, _) => _GuidancePill(
                            text: _guidance,
                            // Answers to a finger cannot wait.
                            atOnce: _finger != null || _editor != null,
                          ),
                        ),
                        const Spacer(),
                        _cornerRow(),
                        _editor == null ? _bottomBar(c, u) : _editBar(c),
                      ],
                    ),
                  ),
                  _loupe(c),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heldPicture(CruColors c) {
    final editor = _editor;
    if (editor == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([_settle, editor]),
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: CornerPainter(
            editor: editor,
            rect: _rect(editor.size),
            settled: _settled,
            accent: c.accent,
            warning: c.amber,
            sensed: c.green,
          ),
        ),
      ),
    );
  }

  Widget _loupe(CruColors c) {
    final editor = _editor;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([_settle, _moved, ?editor]),
        builder: (context, _) {
          final Offset corner;
          final bool sensed;
          if (editor != null) {
            final i = editor.active;
            if (i == null) return const SizedBox.shrink();
            final p = editor.corners.points[i];
            final rect = _rect(editor.size);
            corner =
                rect.topLeft +
                Offset(p.x, p.y) * (rect.width / editor.size.width);
            sensed = editor.found.contains(i);
          } else {
            final i = _held ?? _pressedCorner;
            final size = _previewSize, quad = _outline;
            if (_finger == null || i == null || size == null || quad == null) {
              return const SizedBox.shrink();
            }
            final p = quad.corners[i];
            final rect = _rect(size);
            corner = rect.topLeft + Offset(p.x * rect.width, p.y * rect.height);
            sensed = i == _held
                ? _caught
                : (_flags?[i] ?? 0) & CornerFlag.sensed != 0;
          }
          return CornerLoupe(
            finger: _last,
            corner: corner,
            view: _view,
            safeTop: _safe.top,
            ring: sensed ? c.green : Colors.white,
          );
        },
      ),
    );
  }

  /// Above the buttons: how to set a corner, or the way back into the last
  /// page's corners. Keeps its height so nothing around it moves.
  Widget _cornerRow() {
    Widget? child;
    if (_editor == null && _camera != null && !_loadingPage) {
      if (_flags != null && _update?.phase != ScanPhase.saved) {
        child = _Capsule(
          label: 'Reset corners',
          height: 32,
          fill: Colors.black.withValues(alpha: 0.55),
          ink: Colors.white,
          onTap: _resetCorners,
        );
      } else if (_pages.isEmpty) {
        child = IgnorePointer(
          child: Text(
            'Press and hold a page, or one of its corners',
            style: MobileType.caption.tint(
              Colors.white.withValues(alpha: 0.85),
            ),
          ),
        );
      } else if (_pages.last.source != null) {
        child = _Capsule(
          label: 'Adjust corners',
          height: 32,
          fill: Colors.black.withValues(alpha: 0.55),
          ink: Colors.white,
          onTap: _finishing || _importing || _manualPending
              ? null
              : () => _adjustPage(_pages.length - 1),
        );
      }
    }
    return SizedBox(height: 32, child: Center(child: child));
  }

  Widget _editBar(CruColors c) {
    final editor = _editor!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s12,
        CruSpace.s20,
        CruSpace.s20,
      ),
      // As tall as the shutter's row.
      child: SizedBox(
        height: 76,
        child: Row(
          children: [
            _Capsule(
              label: 'Cancel',
              fill: Colors.white.withValues(alpha: 0.16),
              ink: Colors.white,
              onTap: _cutting ? null : _closeEditor,
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: editor,
              builder: (context, _) => _Capsule(
                label: 'Use page',
                fill: c.accent,
                ink: Colors.white,
                onTap: editor.corners.valid && !_cutting ? _useCorners : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(CruColors c, ScanPhase phase) {
    final ctrl = _camera;
    final size = ctrl?.value.previewSize;
    if (ctrl == null || size == null || !ctrl.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final w = math.min(size.width, size.height);
    final h = math.max(size.width, size.height);
    final color = switch (phase) {
      ScanPhase.saved => c.green,
      ScanPhase.capturing => c.accent,
      _ => _flags == null ? Colors.white : c.accent,
    };
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(ctrl),
              // Same box as the preview, so the outline lines up with it.
              ListenableBuilder(
                listenable: _moved,
                builder: (context, _) => CustomPaint(
                  painter: _OutlinePainter(
                    quad: _editor == null ? _outline : null,
                    flags: _flags,
                    held: _finger == null ? null : _held ?? _pressedCorner,
                    sensed: c.green,
                    color: color,
                    strokeWidth: w / 160,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s8,
        CruSpace.s12,
        0,
      ),
      child: Row(
        children: [
          _RoundButton(
            semanticLabel: 'Close',
            onTap: _close,
            child: const CruIcon(CruIcons.close, color: Colors.white),
          ),
          const Spacer(),
          _RoundButton(
            semanticLabel: _torch ? 'Turn the light off' : 'Turn the light on',
            onTap: _camera == null ? null : _toggleTorch,
            selected: _torch,
            child: Icon(
              _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torch ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: CruSpace.s8),
          CruPressable(
            onTap: _toggleAuto,
            semanticLabel: _auto
                ? 'Automatic capture on. Tap for manual.'
                : 'Manual capture. Tap for automatic.',
            builder: (context, _) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _auto
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
              child: Text(
                _auto ? 'Auto' : 'Manual',
                style: MobileType.subhead.tint(
                  _auto ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(CruColors c, WorkerUpdate? u) {
    final busy = _manualPending || _finishing || _importing;
    final progress = _manualPending
        ? null
        : (u?.phase == ScanPhase.capturing ? u!.progress : 0.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s12,
        CruSpace.s20,
        CruSpace.s20,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _RoundButton(
                semanticLabel: 'Add from photos',
                onTap: busy ? null : _importPhotos,
                size: 48,
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          _Shutter(
            progress: progress,
            ringColor: c.accent,
            onTap: busy || _camera == null ? null : _shutter,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _pages.isEmpty
                  ? const SizedBox(width: 48)
                  : _DoneButton(
                      page: _pages.last,
                      count: _pages.length,
                      onTap: busy && !_finishing ? null : _finish,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.quad,
    required this.flags,
    required this.held,
    required this.sensed,
    required this.color,
    required this.strokeWidth,
  });

  final Quad? quad;
  final List<int>? flags;

  /// The corner under the finger: left clear, for the magnifier.
  final int? held;
  final Color sensed;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final pts = [
      for (final p in q.corners) Offset(p.x * size.width, p.y * size.height),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
    // Handles: big enough to read as something to take hold of.
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (var i = 0; i < 4; i++) {
      if (i == held) continue;
      final onCorner = (flags?[i] ?? 0) & CornerFlag.sensed != 0;
      canvas.drawCircle(
        pts[i],
        strokeWidth * 3.2,
        Paint()..color = onCorner ? sensed : Colors.white,
      );
      canvas.drawCircle(pts[i], strokeWidth * 3.2, ring);
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.quad != quad ||
      old.flags != flags ||
      old.held != held ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// What to do next. A message stays long enough to be read: hints that
/// come and go from frame to frame would otherwise pile up on each other.
class _GuidancePill extends StatefulWidget {
  const _GuidancePill({required this.text, required this.atOnce});

  final String text;
  final bool atOnce;

  @override
  State<_GuidancePill> createState() => _GuidancePillState();
}

class _GuidancePillState extends State<_GuidancePill> {
  static const _dwell = Duration(milliseconds: 700);

  late String _text = widget.text;
  Timer? _resting;

  @override
  void didUpdateWidget(_GuidancePill old) {
    super.didUpdateWidget(old);
    if (widget.text != _text && (widget.atOnce || _resting == null)) {
      _show();
    }
  }

  void _show() {
    _text = widget.text;
    _resting?.cancel();
    _resting = Timer(_dwell, () {
      _resting = null;
      if (mounted && widget.text != _text) setState(_show);
    });
  }

  @override
  void dispose() {
    _resting?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: CruMotion.of(context, CruMotion.fast),
        switchInCurve: CruMotion.curve,
        child: Container(
          key: ValueKey(_text),
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s16,
            vertical: CruSpace.s8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(CruRadius.full),
          ),
          child: Text(_text, style: MobileType.subhead.tint(Colors.white)),
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
    this.height = 48,
  });

  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, _) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(CruRadius.full),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: MobileType.subhead.tint(ink)),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.size = 40,
    this.selected = false,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, _) => Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? Colors.white
                : Colors.black.withValues(alpha: 0.45),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The shutter, with a ring that fills as the automatic capture gathers its
/// frames. [progress] null spins (a manual capture under way).
class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.progress,
    required this.ringColor,
    required this.onTap,
  });

  final double? progress;
  final Color ringColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Capture the page now',
      builder: (context, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
            if (progress == null || progress! > 0)
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  color: ringColor,
                  backgroundColor: Colors.transparent,
                ),
              ),
            AnimatedOpacity(
              duration: CruMotion.of(context, CruMotion.fast),
              opacity: onTap == null ? 0.5 : 1,
              child: Container(
                width: size - 18,
                height: size - 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last page and how many there are; tap to finish.
class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.page,
    required this.count,
    required this.onTap,
  });

  final CapturedPage page;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: onTap,
      semanticLabel: count == 1 ? 'Done, 1 page' : 'Done, $count pages',
      builder: (context, _) => Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s4,
          CruSpace.s4,
          CruSpace.s12,
          CruSpace.s4,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(CruRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.full),
              child: Image.memory(
                page.thumb,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            Text(
              'Done · $count',
              style: MobileType.subhead
                  .tint(Colors.black)
                  .copyWith(fontFeatures: CruType.tabular),
            ),
          ],
        ),
      ),
    );
  }
}
