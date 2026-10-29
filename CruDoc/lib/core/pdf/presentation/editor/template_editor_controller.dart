import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';

enum DocHandle { tl, tr, bl, br }

class TemplateEditorController extends ChangeNotifier {
  TemplateEditorController(DocTemplate initial)
    : _t = initial,
      _savedJson = jsonEncode(initial.toMap()),
      loadedUpdatedAt = initial.updatedAt,
      _base = {for (final b in initial.blocks) b.id: b};

  DocTemplate _t;

  /// Each block as it was when the editor opened (or when it was added):
  /// the 100 % for the size slider and what "Reset" puts back.
  final Map<String, DocBlock> _base;

  DocBlock baseOf(DocBlock b) => _base[b.id] ?? b;
  String _savedJson;
  final int loadedUpdatedAt;

  DocTemplate get template => _t;
  bool get dirty => jsonEncode(_t.toMap()) != _savedJson;

  void markSaved(DocTemplate saved) {
    _t = saved;
    _savedJson = jsonEncode(saved.toMap());
    notifyListeners();
  }

  String? selectedId;
  DocBlock? get selected =>
      _t.blocks.where((b) => b.id == selectedId).firstOrNull;

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  bool snap = true;
  DocKind previewKind = DocKind.invoice;

  /// Guide lines to draw while dragging (mm inside [guideZone]).
  List<double> guideX = const [];
  List<double> guideY = const [];
  DocZone? guideZone;

