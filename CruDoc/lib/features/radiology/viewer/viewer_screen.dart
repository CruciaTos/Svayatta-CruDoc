import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart'
    show FileSource, FilesRepository;
import 'package:doctor_management_app/features/radiology/ai/rad_ai.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_viewer_screen.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_merge.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_look.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/features/radiology/viewer/save_status.dart';
import 'package:doctor_management_app/features/radiology/viewer/side_panel.dart';
import 'package:doctor_management_app/features/radiology/viewer/thumbnail_strip.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_dialogs.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_export.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_phone_bar.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_prefs.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_shortcuts_dialog.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_toolbar.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewport.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ceph/ceph_screen.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/subtraction/subtraction_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _ExportKind { toFiles, pngMarks, png, jpgMarks, jpg, area, dicom }

/// The phone bar's groups: each opens its own row of tools.
enum _PhoneGroup { adjust, measure, draw, rotate, more }

/// Annotations and calibration at one moment (an undo step).
class _Snapshot {
  const _Snapshot(this.annos, this.cal);
  final Map<String, List<RadAnnotation>> annos;
  final Map<String, double> cal;
}

/// The desktop toolbar's groups: the active group's tools show on the row
/// below the group tabs, each with its name.
enum _DeskGroup {
  move('Move'),
  adjust('Adjust'),
  measure('Measure'),
  draw('Draw'),
  tooth('Tooth'),
  view('View');

  const _DeskGroup(this.label);
  final String label;

  /// Its drag tools; the first is picked when the group opens the first
  /// time. View holds actions only.
  List<RadTool> get tools => switch (this) {
    move => const [RadTool.select, RadTool.pan, RadTool.zoom],
    adjust => const [RadTool.window],
    measure => const [
      RadTool.length,
      RadTool.angle,
      RadTool.polygon,
      RadTool.calibrate,
    ],
    draw => const [
      RadTool.arrow,
      RadTool.freehand,
      RadTool.text,
      RadTool.rect,
      RadTool.ellipse,
      RadTool.polyline,
    ],
    tooth => const [RadTool.tooth],
    view => const [],
  };

  static _DeskGroup of(RadTool t) =>
      values.firstWhere((g) => g.tools.contains(t), orElse: () => move);
}

/// The 2D reading page: thumbnails on the left, one to four dark image
/// panes, and a side panel with measurements, key images, image info,
/// adjustments and the AI second read. CBCT slice series page through as
/// one stack. Annotations save to the study as the doctor works.
class RadViewerScreen extends ConsumerStatefulWidget {
  const RadViewerScreen({
    super.key,
    required this.studyId,
    this.initialStudy,
    this.initialImageId,
  });

  final String studyId;
  final RadStudy? initialStudy;
  final String? initialImageId;

  @override
  ConsumerState<RadViewerScreen> createState() => _RadViewerScreenState();
}

