import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/ai/rad_ai.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/features/radiology/viewer/side_panel.dart';
import 'package:doctor_management_app/features/radiology/viewer/thumbnail_strip.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_dialogs.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_export.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_prefs.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_shortcuts_dialog.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_toolbar.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewport.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_screen.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/subtraction/subtraction_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _ExportKind { pngMarks, png, jpgMarks, jpg, area, dicom }

/// Annotations and calibration at one moment (an undo step).
class _Snapshot {
  const _Snapshot(this.annos, this.cal);
  final Map<String, List<RadAnnotation>> annos;
  final Map<String, double> cal;
}

const _toolGroups = [
  [RadTool.select, RadTool.pan, RadTool.zoom, RadTool.window],
  [RadTool.length, RadTool.angle, RadTool.polygon, RadTool.ellipse, RadTool.rect, RadTool.polyline],
  [RadTool.arrow, RadTool.text, RadTool.freehand, RadTool.tooth],
  [RadTool.calibrate],
];

/// The 2D reading page: thumbnails on the left, one to four dark image
/// panes, and a side panel with measurements, key images, image info,
/// adjustments and the AI second read. CBCT slice series page through as
/// one stack. Annotations save to the study as the doctor works.
class RadViewerScreen extends ConsumerStatefulWidget {
  const RadViewerScreen({super.key, required this.studyId, this.initialImageId});

  final String studyId;
  final String? initialImageId;

  @override
  ConsumerState<RadViewerScreen> createState() => _RadViewerScreenState();
}