  final _undo = <DocTemplate>[];
  final _redo = <DocTemplate>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Call once before a change (first move of a drag, a property edit).
  void checkpoint() {
    _undo.add(_t);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_t);
    _t = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_t);
    _t = _redo.removeLast();
    notifyListeners();
  }

  /// Any whole-template edit (paper, style, options, body order).
  void update(DocTemplate Function(DocTemplate t) change) {
    checkpoint();
    _t = change(_t);
    notifyListeners();
  }

  /// Any single-block property edit.
  void updateBlock(String id, DocBlock Function(DocBlock b) change) {
    checkpoint();
    final idx = _t.blocks.indexWhere((b) => b.id == id);
    if (idx != -1) {
      _replace(change(_t.blocks[idx]));
    }
  }

  void _replace(DocBlock b) {
    _t = _t.copyWith(blocks: [for (final x in _t.blocks) x.id == b.id ? b : x]);
    notifyListeners();
  }

  static double r1(double v) => (v * 10).roundToDouble() / 10;
  static double _c(double v, double lo, double hi) =>
      v < lo ? lo : (v > math.max(lo, hi) ? math.max(lo, hi) : v);

  /// Where a block of width [w] may start so it stays on the page both
  /// with a logo and without one (when it slides by its no-logo shift).
  (double, double) _xRange(DocBlock b, double w) {
    final zw = _t.paper.contentWidthMm;
    final dx = b.noLogoDx;
    return (math.max(0, -dx), math.min(zw - w, zw - w - dx));
  }

  (double, double) _yRange(DocBlock b, double h) {
    final zh = _t.zoneHeight(b.zone);
    final dy = b.noLogoDy;
    return (math.max(0, -dy), math.min(zh - h, zh - h - dy));
  }

  /// Drag: [orig] is the block as it was when the drag started.
  void moveTo(DocBlock orig, double dxMm, double dyMm) {
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(orig.zone);
    var x = orig.x + dxMm;
    var y = orig.y + dyMm;
    final gx = <double>[];
    final gy = <double>[];
    if (snap) {
      final sx = _snap(x, orig.w, _targets(orig, zw, horizontal: true));
      x = sx.$1;
      if (sx.$2 != null) gx.add(sx.$2!);
      final sy = _snap(y, orig.h, _targets(orig, zh, horizontal: false));
      y = sy.$1;
      if (sy.$2 != null) gy.add(sy.$2!);
    }
    guideX = gx;
    guideY = gy;
    guideZone = orig.zone;
    final (xLo, xHi) = _xRange(orig, orig.w);
    final (yLo, yHi) = _yRange(orig, orig.h);
    _replace(orig.copyWith(x: r1(_c(x, xLo, xHi)), y: r1(_c(y, yLo, yHi))));
  }

  List<double> _targets(
    DocBlock self,
    double size, {
    required bool horizontal,
  }) => [
    0,
    size / 2,
    size,
    for (final b in _t.blocks)
      if (b.id != self.id && b.zone == self.zone && !b.hidden)
        ...(horizontal
            ? [b.x, b.x + b.w / 2, b.x + b.w]
            : [b.y, b.y + b.h / 2, b.y + b.h]),
  ];

  /// Snaps the block's start, centre or end to the nearest target within
  /// 1.5 mm (returns the guide), else to a 0.5 mm grid.
  (double, double?) _snap(double start, double size, List<double> targets) {
    double? guide;
    var best = 1.5;
    var snapped = start;
    for (final t in targets) {
      for (final off in [0.0, size / 2, size]) {
        final d = (start + off - t).abs();
        if (d < best) {
          best = d;
          guide = t;
          snapped = t - off;
        }
      }
    }
    if (guide != null) return (snapped, guide);
    return ((start * 2).roundToDouble() / 2, null);
  }

  /// Corner drag. Images keep their shape (aspect ratio).
  void resize(DocBlock o, DocHandle h, double dx, double dy) {
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(o.zone);
    const minW = 4.0;
    final minH = o.type == DocBlockType.line ? 0.5 : 3.0;
    var left = o.x, top = o.y, right = o.x + o.w, bottom = o.y + o.h;
    final leftSide = h == DocHandle.tl || h == DocHandle.bl;
    final topSide = h == DocHandle.tl || h == DocHandle.tr;

    if (leftSide) {
      left = _c(left + dx, 0, right - minW);
    } else {
      right = _c(right + dx, left + minW, zw);
    }

    if (topSide) {
      top = _c(top + dy, 0, bottom - minH);
    } else {
      bottom = _c(bottom + dy, top + minH, zh);
    }

    var w = right - left;
    var hh = bottom - top;
    if (o.type == DocBlockType.image && o.w > 0 && o.h > 0) {
      final ratio = o.h / o.w;
      hh = w * ratio;
      final room = topSide ? bottom : zh - top;
      if (hh > room) {
        hh = room;
        w = hh / ratio;
      }
      if (leftSide) left = right - w;
      if (topSide) top = bottom - hh;
    }
    _replace(o.copyWith(x: r1(left), y: r1(top), w: r1(w), h: r1(hh)));
  }

  void endDrag() {
    guideX = const [];
    guideY = const [];
    guideZone = null;
    notifyListeners();
  }

  /// Header/footer height. The body keeps at least 40 mm. Blocks that no
  /// longer fit are pulled up / shrunk (not when the zone is closed to 0).
  void setZoneHeight(DocZone z, double mm) {
    final other = z == DocZone.header ? _t.footerMm : _t.headerMm;
    final v = r1(_c(mm, 0, _t.paper.contentHeightMm - other - 40));
    final zw = _t.paper.contentWidthMm;
    DocBlock fit(DocBlock b) {
      if (b.zone != z || v == 0) return b;
      final h = math.min(b.h, v);
      final w = math.min(b.w, zw);
      return b.copyWith(
        w: w,
        h: h,
        x: _c(b.x, 0, zw - w),
        y: _c(b.y, 0, v - h),
      );
    }

    final blocks = [for (final b in _t.blocks) fit(b)];
    _t = z == DocZone.header
        ? _t.copyWith(headerMm: v, blocks: blocks)
        : _t.copyWith(footerMm: v, blocks: blocks);
    notifyListeners();
  }

  /// New paper size: everything scales with the content width.
  void setPaper(DocPaper p) {
    checkpoint();
    final f = p.contentWidthMm / _t.paper.contentWidthMm;
    DocBlock s(DocBlock b) => b.copyWith(
      x: r1(b.x * f),
      y: r1(b.y * f),
      w: r1(b.w * f),
      h: r1(b.h * f),
      fontPt: _c(b.fontPt * f, 5, 40),
    );
    _t = _t.copyWith(
      paper: p,
      headerMm: r1(_t.headerMm * f),
      footerMm: r1(_t.footerMm * f),
      blocks: [for (final b in _t.blocks) s(b)],
    );
    setZoneHeight(DocZone.header, _t.headerMm);
    setZoneHeight(DocZone.footer, _t.footerMm);
  }

  /// Arrow keys / nudge pad. No snapping, or a block sitting on a guide
  /// would snap straight back and never move.
  void nudge(double dxMm, double dyMm) {
    final b = selected;
    if (b == null || b.locked) return;
    checkpoint();
    final wasSnapping = snap;
    snap = false;
    moveTo(b, dxMm, dyMm);
    snap = wasSnapping;
    endDrag();
  }

  // ---------------------------------------------------------------------------
  // Size and transparency sliders. A slide is one undo step: call
  // [beginLive] when it starts, then the live setters as it moves.

  void beginLive() => checkpoint();

  void endLive() => notifyListeners();

  /// A block change while typing or sliding (no undo step of its own).
  void updateBlockLive(String id, DocBlock Function(DocBlock b) change) {
    final idx = _t.blocks.indexWhere((b) => b.id == id);
    if (idx != -1) _replace(change(_t.blocks[idx]));
  }

  /// A whole-template change during a slide (no undo step of its own).
  void updateLive(DocTemplate Function(DocTemplate t) change) {
    _t = change(_t);
    notifyListeners();
  }

  /// Size against the block's starting size (1.0 = 100 %).
  double scaleOf(DocBlock b) {
    final o = baseOf(b);
    if (o.type == DocBlockType.line) return o.w > 0 ? b.w / o.w : 1;
    if (o.w > 0) return b.w / o.w;
    return 1;
  }

  /// The largest size that still fits in the block's zone.
  double maxScaleOf(DocBlock b) {
    final o = baseOf(b);
    final zw = _t.paper.contentWidthMm - b.noLogoDx.abs();
    final zh = _t.zoneHeight(b.zone) - b.noLogoDy.abs();
    var m = o.w > 0 ? zw / o.w : 2.0;
    if (o.type != DocBlockType.line && o.h > 0) m = math.min(m, zh / o.h);
    return m;
  }

  /// Grows or shrinks the block around its centre: box, text size and
  /// line length together, so it keeps its shape.
  void setScaleLive(String id, double k) {
    final b = _t.blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.locked) return;
    final o = baseOf(b);
    final kk = _c(k, 0.3, math.max(0.3, maxScaleOf(b)));
    final w = r1(o.w * kk);
    final h = o.type == DocBlockType.line ? b.h : r1(o.h * kk);
    final cx = b.x + b.w / 2;
    final cy = b.y + b.h / 2;
    final (xLo, xHi) = _xRange(b, w);
    final (yLo, yHi) = _yRange(b, h);
    _replace(
      b.copyWith(
        w: w,
        h: h,
        x: r1(_c(cx - w / 2, xLo, xHi)),
        y: r1(_c(cy - h / 2, yLo, yHi)),
        fontPt: r1(_c(o.fontPt * kk, 5, 40)),
      ),
    );
  }

  /// 0 = solid, 0.8 = mostly see-through (never invisible: hide it instead).
  void setTransparencyLive(String id, double transparency) {
    final b = _t.blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.locked) return;
    final t = _c(transparency, 0, 0.8);
    _replace(b.copyWith(opacity: ((1 - t) * 100).roundToDouble() / 100));
  }

  /// Puts one block back where and how it was when the editor opened.
  void resetBlock(String id) {
    final b = _t.blocks.where((x) => x.id == id).firstOrNull;
    final o = _base[id];
    if (b == null || o == null) return;
    checkpoint();
    _replace(o.copyWith(hidden: b.hidden, locked: b.locked));
  }

  bool isChanged(DocBlock b) {
    final o = _base[b.id];
    if (o == null) return true;
    return o.x != b.x ||
        o.y != b.y ||
        o.w != b.w ||
        o.h != b.h ||
        o.fontPt != b.fontPt ||
        o.opacity != b.opacity;
  }

  /// The whole layout back to [preset] (header, footer and every block),
  /// scaled to this template's paper. One undo step.
  void resetLayout(DocTemplate preset) {
    checkpoint();
    final f = _t.paper.contentWidthMm / preset.paper.contentWidthMm;
    DocBlock s(DocBlock b) => f == 1
        ? b
        : b.copyWith(
            x: r1(b.x * f),
            y: r1(b.y * f),
            w: r1(b.w * f),
            h: r1(b.h * f),
            fontPt: _c(b.fontPt * f, 5, 40),
          );
    _t = _t.copyWith(
      headerMm: r1(preset.headerMm * f),
      footerMm: r1(preset.footerMm * f),
      blocks: [for (final b in preset.blocks) s(b)],
    );
    for (final b in _t.blocks) {
      _base[b.id] = b;
    }
    selectedId = null;
    notifyListeners();
  }

  /// Adds [b] centred in the header (footer if the header is closed).
  /// Returns false when both zones are closed or blocks reach max 80.
  bool add(DocBlock b) {
    if (_t.blocks.length >= 80) return false;
    final zone = _t.headerMm > 0
        ? DocZone.header
        : (_t.footerMm > 0 ? DocZone.footer : null);
    if (zone == null) return false;

    checkpoint();
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(zone);
    final id = b.id.isNotEmpty
        ? b.id
        : 'b${DateTime.now().microsecondsSinceEpoch}';
    final placed = b.copyWith(
      id: id,
      zone: zone,
      x: r1(_c((zw - b.w) / 2, 0, zw - b.w)),
      y: r1(_c((zh - b.h) / 2, 0, zh - b.h)),
    );
    _t = _t.copyWith(blocks: [..._t.blocks, placed]);
    _base[placed.id] = placed;
    selectedId = placed.id;
    notifyListeners();
    return true;
  }

  void duplicateSelected() {
    final b = selected;
    if (b == null || _t.blocks.length >= 80) return;
    checkpoint();
    final zw = _t.paper.contentWidthMm;
    final zh = _t.zoneHeight(b.zone);
    final newId = 'b${DateTime.now().microsecondsSinceEpoch}';
    final copy = b.copyWith(
      id: newId,
      x: r1(_c(b.x + 3.0, 0, zw - b.w)),
      y: r1(_c(b.y + 3.0, 0, zh - b.h)),
    );
    _t = _t.copyWith(blocks: [..._t.blocks, copy]);
    _base[copy.id] = copy;
    selectedId = copy.id;
    notifyListeners();
  }

  /// Ready-made blocks are hidden; custom text/images/lines/boxes/QR are removed.
  void deleteSelected() {
    final b = selected;
    if (b == null) return;
    checkpoint();
    if (b.id.startsWith('builtin.') || _t.isBuiltin) {
      _replace(b.copyWith(hidden: true));
    } else {
      _t = _t.copyWith(
        blocks: [
          for (final x in _t.blocks)
            if (x.id != b.id) x,
        ],
      );
    }
    selectedId = null;
    notifyListeners();
  }
}