class _RadViewerScreenState extends ConsumerState<RadViewerScreen>
    with WidgetsBindingObserver
    implements RadViewportHost, RadSidePanelHost {
  final _focus = FocusNode(debugLabel: 'Radiology viewer');
  late final RadiologyController _ctl;
  late final RadiologyRepository _repo;
  late final RadPixelCache _cache;
  late final RadThumbCache _thumbs;
  final _roi = RadRoiCache();
  final _headers = RadHeaderCache();

  RadStudy? _study;
  RadStudy? _compare;
  final _studies = <String, RadStudy>{};
  final _stackCache = <String, (RadStudy, Map<String, List<String>>)>{};
  bool _started = false;
  String? _studyDir;

  // Working copy of the study's annotations and ruler calibration.
  Map<String, List<RadAnnotation>> _annos = {};
  Map<String, double> _cal = {};
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  Timer? _saveTimer;
  bool _dirty = false;

  /// The annotations and calibration as last loaded or saved: the base the
  /// working copy is merged from when the study changed elsewhere.
  Map<String, List<RadAnnotation>> _savedAnnos = {};
  Map<String, double> _savedCal = {};

  /// Looks changed since the last save, by image (or stack) key; null
  /// means the image is back to how it opens.
  final _lookEdits = <String, RadImageLook?>{};

  /// Saves run one after another, each merging onto the one before.
  Future<void> _saving = Future.value();

  /// An annotation is being dragged: another device's copy waits.
  bool _editing = false;

  /// A save is being written: its own copy may come back first.
  bool _writing = false;
  RadStudy? _lastFresh;
  final _saveState = ValueNotifier(RadSaveState.none);
  Timer? _syncTimer;

  RadViewerPrefs _prefs = const RadViewerPrefs();
  final _pendingPrefs = <String, dynamic>{};
  Timer? _prefsTimer;
  double _panelWidth = RadViewerPrefs.defaultPanelWidth;

  /// Phone: the side panel opens over the image only when asked for.
  bool _phonePanel = false;

  RadLayout _layout = RadLayout.one;
  final _panes = <RadPane>[];
  int _active = 0;
  RadTool _tool = RadTool.select;
  RadTool _toolBeforeCalibrate = RadTool.select;
  bool _link = false;
  bool _loupe = false;

  /// The phone bar's open group, if any.
  _PhoneGroup? _phoneGroup;

  /// The desktop toolbar's open group, and the tool last used in each, so
  /// opening a group picks up where the doctor left it.
  _DeskGroup _deskGroup = _DeskGroup.move;
  final Map<_DeskGroup, RadTool> _lastTool = {};
  LogicalKeyboardKey? _loupeKey;
  DateTime? _loupeDownAt;
  bool _reading = false;
  RadPanelTab _tab = RadPanelTab.measure;
  String? _selectedId;
  bool _busy = false;
  final Set<String> _fullQualityIds = {};

  RadPane get _pane => _panes[_active.clamp(0, _panes.length - 1)];

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(radiologyProvider);
    _repo = ref.read(radiologyRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _cache = RadPixelCache(_loadPixels, capacity: 12);
    _thumbs = RadThumbCache(_ctl.thumbSourceOf);
    final init = widget.initialStudy;
    if (init != null) {
      _study = init;
      _studies[init.id] = init;
      _start(init);
    }
    _loadPrefs();
    _ctl.studyDir(widget.studyId).then((d) {
      if (mounted) setState(() => _studyDir = d.path);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    if (_dirty || _lookEdits.isNotEmpty) unawaited(_saveStudy((s) => s));
    _flushPrefs();
    for (final p in _panes) {
      p.dispose();
    }
    _thumbs.dispose();
    _focus.dispose();
    _saveState.dispose();
    super.dispose();
  }

  /// Leaving the app (switching away, locking the phone) saves at once:
  /// the app may not come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(_flush());
    _flushPrefs();
  }

  Future<void> _loadPrefs() async {
    RadSettings? settings;
    try {
      settings = await ref
          .read(radSettingsProvider.future)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Defaults are fine when settings can't be read.
    }
    if (!mounted) return;
    setState(() {
      _prefs = RadViewerPrefs.from(settings?.viewer ?? const {});
      _panelWidth = _prefs.panelWidth;
    });
  }

  Future<RadPixels> _loadPixels(
    String studyId,
    String imageId,
    int frame,
  ) async {
    final s = _studies[studyId];
    final i = s?.images.where((x) => x.id == imageId).firstOrNull;
    if (s == null || i == null) throw StateError('Image not found');
    return _ctl.pixelsOf(
      s,
      i,
      frame,
      full: _prefs.fullQuality || _fullQualityIds.contains(imageId),
    );
  }

  /// Takes the provider's copy unless ours is newer (just saved).
  void _accept(RadStudy fresh) {
    if (identical(fresh, _lastFresh)) return;
    _lastFresh = fresh;
    final cur = _study;
    if (cur == null ||
        fresh.updatedAt.millisecondsSinceEpoch >=
            cur.updatedAt.millisecondsSinceEpoch) {
      _study = fresh;
      _studies[fresh.id] = fresh;
    }
    // Another device's annotations show at once while nothing here is
    // waiting to save (otherwise the save merges them in).
    if (_started &&
        !_dirty &&
        !_editing &&
        !_writing &&
        _lookEdits.isEmpty &&
        (!radSameAnnotations(fresh.annotations, _savedAnnos) ||
            !mapEquals(fresh.calibration, _savedCal))) {
      _annos = _copyOf(fresh.annotations);
      _cal = {...fresh.calibration};
      _savedAnnos = _copyOf(fresh.annotations);
      _savedCal = {...fresh.calibration};
      _undo.clear();
      _redo.clear();
    }
  }

  static Map<String, List<RadAnnotation>> _copyOf(
    Map<String, List<RadAnnotation>> m,
  ) => {
    for (final e in m.entries) e.key: [...e.value],
  };

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
      final list = [...e.value]
        ..sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));
      out.addAll(list.map((i) => i.id));
    }
    return out;
  }

  RadImageRef? _imageRef(RadPane p) =>
      _studies[p.studyId]?.images.where((i) => i.id == p.imageId).firstOrNull;

  bool _paneShows(RadPane p, String id) =>
      p.imageId == id || (p.stack?.contains(id) ?? false);

  /// Opens an image in [p] (a slice of a stack brings the whole stack).
  Future<void> _show(
    RadPane p,
    String studyId,
    String imageId, {
    bool keepView = false,
  }) async {
    final s = _studies[studyId];
    final img = s?.images.where((i) => i.id == imageId).firstOrNull;
    if (s == null || img == null) {
      p.clear();
      return;
    }
    if (_panes.isNotEmpty && identical(p, _pane) && p.imageId != imageId) {
      _selectedId = null;
    }
    p.stack = _stackFor(studyId, imageId);
    final unsupported = img.compressed
        ? '${img.transferSyntax.isEmpty ? 'Compressed' : DicomSyntax.name(img.transferSyntax)} '
              'DICOM images are not supported yet'
        : null;
    final thumb = _thumbs.image(studyId, imageId);
    if (thumb == null && !img.compressed) {
      _thumbs.request(s, img, priority: true);
    }
    await p.show(
      studyId,
      imageId,
      _cache,
      keepView: keepView,
      unsupported: unsupported,
      placeholder: thumb,
      nominalWidth: img.width,
      nominalHeight: img.height,
      onThumbArrived: (cb) {
        void listener() {
          final t = _thumbs.image(studyId, imageId);
          if (t != null) cb(t);
        }

        _thumbs.addListener(listener);
        return () => _thumbs.removeListener(listener);
      },
    );
    if (!mounted) return;
    if (!keepView && p.hasImage) {
      final look = _lookFor(studyId, p);
      if (look != null) {
        await p.applyLook(look);
      } else if (!mapEquals(p.filters.toJson(), p.baseFilters.toJson())) {
        // The last image's filters stay with it; this one opens plain.
        await p.applyLook(
          RadImageLook(
            center: p.center,
            width: p.width,
            filters: p.baseFilters,
          ),
        );
      }
      if (!mounted) return;
    }
    if (_link && !keepView && _panes.isNotEmpty && !identical(p, _pane)) {
      p.scale = _pane.scale;
      p.pan = _pane.pan;
      p.touch();
    }
    _checkZoomUpgrade();
  }

  /// Images of one slice stack share a look (by the stack's first slice).
  static String _lookKey(RadPane p) => p.stack?.first ?? p.imageId;

  /// The look [p]'s image was left with: an unsaved change first.
  RadImageLook? _lookFor(String studyId, RadPane p) {
    final key = _lookKey(p);
    if (studyId == _study?.id && _lookEdits.containsKey(key)) {
      return _lookEdits[key];
    }
    final s = _studies[studyId];
    return s == null ? null : radLooksOf(s)[key];
  }

  /// The doctor changed how [p]'s image looks: kept for it, saved shortly.
  void _lookChanged(RadPane p) {
    final s = _study;
    if (s == null || p.studyId != s.id || !p.hasImage) return;
    _lookEdits[_lookKey(p)] = p.look;
    _scheduleSave();
  }

  RadPane _newPane(String studyId, RadFilterSettings filters) {
    final p = RadPane(studyId: studyId, imageId: '')
      ..filters = filters
      ..baseFilters = filters;
    p.onLook = () => _lookChanged(p);
    return p;
  }

  Future<void> _upgradeToFull(Iterable<String> imageIds) async {
    final ids = imageIds.toSet();
    if (ids.isEmpty) return;
    _fullQualityIds.addAll(ids);
    for (final id in ids) {
      _cache.evict(id);
    }
    final affectedPanes = _panes
        .where((p) => ids.contains(p.imageId) && p.studyId.isNotEmpty)
        .toList();
    if (affectedPanes.isEmpty) return;

    for (final p in affectedPanes) {
      p.upgrading = true;
      p.touch();
    }
    try {
      final futures = <Future<void>>[];
      for (final p in affectedPanes) {
        futures.add(_show(p, p.studyId, p.imageId, keepView: true));
      }
      await Future.wait(futures);
    } finally {
      for (final p in affectedPanes) {
        p.upgrading = false;
        p.touch();
      }
    }
  }

  @override
  void upgradeToFull(String imageId) {
    _upgradeToFull([imageId]);
  }

  void _start(RadStudy s) {
    _started = true;
    _annos = {
      for (final e in s.annotations.entries) e.key: [...e.value],
    };
    _cal = {...s.calibration};
    _savedAnnos = _copyOf(s.annotations);
    _savedCal = {...s.calibration};
    unawaited(_checkSynced());
    final st = _prefs.stateFor(s.modality);
    _layout = RadLayout.fromName(st['layout']);
    final tool = RadTool.fromName(st['tool']);
    _tool = tool == RadTool.calibrate ? RadTool.select : tool;
    _link = st['link'] == true;
    _tab = RadPanelTab.fromName(st['tab']);
    final f = st['filters'];
    final filters = f is Map
        ? RadFilterSettings.fromJson(Map<String, dynamic>.from(f))
        : const RadFilterSettings();

    final slots = _slots(s);
    final initial = widget.initialImageId;
    final first = initial != null && s.images.any((i) => i.id == initial)
        ? initial
        : slots
                  .where(
                    (id) =>
                        !(s.images.firstWhere((i) => i.id == id).compressed),
                  )
                  .firstOrNull ??
              slots.firstOrNull ??
              '';
    final firstStack = first.isEmpty ? null : _stackFor(s.id, first);
    final order = [
      first,
      ...slots.where(
        (id) => id != first && !(firstStack?.contains(id) ?? false),
      ),
    ];
    for (var i = 0; i < _layout.panes; i++) {
      final p = _newPane(s.id, filters);
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
        final next =
            _slots(s)
                .where(
                  (id) => !_panes.any(
                    (p) => p.studyId == s.id && _paneShows(p, id),
                  ),
                )
                .firstOrNull ??
            '';
        final p = _newPane(s.id, _pane.baseFilters);
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
      (a.patientExternalId.isNotEmpty &&
          a.patientExternalId == b.patientExternalId);

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
              .where(
                (id) =>
                    !_panes.any((q) => q.studyId == s.id && _paneShows(q, id)),
              )
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
            .where(
              (id) => other.images.any(
                (i) => i.id == id && i.seriesDescription == series,
              ),
            )
            .firstOrNull;
      }
      pick ??=
          slots
              .where(
                (id) => !other.images.firstWhere((i) => i.id == id).compressed,
              )
              .firstOrNull ??
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
    _prefs = _prefs.copyWith(
      states: {..._prefs.states, s.modality.name: state},
    );
    _savePrefs({RadViewerPrefs.stateKey(s.modality): state});
  }

  void _setTool(RadTool t) {
    if (t == RadTool.calibrate && _tool != RadTool.calibrate) {
      _toolBeforeCalibrate = _tool;
    }
    const measuringTools = {
      RadTool.length,
      RadTool.angle,
      RadTool.polygon,
      RadTool.ellipse,
      RadTool.rect,
      RadTool.polyline,
      RadTool.calibrate,
    };
    if (measuringTools.contains(t)) {
      final previewIds = [
        for (final p in _panes)
          if (p.px?.isPreview == true &&
              p.imageId.isNotEmpty &&
              !_fullQualityIds.contains(p.imageId))
            p.imageId,
      ];
      if (previewIds.isNotEmpty) {
        _upgradeToFull(previewIds);
      }
    }
    for (final p in _panes) {
      if (p.draft != null) {
        p.draft = null;
        p.draftHover = null;
        p.touch();
      }
    }
    final group = _DeskGroup.of(t);
    if (t != RadTool.calibrate) _lastTool[group] = t;
    setState(() {
      _tool = t;
      if (t != RadTool.select) _deskGroup = group;
    });
    _rememberState();
  }

  /// Opens [g] on the desktop bar and picks its tool: the one last used
  /// there, else its first.
  void _openGroup(_DeskGroup g) {
    setState(() => _deskGroup = g);
    final tools = g.tools;
    // View has no drawing tools: a drag there moves the image rather than
    // drawing with whatever was picked before.
    if (tools.isEmpty) return _setTool(RadTool.select);
    if (tools.contains(_tool)) return;
    final last = _lastTool[g];
    _setTool(last != null && last != RadTool.calibrate ? last : tools.first);
  }

  /// The side panel on [t], opening it if it's closed.
  void _showPanelTab(RadPanelTab t) {
    if (!_prefs.panelOpen) _togglePanel();
    _setTab(t);
  }

  /// The last tooth number on [imageId], newest first.
  RadAnnotation? _lastTooth(String imageId) {
    final list = _annos[imageId] ?? const <RadAnnotation>[];
    for (final a in list.reversed) {
      if (a.kind == RadAnnoKind.toothLabel &&
          a.text.isNotEmpty &&
          a.points.isNotEmpty) {
        return a;
      }
    }
    return null;
  }

  /// Tooth numbers follow on: clicked beside the last numbered tooth on the
  /// same arch (mostly sideways), the new label takes the neighbouring
  /// number in that direction. Null when it can't tell (first tooth, a jump
  /// to the other arch, the end of the arch): then the picker opens.
  String? _followOnTooth(String imageId, RadAnnotation a) {
    final last = _lastTooth(imageId);
    if (last == null || a.points.isEmpty) return null;
    final dx = a.points.first.x - last.points.first.x;
    final dy = a.points.first.y - last.points.first.y;
    if (dx.abs() < 8 || dy.abs() > dx.abs()) return null;
    return radNextTooth(last.text, dx.sign.toInt());
  }

  /// What the hint at the foot of the image says for the current tool;
  /// null when there's nothing to say (just looking).
  ({String text, String? action, VoidCallback? onAction})? _toolHint() {
    final t = _tool;
    if (t == RadTool.select || !_pane.hasImage) return null;
    if (t == RadTool.tooth) {
      final last = _lastTooth(_pane.imageId);
      if (last != null) {
        return (
          text:
              'Click the next tooth: numbers follow on from ${last.text} · '
              'Shift-click to choose',
          action: null,
          onAction: null,
        );
      }
    }
    const scaled = {
      RadTool.length,
      RadTool.polygon,
      RadTool.ellipse,
      RadTool.rect,
      RadTool.polyline,
    };
    final own = _pane.studyId == _study?.id;
    // The side panel's Measure tab already says so, with its own button.
    final panelSays = _prefs.panelOpen && _tab == RadPanelTab.measure;
    if (scaled.contains(t) && own && !panelSays && _mmPerPxFor(_pane) == null) {
      return (
        text: '${t.mouseHint} · reads in pixels until you calibrate',
        action: 'Calibrate',
        onAction: startCalibration,
      );
    }
    return (text: t.mouseHint, action: null, onAction: null);
  }

  void _setTab(RadPanelTab t) {
    setState(() => _tab = t);
    _rememberState();
  }

  void _togglePanel() {
    if (cruIsPhone(context)) {
      setState(() => _phonePanel = !_phonePanel);
      return;
    }
    _prefs = _prefs.copyWith(panelOpen: !_prefs.panelOpen);
    setState(() {});
    _savePrefs({RadViewerPrefs.panelOpenKey: _prefs.panelOpen});
  }

  void _toggleThumbs() {
    _prefs = _prefs.copyWith(thumbs: !_prefs.thumbs);
    setState(() {});
    _savePrefs({RadViewerPrefs.thumbsKey: _prefs.thumbs});
  }

  void _toggleCursorOffset() {
    final next = !_prefs.cursorOffset;
    _prefs = _prefs.copyWith(cursorOffset: next);
    setState(() {});
    _savePrefs({RadViewerPrefs.cursorOffsetKey: next});
    radToast(
      context,
      next
          ? 'Cursor offset enabled (48 px above touch)'
          : 'Cursor offset disabled',
    );
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
    _setSaveState(RadSaveState.saving);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _flush);
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    if (!_dirty && _lookEdits.isEmpty) return;
    await _saveStudy((s) => s);
  }

  /// Saves the study with [change] applied, the working annotations and
  /// the changed looks. Saves run one at a time.
  Future<void> _saveStudy(
    RadStudy Function(RadStudy s) change, {
    String? audit,
    String detail = '',
  }) {
    final run = _saving.then(
      (_) => _save(change, audit: audit, detail: detail),
    );
    _saving = run.catchError((Object _) {});
    return run;
  }

  /// Merges onto the study as it is in the database now, so whatever
  /// another device synced in meanwhile (annotations, tracing, AI reads)
  /// is kept, then writes it; the write syncs to the cloud from there.
  Future<void> _save(
    RadStudy Function(RadStudy s) change, {
    String? audit,
    String detail = '',
  }) async {
    final mine = _study;
    if (mine == null) return;
    _saveTimer?.cancel();
    _dirty = false;
    final looks = {..._lookEdits};
    _lookEdits.clear();
    _setSaveState(RadSaveState.saving);
    _writing = true;
    try {
      final latest = await _repo.study(mine.id) ?? mine;
      final local = _copyAnnos();
      final cal = {..._cal};
      final annos = radMergeAnnotations(
        base: _savedAnnos,
        local: local,
        remote: latest.annotations,
      );
      final mergedCal = radMergeCalibration(
        base: _savedCal,
        local: cal,
        remote: latest.calibration,
      );
      final changed = change(latest);
      final next = changed.copyWith(
        annotations: annos,
        calibration: mergedCal,
        extras: radExtrasWithLooks(changed.extras, looks),
      );
      await _ctl.saveStudy(next, auditAction: audit, detail: detail);
      _study = next;
      _studies[next.id] = next;
      _savedAnnos = _copyOf(annos);
      _savedCal = {...mergedCal};
      // Another device's annotations came in with the merge: show them,
      // keeping anything drawn here while this save ran.
      final cameIn =
          !radSameAnnotations(annos, local) || !mapEquals(mergedCal, cal);
      if (cameIn && mounted) {
        setState(() {
          _annos = radMergeAnnotations(
            base: local,
            local: _copyAnnos(),
            remote: annos,
          );
          _cal = radMergeCalibration(
            base: cal,
            local: {..._cal},
            remote: mergedCal,
          );
          _undo.clear();
          _redo.clear();
        });
      }
      if (!_dirty && _lookEdits.isEmpty) unawaited(_checkSynced());
    } catch (_) {
      for (final e in looks.entries) {
        _lookEdits.putIfAbsent(e.key, () => e.value);
      }
      _dirty = true;
      _setSaveState(RadSaveState.failed);
      if (mounted) {
        radToast(
          context,
          "Couldn't save the changes. They'll be saved again shortly.",
        );
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(seconds: 3), _flush);
      }
    } finally {
      _writing = false;
    }
  }

  void _setSaveState(RadSaveState state) {
    if (mounted) _saveState.value = state;
  }

  /// Saved on this device until the sync has sent it; checked again every
  /// few seconds until it has.
  Future<void> _checkSynced() async {
    _syncTimer?.cancel();
    final id = _study?.id ?? widget.studyId;
    final synced = await _repo.isSynced(id);
    if (!mounted || _dirty || _lookEdits.isNotEmpty) return;
    if (synced == null) return;
    _setSaveState(synced ? RadSaveState.synced : RadSaveState.savedHere);
    if (!synced) {
      _syncTimer = Timer(const Duration(seconds: 3), _checkSynced);
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
      _annos[image] = [
        for (final a in _annos[image]!) a.id == id ? change(a) : a,
      ];
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
            .map(
              (f) => RadAiFinding.fromJson(Map<String, dynamic>.from(f as Map)),
            )
            .toList();
      }
    }
    return const [];
  }

  double? _mmPerPxFor(RadPane p) {
    final s = _studies[p.studyId];
    if (s == null) return null;
    if (p.studyId == _study?.id) {
      return _cal[p.imageId] ??
          s.images.where((i) => i.id == p.imageId).firstOrNull?.pixelSpacingMm;
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
  Future<void> commitDraft(
    RadPane pane,
    RadAnnotation draft,
    RadTool tool,
  ) async {
    final s = _study;
    if (s == null || pane.studyId != s.id || pane.imageId.isEmpty) return;
    final imageId = pane.imageId;
    var a = draft;
    if (tool == RadTool.calibrate) {
      if (a.points.length < 2) return;
      final pixels =
          (Offset(a.points[0].x, a.points[0].y) -
                  Offset(a.points[1].x, a.points[1].y))
              .distance;
      if (pixels < 2) return;
      final mm = await askRadCalibration(context, pixels: pixels);
      if (mm == null || !mounted) return;
      _mutate(() => _cal[imageId] = mm / pixels);
      _setTool(_toolBeforeCalibrate);
      radToast(
        context,
        'Calibrated: ${(mm / pixels).toStringAsFixed(4)} mm per pixel',
      );
      return;
    }
    if (a.kind == RadAnnoKind.text) {
      final t = await askRadText(
        context,
        title: 'Add a note',
        label: 'Note',
        action: 'Add',
      );
      if (t == null || !mounted) return;
      a = a.copyWith(text: t);
    } else if (a.kind == RadAnnoKind.toothLabel) {
      // Beside the last one: number it straight away. Shift-click asks.
      final follow = HardwareKeyboard.instance.isShiftPressed
          ? null
          : _followOnTooth(imageId, a);
      final t =
          follow ??
          await pickRadTooth(context, initial: _lastTooth(imageId)?.text ?? '');
      if (t == null || !mounted) return;
      a = a.copyWith(text: t);
    }
    _mutate(() {
      _annos[imageId] = [...?_annos[imageId], a];
      _selectedId = a.id;
    });
  }

  @override
  void beginEdit() {
    _editing = true;
    _snapshot();
  }

  @override
  void updateAnnotation(RadPane pane, RadAnnotation a) {
    final list = _annos[pane.imageId];
    if (list == null) return;
    setState(
      () => _annos[pane.imageId] = [for (final x in list) x.id == a.id ? a : x],
    );
  }

  @override
  void endEdit() {
    _editing = false;
    _scheduleSave();
  }

  @override
  void viewChanged(RadPane pane) {
    if (_link) {
      for (final p in _panes) {
        if (identical(p, pane) || !p.hasImage) continue;
        p.scale = pane.scale;
        p.pan = pane.pan;
        p.touch();
      }
    }
    _checkZoomUpgrade();
  }

  void _checkZoomUpgrade() {
    final toUpgrade = <String>[];
    for (final p in _panes) {
      if (p.hasImage &&
          p.px?.isPreview == true &&
          p.zoom > 0.5 &&
          !_fullQualityIds.contains(p.imageId)) {
        toUpgrade.add(p.imageId);
      }
    }
    if (toUpgrade.isNotEmpty) {
      _upgradeToFull(toUpgrade);
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
  void renameAnnotation(RadAnnotation a, String text) =>
      _update(a.id, (x) => x.copyWith(text: text));

  @override
  void recolorAnnotation(RadAnnotation a, Color color) =>
      _update(a.id, (x) => x.copyWith(colorHex: RadInk.hex(color)));

  @override
  void deleteAnnotation(RadAnnotation a) {
    final image = _imageOf(a.id);
    if (image == null) return;
    _mutate(() {
      _annos[image] = [
        for (final x in _annos[image]!)
          if (x.id != a.id) x,
      ];
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
    if (p.px?.isPreview == true) {
      setState(() => _busy = true);
      try {
        await _upgradeToFull([p.imageId]);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
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
      await _saveStudy(
        (st) => st.copyWith(keyImages: [...st.keyImages, k]),
        audit: 'Marked key image',
      );
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
    _saveStudy(
      (st) => st.copyWith(
        keyImages: [
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
        ],
      ),
    );
  }

  @override
  Future<void> deleteKeyImage(RadKeyImage k) async {
    final s = _study;
    if (s == null) return;
    final ok = await confirmDental(
      context,
      title: 'Remove this key image?',
      body:
          'It is also taken out of the report. You can mark the view again at any time.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await _saveStudy(
      (st) => st.copyWith(
        keyImages: [
          for (final x in st.keyImages)
            if (x.id != k.id) x,
        ],
      ),
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
    _savePrefs({
      RadViewerPrefs.presetsKey: [for (final x in list) x.toJson()],
    });
  }

  @override
  void deletePreset(RadWindowPreset preset) {
    final list = [..._prefs.presets.where((x) => x.name != preset.name)];
    setState(() => _prefs = _prefs.copyWith(presets: list));
    _savePrefs({
      RadViewerPrefs.presetsKey: [for (final x in list) x.toJson()],
    });
  }

  @override
  Future<void> setFilters(RadFilterSettings f) async {
    await _pane.setFilters(f);
    _pane.touch();
    _rememberState();
  }

  @override
  void toggleInvert() {
    // setState too, so the Invert button's highlight follows.
    setState(_pane.toggleInvert);
    _pane.touch();
  }

  /// Picks [t], or goes back to Move when [t] is already the tool: tapping
  /// a highlighted tool switches it off.
  void _toggleTool(RadTool t) =>
      _setTool(_tool == t && t != RadTool.select ? RadTool.select : t);

  @override
  Future<void> resetAdjustments() async {
    final p = _pane;
    p.userInvert = false;
    await p.setFilters(const RadFilterSettings());
    p.resetWindow();
    p.touch();
    _rememberState();
    // Invert's highlight follows the reset.
    if (mounted) setState(() {});
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
      case RadViewerAction.cursorOffset:
        _toggleCursorOffset();
      case RadViewerAction.shortcuts:
        _openShortcuts();
      default:
        break;
    }
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorStateOfType<EditableTextState>() != null);
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
        if (down != null &&
            DateTime.now().difference(down) >
                const Duration(milliseconds: 300)) {
          setState(() => _loupe = false);
        }
        _loupeKey = null;
        _loupeDownAt = null;
      }
      return KeyEventResult.ignored;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;

    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
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
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (draft == null) return KeyEventResult.ignored;
      final min = draft.kind == RadAnnoKind.polygon ? 3 : 2;
      p.draft = null;
      p.draftHover = null;
      p.touch();
      if ((draft.kind == RadAnnoKind.polygon ||
              draft.kind == RadAnnoKind.polyline) &&
          draft.points.length >= min) {
        commitDraft(p, draft, _tool);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (draft != null &&
          key == LogicalKeyboardKey.backspace &&
          draft.points.length > 1) {
        p.draft = draft.copyWith(
          points: draft.points.sublist(0, draft.points.length - 1),
        );
        p.touch();
        return KeyEventResult.handled;
      }
      final id = _selectedId;
      final a = id == null
          ? null
          : _annotationsFor(p).where((x) => x.id == id).firstOrNull;
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
      if ((a.kind != RadAnnoKind.rect && a.kind != RadAnnoKind.ellipse) ||
          a.points.length < 2) {
        return null;
      }
      final xs = a.points.map((q) => q.x), ys = a.points.map((q) => q.y);
      return Rect.fromLTRB(
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      );
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
        final bytes = await radAnonymisedDicom(
          await _ctl.fileOf(s, image.path),
        );
        if (!mounted) return;
        if (bytes == null) {
          radToast(
            context,
            "This DICOM file can't be anonymised (big-endian encoding)",
          );
          return;
        }
        final path = await radSaveBytes(
          dialogTitle: 'Save anonymised DICOM',
          fileName: radSafeName(
            'anonymised ${s.modality.short} ${DateFormat('yyyy-MM-dd').format(s.studyDate)}.dcm',
          ),
          extension: 'dcm',
          bytes: bytes,
        );
        if (path == null) return;
        await _ctl.log(
          'Exported',
          targetKind: 'study',
          targetId: s.id,
          detail: 'Anonymised DICOM of image $index',
        );
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
        final r =
            Rect.fromLTRB(
              box.left * sx,
              box.top * sy,
              box.right * sx,
              box.bottom * sy,
            ).intersect(
              Rect.fromLTWH(
                0,
                0,
                full.width.toDouble(),
                full.height.toDouble(),
              ),
            );
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
        await _ctl.log(
          'Exported',
          targetKind: 'study',
          targetId: s.id,
          detail: 'PNG of an area of image $index',
        );
        if (mounted) radToast(context, 'Area saved');
        return;
      }
      if (kind == _ExportKind.toFiles) {
        await _saveToPatientFiles(s, p, index);
        return;
      }
      final marks =
          kind == _ExportKind.pngMarks || kind == _ExportKind.jpgMarks;
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
        detail:
            '${ext.toUpperCase()} of image $index${marks ? ', with marks' : ''}',
      );
      if (mounted) radToast(context, 'Image saved');
    } catch (_) {
      if (mounted) radToast(context, "Couldn't export the image");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The image as the doctor sees it, marks included, added to the
  /// patient's Files (and from there uploaded) instead of saved to a
  /// folder on this device.
  Future<void> _saveToPatientFiles(RadStudy s, RadPane p, int index) async {
    if (s.patientId.isEmpty) {
      radToast(context, 'Link this study to a patient first');
      return;
    }
    final view = await radRenderPaneView(
      p,
      annotations: _annotationsFor(p),
      mmPerPx: _mmPerPxFor(p),
      withAnnotations: true,
      roi: _roi,
    );
    if (view == null) return;
    final bytes = await radEncodePng(view);
    view.dispose();
    if (bytes == null || !mounted) return;
    final added = await FilesRepository.instance.addFiles([
      FileSource(
        name: '${radExportName(s)}_${index}_marked.png',
        sizeBytes: bytes.lengthInBytes,
        bytes: bytes,
      ),
    ], patientId: s.patientId);
    if (!mounted) return;
    if (added == 0) {
      radToast(context, "Couldn't add it to the patient's files");
      return;
    }
    await _ctl.log(
      'Saved to patient files',
      targetKind: 'study',
      targetId: s.id,
      detail: 'PNG of image $index, with marks',
    );
    if (mounted) radToast(context, "Added to the patient's files");
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
    if (st != null) {
      return '$prefix · Slice ${p.sliceIndex + 1} of ${st.length}';
    }
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
      RadLayout.grid => col([
        row([0, 1]),
        row([2, 3]),
      ]),
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

  /// The desktop toolbar: the group tabs on top (Move · Adjust · Measure ·
  /// Draw · Tooth · View) with global utilities, and the active group's
  /// tools on the row directly below.
  Widget _toolbar(RadStudy s, List<RadStudy> others) {
    final c = context.cru;
    final p = _pane;
    final has = p.hasImage;
    final own = p.studyId == s.id;
    final image = _imageRef(p);

    Widget tool(RadTool t) => RadBarButton(
      icon: t.icon,
      label: t.short,
      tooltip: _tip(t.label, RadViewerAction.values.byName(t.name)),
      selected: _tool == t,
      style: RadBarButtonStyle.tool,
      onPressed: t == RadTool.calibrate
          ? (has && own ? startCalibration : null)
          : () => _toggleTool(t),
    );
    Widget act(
      CruIconData icon,
      String label,
      String tip,
      RadViewerAction a, {
      bool enabled = true,
    }) => RadBarButton(
      icon: icon,
      label: label,
      tooltip: _tip(tip, a),
      onPressed: enabled ? () => _run(a) : null,
    );
    Widget toggle(
      CruIconData icon,
      String label,
      String tip,
      bool on,
      VoidCallback? onPressed,
    ) => RadBarButton(
      icon: icon,
      label: label,
      tooltip: tip,
      selected: on,
      style: RadBarButtonStyle.toggle,
      onPressed: onPressed,
    );
    Widget push(CruIconData icon, String label, String tip, Widget? page) =>
        RadBarButton(
          icon: icon,
          label: label,
          tooltip: tip,
          onPressed: page == null ? null : () => _push(page),
        );
    final magnifier = toggle(
      RadViewerIcons.loupe,
      'Magnifier',
      _tip('Magnifier', RadViewerAction.magnifier),
      _loupe,
      () => setState(() => _loupe = !_loupe),
    );

    final List<Widget> groupTools = switch (_deskGroup) {
      _DeskGroup.move => [
        for (final t in _DeskGroup.move.tools) tool(t),
        const RadBarDivider(),
        act(
          RadViewerIcons.fit,
          'Fit',
          'Fit to pane',
          RadViewerAction.fit,
          enabled: has,
        ),
        magnifier,
        act(
          RadViewerIcons.reset,
          'Reset view',
          'Reset view',
          RadViewerAction.reset,
          enabled: has,
        ),
      ],
      _DeskGroup.adjust => [
        tool(RadTool.window),
        toggle(
          RadViewerIcons.invert,
          'Invert',
          _tip('Invert', RadViewerAction.invert),
          p.userInvert,
          has ? toggleInvert : null,
        ),
        RadMenuButton<RadWindowPreset?>(
          icon: RadViewerIcons.window,
          label: 'Presets',
          tooltip: 'Brightness and contrast presets',
          enabled: has,
          items: () => [
            radMenuItem<RadWindowPreset?>(context, null, 'Default'),
            for (final pr in [...radBuiltInPresets, ..._prefs.presets])
              radMenuItem<RadWindowPreset?>(context, pr, pr.name),
          ],
          onSelected: applyPreset,
        ),
        magnifier,
        RadBarButton(
          icon: RadViewerIcons.reset,
          label: 'Reset',
          tooltip: 'Undo every adjustment on this image',
          onPressed: has ? () => unawaited(resetAdjustments()) : null,
        ),
        const RadBarDivider(),
        RadBarButton(
          icon: RadViewerIcons.panel,
          label: 'Sharpen & more',
          tooltip: 'Sharpening, contrast boost and your own presets',
          onPressed: () => _showPanelTab(RadPanelTab.adjust),
        ),
      ],
      _DeskGroup.measure => [
        for (final t in _DeskGroup.measure.tools) tool(t),
        const RadBarDivider(),
        RadBarButton(
          icon: RadViewerIcons.panel,
          label: 'All measurements',
          tooltip: 'The list of measurements on this image',
          onPressed: () => _showPanelTab(RadPanelTab.measure),
        ),
      ],
      _DeskGroup.draw => [for (final t in _DeskGroup.draw.tools) tool(t)],
      _DeskGroup.tooth => [tool(RadTool.tooth)],
      _DeskGroup.view => [
        act(
          RadViewerIcons.rotate,
          'Rotate',
          'Rotate 90°',
          RadViewerAction.rotate,
          enabled: has,
        ),
        act(
          RadViewerIcons.flipH,
          'Mirror',
          'Flip left–right',
          RadViewerAction.flipH,
          enabled: has,
        ),
        act(
          RadViewerIcons.flipV,
          'Flip',
          'Flip up–down',
          RadViewerAction.flipV,
          enabled: has,
        ),
        const RadBarDivider(),
        RadMenuButton<RadLayout>(
          icon: _layout.icon,
          label: 'Layout',
          tooltip: 'How many images side by side',
          items: () => [
            for (final l in RadLayout.values)
              radMenuItem(
                context,
                l,
                l.label,
                icon: l.icon,
                checked: l == _layout,
              ),
          ],
          onSelected: _setLayout,
        ),
        if (others.isNotEmpty)
          RadMenuButton<String>(
            icon: RadViewerIcons.compare,
            label: 'Compare',
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
            onSelected: (id) => _setCompare(
              id.isEmpty ? null : others.where((o) => o.id == id).firstOrNull,
            ),
          ),
        if (_panes.length > 1)
          toggle(
            RadViewerIcons.link,
            'Link',
            _link ? 'Zoom and pan are linked' : 'Link zoom and pan',
            _link,
            _toggleLink,
          ),
        push(
          RadViewerIcons.subtract,
          'Subtract',
          'Compare two images and show what changed',
          has && own
              ? RadSubtractionScreen(studyId: s.id, imageIdA: p.imageId)
              : null,
        ),
        if (_isCeph(s))
          push(
            RadViewerIcons.ceph,
            'Ceph tracing',
            'Trace landmarks and angles',
            has && own
                ? RadCephScreen(studyId: s.id, imageId: p.imageId)
                : null,
          ),
      ],
    };

    return Container(
      height: radToolbarHeight,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              child: Row(
                children: [
                  CruSegmentedControl<_DeskGroup>(
                    semanticLabel: 'Tool groups',
                    segments: [
                      for (final g in _DeskGroup.values) CruSegment(g, g.label),
                    ],
                    selected: _deskGroup,
                    onChanged: _openGroup,
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
                  RadBarButton(
                    icon: RadViewerIcons.keyImage,
                    tooltip: _tip('Mark key image', RadViewerAction.keyImage),
                    onPressed: has && own && !_busy
                        ? () => _run(RadViewerAction.keyImage)
                        : null,
                  ),
                  RadMenuButton<_ExportKind>(
                    icon: RadViewerIcons.export,
                    tooltip: 'Export',
                    enabled: has && !_busy,
                    items: () => [
                      radMenuItem(
                        context,
                        _ExportKind.toFiles,
                        "Save to patient's files (with marks)",
                        icon: RadViewerIcons.file,
                      ),
                      radMenuItem(
                        context,
                        _ExportKind.pngMarks,
                        'PNG with marks',
                        icon: RadViewerIcons.export,
                      ),
                      radMenuItem(
                        context,
                        _ExportKind.png,
                        'PNG without marks',
                        icon: RadViewerIcons.export,
                      ),
                      radMenuItem(
                        context,
                        _ExportKind.jpgMarks,
                        'JPG with marks',
                        icon: RadViewerIcons.export,
                      ),
                      radMenuItem(
                        context,
                        _ExportKind.jpg,
                        'JPG without marks',
                        icon: RadViewerIcons.export,
                      ),
                      if (_selectedBox(_pane) != null)
                        radMenuItem(
                          context,
                          _ExportKind.area,
                          'PNG of the selected area',
                          icon: RadViewerIcons.export,
                        ),
                      if (image?.kind == RadFileKind.dicom)
                        radMenuItem(
                          context,
                          _ExportKind.dicom,
                          'Anonymised DICOM',
                          icon: RadViewerIcons.file,
                        ),
                    ],
                    onSelected: _export,
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
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.separator),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                child: AnimatedSwitcher(
                  duration: CruMotion.of(context, CruMotion.fast),
                  switchInCurve: CruMotion.curve,
                  switchOutCurve: CruMotion.curve,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: SingleChildScrollView(
                    key: ValueKey(_deskGroup),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        for (var i = 0; i < groupTools.length; i++) ...[
                          if (i > 0 &&
                              groupTools[i] is! RadBarDivider &&
                              groupTools[i - 1] is! RadBarDivider)
                            const SizedBox(width: CruSpace.s4),
                          groupTools[i],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Phone bar ─────────────────────────────

  bool _isCeph(RadStudy s) {
    final image = _imageRef(_pane);
    return s.modality == RadModality.ceph ||
        (image?.seriesDescription.toLowerCase().contains('ceph') ?? false);
  }

  /// The tools as a photo editor lays them out: labelled buttons along the
  /// bottom, groups opening their own row, and a line on how to use the
  /// current tool.
  Widget _phoneBar(RadStudy s, List<RadStudy> others) {
    final p = _pane;
    final has = p.hasImage;
    final own = p.studyId == s.id;
    final group = _phoneGroup;

    void open(_PhoneGroup g) =>
        setState(() => _phoneGroup = group == g ? null : g);
    RadPhoneBarItem tool(RadTool t, {bool enabled = true}) => RadPhoneBarItem(
      icon: t.icon,
      label: t.short,
      selected: _tool == t,
      onTap: !enabled
          ? null
          : t == RadTool.calibrate && _tool != RadTool.calibrate
          ? startCalibration
          : () => _toggleTool(t),
    );
    RadPhoneBarItem act(
      CruIconData icon,
      String label,
      VoidCallback action, {
      bool enabled = true,
      bool selected = false,
    }) => RadPhoneBarItem(
      icon: icon,
      label: label,
      selected: selected,
      onTap: enabled ? action : null,
    );

    const measuring = {
      RadTool.length,
      RadTool.angle,
      RadTool.polygon,
      RadTool.calibrate,
    };
    const drawing = {
      RadTool.arrow,
      RadTool.freehand,
      RadTool.text,
      RadTool.rect,
      RadTool.ellipse,
      RadTool.polyline,
    };

    final items = [
      RadPhoneBarItem(
        icon: RadTool.select.icon,
        label: 'Move',
        selected:
            group == null &&
            {RadTool.select, RadTool.pan, RadTool.zoom}.contains(_tool),
        onTap: () {
          _setTool(RadTool.select);
          setState(() => _phoneGroup = null);
        },
      ),
      RadPhoneBarItem(
        icon: RadTool.window.icon,
        label: 'Adjust',
        selected:
            group == _PhoneGroup.adjust ||
            (group == null && _tool == RadTool.window),
        onTap: () => open(_PhoneGroup.adjust),
      ),
      RadPhoneBarItem(
        icon: RadTool.length.icon,
        label: 'Measure',
        selected:
            group == _PhoneGroup.measure ||
            (group == null && measuring.contains(_tool)),
        onTap: () => open(_PhoneGroup.measure),
      ),
      RadPhoneBarItem(
        icon: RadTool.freehand.icon,
        label: 'Draw',
        selected:
            group == _PhoneGroup.draw ||
            (group == null && drawing.contains(_tool)),
        onTap: () => open(_PhoneGroup.draw),
      ),
      RadPhoneBarItem(
        icon: RadTool.tooth.icon,
        label: 'Tooth',
        selected: group == null && _tool == RadTool.tooth,
        onTap: () {
          _toggleTool(RadTool.tooth);
          setState(() => _phoneGroup = null);
        },
      ),
      RadPhoneBarItem(
        icon: RadViewerIcons.rotate,
        label: 'Rotate',
        selected: group == _PhoneGroup.rotate,
        onTap: () => open(_PhoneGroup.rotate),
      ),
      act(
        RadViewerIcons.fit,
        'Fit',
        () => _run(RadViewerAction.fit),
        enabled: has,
      ),
      act(RadViewerIcons.panel, 'Details', _togglePanel, selected: _phonePanel),
      act(
        RadViewerIcons.export,
        'Export',
        () => _exportSheet(),
        enabled: has && !_busy,
      ),
      RadPhoneBarItem(
        icon: CruIcons.more,
        label: 'More',
        selected: group == _PhoneGroup.more,
        onTap: () => open(_PhoneGroup.more),
      ),
    ];

    final List<RadPhoneBarItem>? sub = switch (group) {
      null => null,
      _PhoneGroup.adjust => [
        tool(RadTool.window, enabled: has),
        act(
          RadViewerIcons.invert,
          'Invert',
          toggleInvert,
          enabled: has,
          selected: p.userInvert,
        ),
        act(
          RadViewerIcons.loupe,
          'Magnifier',
          () => setState(() => _loupe = !_loupe),
          selected: _loupe,
        ),
        act(
          RadViewerIcons.cursorOffset,
          'Offset',
          _toggleCursorOffset,
          selected: _prefs.cursorOffset,
        ),
        act(
          RadViewerIcons.reset,
          'Reset',
          () => _run(RadViewerAction.reset),
          enabled: has,
        ),
      ],
      _PhoneGroup.measure => [
        tool(RadTool.length),
        tool(RadTool.angle),
        tool(RadTool.polygon),
        tool(RadTool.calibrate, enabled: has && own),
      ],
      _PhoneGroup.draw => [
        tool(RadTool.arrow),
        tool(RadTool.freehand),
        tool(RadTool.text),
        tool(RadTool.rect),
        tool(RadTool.ellipse),
        tool(RadTool.polyline),
      ],
      _PhoneGroup.rotate => [
        act(
          RadViewerIcons.rotate,
          'Rotate 90°',
          () => _run(RadViewerAction.rotate),
          enabled: has,
        ),
        act(
          RadViewerIcons.flipH,
          'Mirror',
          () => _run(RadViewerAction.flipH),
          enabled: has,
        ),
        act(
          RadViewerIcons.flipV,
          'Flip',
          () => _run(RadViewerAction.flipV),
          enabled: has,
        ),
      ],
      _PhoneGroup.more => [
        act(
          RadViewerIcons.keyImage,
          'Key image',
          () => _run(RadViewerAction.keyImage),
          enabled: has && own && !_busy,
        ),
        if (others.isNotEmpty)
          act(
            RadViewerIcons.compare,
            'Compare',
            // Tapped again while comparing: stop comparing.
            _compare != null
                ? () => _setCompare(null)
                : () => _compareSheet(others),
            selected: _compare != null,
          ),
        if (_panes.length > 1)
          act(RadViewerIcons.link, 'Link', _toggleLink, selected: _link),
        act(
          RadViewerIcons.subtract,
          'Subtract',
          () => _push(RadSubtractionScreen(studyId: s.id, imageIdA: p.imageId)),
          enabled: has && own,
        ),
        if (_isCeph(s))
          act(
            RadViewerIcons.ceph,
            'Ceph',
            () => _push(RadCephScreen(studyId: s.id, imageId: p.imageId)),
            enabled: has && own,
          ),
        act(
          RadViewerIcons.cursorOffset,
          'Cursor offset',
          _toggleCursorOffset,
          selected: _prefs.cursorOffset,
        ),
        act(
          RadViewerIcons.readingMode,
          'Full screen',
          () => setState(() => _reading = true),
        ),
      ],
    };

    return RadPhoneToolBar(
      hint: _tool.hint,
      items: items,
      subItems: sub,
      onUndo: _undo.isEmpty ? null : _undoStep,
      onRedo: _redo.isEmpty ? null : _redoStep,
    );
  }

  /// A bottom sheet of choices; returns the picked value.
  Future<T?> _sheet<T>(String title, List<(T, String)> choices) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheet) {
        final c = sheet.cru;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s8,
              0,
              CruSpace.s8,
              CruSpace.s16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CruSpace.s16,
                    0,
                    CruSpace.s16,
                    CruSpace.s8,
                  ),
                  child: Text(title, style: CruType.headline.tint(c.label)),
                ),
                for (final (value, label) in choices)
                  ListTile(
                    title: Text(label, style: CruType.text.tint(c.label)),
                    onTap: () => Navigator.pop(sheet, value),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportSheet() async {
    final image = _imageRef(_pane);
    final kind = await _sheet<_ExportKind>('Export', [
      (_ExportKind.toFiles, "Save to patient's files (with marks)"),
      (_ExportKind.pngMarks, 'PNG with marks'),
      (_ExportKind.png, 'PNG without marks'),
      (_ExportKind.jpgMarks, 'JPG with marks'),
      (_ExportKind.jpg, 'JPG without marks'),
      if (_selectedBox(_pane) != null)
        (_ExportKind.area, 'PNG of the selected area'),
      if (image?.kind == RadFileKind.dicom)
        (_ExportKind.dicom, 'Anonymised DICOM'),
    ]);
    if (kind != null && mounted) await _export(kind);
  }

  Future<void> _compareSheet(List<RadStudy> others) async {
    final id = await _sheet<String>('Compare with', [
      for (final o in others)
        (o.id, '${o.modality.short} · ${RadFormat.date(o.studyDate)}'),
      if (_compare != null) ('', 'Stop comparing'),
    ]);
    if (id == null || !mounted) return;
    _setCompare(
      id.isEmpty ? null : others.where((o) => o.id == id).firstOrNull,
    );
  }

  Widget _panel(RadStudy s, RadReport? report, {double? width}) {
    final p = _pane;
    final own = p.studyId == s.id;
    final paneStudy = own
        ? s.copyWith(annotations: _annos, calibration: _cal)
        : (_studies[p.studyId] ?? s);
    final image = _imageRef(p);
    final header = image != null && image.kind == RadFileKind.dicom
        ? _headers.get(
            '${p.studyId}/${image.id}',
            () async =>
                radDicomHeader(await _ctl.fileOf(paneStudy, image.path)),
          )
        : null;
    return Row(
      children: [
        // Phone: no resize handle; the panel takes the width it is given.
        if (width == null)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() {
                _panelWidth = (_panelWidth - d.delta.dx).clamp(
                  RadViewerPrefs.minPanelWidth,
                  RadViewerPrefs.maxPanelWidth,
                );
              }),
              onHorizontalDragEnd: (_) {
                _prefs = _prefs.copyWith(panelWidth: _panelWidth);
                _savePrefs({RadViewerPrefs.panelWidthKey: _panelWidth});
              },
              child: SizedBox(
                width: CruSpace.s6,
                child: ColoredBox(color: context.cru.surface),
              ),
            ),
          ),
        RadViewerSidePanel(
          host: this,
          width: width ?? _panelWidth,
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
    if (s == null) {
      final gone = !async.isLoading && fresh == null && !async.hasError;
      return Scaffold(
        backgroundColor: c.canvas,
        body: Center(
          child: gone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'This study is no longer here',
                      style: CruType.title2.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s12),
                    CruButton(
                      label: 'Back',
                      kind: CruButtonKind.secondary,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                      ),
                    ),
                    const SizedBox(height: CruSpace.s16),
                    Text('Opening study…', style: CruType.text.tint(c.label2)),
                    const SizedBox(height: CruSpace.s16),
                    CruButton(
                      label: 'Cancel',
                      kind: CruButtonKind.secondary,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
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

    final phone = cruIsPhone(context);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        top: phone,
        bottom: false,
        left: false,
        right: false,
        child: Focus(
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
                  saveState: _saveState,
                ),
                if (!phone) _toolbar(s, others),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_reading && _prefs.thumbs && !phone)
                      RadThumbnailStrip(
                        study: s,
                        compare: _compare,
                        cache: _thumbs,
                        shown: {
                          for (final q in _panes)
                            if (q.imageId.isNotEmpty)
                              '${q.studyId}/${q.imageId}',
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
                                child: Text(
                                  'This study has no images yet',
                                  style: CruType.text.tint(RadInk.overlayQuiet),
                                ),
                              ),
                            ),
                          if (_reading)
                            Positioned(
                              top: CruSpace.s12,
                              right: CruSpace.s12,
                              child: _OverlayPill(
                                icon: CruIcons.close,
                                label:
                                    _prefs
                                        .keyFor(RadViewerAction.readingMode)
                                        .isEmpty
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
                              child: Center(
                                child: _OverlayPill(label: 'Working…'),
                              ),
                            )
                          else if (!phone && !_reading)
                            Positioned(
                              left: CruSpace.s16,
                              right: CruSpace.s16,
                              bottom: CruSpace.s16,
                              child: Center(
                                child: _ToolHint(hint: _toolHint()),
                              ),
                            ),
                          if (phone && _phonePanel && !_reading)
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, box) =>
                                    _panel(s, report, width: box.maxWidth),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!_reading && !phone && _prefs.panelOpen)
                      _panel(s, report),
                  ],
                ),
              ),
              if (!_reading && phone) _phoneBar(s, others),
            ],
          ),
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
      decoration: const ShapeDecoration(
        color: RadInk.overlayFill,
        shape: StadiumBorder(),
      ),
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
    return CruPressable(
      onTap: tap,
      semanticLabel: label,
      builder: (context, _) => pill,
    );
  }
}

/// How to use the current tool, at the foot of the image; with an action
/// when a step is missing (Calibrate). Fades between tools.
class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.hint});

  final ({String text, String? action, VoidCallback? onAction})? hint;

  @override
  Widget build(BuildContext context) {
    final h = hint;
    return AnimatedSwitcher(
      duration: CruMotion.of(context, CruMotion.fast),
      switchInCurve: CruMotion.curve,
      switchOutCurve: CruMotion.curve,
      child: h == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(h.text),
              height: CruSize.capsule,
              padding: EdgeInsets.only(
                left: CruSpace.s12,
                right: h.action == null ? CruSpace.s12 : CruSpace.s4,
              ),
              decoration: const ShapeDecoration(
                color: RadInk.overlayFill,
                shape: StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      h.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.w500.tint(RadInk.overlay),
                    ),
                  ),
                  if (h.action != null) ...[
                    const SizedBox(width: CruSpace.s8),
                    CruPressable(
                      onTap: h.onAction,
                      semanticLabel: h.action,
                      builder: (context, hovered) => Container(
                        height: CruSize.capsule - CruSpace.s8,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s10,
                        ),
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(
                          color: context.cru.accent,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          h.action!,
                          style: CruType.caption.w600.tint(
                            context.cru.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
