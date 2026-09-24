import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_canvas.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/plus_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Compares an image of this study (A) with an earlier one of the same
/// patient and type (B): B is aligned onto A by dragging and the rotation
/// and scale sliders, then shown alone, as an overlay, or as a subtraction
/// (A − B, mid-grey = no change). The alignment saves in
/// `extras['subtraction'][imageIdA]`.
class RadSubtractionScreen extends ConsumerStatefulWidget {
  const RadSubtractionScreen({super.key, required this.studyId, required this.imageIdA, this.imageIdB});

  final String studyId;
  final String imageIdA;

  /// An image id from any of the patient's studies of the same type.
  final String? imageIdB;

  @override
  ConsumerState<RadSubtractionScreen> createState() => _RadSubtractionScreenState();
}

enum _Mode {
  a('A'),
  b('B'),
  overlay('Overlay'),
  difference('Difference');

  const _Mode(this.label);
  final String label;
}

/// An image shrunk to ≤ 1024 px with values scaled 0–1 (bright = dense),
/// for the subtraction. Each image uses its own display range, which evens
/// out exposure differences between visits.
class _Small {
  const _Small(this.values, this.width, this.height, this.factor);

  final Float32List values;
  final int width;
  final int height;

  /// Full-size pixels per small pixel.
  final int factor;
}

/// One loaded side of the comparison.
class _Side {
  _Side(this.study, this.imageId, this.raster, this.small);

  final RadStudy study;
  final String imageId;
  final PlusRaster raster;
  final _Small small;
  ui.Image? image;

  int get width => raster.px.width;
  int get height => raster.px.height;
  Offset get centre => Offset(width / 2, height / 2);
}

/// An image the doctor can pick as B.
class _Candidate {
  const _Candidate(this.study, this.image);

  final RadStudy study;
  final RadImageRef image;
}

class _RadSubtractionScreenState extends ConsumerState<RadSubtractionScreen> {
  late final RadiologyController _rad;
  late final RadiologyRepository _repo;

  final _view = PlusView();
  final _tick = ValueNotifier<int>(0);
  final _focus = FocusNode(debugLabel: 'Subtraction');
  final _renderA = PlusLatest();
  final _renderB = PlusLatest();
  final _diffJob = PlusLatest();
  final _diffPaint = PlusLatest();
  Future<void> _writes = Future<void>.value();

  RadStudy? _study;
  _Side? _a;
  _Side? _b;
  String? _errorA;
  String? _errorB;
  bool _loadingB = false;

  _Mode _mode = _Mode.overlay;

  // Alignment of B onto A: A = centreA + (dx, dy) + scale · R(rotation) · (B − centreB).
  double _dx = 0;
  double _dy = 0;
  double _rot = 0;
  double _scale = 1;
  double _opacity = 0.5;

  // Brightness/contrast of A and B, relative to each image's own window.
  double _wShift = 0;
  double _wGain = 1;

  // The subtraction's window (values are A − B in 0–1 units).
  double _dCenter = 0;
  double _dWidth = 1;
  Float32List? _diff;
  ui.Image? _diffImage;

  /// Where the drag moving B last was (A's pixels).
  Offset? _moveFrom;

  Timer? _saveTimer;
  bool _dirty = false;
  bool _audited = false;
  double _panelWidth = 340;

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
    _a?.image?.dispose();
    _b?.image?.dispose();
    _diffImage?.dispose();
    _tick.dispose();
    _view.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ───────────────────────────── Loading ─────────────────────────────

