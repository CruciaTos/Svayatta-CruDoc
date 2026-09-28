import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';

/// A thumbnail being dragged into a pane.
class RadImageDrag {
  const RadImageDrag(this.studyId, this.imageId);
  final String studyId;
  final String imageId;
}

/// Series that page as one stack of slices (CBCT / CT): several
/// single-frame images with slice positions, or any series of a CBCT
/// study. Series UID → image ids in slice order. Slices load one at a
/// time as the doctor pages; the volume is never loaded whole.
Map<String, List<String>> radStacks(RadStudy s) {
  final bySeries = <String, List<RadImageRef>>{};
  for (final i in s.images) {
    (bySeries[i.seriesUid] ??= []).add(i);
  }
  final out = <String, List<String>>{};
  for (final e in bySeries.entries) {
    final list = e.value;
    if (list.length < 2 || list.any((i) => i.frames > 1)) continue;
    final sliced = s.modality.isVolume ||
        list.every((i) => i.position != null) ||
        list.every((i) => i.dicomModality == 'CT');
    if (!sliced) continue;
    final sorted = [...list]..sort(_sliceOrder);
    out[e.key] = [for (final i in sorted) i.id];
  }
  return out;
}

/// Where a slice sits along the stack: its position projected on the
/// slice normal, else the slice location.
double? _along(RadImageRef i) {
  final p = i.position, o = i.orientation;
  if (p != null && p.length >= 3 && o != null && o.length >= 6) {
    final nx = o[1] * o[5] - o[2] * o[4];
    final ny = o[2] * o[3] - o[0] * o[5];
    final nz = o[0] * o[4] - o[1] * o[3];
    return p[0] * nx + p[1] * ny + p[2] * nz;
  }
  if (i.sliceLocation != null) return i.sliceLocation;
  if (p != null && p.length >= 3) return p[2];
  return null;
}

int _sliceOrder(RadImageRef a, RadImageRef b) {
  final x = _along(a), y = _along(b);
  if (x != null && y != null && x != y) return x.compareTo(y);
  return a.instanceNumber.compareTo(b.instanceNumber);
}

/// Loads one frame of one image of a study.
typedef RadPixelLoader = Future<RadPixels> Function(String studyId, String imageId, int frame);

/// Keeps the last few decoded images so switching panes, frames and
/// layouts doesn't decode the same file again.
class RadPixelCache {
  RadPixelCache(this._load, {this.capacity = 6});

  final RadPixelLoader _load;
  final int capacity;
  final _entries = <String, Future<RadPixels>>{};

  Future<RadPixels> get(String studyId, String imageId, int frame) {
    final key = '$studyId/$imageId#$frame';
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final f = _load(studyId, imageId, frame);
    _entries[key] = f;
    // A failed decode isn't kept: the next try reads the file again.
    unawaited(f.then<void>((_) {}, onError: (Object e) {
      if (identical(_entries[key], f)) _entries.remove(key);
    }));
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return f;
  }
}

/// One viewport's image and how it is shown: window, filters, zoom, pan,
/// rotation and flips, plus the rendered GPU image and what the pointer
/// is doing over it. Painters listen to it, so hover and drags repaint
/// only the pane.
class RadPane extends ChangeNotifier {
  RadPane({required this.studyId, required this.imageId, this.frame = 0});

  String studyId;

  /// Empty when the pane shows nothing yet.
  String imageId;
  int frame;

  /// The slices of the stack [imageId] belongs to (CBCT), in order;
  /// null for a single image.
  List<String>? stack;

  RadPixels? px;

  /// Values after sharpening / CLAHE (the raw values when no filter
  /// changes them). Measurements always use the raw values.
  Float32List? values;
  bool loading = false;
  String? error;

  // ── Display ──
  double center = 0;
  double width = 1;

  /// The doctor's invert toggle (MONOCHROME1 images start inverted).
  bool userInvert = false;
  RadFilterSettings filters = const RadFilterSettings();

  // ── View ──
  /// Zoom relative to "fit" (1 = the whole image fits the pane).
  double scale = 1;

