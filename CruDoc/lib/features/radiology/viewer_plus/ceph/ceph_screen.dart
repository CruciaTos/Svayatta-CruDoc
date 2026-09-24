import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ai/ai_panels.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_analysis.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_tracing.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_canvas.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Cephalometric tracing on one lateral ceph: guided landmark placement,
/// planes drawn as the landmarks go in, and the standard analyses against
/// their norms. The tracing saves as you go (`extras['ceph'][imageId]`)
/// and its values join the report's measurements.
class RadCephScreen extends ConsumerStatefulWidget {
  const RadCephScreen({super.key, required this.studyId, required this.imageId});

  final String studyId;
  final String imageId;

  @override
  ConsumerState<RadCephScreen> createState() => _RadCephScreenState();
}

/// Landmarks and skips at one moment, for undo.
class _Snapshot {
  _Snapshot(Map<String, Offset> points, Set<String> skipped)
      : points = Map.of(points),
        skipped = Set.of(skipped);

  final Map<String, Offset> points;
  final Set<String> skipped;
}

class _RadCephScreenState extends ConsumerState<RadCephScreen> {
  late final RadiologyController _rad;
  late final RadiologyRepository _repo;

  final _view = PlusView();
  final _image = ValueNotifier<ui.Image?>(null);
  final _tick = ValueNotifier<int>(0);
  final _focus = FocusNode(debugLabel: 'Ceph tracing');
  final _renderer = PlusLatest();
  Future<void> _writes = Future<void>.value();

  RadStudy? _study;
  PlusRaster? _raster;
  String? _error;
  double _wc = 0;
  double _ww = 1;
  bool _invert = false;

  final Map<String, Offset> _points = {};
  final Set<String> _skipped = {};

  /// The landmark being placed or adjusted ("now").
  String? _current;
  String? _dragging;