  Future<void> _load() async {
    try {
      final settings = await ref.read(radSettingsProvider.future);
      final w = settings.viewer['plus.sub.panel'];
      if (w is num) _panelWidth = w.toDouble().clamp(PlusSize.panelMin, PlusSize.panelMax);
    } catch (_) {
      // Preferences are a convenience; the defaults work.
    }
    if (!mounted) return;
    final s = await _repo.study(widget.studyId);
    if (!mounted) return;
    if (s == null) {
      setState(() => _errorA = 'This study is no longer here');
      return;
    }
    _study = s;
    try {
      final a = await _open(s, widget.imageIdA);
      if (!mounted) return;
      _a = a;
      _view.setImage(Size(a.width.toDouble(), a.height.toDouble()));
      _render(a, _renderA);
    } on RadUnsupportedImage catch (e) {
      if (mounted) setState(() => _errorA = e.reason);
      return;
    } catch (_) {
      if (mounted) setState(() => _errorA = "This image couldn't be opened");
      return;
    }

    // B: the one asked for, else the pair saved last time.
    final saved = _savedPair(s);
    final wantB = widget.imageIdB ?? (saved?['bImageId'] as String?);
    if (wantB == null) return;
    final all = await ref.read(radStudiesProvider.future);
    if (!mounted) return;
    for (final c in _candidates(all, s)) {
      if (c.image.id == wantB) {
        final restore = saved != null && saved['bImageId'] == wantB ? saved : null;
        await _pickB(c, restore: restore);
        return;
      }
    }
  }

  Map<String, dynamic>? _savedPair(RadStudy s) {
    final all = s.extras['subtraction'];
    final mine = all is Map ? all[widget.imageIdA] : null;
    return mine is Map ? Map<String, dynamic>.from(mine) : null;
  }

  Future<_Side> _open(RadStudy s, String imageId) async {
    final px = await plusLoadPixels(_rad, s, imageId);
    final raster = await PlusRaster.of(px);
    final values = px.values;
    final w = px.width, h = px.height;
    final lo = px.lowPct, hi = px.highPct;
    final invert = px.invert;
    final small = await Isolate.run(() => _shrink(values, w, h, lo, hi, invert));
    return _Side(s, imageId, raster, small);
  }

  /// The patient's images of the same study type (this study included),
  /// newest study first, except image A.
  List<_Candidate> _candidates(List<RadStudy> all, RadStudy a) {
    bool samePatient(RadStudy o) =>
        o.id == a.id ||
        (a.patientId.isNotEmpty && o.patientId == a.patientId) ||
        (a.patientId.isEmpty &&
            a.patientExternalId.isNotEmpty &&
            o.patientExternalId == a.patientExternalId);
    final studies = [
      for (final o in all)
        if (samePatient(o) && o.modality == a.modality && !o.modality.isVolume) o,
    ]..sort((x, y) => y.studyDate.compareTo(x.studyDate));
    if (!studies.any((o) => o.id == a.id)) studies.insert(0, a);
    return [
      for (final o in studies)
        for (final i in o.images)
          if (!i.compressed && !(o.id == a.id && i.id == widget.imageIdA)) _Candidate(o, i),
    ];
  }

  Future<void> _pickB(_Candidate c, {Map<String, dynamic>? restore}) async {
    if (_b?.imageId == c.image.id || _loadingB) return;
    setState(() {
      _loadingB = true;
      _errorB = null;
    });
    try {
      final b = await _open(c.study, c.image.id);
      if (!mounted) return;
      final old = _b;
      _b = b;
      old?.image?.dispose();
      final a = _a!;
      if (restore != null) {
        _dx = (restore['dx'] as num?)?.toDouble() ?? 0;
        _dy = (restore['dy'] as num?)?.toDouble() ?? 0;
        _rot = (restore['rotation'] as num?)?.toDouble() ?? 0;
        _scale = (restore['scale'] as num?)?.toDouble() ?? 1;
        _opacity = (restore['opacity'] as num?)?.toDouble() ?? 0.5;
        _mode = _Mode.values.firstWhere((m) => m.name == restore['mode'], orElse: () => _mode);
      } else {
        _resetAlignmentValues(a, b);
        _dirty = true;
      }
      _render(b, _renderB);
      _scheduleDiff();
      setState(() => _loadingB = false);
      if (_dirty) _scheduleSave();
    } on RadUnsupportedImage catch (e) {
      if (mounted) {
        setState(() {
          _loadingB = false;
          _errorB = e.reason;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingB = false;
          _errorB = "This image couldn't be opened";
        });
      }
    }
  }