  /// Offset of the image centre from the pane centre, in screen pixels.
  Offset pan = Offset.zero;
  int quarterTurns = 0;
  bool flipH = false;
  bool flipV = false;
  Size viewport = Size.zero;

  // ── Rendered ──
  ui.Image? image;
  ui.Image? placeholder;
  int nominalWidth = 0;
  int nominalHeight = 0;
  VoidCallback? _thumbListener;
  int _loadGen = 0;
  int _filterGen = 0;
  bool _rendering = false;
  int? _queuedStep;
  Timer? _fullTimer;
  bool _disposed = false;

  // ── Pointer ──
  /// Where the pointer is, in pane coordinates (null when outside).
  Offset? cursor;

  /// The annotation being drawn, and the rubber-band point after it.
  RadAnnotation? draft;
  Offset? draftHover;

  bool get hasImage => px != null && error == null;
  bool get invert => (px?.invert ?? false) != userInvert;
  bool get isColor => px?.isColor ?? false;
  int get frames => px?.frames ?? 1;

  /// Slices of the stack, else frames of the file.
  int get sliceCount => stack?.length ?? frames;
  int get sliceIndex {
    final st = stack;
    if (st == null) return frame;
    final i = st.indexOf(imageId);
    return i < 0 ? 0 : i;
  }

  RadDisplay get display => RadDisplay(
        center: center,
        width: width,
        invert: invert,
        gamma: filters.gamma,
        colormap: isColor ? 'gray' : filters.colormap,
      );

  void touch() {
    if (!_disposed) notifyListeners();
  }

  // ───────────────────────────── Loading ─────────────────────────────

  /// Shows [imageId] of [studyId]; [keepView] keeps the window and view
  /// (switching frames of one file). Supports progressive fuzzy preview via [placeholder]
  /// or [onThumbArrived].
  Future<void> show(
    String studyId,
    String imageId,
    RadPixelCache cache, {
    int frame = 0,
    bool keepView = false,
    String? unsupported,
    ui.Image? placeholder,
    int? nominalWidth,
    int? nominalHeight,
    VoidCallback Function(void Function(ui.Image thumb))? onThumbArrived,
  }) async {
    this.studyId = studyId;
    this.imageId = imageId;
    this.frame = frame;
    this.placeholder = placeholder;
    this.nominalWidth = nominalWidth ?? 0;
    this.nominalHeight = nominalHeight ?? 0;
    draft = null;
    draftHover = null;
    final gen = ++_loadGen;
    if (unsupported != null) {
      _setError(unsupported);
      return;
    }
    loading = true;
    error = null;

    _thumbListener?.call();
    _thumbListener = null;
    if (this.placeholder == null && onThumbArrived != null) {
      _thumbListener = onThumbArrived((thumb) {
        if (_disposed || gen != _loadGen || px != null || image != null) return;
        this.placeholder = thumb;
        touch();
      });
    }

    touch();
    try {
      final p = await cache.get(studyId, imageId, frame);
      if (gen != _loadGen || _disposed) return;
      _thumbListener?.call();
      _thumbListener = null;
      px = p;
      values = p.values;
      loading = false;
      if (!keepView) {
        final (c, w) = p.defaultWindow;
        center = c;
        width = w;
        userInvert = false;
        scale = 1;
        pan = Offset.zero;
        quarterTurns = 0;
        flipH = false;
        flipV = false;
      }
      if (filters.changesValues) {
        await _applyValueFilters();
      } else {
        requestRender(progressive: true);
      }
    } on RadUnsupportedImage catch (e) {
      _thumbListener?.call();
      _thumbListener = null;
      if (gen == _loadGen) _setError(e.reason);
    } catch (_) {
      _thumbListener?.call();
      _thumbListener = null;
      if (gen == _loadGen) _setError("This image couldn't be opened");
    }
  }

  void _setError(String message) {
    _thumbListener?.call();
    _thumbListener = null;
    loading = false;
    error = message;
    px = null;
    values = null;
    image?.dispose();
    image = null;
    placeholder = null;
    nominalWidth = 0;
    nominalHeight = 0;
    touch();
  }