class _RadViewerScreenState extends ConsumerState<RadViewerScreen>
    implements RadViewportHost, RadSidePanelHost {
  final _focus = FocusNode(debugLabel: 'Radiology viewer');
  late final RadiologyController _ctl;
  late final RadPixelCache _cache;
  late final RadThumbCache _thumbs;
  final _roi = RadRoiCache();
  final _headers = RadHeaderCache();

  RadStudy? _study;
  RadStudy? _compare;
  final _studies = <String, RadStudy>{};
  final _stackCache = <String, (RadStudy, Map<String, List<String>>)>{};
  bool _prefsLoaded = false;
  bool _started = false;
  String? _studyDir;

  // Working copy of the study's annotations and ruler calibration.
  Map<String, List<RadAnnotation>> _annos = {};
  Map<String, double> _cal = {};
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  Timer? _saveTimer;
  bool _dirty = false;

  RadViewerPrefs _prefs = const RadViewerPrefs();
  final _pendingPrefs = <String, dynamic>{};
  Timer? _prefsTimer;
  double _panelWidth = RadViewerPrefs.defaultPanelWidth;

  RadLayout _layout = RadLayout.one;
  final _panes = <RadPane>[];
  int _active = 0;
  RadTool _tool = RadTool.select;
  RadTool _toolBeforeCalibrate = RadTool.select;
  bool _link = false;
  bool _loupe = false;
  LogicalKeyboardKey? _loupeKey;
  DateTime? _loupeDownAt;
  bool _reading = false;
  RadPanelTab _tab = RadPanelTab.measure;
  String? _selectedId;
  bool _busy = false;

  RadPane get _pane => _panes[_active.clamp(0, _panes.length - 1)];

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(radiologyProvider);
    _cache = RadPixelCache(_loadPixels, capacity: 12);
    _thumbs = RadThumbCache(_ctl.fileOf);
    _loadPrefs();
    _ctl.studyDir(widget.studyId).then((d) {
      if (mounted) setState(() => _studyDir = d.path);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final s = _study;
    if (_dirty && s != null) {
      unawaited(_ctl.saveStudy(s.copyWith(annotations: _copyAnnos(), calibration: {..._cal})));
    }
    _flushPrefs();
    for (final p in _panes) {
      p.dispose();
    }
    _thumbs.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    RadSettings? settings;
    try {
      settings = await ref.read(radSettingsProvider.future);
    } catch (_) {
      // Defaults are fine when settings can't be read.
    }
    if (!mounted) return;
    setState(() {
      _prefs = RadViewerPrefs.from(settings?.viewer ?? const {});
      _panelWidth = _prefs.panelWidth;
      _prefsLoaded = true;
    });
  }

  Future<RadPixels> _loadPixels(String studyId, String imageId, int frame) async {
    final s = _studies[studyId];
    final i = s?.images.where((x) => x.id == imageId).firstOrNull;
    if (s == null || i == null) throw StateError('Image not found');
    return loadRadPixels(await _ctl.fileOf(s, i.path), i.kind, frame: frame);
  }

  /// Takes the provider's copy unless ours is newer (just saved).
  void _accept(RadStudy fresh) {
    final cur = _study;
    if (cur == null || fresh.updatedAt.millisecondsSinceEpoch >= cur.updatedAt.millisecondsSinceEpoch) {
      _study = fresh;
      _studies[fresh.id] = fresh;
    }
  }

  // ───────────────────────────── Images and stacks ─────────────────────────────

  Map<String, List<String>> _stacksOf(RadStudy s) {
    final hit = _stackCache[s.id];
    if (hit != null && identical(hit.$1, s)) return hit.$2;
    final m = radStacks(s);
    _stackCache[s.id] = (s, m);
    return m;
  }

  List<String>? _stackFor(String studyId, String imageId) {
    final s = _studies[studyId];
    if (s == null) return null;
    for (final st in _stacksOf(s).values) {
      if (st.contains(imageId)) return st;
    }
    return null;
  }

  /// What paging through images steps over, in thumbnail order: every
  /// image, with a slice stack counted once (by its middle slice).
  List<String> _slots(RadStudy s) {
    final stacks = _stacksOf(s);
    final bySeries = <String, List<RadImageRef>>{};
    for (final i in s.images) {
      (bySeries[i.seriesUid] ??= []).add(i);
    }
    final out = <String>[];
    for (final e in bySeries.entries) {
      final st = stacks[e.key];
      if (st != null) {
        out.add(st[st.length ~/ 2]);
        continue;
      }
      final list = [...e.value]..sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));
      out.addAll(list.map((i) => i.id));
    }
    return out;
  }

  RadImageRef? _imageRef(RadPane p) =>
      _studies[p.studyId]?.images.where((i) => i.id == p.imageId).firstOrNull;

  bool _paneShows(RadPane p, String id) => p.imageId == id || (p.stack?.contains(id) ?? false);

  /// Opens an image in [p] (a slice of a stack brings the whole stack).
  void _show(RadPane p, String studyId, String imageId, {bool keepView = false}) {
    final s = _studies[studyId];
    final img = s?.images.where((i) => i.id == imageId).firstOrNull;
    if (s == null || img == null) {
      p.clear();
      return;
    }
    if (_panes.isNotEmpty && identical(p, _pane) && p.imageId != imageId) _selectedId = null;
    p.stack = _stackFor(studyId, imageId);
    final unsupported = img.compressed
        ? '${img.transferSyntax.isEmpty ? 'Compressed' : DicomSyntax.name(img.transferSyntax)} '
            'DICOM images are not supported yet'
        : null;
    p
        .show(studyId, imageId, _cache, keepView: keepView, unsupported: unsupported)
        .then((_) {
      if (!mounted || !_link || keepView || _panes.isEmpty || identical(p, _pane)) return;
      p.scale = _pane.scale;
      p.pan = _pane.pan;
      p.touch();
    });
  }

  void _start(RadStudy s) {
    _started = true;
    _annos = {for (final e in s.annotations.entries) e.key: [...e.value]};
    _cal = {...s.calibration};
    final st = _prefs.stateFor(s.modality);
    _layout = RadLayout.fromName(st['layout']);
    final tool = RadTool.fromName(st['tool']);
    _tool = tool == RadTool.calibrate ? RadTool.select : tool;
    _link = st['link'] == true;
    _tab = RadPanelTab.fromName(st['tab']);
    final f = st['filters'];
    final filters =
        f is Map ? RadFilterSettings.fromJson(Map<String, dynamic>.from(f)) : const RadFilterSettings();

    final slots = _slots(s);
    final initial = widget.initialImageId;
    final first = initial != null && s.images.any((i) => i.id == initial)
        ? initial
        : slots.where((id) => !(s.images.firstWhere((i) => i.id == id).compressed)).firstOrNull ??
            slots.firstOrNull ??
            '';
    final firstStack = first.isEmpty ? null : _stackFor(s.id, first);
    final order = [
      first,
      ...slots.where((id) => id != first && !(firstStack?.contains(id) ?? false)),
    ];
    for (var i = 0; i < _layout.panes; i++) {
      final p = RadPane(studyId: s.id, imageId: '')..filters = filters;
      _panes.add(p);
      if (i < order.length && order[i].isNotEmpty) _show(p, s.id, order[i]);
    }
  }

  // ───────────────────────────── Layout and compare ─────────────────────────────

  void _setLayout(RadLayout l) {
    final s = _study;
    if (s == null || l == _layout) return;
    setState(() {
      while (_panes.length > l.panes) {
        final p = _panes.removeLast();
        // Its viewport leaves the tree this frame; dispose after it.
        WidgetsBinding.instance.addPostFrameCallback((_) => p.dispose());
      }
      while (_panes.length < l.panes) {
        final next = _slots(s)
                .where((id) => !_panes.any((p) => p.studyId == s.id && _paneShows(p, id)))
                .firstOrNull ??
            '';
        final p = RadPane(studyId: s.id, imageId: '')..filters = _pane.filters;
        _panes.add(p);
        if (next.isNotEmpty) _show(p, s.id, next);
      }
      _layout = l;
      _active = _active.clamp(0, _panes.length - 1);
    });
    _rememberState();
  }

  static bool _samePatient(RadStudy a, RadStudy b) =>
      (a.patientId.isNotEmpty && a.patientId == b.patientId) ||
      (a.patientExternalId.isNotEmpty && a.patientExternalId == b.patientExternalId);

  void _setCompare(RadStudy? other) {
    final s = _study;
    if (s == null) return;
    final old = _compare;
    if (other == null) {
      setState(() {
        _compare = null;
        for (final p in _panes) {
          if (old == null || p.studyId != old.id) continue;
          final next = _slots(s)
              .where((id) => !_panes.any((q) => q.studyId == s.id && _paneShows(q, id)))
              .firstOrNull;
          if (next == null) {
            p.clear();
          } else {
            _show(p, s.id, next);
          }
        }
      });
      return;
    }
    _studies[other.id] = other;
    if (_layout.panes < 2) _setLayout(RadLayout.sideBySide);
    setState(() {
      _compare = other;
      final target = _panes[_active == 1 ? 0 : 1];
      final series = _imageRef(_pane)?.seriesDescription ?? '';
      final slots = _slots(other);
      String? pick;
      if (series.isNotEmpty) {
        pick = slots
            .where((id) => other.images.any((i) => i.id == id && i.seriesDescription == series))
            .firstOrNull;
      }
      pick ??= slots.where((id) => !other.images.firstWhere((i) => i.id == id).compressed).firstOrNull ??
          slots.firstOrNull;
      if (pick != null) _show(target, other.id, pick);
      _link = true;
    });
    _rememberState();
  }

  void _toggleLink() {
    setState(() => _link = !_link);
    if (_link) viewChanged(_pane);
    _rememberState();
  }

  // ───────────────────────────── Prefs ─────────────────────────────

  void _savePrefs(Map<String, dynamic> values) {
    _pendingPrefs.addAll(values);
    _prefsTimer?.cancel();
    _prefsTimer = Timer(const Duration(milliseconds: 800), _flushPrefs);
  }

  void _flushPrefs() {
    _prefsTimer?.cancel();
    if (_pendingPrefs.isEmpty) return;
    final values = Map<String, dynamic>.of(_pendingPrefs);
    _pendingPrefs.clear();
    unawaited(_ctl.saveViewerPrefs(values));
  }

  /// Remembers layout, tool, link, tab and filters for this study type.
  void _rememberState() {
    final s = _study;
    if (s == null || !_started || _panes.isEmpty) return;
    final state = <String, dynamic>{
      'layout': _layout.name,
      'tool': (_tool == RadTool.calibrate ? _toolBeforeCalibrate : _tool).name,
      'link': _link,
      'tab': _tab.name,
      'filters': _pane.filters.toJson(),
    };
    _prefs = _prefs.copyWith(states: {..._prefs.states, s.modality.name: state});
    _savePrefs({RadViewerPrefs.stateKey(s.modality): state});
  }

  void _setTool(RadTool t) {
    if (t == RadTool.calibrate && _tool != RadTool.calibrate) _toolBeforeCalibrate = _tool;
    for (final p in _panes) {
      if (p.draft != null) {
        p.draft = null;
        p.draftHover = null;
        p.touch();
      }
    }
    setState(() => _tool = t);
    _rememberState();
  }

  void _setTab(RadPanelTab t) {
    setState(() => _tab = t);
    _rememberState();
  }

  void _togglePanel() {
    _prefs = _prefs.copyWith(panelOpen: !_prefs.panelOpen);
    setState(() {});
    _savePrefs({RadViewerPrefs.panelOpenKey: _prefs.panelOpen});
  }

  void _toggleThumbs() {
    _prefs = _prefs.copyWith(thumbs: !_prefs.thumbs);
    setState(() {});
    _savePrefs({RadViewerPrefs.thumbsKey: _prefs.thumbs});
  }

  Future<void> _openShortcuts() => showRadShortcuts(
        context,
        prefs: _prefs,
        onChanged: (next, save) {
          setState(() => _prefs = next);
          _savePrefs(save);
        },
      );

  // ───────────────────────────── Saving ─────────────────────────────

  Map<String, List<RadAnnotation>> _copyAnnos() => {
        for (final e in _annos.entries)
          if (e.value.isNotEmpty) e.key: [...e.value],
      };

  void _snapshot() {
    _undo.add(_Snapshot(_copyAnnos(), {..._cal}));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  /// One undoable change to annotations or calibration, saved shortly.
  void _mutate(VoidCallback change) {
    _snapshot();
    setState(change);
    _scheduleSave();
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _flush);
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    await _saveStudy((s) => s);
  }

  /// Saves the study with [change] applied and the working annotations.
  Future<void> _saveStudy(
    RadStudy Function(RadStudy s) change, {
    String? audit,
    String detail = '',
  }) async {
    final base = _study;
    if (base == null) return;
    _saveTimer?.cancel();
    _dirty = false;
    final next = change(base).copyWith(annotations: _copyAnnos(), calibration: {..._cal});
    _study = next;
    _studies[next.id] = next;
    try {
      await _ctl.saveStudy(next, auditAction: audit, detail: detail);
    } catch (_) {
      _dirty = true;
      if (mounted) radToast(context, "Couldn't save the changes. They'll be saved again shortly.");
      _scheduleSave();
    }
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_copyAnnos(), {..._cal}));
    final s = _undo.removeLast();
    setState(() {
      _annos = s.annos;
      _cal = s.cal;
      _selectedId = null;
    });
    _scheduleSave();
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_copyAnnos(), {..._cal}));
    final s = _redo.removeLast();
    setState(() {
      _annos = s.annos;
      _cal = s.cal;
      _selectedId = null;
    });
    _scheduleSave();
  }

  String? _imageOf(String annotationId) {
    for (final e in _annos.entries) {
      if (e.value.any((a) => a.id == annotationId)) return e.key;
    }
    return null;
  }

  void _update(String id, RadAnnotation Function(RadAnnotation a) change) {
    final image = _imageOf(id);
    if (image == null) return;
    _mutate(() {
      _annos[image] = [for (final a in _annos[image]!) a.id == id ? change(a) : a];
    });
  }

  List<RadAnnotation> _annotationsFor(RadPane p) {
    if (p.studyId == _study?.id) return _annos[p.imageId] ?? const [];
    return _studies[p.studyId]?.annotations[p.imageId] ?? const [];
  }

  List<RadAiFinding> _aiFindingsFor(RadPane p) {
    final s = _studies[p.studyId] ?? (_study?.id == p.studyId ? _study : null);
    if (s == null || p.imageId.isEmpty) return const [];
    for (final read in s.aiReads.reversed) {
      if (read['imageId'] == p.imageId) {
        final list = (read['findings'] as List?) ?? const [];
        return list
            .map((f) => RadAiFinding.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList();
      }
    }
    return const [];
  }

  double? _mmPerPxFor(RadPane p) {
    final s = _studies[p.studyId];
    if (s == null) return null;
    if (p.studyId == _study?.id) {
      return _cal[p.imageId] ?? s.images.where((i) => i.id == p.imageId).firstOrNull?.pixelSpacingMm;
    }
    return RadMeasure.mmPerPx(s, p.imageId);
  }

  // ───────────────────────────── Viewport host ─────────────────────────────

  @override
  RadViewerPrefs get prefs => _prefs;

  @override
  RadRoiCache get roi => _roi;

  @override
  void activatePane(RadPane pane) {
    final i = _panes.indexOf(pane);
    if (i >= 0 && i != _active) {
      setState(() {
        _active = i;
        _selectedId = null;
      });
    }
    if (!_focus.hasPrimaryFocus) _focus.requestFocus();
  }

  @override
  void select(String? id) => setState(() => _selectedId = id);

  @override
  Future<void> commitDraft(RadPane pane, RadAnnotation draft, RadTool tool) async {
    final s = _study;
    if (s == null || pane.studyId != s.id || pane.imageId.isEmpty) return;
    final imageId = pane.imageId;
    var a = draft;
    if (tool == RadTool.calibrate) {
      if (a.points.length < 2) return;
      final pixels = (Offset(a.points[0].x, a.points[0].y) - Offset(a.points[1].x, a.points[1].y)).distance;
      if (pixels < 2) return;
      final mm = await askRadCalibration(context, pixels: pixels);
      if (mm == null || !mounted) return;
      _mutate(() => _cal[imageId] = mm / pixels);
      _setTool(_toolBeforeCalibrate);
      radToast(context, 'Calibrated: ${(mm / pixels).toStringAsFixed(4)} mm per pixel');
      return;
    }
    if (a.kind == RadAnnoKind.text) {
      final t = await askRadText(context, title: 'Add a note', label: 'Note', action: 'Add');
      if (t == null || !mounted) return;
      a = a.copyWith(text: t);
    } else if (a.kind == RadAnnoKind.toothLabel) {
      final t = await pickRadTooth(context);
      if (t == null || !mounted) return;
      a = a.copyWith(text: t);
    }
    _mutate(() {
      _annos[imageId] = [...?_annos[imageId], a];
      _selectedId = a.id;
    });
  }

  @override
  void beginEdit() => _snapshot();

  @override
  void updateAnnotation(RadPane pane, RadAnnotation a) {
    final list = _annos[pane.imageId];
    if (list == null) return;
    setState(() => _annos[pane.imageId] = [for (final x in list) x.id == a.id ? a : x]);
  }

  @override
  void endEdit() => _scheduleSave();

  @override
  void viewChanged(RadPane pane) {
    if (!_link) return;
    for (final p in _panes) {
      if (identical(p, pane) || !p.hasImage) continue;
      p.scale = pane.scale;
      p.pan = pane.pan;
      p.touch();
    }
  }

  @override
  void dropImage(RadPane pane, RadImageDrag drag) {
    setState(() => _show(pane, drag.studyId, drag.imageId));
    activatePane(pane);
  }

  @override
  void step(RadPane pane, int delta) {
    if (pane.sliceCount > 1) {
      setFrame(pane, (pane.sliceIndex + delta).clamp(0, pane.sliceCount - 1));
      return;
    }
    _stepImage(pane, delta);
  }

  @override
  void setFrame(RadPane pane, int index) {
    final st = pane.stack;
    if (st != null) {
      if (index < 0 || index >= st.length || st[index] == pane.imageId) return;
      setState(() => _show(pane, pane.studyId, st[index], keepView: true));
      return;
    }
    if (index == pane.frame || index < 0 || index >= pane.frames) return;
    pane.show(pane.studyId, pane.imageId, _cache, frame: index, keepView: true);
  }

  void _stepImage(RadPane pane, int delta) {
    final s = _studies[pane.studyId];
    if (s == null) return;
    final slots = _slots(s);
    final i = slots.indexWhere((id) => _paneShows(pane, id));
    final next = i + delta;
    if (next < 0 || next >= slots.length) return;
    setState(() => _show(pane, s.id, slots[next]));
  }

  // ───────────────────────────── Side panel host ─────────────────────────────

  @override
  void renameAnnotation(RadAnnotation a, String text) => _update(a.id, (x) => x.copyWith(text: text));

  @override
  void recolorAnnotation(RadAnnotation a, Color color) =>
      _update(a.id, (x) => x.copyWith(colorHex: RadInk.hex(color)));

  @override
  void deleteAnnotation(RadAnnotation a) {
    final image = _imageOf(a.id);
    if (image == null) return;
    _mutate(() {
      _annos[image] = [for (final x in _annos[image]!) if (x.id != a.id) x];
      if (_selectedId == a.id) _selectedId = null;
    });
  }

  @override
  Future<void> includeInReport(RadAnnotation a, bool include) async {
    final r = ref.read(radReportForStudyProvider(widget.studyId));
    if (r == null || r.isSigned) return;
    await _flush();
    final ids = [...r.measurementIds]..remove(a.id);
    if (include) ids.add(a.id);
    await _ctl.saveReport(r.copyWith(measurementIds: ids));
  }

  @override
  void startCalibration() {
    if (!_pane.hasImage || _pane.studyId != _study?.id) return;
    _setTool(RadTool.calibrate);
    radToast(context, 'Draw a line along something of known length');
  }

  @override
  void clearCalibration() => _mutate(() => _cal.remove(_pane.imageId));

  @override
  Future<void> markKeyImage() async {
    final s = _study;
    final p = _pane;
    if (s == null || !p.hasImage || _busy) return;
    if (p.studyId != s.id) {
      radToast(context, 'Key images come from the study being read');
      return;
    }
    setState(() => _busy = true);
    try {
      final k = await radWriteKeyImage(
        _ctl,
        s,
        p,
        annotations: _annotationsFor(p),
        mmPerPx: _mmPerPxFor(p),
        roi: _roi,
      );
      if (k == null || !mounted) return;
      await _saveStudy((st) => st.copyWith(keyImages: [...st.keyImages, k]), audit: 'Marked key image');
      if (mounted) radToast(context, 'Key image saved');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't save the key image");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void openKeyImage(RadKeyImage k) {
    final s = _study;
    if (s == null) return;
    setState(() => _show(_pane, s.id, k.imageId));
  }

  @override
  void captionKeyImage(RadKeyImage k, String caption) {
    _saveStudy((st) => st.copyWith(keyImages: [
          for (final x in st.keyImages)
            x.id == k.id
                ? RadKeyImage(
                    id: x.id,
                    imageId: x.imageId,
                    pngPath: x.pngPath,
                    caption: caption,
                    createdAt: x.createdAt,
                  )
                : x,
        ]));
  }

  @override
  Future<void> deleteKeyImage(RadKeyImage k) async {
    final s = _study;
    if (s == null) return;
    final ok = await confirmDental(
      context,
      title: 'Remove this key image?',
      body: 'It is also taken out of the report. You can mark the view again at any time.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await _saveStudy(
      (st) => st.copyWith(keyImages: [for (final x in st.keyImages) if (x.id != k.id) x]),
      audit: 'Removed key image',
    );
    try {
      final f = await _ctl.fileOf(s, k.pngPath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // The record is gone; a stray file does no harm.
    }
  }

  @override
  void applyPreset(RadWindowPreset? preset) {
    final p = _pane;
    final px = p.px;
    if (px == null) return;
    if (preset == null) {
      p.resetWindow();
    } else {
      final (c, w) = preset.resolve(px);
      p.setWindow(c, w);
    }
  }

  @override
  Future<void> saveCurrentPreset() async {
    final p = _pane;
    final px = p.px;
    if (px == null) return;
    final name = await askRadText(
      context,
      title: 'Save window preset',
      label: 'Name',
      hint: 'Periapical bone',
    );
    if (name == null || !mounted) return;
    final preset = RadWindowPreset.fromWindow(name, px, p.center, p.width);
    final list = [..._prefs.presets.where((x) => x.name != name), preset];
    setState(() => _prefs = _prefs.copyWith(presets: list));
    _savePrefs({RadViewerPrefs.presetsKey: [for (final x in list) x.toJson()]});
  }

  @override
  void deletePreset(RadWindowPreset preset) {
    final list = [..._prefs.presets.where((x) => x.name != preset.name)];
    setState(() => _prefs = _prefs.copyWith(presets: list));
    _savePrefs({RadViewerPrefs.presetsKey: [for (final x in list) x.toJson()]});
  }

  @override
  Future<void> setFilters(RadFilterSettings f) async {
    await _pane.setFilters(f);
    _pane.touch();
    _rememberState();
  }

  @override
  void toggleInvert() {
    _pane.toggleInvert();
    _pane.touch();
  }

  @override
  Future<void> resetAdjustments() async {
    final p = _pane;
    p.userInvert = false;
    await p.setFilters(const RadFilterSettings());
    p.resetWindow();
    p.touch();
    _rememberState();
  }

  // ───────────────────────────── Actions ─────────────────────────────

  void _run(RadViewerAction a) {
    final tool = a.tool;
    if (tool != null) {
      if (tool == RadTool.calibrate) {
        startCalibration();
      } else {
        _setTool(tool);
      }
      return;
    }
    final p = _pane;
    switch (a) {
      case RadViewerAction.magnifier:
        setState(() => _loupe = !_loupe);
      case RadViewerAction.fit:
        p.fit();
        viewChanged(p);
      case RadViewerAction.invert:
        toggleInvert();
      case RadViewerAction.rotate:
        p.rotate();
      case RadViewerAction.flipH:
        p.flip();
      case RadViewerAction.flipV:
        p.flip(horizontal: false);
      case RadViewerAction.reset:
        p.resetView();
        viewChanged(p);
      case RadViewerAction.readingMode:
        setState(() => _reading = !_reading);
      case RadViewerAction.keyImage:
        markKeyImage();
      case RadViewerAction.nextImage:
        _stepImage(p, 1);
      case RadViewerAction.prevImage:
        _stepImage(p, -1);
      case RadViewerAction.nextFrame:
        step(p, 1);
      case RadViewerAction.prevFrame:
        step(p, -1);
      case RadViewerAction.thumbnails:
        _toggleThumbs();
      case RadViewerAction.panel:
        _togglePanel();
      case RadViewerAction.shortcuts:
        _openShortcuts();
      default:
        break;
    }
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_typing || _panes.isEmpty) return KeyEventResult.ignored;
    final key = e.logicalKey;
    // Space is held to pan; don't let it press a focused button.
    if (key == LogicalKeyboardKey.space) return KeyEventResult.handled;

    if (e is KeyUpEvent) {
      // Holding the magnifier key shows the loupe only while held.
      if (key == _loupeKey) {
        final down = _loupeDownAt;
        if (down != null && DateTime.now().difference(down) > const Duration(milliseconds: 300)) {
          setState(() => _loupe = false);
        }
        _loupeKey = null;
        _loupeDownAt = null;
      }
      return KeyEventResult.ignored;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        HardwareKeyboard.instance.isShiftPressed ? _redoStep() : _undoStep();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redoStep();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final p = _pane;
    final draft = p.draft;
    if (key == LogicalKeyboardKey.escape) {
      if (draft != null) {
        p.draft = null;
        p.draftHover = null;
        p.touch();
      } else if (_selectedId != null) {
        setState(() => _selectedId = null);
      } else if (_reading) {
        setState(() => _reading = false);
      } else if (_loupe) {
        setState(() => _loupe = false);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (draft == null) return KeyEventResult.ignored;
      final min = draft.kind == RadAnnoKind.polygon ? 3 : 2;
      p.draft = null;
      p.draftHover = null;
      p.touch();
      if ((draft.kind == RadAnnoKind.polygon || draft.kind == RadAnnoKind.polyline) &&
          draft.points.length >= min) {
        commitDraft(p, draft, _tool);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (draft != null && key == LogicalKeyboardKey.backspace && draft.points.length > 1) {
        p.draft = draft.copyWith(points: draft.points.sublist(0, draft.points.length - 1));
        p.touch();
        return KeyEventResult.handled;
      }
      final id = _selectedId;
      final a = id == null ? null : _annotationsFor(p).where((x) => x.id == id).firstOrNull;
      if (a == null || p.studyId != _study?.id) return KeyEventResult.ignored;
      deleteAnnotation(a);
      return KeyEventResult.handled;
    }

    final name = radKeyName(e);
    if (name == null) return KeyEventResult.ignored;
    final action = _prefs.actionFor(name);
    if (action == null) return KeyEventResult.ignored;
    if (action == RadViewerAction.magnifier) {
      if (_loupe) {
        setState(() => _loupe = false);
      } else {
        setState(() => _loupe = true);
        _loupeKey = key;
        _loupeDownAt = DateTime.now();
      }
      return KeyEventResult.handled;
    }
    _run(action);
    return KeyEventResult.handled;
  }

  // ───────────────────────────── Export and other screens ─────────────────────────────

  /// The selected rectangle or ellipse ROI's bounds, in image pixels.
  Rect? _selectedBox(RadPane p) {
    final id = _selectedId;
    if (id == null) return null;
    for (final a in _annotationsFor(p)) {
      if (a.id != id) continue;
      if ((a.kind != RadAnnoKind.rect && a.kind != RadAnnoKind.ellipse) || a.points.length < 2) {
        return null;
      }
      final xs = a.points.map((q) => q.x), ys = a.points.map((q) => q.y);
      return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
    }
    return null;
  }

  Future<void> _export(_ExportKind kind) async {
    final p = _pane;
    final s = _studies[p.studyId];
    final image = _imageRef(p);
    if (s == null || image == null || !p.hasImage || _busy) return;
    final index = _slots(s).indexWhere((id) => _paneShows(p, id)) + 1;
    setState(() => _busy = true);
    try {
      if (kind == _ExportKind.dicom) {
        final bytes = await radAnonymisedDicom(await _ctl.fileOf(s, image.path));
        if (!mounted) return;
        if (bytes == null) {
          radToast(context, "This DICOM file can't be anonymised (big-endian encoding)");
          return;
        }
        final path = await radSaveBytes(
          dialogTitle: 'Save anonymised DICOM',
          fileName: radSafeName(
              'anonymised ${s.modality.short} ${DateFormat('yyyy-MM-dd').format(s.studyDate)}.dcm'),
          extension: 'dcm',
          bytes: bytes,
        );
        if (path == null) return;
        await _ctl.log('Exported', targetKind: 'study', targetId: s.id, detail: 'Anonymised DICOM of image $index');
        if (mounted) radToast(context, 'Saved an anonymised copy');
        return;
      }
      if (kind == _ExportKind.area) {
        // The selected rectangle or ellipse ROI, at full resolution, as
        // the doctor sees it (window and filters), without marks.
        final box = _selectedBox(p);
        final px = p.px;
        final full = box == null || px == null ? null : await p.renderFull();
        if (box == null || px == null || full == null) return;
        final sx = full.width / px.width, sy = full.height / px.height;
        final r = Rect.fromLTRB(box.left * sx, box.top * sy, box.right * sx, box.bottom * sy)
            .intersect(Rect.fromLTWH(0, 0, full.width.toDouble(), full.height.toDouble()));
        if (r.width < 2 || r.height < 2) {
          full.dispose();
          return;
        }
        final rec = ui.PictureRecorder();
        Canvas(rec).drawImageRect(full, r, Offset.zero & r.size, Paint());
        final picture = rec.endRecording();
        final crop = await picture.toImage(r.width.round(), r.height.round());
        picture.dispose();
        full.dispose();
        final bytes = await radEncodePng(crop);
        crop.dispose();
        if (bytes == null || !mounted) return;
        final path = await radSaveBytes(
          dialogTitle: 'Save selected area',
          fileName: '${radExportName(s)}_${index}_area.png',
          extension: 'png',
          bytes: bytes,
        );
        if (path == null) return;
        await _ctl.log('Exported', targetKind: 'study', targetId: s.id, detail: 'PNG of an area of image $index');
        if (mounted) radToast(context, 'Area saved');
        return;
      }
      final marks = kind == _ExportKind.pngMarks || kind == _ExportKind.jpgMarks;
      final jpg = kind == _ExportKind.jpg || kind == _ExportKind.jpgMarks;
      final view = await radRenderPaneView(
        p,
        annotations: _annotationsFor(p),
        mmPerPx: _mmPerPxFor(p),
        withAnnotations: marks,
        roi: _roi,
      );
      if (view == null) return;
      final bytes = jpg ? await radEncodeJpg(view) : await radEncodePng(view);
      view.dispose();
      if (bytes == null || !mounted) return;
      final ext = jpg ? 'jpg' : 'png';
      final path = await radSaveBytes(
        dialogTitle: 'Save image',
        fileName: '${radExportName(s)}_$index.$ext',
        extension: ext,
        bytes: bytes,
      );
      if (path == null) return;
      await _ctl.log(
        'Exported',
        targetKind: 'study',
        targetId: s.id,
        detail: '${ext.toUpperCase()} of image $index${marks ? ', with marks' : ''}',
      );
      if (mounted) radToast(context, 'Image saved');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't export the image");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push(Widget page) async {
    await _flush();
    if (!mounted) return;
    await Navigator.of(context).push(radRoute<void>(page));
    if (mounted) _focus.requestFocus();
  }

  Future<void> _openReport() async {
    final s = _study;
    if (s == null) return;
    await _flush();
    if (!mounted) return;
    await openRadReport(context, s);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _open3d() async {
    final s = _study;
    if (s == null) return;
    await _flush();
    if (!mounted) return;
    await openRadCbct3d(context, s);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _back() async {
    await _flush();
    _flushPrefs();
    if (mounted) Navigator.of(context).maybePop();
  }

  // ───────────────────────────── Build ─────────────────────────────

  String _tip(String label, RadViewerAction a) {
    final k = _prefs.keyFor(a);
    return k.isEmpty ? label : '$label ($k)';
  }

  String _paneTitle(RadPane p) {
    final s = _studies[p.studyId];
    if (s == null || p.imageId.isEmpty) return '';
    final prefix = p.studyId == _study?.id
        ? s.modality.short
        : 'Compare · ${s.modality.short} · ${RadFormat.date(s.studyDate)}';
    final st = p.stack;
    if (st != null) return '$prefix · Slice ${p.sliceIndex + 1} of ${st.length}';
    final slots = _slots(s);
    final i = slots.indexOf(p.imageId);
    final series = _imageRef(p)?.seriesDescription ?? '';
    return [
      prefix,
      if (i >= 0 && slots.length > 1) 'Image ${i + 1} of ${slots.length}',
      if (series.isNotEmpty) series,
    ].join(' · ');
  }

  Widget _cell(int i) {
    final p = _panes[i];
    return RadViewport(
      key: ObjectKey(p),
      pane: p,
      host: this,
      tool: _tool,
      annotations: _annotationsFor(p),
      selectedId: i == _active ? _selectedId : null,
      mmPerPx: _mmPerPxFor(p),
      canAnnotate: p.studyId == _study?.id,
      active: i == _active,
      showActive: _panes.length > 1,
      loupe: _loupe,
      title: _paneTitle(p),
      aiFindings: _aiFindingsFor(p),
      showAiMarks: ref.watch(radShowAiMarksProvider),
    );
  }

  Widget _grid() {
    const gap = SizedBox(width: 2, height: 2);
    Widget row(List<int> ids) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < ids.length; k++) ...[
              if (k > 0) gap,
              Expanded(child: _cell(ids[k])),
            ],
          ],
        );
    Widget col(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < children.length; k++) ...[
              if (k > 0) gap,
              Expanded(child: children[k]),
            ],
          ],
        );
    final grid = switch (_layout) {
      RadLayout.one => _cell(0),
      RadLayout.sideBySide => row([0, 1]),
      RadLayout.stacked => col([_cell(0), _cell(1)]),
      RadLayout.grid => col([row([0, 1]), row([2, 3])]),
      RadLayout.onePlusThree => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: _cell(0)),
            gap,
            Expanded(child: col([_cell(1), _cell(2), _cell(3)])),
          ],
        ),
    };
    return ColoredBox(color: RadInk.gutter, child: grid);
  }

  Widget _toolbar(RadStudy s, List<RadStudy> others) {
    final c = context.cru;
    final p = _pane;
    final has = p.hasImage;
    final own = p.studyId == s.id;
    final image = _imageRef(p);
    final isCeph = s.modality == RadModality.ceph ||
        (image?.seriesDescription.toLowerCase().contains('ceph') ?? false);
    RadBarButton action(CruIconData icon, String label, RadViewerAction a, {bool enabled = true}) =>
        RadBarButton(
          icon: icon,
          tooltip: _tip(label, a),
          onPressed: enabled ? () => _run(a) : null,
        );
    return Container(
      height: radToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final group in _toolGroups) ...[
                    for (final t in group)
                      RadBarButton(
                        icon: t.icon,
                        tooltip: _tip(t.label, RadViewerAction.values.byName(t.name)),
                        selected: _tool == t,
                        style: RadBarButtonStyle.tool,
                        onPressed: t == RadTool.calibrate
                            ? (has && own ? startCalibration : null)
                            : () => _setTool(t),
                      ),
                    const RadBarDivider(),
                  ],
                  action(RadViewerIcons.fit, 'Fit to pane', RadViewerAction.fit, enabled: has),
                  action(RadViewerIcons.rotate, 'Rotate 90°', RadViewerAction.rotate, enabled: has),
                  action(RadViewerIcons.flipH, 'Flip left–right', RadViewerAction.flipH, enabled: has),
                  action(RadViewerIcons.flipV, 'Flip up–down', RadViewerAction.flipV, enabled: has),
                  RadBarButton(
                    icon: RadViewerIcons.invert,
                    tooltip: _tip('Invert', RadViewerAction.invert),
                    selected: p.userInvert,
                    style: RadBarButtonStyle.toggle,
                    onPressed: has ? toggleInvert : null,
                  ),
                  RadBarButton(
                    icon: RadViewerIcons.loupe,
                    tooltip: _tip('Magnifier', RadViewerAction.magnifier),
                    selected: _loupe,
                    style: RadBarButtonStyle.toggle,
                    onPressed: () => setState(() => _loupe = !_loupe),
                  ),
                  action(RadViewerIcons.reset, 'Reset view', RadViewerAction.reset, enabled: has),
                  const RadBarDivider(),
                  RadMenuButton<RadLayout>(
                    icon: _layout.icon,
                    tooltip: 'Layout',
                    items: () => [
                      for (final l in RadLayout.values)
                        radMenuItem(context, l, l.label, icon: l.icon, checked: l == _layout),
                    ],
                    onSelected: _setLayout,
                  ),
                  if (others.isNotEmpty)
                    RadMenuButton<String>(
                      icon: RadViewerIcons.compare,
                      tooltip: 'Compare with another study of this patient',
                      selected: _compare != null,
                      items: () => [
                        for (final o in others)
                          radMenuItem(
                            context,
                            o.id,
                            '${o.modality.short} · ${RadFormat.date(o.studyDate)}',
                            hint: RadFormat.images(o.images.length),
                            checked: o.id == _compare?.id,
                          ),
                        if (_compare != null) radMenuItem(context, '', 'Stop comparing'),
                      ],
                      onSelected: (id) =>
                          _setCompare(id.isEmpty ? null : others.where((o) => o.id == id).firstOrNull),
                    ),
                  if (_panes.length > 1)
                    RadBarButton(
                      icon: RadViewerIcons.link,
                      tooltip: _link ? 'Zoom and pan are linked' : 'Link zoom and pan',
                      selected: _link,
                      style: RadBarButtonStyle.toggle,
                      onPressed: _toggleLink,
                    ),
                  const RadBarDivider(),
                  RadBarButton(
                    icon: RadViewerIcons.undo,
                    tooltip: 'Undo (Ctrl Z)',
                    onPressed: _undo.isEmpty ? null : _undoStep,
                  ),
                  RadBarButton(
                    icon: RadViewerIcons.redo,
                    tooltip: 'Redo (Ctrl Y)',
                    onPressed: _redo.isEmpty ? null : _redoStep,
                  ),
                  const RadBarDivider(),
                  action(RadViewerIcons.keyImage, 'Mark key image', RadViewerAction.keyImage,
                      enabled: has && own && !_busy),
                  RadMenuButton<_ExportKind>(
                    icon: RadViewerIcons.export,
                    tooltip: 'Export',
                    enabled: has && !_busy,
                    items: () => [
                      radMenuItem(context, _ExportKind.pngMarks, 'PNG with marks', icon: RadViewerIcons.export),
                      radMenuItem(context, _ExportKind.png, 'PNG without marks', icon: RadViewerIcons.export),
                      radMenuItem(context, _ExportKind.jpgMarks, 'JPG with marks', icon: RadViewerIcons.export),
                      radMenuItem(context, _ExportKind.jpg, 'JPG without marks', icon: RadViewerIcons.export),
                      if (_selectedBox(_pane) != null)
                        radMenuItem(context, _ExportKind.area, 'PNG of the selected area', icon: RadViewerIcons.export),
                      if (image?.kind == RadFileKind.dicom)
                        radMenuItem(context, _ExportKind.dicom, 'Anonymised DICOM', icon: RadViewerIcons.file),
                    ],
                    onSelected: _export,
                  ),
                  if (isCeph) ...[
                    const SizedBox(width: CruSpace.s8),
                    CruButton(
                      label: 'Ceph tracing',
                      icon: RadViewerIcons.ceph,
                      kind: CruButtonKind.inset,
                      onPressed: has && own
                          ? () => _push(RadCephScreen(studyId: s.id, imageId: p.imageId))
                          : null,
                    ),
                  ],
                  const SizedBox(width: CruSpace.s8),
                  CruButton(
                    label: 'Compare / subtract',
                    icon: RadViewerIcons.subtract,
                    kind: CruButtonKind.inset,
                    onPressed: has && own
                        ? () => _push(RadSubtractionScreen(studyId: s.id, imageIdA: p.imageId))
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const RadBarDivider(),
          RadBarButton(
            icon: RadViewerIcons.thumbnails,
            tooltip: _tip('Thumbnails', RadViewerAction.thumbnails),
            selected: _prefs.thumbs,
            style: RadBarButtonStyle.toggle,
            onPressed: _toggleThumbs,
          ),
          RadBarButton(
            icon: RadViewerIcons.panel,
            tooltip: _tip('Side panel', RadViewerAction.panel),
            selected: _prefs.panelOpen,
            style: RadBarButtonStyle.toggle,
            onPressed: _togglePanel,
          ),
          RadBarButton(
            icon: RadViewerIcons.readingMode,
            tooltip: _tip('Reading mode', RadViewerAction.readingMode),
            onPressed: () => setState(() => _reading = true),
          ),
        ],
      ),
    );
  }

  Widget _panel(RadStudy s, RadReport? report) {
    final p = _pane;
    final own = p.studyId == s.id;
    final paneStudy = own
        ? s.copyWith(annotations: _annos, calibration: _cal)
        : (_studies[p.studyId] ?? s);
    final image = _imageRef(p);
    final header = image != null && image.kind == RadFileKind.dicom
        ? _headers.get(
            '${p.studyId}/${image.id}',
            () async => radDicomHeader(await _ctl.fileOf(paneStudy, image.path)),
          )
        : null;
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() {
              _panelWidth = (_panelWidth - d.delta.dx)
                  .clamp(RadViewerPrefs.minPanelWidth, RadViewerPrefs.maxPanelWidth);
            }),
            onHorizontalDragEnd: (_) {
              _prefs = _prefs.copyWith(panelWidth: _panelWidth);
              _savePrefs({RadViewerPrefs.panelWidthKey: _panelWidth});
            },
            child: SizedBox(width: CruSpace.s6, child: ColoredBox(color: context.cru.surface)),
          ),
        ),
        RadViewerSidePanel(
          host: this,
          width: _panelWidth,
          tab: _tab,
          onTab: _setTab,
          study: s,
          paneStudy: paneStudy,
          pane: p,
          annotations: _annotationsFor(p),
          readOnly: !own,
          selectedId: _selectedId,
          report: report,
          mmPerPx: _mmPerPxFor(p),
          roi: _roi,
          studyDir: _studyDir,
          header: header,
          presets: _prefs.presets,
          keyForKeyImage: _prefs.keyFor(RadViewerAction.keyImage),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final async = ref.watch(radStudyProvider(widget.studyId));
    final fresh = async.value;
    if (fresh != null) _accept(fresh);
    final s = _study;
    if (s == null || !_prefsLoaded) {
      final gone = _prefsLoaded && !async.isLoading && fresh == null;
      return Scaffold(
        backgroundColor: c.canvas,
        body: Center(
          child: gone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('This study is no longer here', style: CruType.title2.tint(c.label)),
                    const SizedBox(height: CruSpace.s12),
                    CruButton(
                      label: 'Back',
                      kind: CruButtonKind.secondary,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                )
              : Text('Opening study…', style: CruType.text.tint(c.label2)),
        ),
      );
    }
    if (!_started) _start(s);

    final all = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
    final others = [
      for (final o in all)
        if (o.id != s.id && _samePatient(o, s)) o,
    ]..sort((a, b) => b.studyDate.compareTo(a.studyDate));
    final cmp = _compare;
    if (cmp != null) {
      final latest = others.where((o) => o.id == cmp.id).firstOrNull;
      if (latest != null) {
        _compare = latest;
        _studies[latest.id] = latest;
      }
    }
    final report = ref.watch(radReportForStudyProvider(s.id));
    final referrer = ref.watch(radReferrerByIdProvider)[s.referrerId];
    final p = _pane;

    return Scaffold(
      backgroundColor: c.canvas,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_reading) ...[
              RadViewerTopBar(
                study: s,
                referrer: referrer?.display,
                report: report,
                onBack: _back,
                onReport: _openReport,
                onShortcuts: _openShortcuts,
                shortcutsKey: _prefs.keyFor(RadViewerAction.shortcuts),
                onOpen3d: radIsVolume(s) ? _open3d : null,
              ),
              _toolbar(s, others),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_reading && _prefs.thumbs)
                    RadThumbnailStrip(
                      study: s,
                      compare: _compare,
                      cache: _thumbs,
                      shown: {
                        for (final q in _panes)
                          if (q.imageId.isNotEmpty) '${q.studyId}/${q.imageId}',
                      },
                      active: '${p.studyId}/${p.imageId}',
                      onOpen: (studyId, imageId) {
                        setState(() => _show(_pane, studyId, imageId));
                        _focus.requestFocus();
                      },
                    ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _grid(),
                        if (s.images.isEmpty)
                          ColoredBox(
                            color: RadInk.viewport,
                            child: Center(
                              child: Text('This study has no images yet',
                                  style: CruType.text.tint(RadInk.overlayQuiet)),
                            ),
                          ),
                        if (_reading)
                          Positioned(
                            top: CruSpace.s12,
                            right: CruSpace.s12,
                            child: _OverlayPill(
                              icon: CruIcons.close,
                              label: _prefs.keyFor(RadViewerAction.readingMode).isEmpty
                                  ? 'Leave reading mode'
                                  : 'Leave reading mode · ${_prefs.keyFor(RadViewerAction.readingMode)}',
                              onTap: () => setState(() => _reading = false),
                            ),
                          ),
                        if (_busy)
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: CruSpace.s16,
                            child: Center(child: _OverlayPill(label: 'Working…')),
                          ),
                      ],
                    ),
                  ),
                  if (!_reading && _prefs.panelOpen) _panel(s, report),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small dark pill on top of the image panes.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.label, this.icon, this.onTap});

  final String label;
  final CruIconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: CruSize.capsule,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: const ShapeDecoration(color: RadInk.overlayFill, shape: StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 13, strokeWidth: 2.2, color: RadInk.overlay),
            const SizedBox(width: CruSpace.s6),
          ],
          Text(label, style: CruType.caption.w500.tint(RadInk.overlay)),
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return pill;
    return CruPressable(onTap: tap, semanticLabel: label, builder: (context, _) => pill);
  }
}