  /// Centres B on A; when both files give pixel spacing, B is scaled so a
  /// millimetre is the same length in both.
  void _resetAlignmentValues(_Side a, _Side b) {
    final sa = a.raster.px.pixelSpacingMm, sb = b.raster.px.pixelSpacingMm;
    _dx = 0;
    _dy = 0;
    _rot = 0;
    _scale = sa != null && sb != null && sa > 0 && sb > 0 ? (sb / sa).clamp(0.5, 2.0) : 1;
  }

  void _resetAlignment() {
    final a = _a, b = _b;
    if (a == null || b == null) return;
    setState(() => _resetAlignmentValues(a, b));
    _alignmentChanged();
  }

  // ───────────────────────────── Rendering ─────────────────────────────

  void _render(_Side side, PlusLatest runner) {
    final (c0, w0) = side.raster.px.defaultWindow;
    final w = w0 * _wGain, c = c0 + _wShift * w0;
    runner.run(() async {
      final img = await side.raster.render(c, w);
      if (!mounted || (side != _a && side != _b)) {
        img.dispose();
        return;
      }
      final old = side.image;
      side.image = img;
      old?.dispose();
      if (old == null) {
        setState(() {});
      } else {
        _tick.value++;
      }
    });
  }

  /// Works out A − B on the small grids off the UI thread.
  void _scheduleDiff() {
    final a = _a, b = _b;
    if (a == null || b == null) return;
    final sa = a.small, sb = b.small;
    final av = sa.values, bv = sb.values;
    final aw = sa.width, ah = sa.height, af = sa.factor;
    final bw = sb.width, bh = sb.height, bf = sb.factor;
    final ca = a.centre, cb = b.centre;
    final dx = _dx, dy = _dy, rot = _rot * math.pi / 180, scale = _scale;
    _diffJob.run(() async {
      final diff = await Isolate.run(() => _difference(
            av, aw, ah, af, bv, bw, bh, bf,
            ca.dx, ca.dy, cb.dx, cb.dy, dx, dy, rot, scale,
          ));
      if (!mounted || a != _a || b != _b) return;
      _diff = diff;
      _paintDifference();
    });
  }

  /// The subtraction through its window, as an image.
  void _paintDifference() {
    final a = _a, d = _diff;
    if (a == null || d == null) return;
    final center = _dCenter, width = _dWidth;
    final w = a.small.width, h = a.small.height;
    _diffPaint.run(() async {
      final out = Uint32List(d.length);
      final low = center - width / 2;
      for (var i = 0; i < d.length; i++) {
        final v = d[i];
        if (v.isNaN) continue; // Outside B: left transparent.
        var t = (v - low) / width;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        final g = (t * 255).round();
        out[i] = 0xFF000000 | (g << 16) | (g << 8) | g;
      }
      final img = await plusDecode(out.buffer.asUint8List(), w, h);
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _diffImage;
      _diffImage = img;
      old?.dispose();
      _tick.value++;
    });
  }

  double get _theta => _rot * math.pi / 180;

  /// Moves [canvas] from A's pixels into B's.
  void _intoB(Canvas canvas, _Side a, _Side b) {
    canvas
      ..translate(a.centre.dx + _dx, a.centre.dy + _dy)
      ..rotate(_theta)
      ..scale(_scale)
      ..translate(-b.centre.dx, -b.centre.dy);
  }

  /// The chosen view in A's pixels (the stage and the key image).
  void _paintView(Canvas canvas, _Side a, {required FilterQuality quality}) {
    final b = _b;
    final imgA = a.image;
    final imgB = b?.image;
    final paint = Paint()..filterQuality = quality;
    void drawB(double opacity) {
      canvas.save();
      _intoB(canvas, a, b!);
      canvas.drawImage(
        imgB!,
        Offset.zero,
        Paint()
          ..filterQuality = quality
          ..color = PlusStage.background.withValues(alpha: opacity),
      );
      canvas.restore();
    }

    final hasB = imgB != null && b != null;
    switch (_mode) {
      case _Mode.a:
        if (imgA != null) canvas.drawImage(imgA, Offset.zero, paint);
      case _Mode.b:
        if (hasB) {
          drawB(1);
        } else if (imgA != null) {
          canvas.drawImage(imgA, Offset.zero, paint);
        }
      case _Mode.overlay:
        if (imgA != null) canvas.drawImage(imgA, Offset.zero, paint);
        if (hasB) drawB(_opacity);
      case _Mode.difference:
        final diff = _diffImage;
        if (hasB && diff != null) {
          canvas
            ..save()
            ..scale(a.small.factor.toDouble())
            ..drawImage(diff, Offset.zero, paint)
            ..restore();
        } else if (imgA != null) {
          canvas.drawImage(imgA, Offset.zero, paint);
        }
    }
  }