  /// Empties the pane (the layout grew past the study's images).
  void clear() {
    _loadGen++;
    _thumbListener?.call();
    _thumbListener = null;
    imageId = '';
    stack = null;
    px = null;
    values = null;
    error = null;
    loading = false;
    image?.dispose();
    image = null;
    placeholder = null;
    nominalWidth = 0;
    nominalHeight = 0;
    touch();
  }

  // ───────────────────────────── Display ─────────────────────────────

  void setWindow(double c, double w, {bool interactive = false}) {
    center = c;
    width = math.max(w, 1e-3);
    requestRender(interactive: interactive);
  }

  void resetWindow() {
    final p = px;
    if (p == null) return;
    final (c, w) = p.defaultWindow;
    center = c;
    width = w;
    requestRender(progressive: true);
  }

  void toggleInvert() {
    userInvert = !userInvert;
    requestRender(progressive: true);
  }

  Future<void> setFilters(RadFilterSettings f) async {
    final valuesChanged = f.sharpen != filters.sharpen || f.clahe != filters.clahe;
    filters = f;
    if (px == null) {
      touch();
      return;
    }
    if (valuesChanged) {
      await _applyValueFilters();
    } else {
      requestRender(progressive: true);
    }
  }

  Future<void> _applyValueFilters() async {
    final p = px;
    if (p == null) return;
    final gen = ++_filterGen;
    if (!filters.changesValues) {
      values = p.values;
      requestRender(progressive: true);
      return;
    }
    final out = await applyValueFilters(p, filters);
    if (gen != _filterGen || _disposed || !identical(p, px)) return;
    values = out;
    requestRender(progressive: true);
  }

  // ───────────────────────────── Rendering ─────────────────────────────

  /// Re-renders the image.
  /// - [interactive]: renders a quick reduced-resolution preview now, full image once drag pauses.
  /// - [progressive]: fuzzy loading - renders a fast preview immediately and schedules full-res on next tick.
  void requestRender({bool interactive = false, bool progressive = false}) {
    final p = px;
    if (p == null || _disposed) return;
    _fullTimer?.cancel();
    if (interactive) {
      _render(radPreviewStep(p.width, p.height));
      _fullTimer = Timer(const Duration(milliseconds: 160), () => _render(1));
    } else if (progressive) {
      final step = radPreviewStep(p.width, p.height);
      if (step > 1) {
        _render(step);
        _fullTimer = Timer(Duration.zero, () => _render(1));
      } else {
        _render(1);
      }
    } else {
      _render(1);
    }
  }

  Future<void> _render(int step) async {
    if (_rendering) {
      _queuedStep = _queuedStep == null ? step : math.min(_queuedStep!, step);
      return;
    }
    final p = px, v = values;
    if (p == null || v == null) return;
    _rendering = true;
    try {
      final rgba = renderDisplay(p, v, display, step: step);
      final img = await radImageFromRgba(rgba);
      if (_disposed || !identical(p, px)) {
        img.dispose();
        return;
      }
      image?.dispose();
      image = img;
      placeholder = null;
      notifyListeners();
    } finally {
      _rendering = false;
      final q = _queuedStep;
      _queuedStep = null;
      if (q != null && !_disposed) unawaited(_render(q));
    }
  }

  /// A full-resolution render of the current display (for exports). The
  /// caller disposes it.
  Future<ui.Image?> renderFull() async {
    final p = px, v = values;
    if (p == null || v == null) return null;
    return radImageFromRgba(renderDisplay(p, v, display));
  }

  // ───────────────────────────── Geometry ─────────────────────────────

  /// Image size after rotation.
  Size get _turnedSize {
    final p = px;
    if (p == null) {
      final w = nominalWidth > 0 ? nominalWidth : (placeholder?.width ?? 0);
      final h = nominalHeight > 0 ? nominalHeight : (placeholder?.height ?? 0);
      if (w <= 0 || h <= 0) return Size.zero;
      return quarterTurns.isOdd
          ? Size(h.toDouble(), w.toDouble())
          : Size(w.toDouble(), h.toDouble());
    }
    return quarterTurns.isOdd
        ? Size(p.height.toDouble(), p.width.toDouble())
        : Size(p.width.toDouble(), p.height.toDouble());
  }