  /// The drag placed a new point: move on to the next landmark on release.
  bool _placing = false;
  String? _hover;
  String _analysis = cephAnalyses.first.key;
  bool _planes = true;
  bool _labels = true;
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];

  bool _ruler = false;
  Offset? _rulerA;
  Offset? _rulerB;

  Timer? _saveTimer;
  bool _dirty = false;
  bool _audited = false;
  DateTime? _savedAt;

  double _leftWidth = 272;
  double _rightWidth = 380;

  @override
  void initState() {
    super.initState();
    _rad = ref.read(radiologyProvider);
    _repo = ref.read(radiologyRepositoryProvider);
    unawaited(_load());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(_write(_saveNow));
    _image.value?.dispose();
    _image.dispose();
    _tick.dispose();
    _view.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ───────────────────────────── Loading ─────────────────────────────

  Future<void> _load() async {
    try {
      final settings = await ref.read(radSettingsProvider.future);
      _applyPrefs(settings.viewer);
    } catch (_) {
      // Preferences are a convenience; the defaults work.
    }
    final s = await _repo.study(widget.studyId);
    if (!mounted) return;
    if (s == null) {
      setState(() => _error = 'This study is no longer here');
      return;
    }
    _study = s;
    _restore(s);
    setState(() {});
    try {
      final px = await plusLoadPixels(_rad, s, widget.imageId);
      final raster = await PlusRaster.of(px);
      if (!mounted) return;
      final (c, w) = px.defaultWindow;
      _raster = raster;
      _wc = c;
      _ww = w;
      _view.setImage(Size(px.width.toDouble(), px.height.toDouble()));
      _render();
    } on RadUnsupportedImage catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } catch (_) {
      if (mounted) setState(() => _error = "This image couldn't be opened");
    }
  }

  void _applyPrefs(Map<String, dynamic> v) {
    final left = v['plus.ceph.left'], right = v['plus.ceph.right'];
    if (left is num) _leftWidth = left.toDouble().clamp(PlusSize.panelMin, PlusSize.panelMax);
    if (right is num) _rightWidth = right.toDouble().clamp(PlusSize.panelMin, PlusSize.panelMax);
    final analysis = v['plus.ceph.analysis'];
    if (analysis is String) _analysis = cephAnalysis(analysis).key;
    if (v['plus.ceph.planes'] is bool) _planes = v['plus.ceph.planes'] as bool;
    if (v['plus.ceph.labels'] is bool) _labels = v['plus.ceph.labels'] as bool;
  }

  void _savePref(String key, Object value) => unawaited(_rad.saveViewerPrefs({key: value}));

  /// The saved tracing of this image, if any.
  void _restore(RadStudy s) {
    final all = s.extras['ceph'];
    final mine = all is Map ? all[widget.imageId] : null;
    if (mine is Map) {
      final landmarks = mine['landmarks'];
      if (landmarks is Map) {
        for (final e in landmarks.entries) {
          final v = e.value;
          if (v is List && v.length >= 2 && v[0] is num && v[1] is num) {
            _points['${e.key}'] = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
          }
        }
      }
      final skipped = mine['skipped'];
      if (skipped is List) _skipped.addAll(skipped.map((e) => '$e'));
      final analysis = mine['analysis'];
      if (analysis is String) _analysis = cephAnalysis(analysis).key;
    }
    _current = _nextAfter(null);
  }

  void _render() {
    final raster = _raster;
    if (raster == null) return;
    final c = _wc, w = _ww, invert = _invert;
    _renderer.run(() async {
      final img = await raster.render(c, w, invert: invert);
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _image.value;
      _image.value = img;
      old?.dispose();
      if (old == null) setState(() {});
    });
  }

  double? get _mmPerPx {
    final s = _study;
    return (s == null ? null : RadMeasure.mmPerPx(s, widget.imageId)) ??
        _raster?.px.pixelSpacingMm;
  }

  // ───────────────────────────── Landmarks ─────────────────────────────

  /// The next landmark after [id] (in placement order) still to place.
  String? _nextAfter(String? id) {
    final start = id == null ? -1 : cephLandmarks.indexWhere((l) => l.id == id);
    for (var k = 1; k <= cephLandmarks.length; k++) {
      final l = cephLandmarks[(start + k) % cephLandmarks.length];
      if (!_points.containsKey(l.id) && !_skipped.contains(l.id)) return l.id;
    }
    return null;
  }

  Offset _clamp(Offset p) {
    final size = _view.imageSize;
    return Offset(p.dx.clamp(0, size.width), p.dy.clamp(0, size.height));
  }

  /// The landmark within reach of [p] on screen.
  String? _hit(Offset p) {
    final at = _view.toScreen(p);
    String? best;
    var bestD = CruSpace.s10;
    for (final e in _points.entries) {
      final d = (_view.toScreen(e.value) - at).distance;
      if (d < bestD) {
        best = e.key;
        bestD = d;
      }
    }
    return best;
  }

  void _snapshot() {
    _undo.add(_Snapshot(_points, _skipped));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  void _restoreSnapshot(_Snapshot s) {
    _points
      ..clear()
      ..addAll(s.points);
    _skipped
      ..clear()
      ..addAll(s.skipped);
    _changed();
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_points, _skipped));
    _restoreSnapshot(_undo.removeLast());
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_points, _skipped));
    _restoreSnapshot(_redo.removeLast());
  }

  /// Something in the tracing changed: redraw and save shortly.
  void _changed() {
    setState(() {});
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () => unawaited(_write(_saveNow)));
  }

  void _skip() {
    final id = _current;
    if (id == null) return;
    _snapshot();
    _skipped.add(id);
    _current = _nextAfter(id);
    _changed();
  }

  void _clearCurrent() {
    final id = _current;
    if (id == null || !_points.containsKey(id)) return;
    _snapshot();
    _points.remove(id);
    _changed();
  }

  Future<void> _clearAll() async {
    final ok = await confirmDental(
      context,
      title: 'Clear all landmarks?',
      body: 'The tracing and its values go. Undo (Ctrl+Z) brings them back.',
      action: 'Clear all',
    );
    if (!ok || !mounted) return;
    _snapshot();
    _points.clear();
    _skipped.clear();
    _current = _nextAfter(null);
    _changed();
  }

  void _nudge(Offset d, {required bool first}) {
    final id = _current;
    final p = id == null ? null : _points[id];
    if (id == null || p == null) return;
    if (first) _snapshot();
    _points[id] = _clamp(p + d);
    _changed();
  }

  void _pick(String id) {
    setState(() => _current = id);
    _focus.requestFocus();
  }

  // ───────────────────────────── Stage input ─────────────────────────────

  bool _down(Offset p) {
    if (_image.value == null) return false;
    if (_ruler) {
      _rulerA = p;
      _rulerB = p;
      _tick.value++;
      return true;
    }
    final hit = _hit(p);
    if (hit != null) {
      _snapshot();
      _dragging = hit;
      _placing = false;
      setState(() => _current = hit);
      return true;
    }
    final id = _current;
    if (id == null) return false;
    _snapshot();
    _points[id] = _clamp(p);
    _skipped.remove(id);
    _dragging = id;
    _placing = !_placedBefore(id);
    _changed();
    return true;
  }

  /// Whether [id] had a point before this drag (then it's a move, and
  /// placement doesn't advance).
  bool _placedBefore(String id) => _undo.isNotEmpty && _undo.last.points.containsKey(id);

  void _move(Offset p) {
    if (_ruler) {
      _rulerB = p;
      _tick.value++;
      return;
    }
    final id = _dragging;
    if (id == null) return;
    _points[id] = _clamp(p);
    _changed();
  }

  void _up() {
    if (_ruler) {
      unawaited(_finishRuler());
      return;
    }
    final id = _dragging;
    if (id == null) return;
    if (_placing) _current = _nextAfter(id);
    _dragging = null;
    _placing = false;
    _changed();
  }

  void _hoverAt(Offset? p) {
    final h = p == null || _dragging != null ? _hover : _hit(p);
    if (h != _hover) setState(() => _hover = h);
  }

  void _window(Offset d) {
    final px = _raster?.px;
    if (px == null) return;
    final k = math.max(1e-6, (px.highPct - px.lowPct).abs()) / 400;
    _ww = math.max(k, _ww + d.dx * k);
    _wc += d.dy * k;
    _tick.value++;
    _render();
  }

  void _resetWindow() {
    final px = _raster?.px;
    if (px == null) return;
    final (c, w) = px.defaultWindow;
    _wc = c;
    _ww = w;
    _tick.value++;
    _render();
  }

  void _toggleInvert() {
    setState(() => _invert = !_invert);
    _render();
  }

  void _togglePlanes() {
    setState(() => _planes = !_planes);
    _savePref('plus.ceph.planes', _planes);
  }

  void _toggleLabels() {
    setState(() => _labels = !_labels);
    _savePref('plus.ceph.labels', _labels);
  }

  void _startRuler() {
    setState(() {
      _ruler = true;
      _rulerA = null;
      _rulerB = null;
    });
    _focus.requestFocus();
  }

  void _cancelRuler() => setState(() {
        _ruler = false;
        _rulerA = null;
        _rulerB = null;
      });

  Future<void> _finishRuler() async {
    final a = _rulerA, b = _rulerB;
    final px = a == null || b == null ? 0.0 : (b - a).distance;
    if (px < 4) {
      setState(() {
        _rulerA = null;
        _rulerB = null;
      });
      return;
    }
    final mm = await showDialog<double>(context: context, builder: (_) => _RulerDialog(px: px));
    if (!mounted) return;
    _cancelRuler();
    if (mm == null) return;
    try {
      await _write(() async {
        final fresh = await _repo.study(widget.studyId);
        if (fresh == null) return;
        await _rad.saveStudy(
          fresh.copyWith(calibration: {...fresh.calibration, widget.imageId: mm / px}),
          auditAction: 'Calibrated image',
          detail: '${mm.toStringAsFixed(1)} mm over ${px.round()} px',
        );
      });
      // Millimetre values can be worked out now: refresh the saved ones.
      _dirty = true;
      unawaited(_write(_saveNow));
      if (mounted) radToast(context, 'Scale set: ${(mm / px).toStringAsFixed(3)} mm per pixel');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't save the scale");
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final repeat = e is KeyRepeatEvent;
    if (kb.isControlPressed || kb.isMetaPressed) {
      if (repeat) return KeyEventResult.ignored;
      if (k == LogicalKeyboardKey.keyZ) {
        kb.isShiftPressed ? _redoOnce() : _undoOnce();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        _redoOnce();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final step = kb.isShiftPressed ? 10.0 : 1.0;
    final nudge = switch (k) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (nudge != null) {
      _nudge(nudge, first: !repeat);
      return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.ignored;
    switch (k) {
      case LogicalKeyboardKey.space:
        break; // Held for panning; the stage reads it.
      case LogicalKeyboardKey.escape:
        if (_ruler) {
          _cancelRuler();
        } else if (_current != null) {
          setState(() => _current = null);
        } else {
          return KeyEventResult.ignored;
        }
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _clearCurrent();
      case LogicalKeyboardKey.keyF:
        _view.fit();
      case LogicalKeyboardKey.keyI:
        _toggleInvert();
      case LogicalKeyboardKey.keyP:
        _togglePlanes();
      case LogicalKeyboardKey.keyL:
        _toggleLabels();
      case LogicalKeyboardKey.keyR:
        _startRuler();
      case LogicalKeyboardKey.keyN:
        _skip();
      case LogicalKeyboardKey.keyK:
        unawaited(_markKeyImage());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ───────────────────────────── Saving ─────────────────────────────

  /// Study writes run one after another, each on a fresh copy, so an
  /// autosave can't undo a key image saved a moment before.
  Future<void> _write(Future<void> Function() job) {
    final next = _writes.then((_) => job());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveNow() async {
    if (!_dirty) return;
    _dirty = false;
    final fresh = await _repo.study(widget.studyId);
    if (fresh == null) return;
    final a = cephAnalysis(_analysis);
    final mmPerPx = RadMeasure.mmPerPx(fresh, widget.imageId) ?? _raster?.px.pixelSpacingMm;
    final values = [
      for (final v in cephValues(a, _points, mmPerPx))
        if (v.value != null) v,
    ];
    final ceph = <String, dynamic>{
      if (fresh.extras['ceph'] is Map) ...Map<String, dynamic>.from(fresh.extras['ceph'] as Map),
      widget.imageId: {
        'landmarks': {
          for (final e in _points.entries)
            e.key: [_round(e.value.dx, 10), _round(e.value.dy, 10)],
        },
        'skipped': _skipped.toList(),
        'analysis': a.key,
        'analysisName': a.name,
        'values': [
          for (final v in values)
            {
              'key': v.measure.key,
              'name': v.measure.name,
              'value': _round(v.value!, 10),
              'unit': v.measure.unit.suffix.trim(),
              'norm': v.measure.normText,
              'mean': v.measure.mean,
              'sd': v.measure.sd,
            },
        ],
        'mmPerPx': mmPerPx,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    };
    // Replace this image's ceph rows in the report measurements.
    final prefix = 'ceph_${widget.imageId}_';
    final old = fresh.extras['reportMeasurements'];
    final rows = [
      if (old is List)
        for (final m in old)
          if (m is Map && !'${m['id']}'.startsWith(prefix)) m,
      for (final v in values)
        {
          'id': '$prefix${v.measure.key}',
          'label': '${v.measure.name} (${a.name})',
          'value': v.measure.mean == null
              ? v.text
              : '${v.text} (norm ${v.measure.normText}${v.measure.unit.suffix})',
        },
    ];
    await _rad.saveStudy(
      fresh.copyWith(extras: {...fresh.extras, 'ceph': ceph, 'reportMeasurements': rows}),
      auditAction: _audited ? null : 'Traced ceph',
      detail: a.name,
    );
    _audited = true;
    if (mounted) setState(() => _savedAt = DateTime.now());
  }

  static double _round(double v, int per) => (v * per).roundToDouble() / per;

  void _setAnalysis(String key) {
    if (key == _analysis) return;
    _analysis = key;
    _savePref('plus.ceph.analysis', key);
    _changed();
  }

  /// The image with the tracing burnt in, at full size.
  Future<Uint8List?> _tracingPng() async {
    final img = _image.value;
    if (img == null) return null;
    final unit = math.max(1.0, math.max(img.width, img.height) / 900);
    return plusRenderPng(img.width, img.height, (canvas) {
      canvas.drawImage(img, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
      paintCephTracing(
        canvas,
        points: _points,
        analysis: _analysis,
        toScreen: (p) => p,
        unit: unit,
        planes: _planes,
        labels: _labels,
      );
    });
  }

  Future<void> _exportPng() async {
    final s = _study;
    final png = await _tracingPng();
    if (png == null || s == null) return;
    try {
      final path = await plusSavePngAs(png, plusFileName(s, 'ceph tracing'));
      if (path == null) return;
      unawaited(_rad.log('Exported ceph tracing', targetKind: 'study', targetId: s.id, detail: path));
      if (mounted) radToast(context, 'Tracing saved');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't save the picture");
    }
  }

  Future<void> _markKeyImage() async {
    final png = await _tracingPng();
    if (png == null) return;
    final caption = 'Ceph tracing · ${cephAnalysis(_analysis).name}';
    try {
      await _write(() async {
        final fresh = await _repo.study(widget.studyId);
        if (fresh == null) return;
        final key = await plusWriteKeyImage(_rad, fresh,
            imageId: widget.imageId, png: png, caption: caption);
        await _rad.saveStudy(
          fresh.copyWith(keyImages: [...fresh.keyImages, key]),
          auditAction: 'Marked key image',
          detail: caption,
        );
      });
      if (mounted) radToast(context, 'Key image added for the report');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't save the key image");
    }
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final live = ref.watch(radStudyProvider(widget.studyId)).value;
    if (live != null) _study = live;
    final s = _study;
    final analysis = cephAnalysis(_analysis);
    final mmPerPx = _mmPerPx;
    final values = cephValues(analysis, _points, mmPerPx);
    final ready = _image.value != null;
    return Scaffold(
      backgroundColor: c.canvas,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            PlusTopBar(
              title: 'Ceph tracing',
              subtitle: s == null
                  ? ''
                  : '${s.patientName} · ${plusImageLabel(s, widget.imageId)} · '
                      '${RadFormat.date(s.studyDate)}',
              actions: [
                if (_savedAt != null)
                  Text('Saved ${RadFormat.time(_savedAt!)}',
                      style: CruType.caption.tabular.tint(c.label3)),
                CruButton(
                  label: 'Export PNG',
                  kind: CruButtonKind.secondary,
                  icon: CruIcons.download,
                  onPressed: ready ? _exportPng : null,
                ),
                CruButton(
                  label: 'Mark key image',
                  icon: PlusIcons.keyImage,
                  onPressed: ready ? _markKeyImage : null,
                ),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlusSidePanel(
                    left: true,
                    width: _leftWidth,
                    onResized: (w) {
                      _leftWidth = w;
                      _savePref('plus.ceph.left', w);
                    },
                    child: _landmarkPanel(c),
                  ),
                  Expanded(child: _stage(ready)),
                  PlusSidePanel(
                    width: _rightWidth,
                    onResized: (w) {
                      _rightWidth = w;
                      _savePref('plus.ceph.right', w);
                    },
                    child: _analysisPanel(c, s, analysis, values, mmPerPx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(bool ready) {
    final cur = _current == null ? null : cephLandmark(_current!);
    final (String title, String body) = _ruler
        ? ('Draw the ruler', 'Drag across a known length, such as the marks on the nasal rod.')
        : cur != null
            ? ('${_points.containsKey(cur.id) ? 'Move' : 'Place'} ${cur.name} (${cur.id})', cur.hint)
            : _nextAfter(null) == null
                ? ('Tracing complete', 'Drag any point to adjust it.')
                : ('Pick a landmark', 'Choose one in the list to place or move it.');
    return PlusCanvas(
      view: _view,
      repaint: Listenable.merge([_tick, _image]),
      focusNode: _focus,
      painter: _paint,
      onPrimaryDown: _down,
      onPrimaryMove: _move,
      onPrimaryUp: _up,
      onWindowDrag: ready ? _window : null,
      onHover: _hoverAt,
      cursor: _hover != null
          ? SystemMouseCursors.move
          : (_ruler || _current != null ? SystemMouseCursors.precise : SystemMouseCursors.basic),
      overlays: [
        if (!ready)
          PlusStageMessage(title: _error ?? 'Opening the image…', loading: _error == null)
        else ...[
          Positioned(
            left: CruSpace.s16,
            top: CruSpace.s16,
            child: IgnorePointer(child: PlusStageNote(title: title, body: body)),
          ),
          Positioned(
            right: CruSpace.s16,
            top: CruSpace.s16,
            child: PlusStageBar(children: [
              PlusStageButton(
                icon: PlusIcons.undo,
                tooltip: 'Undo (Ctrl+Z)',
                onTap: _undo.isEmpty ? null : _undoOnce,
              ),
              PlusStageButton(
                icon: PlusIcons.redo,
                tooltip: 'Redo (Ctrl+Y)',
                onTap: _redo.isEmpty ? null : _redoOnce,
              ),
              const PlusStageDivider(),
              PlusStageButton(icon: PlusIcons.fit, tooltip: 'Fit (F)', onTap: _view.fit),
              PlusStageButton(
                icon: PlusIcons.invert,
                tooltip: 'Invert (I)',
                active: _invert,
                onTap: _toggleInvert,
              ),
              PlusStageButton(
                icon: PlusIcons.resetWindow,
                tooltip: 'Reset brightness and contrast',
                onTap: _resetWindow,
              ),
              const PlusStageDivider(),
              PlusStageButton(
                icon: PlusIcons.planes,
                tooltip: 'Planes and lines (P)',
                active: _planes,
                onTap: _togglePlanes,
              ),
              PlusStageButton(
                icon: PlusIcons.labels,
                tooltip: 'Landmark names (L)',
                active: _labels,
                onTap: _toggleLabels,
              ),
              PlusStageButton(
                icon: PlusIcons.ruler,
                tooltip: 'Ruler: set the scale (R)',
                active: _ruler,
                onTap: _ruler ? _cancelRuler : _startRuler,
              ),
            ]),
          ),
          Positioned(
            left: CruSpace.s16,
            bottom: CruSpace.s16,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: Listenable.merge([_view, _tick]),
                builder: (context, _) => PlusStageReadout(
                  'W ${_ww.toStringAsFixed(0)} · C ${_wc.toStringAsFixed(0)} · '
                  '${(_view.scale * 100).round()}%   ·   Right-drag: brightness · '
                  'Wheel: zoom · Space-drag: pan',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _paint(Canvas canvas, Size size) {
    final img = _image.value;
    if (img == null) return;
    plusPaintImage(canvas, _view, img);
    paintCephTracing(
      canvas,
      points: _points,
      analysis: _analysis,
      toScreen: _view.toScreen,
      current: _current,
      hover: _hover,
      planes: _planes,
      labels: _labels,
    );
    final a = _rulerA, b = _rulerB;
    if (_ruler && a != null && b != null) {
      const ink = PlusStage.ink;
      final sa = _view.toScreen(a), sb = _view.toScreen(b);
      final paint = Paint()
        ..color = ink.amber
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(sa, sb, paint)
        ..drawCircle(sa, 3, paint)
        ..drawCircle(sb, 3, paint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(b - a).distance.round()} px',
          style: CruType.micro.tabular.copyWith(color: ink.amberText, shadows: PlusStage.textShadow),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, (sa + sb) / 2 + const Offset(CruSpace.s8, -CruSpace.s20));
    }
    plusPaintScaleBar(canvas, size, _view, _mmPerPx);
  }

  // ───────────────────────────── Panels ─────────────────────────────

  Widget _landmarkPanel(CruColors c) {
    final placed = _points.length;
    final total = cephLandmarks.length;
    final cur = _current == null ? null : cephLandmark(_current!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(CruSpace.s16, CruSpace.s16, CruSpace.s12, CruSpace.s24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Landmarks', style: CruType.headline.tint(c.label))),
            Text('$placed of $total', style: CruType.subhead.tabular.tint(c.label2)),
          ],
        ),
        const SizedBox(height: CruSpace.s10),
        CruProgressBar(value: placed / total, semanticLabel: 'Landmarks placed'),
        const SizedBox(height: CruSpace.s16),
        _currentCard(c, cur),
        const SizedBox(height: CruSpace.s12),
        const RadAiActionButton(label: 'AI place landmarks', expand: true),
        const SizedBox(height: CruSpace.s6),
        const RadNotConnected(
          compact: true,
          title: 'No AI key connected',
          body: '',
        ),
        for (final g in CephGroup.values) ...[
          PlusPanelLabel(g.label),
          for (final l in cephLandmarks)
            if (l.group == g)
              _LandmarkRow(
                landmark: l,
                placed: _points.containsKey(l.id),
                skipped: _skipped.contains(l.id),
                current: l.id == _current,
                onTap: () => _pick(l.id),
              ),
        ],
        if (_points.isNotEmpty || _skipped.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s20),
          CruButton(
            label: 'Clear all landmarks',
            kind: CruButtonKind.inset,
            expand: true,
            onPressed: _clearAll,
          ),
        ],
      ],
    );
  }

  Widget _currentCard(CruColors c, CephLandmark? cur) {
    final placed = cur != null && _points.containsKey(cur.id);
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: ShapeDecoration(
        color: cur == null ? c.inset : c.accentWash,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cur == null) ...[
            Text(
              _nextAfter(null) == null ? 'All landmarks placed' : 'Pick a landmark',
              style: CruType.callout.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s2),
            Text(
              _nextAfter(null) == null
                  ? 'Drag any point on the image to adjust it.'
                  : 'Choose one below to place or move it.',
              style: CruType.caption.tint(c.label2),
            ),
          ] else ...[
            Text(placed ? 'Adjusting' : 'Now placing',
                style: CruType.micro.tint(c.accentText)),
            const SizedBox(height: CruSpace.s4),
            Text('${cur.name} (${cur.id})', style: CruType.callout.tint(c.label)),
            const SizedBox(height: CruSpace.s2),
            Text(cur.hint, style: CruType.caption.tint(c.label2)),
            const SizedBox(height: CruSpace.s12),
            Row(
              children: [
                CruCapsuleButton(
                  label: 'Skip',
                  icon: PlusIcons.skip,
                  kind: CruCapsuleKind.surface,
                  onPressed: _skip,
                ),
                if (placed) ...[
                  const SizedBox(width: CruSpace.s8),
                  CruCapsuleButton(
                    label: 'Clear point',
                    kind: CruCapsuleKind.surface,
                    onPressed: _clearCurrent,
                  ),
                ],
              ],
            ),
            const SizedBox(height: CruSpace.s10),
            Text('N skips · arrows nudge (Shift ×10) · Del clears',
                style: CruType.micro.tint(c.label3)),
          ],
        ],
      ),
    );
  }

  Widget _analysisPanel(
    CruColors c,
    RadStudy? s,
    CephAnalysis a,
    List<CephValue> values,
    double? mmPerPx,
  ) {
    final done = values.where((v) => v.value != null).length;
    final fromRuler = s != null && s.calibration.containsKey(widget.imageId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, CruSpace.s16, CruSpace.s16, CruSpace.s24),
      children: [
        Text('Analysis', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s12),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            for (final an in cephAnalyses)
              DentalChoiceChip(
                label: an.name,
                selected: an.key == a.key,
                onTap: () => _setAnalysis(an.key),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s8),
        Text(a.detail, style: CruType.caption.tint(c.label2)),
        const SizedBox(height: CruSpace.s16),
        if (mmPerPx != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${mmPerPx.toStringAsFixed(3)} mm per pixel · '
                  '${fromRuler ? 'from your ruler' : 'from the file'}',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ),
              CruCapsuleButton(
                label: 'Recalibrate',
                icon: PlusIcons.ruler,
                onPressed: _image.value == null ? null : _startRuler,
              ),
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(CruSpace.s14),
            decoration: ShapeDecoration(color: c.amberTint, shape: cruShape(CruRadius.control)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not calibrated', style: CruType.subhead.w600.tint(c.amberText)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  'Draw a ruler over a known length to get the millimetre values.',
                  style: CruType.caption.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s10),
                CruCapsuleButton(
                  label: 'Draw ruler',
                  icon: PlusIcons.ruler,
                  kind: CruCapsuleKind.surface,
                  onPressed: _image.value == null ? null : _startRuler,
                ),
              ],
            ),
          ),
        PlusPanelLabel(
          'Values',
          trailing: Text('$done of ${values.length}', style: CruType.caption.tabular.tint(c.label3)),
        ),
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const CruSeparator(),
          _ValueRow(values[i]),
        ],
        const SizedBox(height: CruSpace.s16),
        Text(
          'Norms are adult means ± 1 SD. Amber is outside 1 SD. '
          'Values save with the tracing and appear in the report.',
          style: CruType.caption.tint(c.label3),
        ),
      ],
    );
  }
}

class _LandmarkRow extends StatelessWidget {
  const _LandmarkRow({
    required this.landmark,
    required this.placed,
    required this.skipped,
    required this.current,
    required this.onTap,
  });

  final CephLandmark landmark;
  final bool placed;
  final bool skipped;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final Widget status;
    if (placed) {
      status = Container(
        width: PlusSize.landmarkDot,
        height: PlusSize.landmarkDot,
        alignment: Alignment.center,
        decoration: ShapeDecoration(color: c.greenTint, shape: const CircleBorder()),
        child: CruIcon(CruIcons.check, size: 13, strokeWidth: 2.4, color: c.greenText),
      );
    } else {
      status = Container(
        width: PlusSize.landmarkDot,
        height: PlusSize.landmarkDot,
        decoration: ShapeDecoration(
          shape: CircleBorder(
            side: BorderSide(color: current ? c.accent : c.track, width: current ? 2 : 1.5),
          ),
        ),
      );
    }
    return Semantics(
      selected: current,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '${landmark.name}, ${placed ? 'placed' : skipped ? 'skipped' : 'not placed'}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.control,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
          decoration: ShapeDecoration(
            color: current
                ? c.accentWash
                : hovered
                    ? c.hoverFill
                    : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              status,
              const SizedBox(width: CruSpace.s10),
              SizedBox(
                width: CruSpace.s32 + CruSpace.s8,
                child: Text(landmark.id, style: CruType.callout.tint(c.label)),
              ),
              Expanded(
                child: Text(
                  landmark.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tint(c.label2),
                ),
              ),
              if (skipped && !placed) Text('Skipped', style: CruType.micro.tint(c.label3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.v);

  final CephValue v;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = v.measure;
    final has = v.value != null;
    final note = has
        ? m.detail
        : v.needsScale
            ? 'Needs the scale'
            : 'Needs ${v.missing.join(', ')}';
    final dev = v.deviation;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: CruType.callout.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tint(has ? c.label2 : c.label3)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                has ? v.text : '—',
                style: CruType.callout.tabular.tint(
                  !has
                      ? c.label3
                      : v.outside
                          ? c.amberText
                          : c.label,
                ),
              ),
              if (m.mean != null)
                Text('${m.normText}${m.unit.suffix}',
                    style: CruType.micro.tabular.tint(c.label3)),
            ],
          ),
          const SizedBox(width: CruSpace.s12),
          SizedBox(
            width: PlusSize.deviationBar,
            height: PlusSize.deviationBarHeight,
            child: dev == null
                ? null
                : Semantics(
                    label: '${dev.abs().toStringAsFixed(1)} SD '
                        '${dev < 0 ? 'below' : 'above'} the norm',
                    child: CustomPaint(
                      painter: _DeviationPainter(
                        dev,
                        track: c.inset,
                        band: c.track,
                        tick: c.label3,
                        marker: v.outside ? c.amber : c.label2,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Where a value sits against its norm: the band is ±1 SD, the ends ±3 SD.
class _DeviationPainter extends CustomPainter {
  _DeviationPainter(
    this.deviation, {
    required this.track,
    required this.band,
    required this.tick,
    required this.marker,
  });

  final double deviation;
  final Color track;
  final Color band;
  final Color tick;
  final Color marker;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    const r = Radius.circular(2);
    final half = size.width / 2 - 4;
    double x(double d) => size.width / 2 + d.clamp(-3.0, 3.0) / 3 * half;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(0, mid - 2, size.width, mid + 2), r),
        Paint()..color = track,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x(-1), mid - 2, x(1), mid + 2), r),
        Paint()..color = band,
      )
      ..drawLine(
        Offset(size.width / 2, mid - 4),
        Offset(size.width / 2, mid + 4),
        Paint()
          ..color = tick
          ..strokeWidth = 1,
      )
      ..drawCircle(Offset(x(deviation), mid), 4, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(covariant _DeviationPainter old) =>
      old.deviation != deviation || old.marker != marker || old.track != track;
}

/// Asks for the real length of the ruler line.
class _RulerDialog extends StatefulWidget {
  const _RulerDialog({required this.px});

  final double px;

  @override
  State<_RulerDialog> createState() => _RulerDialogState();
}

class _RulerDialogState extends State<_RulerDialog> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _done() {
    final v = double.tryParse(_ctl.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0 || v > 1000) {
      setState(() => _error = 'Type the length in millimetres');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'Set the scale',
      subtitle: 'The ruler you drew is ${widget.px.round()} pixels long',
      width: CruSize.formDialog * 0.62,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CruTextField(
              label: 'Real length (mm)',
              controller: _ctl,
              hint: '10',
              autofocus: true,
              tabular: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _done(),
            ),
            if (_error != null) ...[
              const SizedBox(height: CruSpace.s6),
              Text(_error!, style: CruType.caption.tint(c.amberText)),
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
          CruButton(label: 'Set scale', onPressed: _done),
        ],
      ),
    );
  }
}