  void _paint(Canvas canvas, Size size) {
    final a = _a;
    if (a == null || a.image == null) return;
    canvas
      ..save()
      ..translate(_view.offset.dx, _view.offset.dy)
      ..scale(_view.scale);
    _paintView(canvas, a,
        quality: _view.scale < 1 ? FilterQuality.medium : FilterQuality.low);
    canvas.restore();
    final s = _study;
    plusPaintScaleBar(canvas, size, _view, s == null ? null : RadMeasure.mmPerPx(s, widget.imageIdA));
  }

  // ───────────────────────────── Input ─────────────────────────────

  bool _down(Offset p) {
    if (_a?.image == null || _b?.image == null || _mode == _Mode.a) return false;
    _moveFrom = p;
    return true;
  }

  void _move(Offset p) {
    final from = _moveFrom;
    if (from == null) return;
    setState(() {
      _dx += p.dx - from.dx;
      _dy += p.dy - from.dy;
    });
    _moveFrom = p;
    _scheduleDiff();
  }

  void _up() {
    if (_moveFrom == null) return;
    _moveFrom = null;
    _alignmentChanged();
  }

  void _window(Offset d) {
    if (_mode == _Mode.difference) {
      _dWidth = (_dWidth * (1 + d.dx * 0.005)).clamp(0.02, 4.0);
      _dCenter = (_dCenter + d.dy * 0.002).clamp(-1.0, 1.0);
      _paintDifference();
    } else {
      _wGain = (_wGain * (1 + d.dx * 0.005)).clamp(0.05, 20.0);
      _wShift = (_wShift + d.dy * 0.002).clamp(-2.0, 2.0);
      if (_a case final a?) _render(a, _renderA);
      if (_b case final b?) _render(b, _renderB);
    }
    _tick.value++;
  }

  void _resetWindow() {
    if (_mode == _Mode.difference) {
      _dCenter = 0;
      _dWidth = 1;
      _paintDifference();
    } else {
      _wShift = 0;
      _wGain = 1;
      if (_a case final a?) _render(a, _renderA);
      if (_b case final b?) _render(b, _renderB);
    }
    _tick.value++;
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _dirty = true;
    _scheduleSave();
  }