  /// Screen pixels per image pixel at "fit".
  double fitZoomFor(Size box) {
    final s = _turnedSize;
    if (s.isEmpty || box.isEmpty) return 1;
    return math.min(box.width / s.width, box.height / s.height) * 0.96;
  }

  double get zoom => fitZoomFor(viewport) * scale;

  Offset get _origin => viewport.center(Offset.zero) + pan;

  /// Image pixel → pane coordinates.
  Offset toScreen(double x, double y) {
    final p = px;
    if (p == null) return Offset.zero;
    var dx = x - p.width / 2, dy = y - p.height / 2;
    if (flipH) dx = -dx;
    if (flipV) dy = -dy;
    for (var i = 0; i < quarterTurns % 4; i++) {
      final t = dx;
      dx = -dy;
      dy = t;
    }
    return _origin + Offset(dx, dy) * zoom;
  }

  Offset pointToScreen(RadPoint p) => toScreen(p.x, p.y);

  /// Pane coordinates → image pixel.
  Offset toImage(Offset s) {
    final p = px;
    if (p == null) return Offset.zero;
    final z = zoom == 0 ? 1 : zoom;
    var dx = (s.dx - _origin.dx) / z, dy = (s.dy - _origin.dy) / z;
    for (var i = 0; i < quarterTurns % 4; i++) {
      final t = dx;
      dx = dy;
      dy = -t;
    }
    if (flipH) dx = -dx;
    if (flipV) dy = -dy;
    return Offset(dx + p.width / 2, dy + p.height / 2);
  }

  /// Applies the image → pane transform to [canvas].
  void applyTransform(Canvas canvas) {
    final w = (px?.width ?? (nominalWidth > 0 ? nominalWidth : placeholder?.width))?.toDouble();
    final h = (px?.height ?? (nominalHeight > 0 ? nominalHeight : placeholder?.height))?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return;
    final o = _origin;
    canvas
      ..translate(o.dx, o.dy)
      ..scale(zoom)
      ..rotate(quarterTurns % 4 * math.pi / 2)
      ..scale(flipH ? -1 : 1, flipV ? -1 : 1)
      ..translate(-w / 2, -h / 2);
  }

  /// Zooms by [factor] keeping the image point under [focal] still.
  void zoomAt(Offset focal, double factor) {
    if (px == null) return;
    final before = toImage(focal);
    scale = (scale * factor).clamp(0.1, 60.0);
    final after = toScreen(before.dx, before.dy);
    pan += focal - after;
    touch();
  }

  void fit() {
    scale = 1;
    pan = Offset.zero;
    touch();
  }

  void rotate() {
    quarterTurns = (quarterTurns + 1) % 4;
    touch();
  }

  void flip({bool horizontal = true}) {
    if (horizontal) {
      flipH = !flipH;
    } else {
      flipV = !flipV;
    }
    touch();
  }

  /// Back to how the image opened.
  void resetView() {
    scale = 1;
    pan = Offset.zero;
    quarterTurns = 0;
    flipH = false;
    flipV = false;
    userInvert = false;
    final p = px;
    if (p != null) {
      final (c, w) = p.defaultWindow;
      center = c;
      width = w;
    }
    requestRender();
    touch();
  }

  /// The raw value under a pane point, with the image coordinates.
  ({int x, int y, double value, Uint8List? rgb})? probe(Offset s) {
    final p = px;
    if (p == null) return null;
    final i = toImage(s);
    final x = i.dx.floor(), y = i.dy.floor();
    if (x < 0 || y < 0 || x >= p.width || y >= p.height) return null;
    final rgba = p.rgba;
    return (
      x: x,
      y: y,
      value: p.valueAt(x, y),
      rgb: rgba == null ? null : Uint8List.sublistView(rgba, (y * p.width + x) * 4, (y * p.width + x) * 4 + 3),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _thumbListener?.call();
    _thumbListener = null;
    _fullTimer?.cancel();
    image?.dispose();
    image = null;
    placeholder = null;
    super.dispose();
  }
}