  void _alignmentChanged() {
    _scheduleDiff();
    _dirty = true;
    _scheduleSave();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final step = kb.isShiftPressed ? 10.0 : 1.0;
    final nudge = switch (k) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (nudge != null) {
      if (_b == null) return KeyEventResult.ignored;
      setState(() {
        _dx += nudge.dx;
        _dy += nudge.dy;
      });
      _alignmentChanged();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.bracketLeft || k == LogicalKeyboardKey.bracketRight) {
      if (_b == null) return KeyEventResult.ignored;
      final turn = (kb.isShiftPressed ? 2.0 : 0.5) * (k == LogicalKeyboardKey.bracketLeft ? -1 : 1);
      setState(() => _rot = (_rot + turn).clamp(-45.0, 45.0));
      _alignmentChanged();
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    switch (k) {
      case LogicalKeyboardKey.space:
        break; // Held for panning; the stage reads it.
      case LogicalKeyboardKey.digit1:
        _setMode(_Mode.a);
      case LogicalKeyboardKey.digit2:
        _setMode(_Mode.b);
      case LogicalKeyboardKey.digit3:
        _setMode(_Mode.overlay);
      case LogicalKeyboardKey.digit4:
        _setMode(_Mode.difference);
      case LogicalKeyboardKey.keyF:
        _view.fit();
      case LogicalKeyboardKey.keyK:
        unawaited(_markKeyImage());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ───────────────────────────── Saving ─────────────────────────────

  /// Study writes run one after another, each on a fresh copy.
  Future<void> _write(Future<void> Function() job) {
    final next = _writes.then((_) => job());
    _writes = next.catchError((Object _) {});
    return next;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () => unawaited(_write(_saveNow)));
  }

  Future<void> _saveNow() async {
    final b = _b;
    if (!_dirty || b == null) return;
    _dirty = false;
    final fresh = await _repo.study(widget.studyId);
    if (fresh == null) return;
    final all = <String, dynamic>{
      if (fresh.extras['subtraction'] is Map)
        ...Map<String, dynamic>.from(fresh.extras['subtraction'] as Map),
      widget.imageIdA: {
        'bStudyId': b.study.id,
        'bImageId': b.imageId,
        'dx': _dx,
        'dy': _dy,
        'rotation': _rot,
        'scale': _scale,
        'opacity': _opacity,
        'mode': _mode.name,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    };
    await _rad.saveStudy(
      fresh.copyWith(extras: {...fresh.extras, 'subtraction': all}),
      auditAction: _audited ? null : 'Compared images',
      detail: 'With ${RadFormat.date(b.study.studyDate)}',
    );
    _audited = true;
  }

  String _caption() {
    final a = _a, b = _b;
    final da = a == null ? '' : RadFormat.date(a.study.studyDate);
    final db = b == null ? '' : RadFormat.date(b.study.studyDate);
    return switch (_mode) {
      _Mode.a => 'Image A · $da',
      _Mode.b => 'Image B aligned · $db',
      _Mode.overlay => 'Overlay · $da with $db',
      _Mode.difference => 'Subtraction · $da − $db',
    };
  }

  Future<void> _markKeyImage() async {
    final a = _a;
    if (a == null || a.image == null) return;
    final caption = _caption();
    try {
      final png = await plusRenderPng(
        a.width,
        a.height,
        (canvas) => _paintView(canvas, a, quality: FilterQuality.medium),
      );
      await _write(() async {
        final fresh = await _repo.study(widget.studyId);
        if (fresh == null) return;
        final key = await plusWriteKeyImage(_rad, fresh,
            imageId: widget.imageIdA, png: png, caption: caption);
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
    final all = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
    final candidates = s == null ? const <_Candidate>[] : _candidates(all, s);
    final ready = _a?.image != null;
    return Scaffold(
      backgroundColor: c.canvas,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            PlusTopBar(
              title: 'Compare and subtract',
              subtitle: s == null
                  ? ''
                  : '${s.patientName} · ${s.modality.label} · ${RadFormat.date(s.studyDate)}',
              actions: [
                CruSegmentedControl<_Mode>(
                  semanticLabel: 'View',
                  segments: [for (final m in _Mode.values) CruSegment(m, m.label)],
                  selected: _mode,
                  onChanged: _setMode,
                ),
                const SizedBox(width: CruSpace.s8),
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
                  Expanded(child: _stage(ready)),
                  PlusSidePanel(
                    width: _panelWidth,
                    onResized: (w) {
                      _panelWidth = w;
                      unawaited(_rad.saveViewerPrefs({'plus.sub.panel': w}));
                    },
                    child: _panel(c, s, candidates),
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
    final a = _a, b = _b;
    final String title;
    final String? body;
    if (b == null && _mode != _Mode.a) {
      title = 'Pick image B';
      body = 'Choose an earlier image in the panel to compare with.';
    } else {
      title = switch (_mode) {
        _Mode.a => 'A · ${a == null ? '' : RadFormat.date(a.study.studyDate)}',
        _Mode.b => 'B · ${b == null ? '' : RadFormat.date(b.study.studyDate)} (aligned)',
        _Mode.overlay => 'Overlay',
        _Mode.difference => 'Subtraction A − B',
      };
      body = switch (_mode) {
        _Mode.a => 'Press 2 to flick to B.',
        _Mode.b || _Mode.overlay => 'Drag to move B · arrows nudge · [ ] rotate',
        _Mode.difference => 'Mid-grey is no change.',
      };
    }
    return PlusCanvas(
      view: _view,
      repaint: _tick,
      focusNode: _focus,
      painter: _paint,
      onPrimaryDown: _down,
      onPrimaryMove: _move,
      onPrimaryUp: _up,
      onWindowDrag: ready ? _window : null,
      cursor: b != null && _mode != _Mode.a ? SystemMouseCursors.move : SystemMouseCursors.basic,
      overlays: [
        if (!ready)
          PlusStageMessage(title: _errorA ?? 'Opening the image…', loading: _errorA == null)
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
              PlusStageButton(icon: PlusIcons.fit, tooltip: 'Fit (F)', onTap: _view.fit),
              PlusStageButton(
                icon: PlusIcons.resetWindow,
                tooltip: 'Reset brightness and contrast',
                onTap: _resetWindow,
              ),
            ]),
          ),
          Positioned(
            left: CruSpace.s16,
            bottom: CruSpace.s16,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _view,
                builder: (context, _) => PlusStageReadout(
                  '${(_view.scale * 100).round()}%   ·   1–4: views · Right-drag: contrast · '
                  'Wheel: zoom · Space-drag: pan',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _panel(CruColors c, RadStudy? s, List<_Candidate> candidates) {
    final a = _a;
    final hasB = _b != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, CruSpace.s16, CruSpace.s16, CruSpace.s24),
      children: [
        Text('Images', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s12),
        if (s != null)
          _ImageTile(
            badge: 'A',
            title: RadFormat.date(s.studyDate),
            subtitle: '${plusImageLabel(s, widget.imageIdA)} · this study',
            selected: true,
          ),
        PlusPanelLabel('Compare with (B)'),
        if (candidates.isEmpty)
          Text(
            s == null
                ? ''
                : 'No other ${s.modality.label} images of this patient yet. '
                    'Import an earlier study to compare.',
            style: CruType.caption.tint(c.label2),
          )
        else
          for (final cand in candidates) ...[
            _ImageTile(
              badge: 'B',
              title: RadFormat.date(cand.study.studyDate),
              subtitle: '${plusImageLabel(cand.study, cand.image.id)}'
                  '${cand.study.id == s?.id ? ' · this study' : ''}',
              selected: _b?.imageId == cand.image.id,
              onTap: a == null || _loadingB ? null : () => unawaited(_pickB(cand)),
            ),
            const SizedBox(height: CruSpace.s6),
          ],
        if (_loadingB) ...[
          const SizedBox(height: CruSpace.s6),
          const CruProgressBar(value: 0.5, semanticLabel: 'Opening image B'),
        ],
        if (_errorB != null) ...[
          const SizedBox(height: CruSpace.s6),
          Text(_errorB!, style: CruType.caption.tint(c.label2)),
        ],
        PlusPanelLabel(
          'Alignment',
          trailing: hasB
              ? CruCapsuleButton(label: 'Reset', onPressed: _resetAlignment)
              : null,
        ),
        Text(
          'Drag on the image to move B. Arrows nudge it (Shift ×10); [ and ] rotate.',
          style: CruType.caption.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s12),
        IgnorePointer(
          ignoring: !hasB,
          child: Opacity(
            opacity: hasB ? 1 : 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlusSlider(
                  label: 'Rotation',
                  value: _rot,
                  min: -45,
                  max: 45,
                  format: (v) => '${v.toStringAsFixed(1)}°',
                  onChanged: (v) {
                    setState(() => _rot = v);
                    _scheduleDiff();
                  },
                  onChangeEnd: (_) => _alignmentChanged(),
                ),
                PlusSlider(
                  label: 'Scale',
                  value: _scale,
                  min: 0.5,
                  max: 2,
                  format: (v) => '${(v * 100).toStringAsFixed(1)}%',
                  onChanged: (v) {
                    setState(() => _scale = v);
                    _scheduleDiff();
                  },
                  onChangeEnd: (_) => _alignmentChanged(),
                ),
                Text(
                  'Moved ${_dx.toStringAsFixed(0)}, ${_dy.toStringAsFixed(0)} px',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ],
            ),
          ),
        ),
        if (hasB && _mode == _Mode.overlay) ...[
          PlusPanelLabel('Overlay'),
          PlusSlider(
            label: 'Opacity of B',
            value: _opacity,
            min: 0,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) {
              setState(() => _opacity = v);
              _tick.value++;
            },
            onChangeEnd: (_) {
              _dirty = true;
              _scheduleSave();
            },
          ),
        ],
        if (hasB && _mode == _Mode.difference) ...[
          PlusPanelLabel('Subtraction'),
          Text(
            'Mid-grey is no change. Brighter is denser in A, darker is denser in B. '
            'Right-drag on the image for contrast.',
            style: CruType.caption.tint(c.label2),
          ),
        ],
      ],
    );
  }
}

/// A selectable image row: badge, date and what it is.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String badge;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: '$title, $subtitle',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.all(CruSpace.s10),
          decoration: ShapeDecoration(
            color: selected ? c.inset : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: selected ? c.separator : c.hairline),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: CruSize.monogramRow,
                height: CruSize.monogramRow,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: selected ? c.label : c.inset,
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: Text(badge, style: CruType.callout.tint(selected ? c.surface : c.label2)),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.callout.tabular.tint(c.label)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.tint(c.label2)),
                  ],
                ),
              ),
              if (selected && badge == 'B')
                CruIcon(CruIcons.check, size: 16, strokeWidth: 2.2, color: c.label2),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Off the UI thread ─────────────────────────────

/// Box-averages to ≤ 1024 px on the long side and scales to 0–1 over the
/// image's display range (flipped for MONOCHROME1 so bright = dense).
_Small _shrink(Float32List v, int w, int h, double lo, double hi, bool invert) {
  final f = math.max(1, (math.max(w, h) / 1024).ceil());
  final sw = math.max(1, w ~/ f), sh = math.max(1, h ~/ f);
  final range = hi - lo == 0 ? 1.0 : hi - lo;
  final out = Float32List(sw * sh);
  final n = f * f;
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var sum = 0.0;
      for (var j = 0; j < f; j++) {
        final row = (y * f + j) * w + x * f;
        for (var i = 0; i < f; i++) {
          sum += v[row + i];
        }
      }
      var t = (sum / n - lo) / range;
      if (invert) t = 1 - t;
      out[y * sw + x] = t;
    }
  }
  return _Small(out, sw, sh, f);
}

/// A − B on A's small grid, B sampled through the alignment (bilinear).
/// NaN where B doesn't cover A.
Float32List _difference(
  Float32List av,
  int aw,
  int ah,
  int af,
  Float32List bv,
  int bw,
  int bh,
  int bf,
  double cax,
  double cay,
  double cbx,
  double cby,
  double dx,
  double dy,
  double rot,
  double scale,
) {
  final out = Float32List(aw * ah);
  final c = math.cos(rot), s = math.sin(rot);
  for (var y = 0; y < ah; y++) {
    final ay = (y + 0.5) * af;
    for (var x = 0; x < aw; x++) {
      final ax = (x + 0.5) * af;
      final qx = (ax - cax - dx) / scale, qy = (ay - cay - dy) / scale;
      final bx = (cbx + qx * c + qy * s) / bf - 0.5;
      final by = (cby - qx * s + qy * c) / bf - 0.5;
      final i = y * aw + x;
      if (bx < 0 || by < 0 || bx > bw - 1 || by > bh - 1) {
        out[i] = double.nan;
        continue;
      }
      final x0 = bx.floor(), y0 = by.floor();
      final x1 = math.min(x0 + 1, bw - 1), y1 = math.min(y0 + 1, bh - 1);
      final fx = bx - x0, fy = by - y0;
      final top = bv[y0 * bw + x0] * (1 - fx) + bv[y0 * bw + x1] * fx;
      final bottom = bv[y1 * bw + x0] * (1 - fx) + bv[y1 * bw + x1] * fx;
      out[i] = av[i] - (top * (1 - fy) + bottom * fy);
    }
  }
  return out;
}
