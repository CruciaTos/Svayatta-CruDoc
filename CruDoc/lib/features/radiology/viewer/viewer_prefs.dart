import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What a left-drag on the image does.
enum RadTool {
  select('Select', RadViewerIcons.select),
  pan('Pan', RadViewerIcons.pan),
  zoom('Zoom', RadViewerIcons.zoom),
  window('Brightness / contrast', RadViewerIcons.window),
  length('Length', RadViewerIcons.length),
  angle('Angle', RadViewerIcons.angle),
  polygon('Area', RadViewerIcons.polygon),
  ellipse('Ellipse ROI', RadViewerIcons.ellipse),
  rect('Rectangle ROI', RadViewerIcons.rect),
  polyline('Path', RadViewerIcons.polyline),
  arrow('Arrow', RadViewerIcons.arrow),
  text('Note', RadViewerIcons.text),
  freehand('Pen', RadViewerIcons.pen),
  tooth('Tooth number', RadViewerIcons.tooth),
  calibrate('Calibrate', RadViewerIcons.calibrate);

  const RadTool(this.label, this.icon);
  final String label;
  final CruIconData icon;

  /// The annotation it draws; null for navigation tools. Calibrate draws
  /// a length line that becomes the calibration, not an annotation.
  RadAnnoKind? get kind => switch (this) {
        length || calibrate => RadAnnoKind.length,
        angle => RadAnnoKind.angle,
        polygon => RadAnnoKind.polygon,
        ellipse => RadAnnoKind.ellipse,
        rect => RadAnnoKind.rect,
        polyline => RadAnnoKind.polyline,
        arrow => RadAnnoKind.arrow,
        text => RadAnnoKind.text,
        freehand => RadAnnoKind.freehand,
        tooth => RadAnnoKind.toothLabel,
        _ => null,
      };

  bool get draws => kind != null;

  static RadTool fromName(Object? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => select);
}

/// Pane arrangements.
enum RadLayout {
  one('1 × 1', 1, RadViewerIcons.layout1x1),
  sideBySide('1 × 2', 2, RadViewerIcons.layout1x2),
  stacked('2 × 1', 2, RadViewerIcons.layout2x1),
  grid('2 × 2', 4, RadViewerIcons.layout2x2),
  onePlusThree('1 + 3', 4, RadViewerIcons.layout1p3);

  const RadLayout(this.label, this.panes, this.icon);
  final String label;
  final int panes;
  final CruIconData icon;

  static RadLayout fromName(Object? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => one);
}

/// What a right or middle drag does.
enum RadDragAction {
  window('Brightness / contrast'),
  pan('Pan'),
  zoom('Zoom');

  const RadDragAction(this.label);
  final String label;

  static RadDragAction fromName(Object? name, RadDragAction fallback) =>
      values.firstWhere((a) => a.name == name, orElse: () => fallback);
}

/// What the mouse wheel does (Ctrl + wheel does the other).
enum RadWheelAction {
  zoom('Zoom'),
  scroll('Frames and images');

  const RadWheelAction(this.label);
  final String label;

  static RadWheelAction fromName(Object? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => zoom);
}

enum RadActionGroup { tools, view, image, panels }

/// Everything a single key can do. The doctor can rebind each one in the
/// shortcuts dialog.
enum RadViewerAction {
  select('Select', 'V', RadActionGroup.tools),
  pan('Pan', 'H', RadActionGroup.tools),
  zoom('Zoom', 'Z', RadActionGroup.tools),
  window('Brightness / contrast', 'W', RadActionGroup.tools),
  length('Length', 'L', RadActionGroup.tools),
  angle('Angle', 'A', RadActionGroup.tools),
  polygon('Area', 'P', RadActionGroup.tools),
  ellipse('Ellipse ROI', 'E', RadActionGroup.tools),
  rect('Rectangle ROI', 'R', RadActionGroup.tools),
  polyline('Path', 'U', RadActionGroup.tools),
  arrow('Arrow', 'O', RadActionGroup.tools),
  text('Note', 'T', RadActionGroup.tools),
  freehand('Pen', 'D', RadActionGroup.tools),
  tooth('Tooth number', 'N', RadActionGroup.tools),
  calibrate('Calibrate', 'C', RadActionGroup.tools),
  magnifier('Magnifier (hold or tap)', 'M', RadActionGroup.view),
  fit('Fit to pane', 'F', RadActionGroup.view),
  invert('Invert', 'I', RadActionGroup.view),
  rotate('Rotate 90°', 'Q', RadActionGroup.view),
  flipH('Flip left–right', 'X', RadActionGroup.view),
  flipV('Flip up–down', 'Y', RadActionGroup.view),
  reset('Reset view', '0', RadActionGroup.view),
  readingMode('Reading mode', 'F11', RadActionGroup.view),
  keyImage('Mark key image', 'K', RadActionGroup.image),
  nextImage('Next image', 'Page Down', RadActionGroup.image),
  prevImage('Previous image', 'Page Up', RadActionGroup.image),
  nextFrame('Next frame', ']', RadActionGroup.image),
  prevFrame('Previous frame', '[', RadActionGroup.image),
  thumbnails('Thumbnails', 'B', RadActionGroup.panels),
  panel('Side panel', 'J', RadActionGroup.panels),
  shortcuts('Shortcuts', '?', RadActionGroup.panels);

  const RadViewerAction(this.label, this.defaultKey, this.group);
  final String label;
  final String defaultKey;
  final RadActionGroup group;

  /// The tool this action picks, if it's a tool.
  RadTool? get tool => group == RadActionGroup.tools ? RadTool.fromName(name) : null;
}

/// The name a key press is stored under: the printed character in
/// upper case ("L", "?", "0"), else the key's label ("F11", "Page Down").
/// Null for keys that can't be bound (Space, modifiers).
String? radKeyName(KeyEvent e) {
  final key = e.logicalKey;
  if (key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.tab ||
      key == LogicalKeyboardKey.delete ||
      key == LogicalKeyboardKey.backspace) {
    return null;
  }
  if (HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    return null;
  }
  final modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };
  if (modifiers.contains(key)) return null;
  final ch = e.character;
  if (ch != null && ch.length == 1) {
    final code = ch.codeUnitAt(0);
    if (code > 32 && code < 127) return ch.toUpperCase();
  }
  final label = key.keyLabel;
  return label.isEmpty ? null : label;
}

/// The doctor's viewer preferences, kept in `settings.viewer` under
/// `v2d.` keys: key bindings, mouse buttons, custom window presets,
/// panel sizes and the last state per study type.
class RadViewerPrefs {
  const RadViewerPrefs({
    this.keys = const {},
    this.right = RadDragAction.window,
    this.middle = RadDragAction.pan,
    this.wheel = RadWheelAction.zoom,
    this.presets = const [],
    this.panelWidth = defaultPanelWidth,
    this.panelOpen = true,
    this.thumbs = true,
    this.states = const {},
  });

  static const defaultPanelWidth = 320.0;
  static const minPanelWidth = 280.0;
  static const maxPanelWidth = 560.0;

  /// Rebound keys by action name ('' = no key).
  final Map<String, String> keys;
  final RadDragAction right;
  final RadDragAction middle;
  final RadWheelAction wheel;
  final List<RadWindowPreset> presets;
  final double panelWidth;
  final bool panelOpen;
  final bool thumbs;

  /// Last state by study type name: layout, tool, link, tab.
  final Map<String, Map<String, dynamic>> states;

  static const keysKey = 'v2d.keys';
  static const mouseKey = 'v2d.mouse';
  static const presetsKey = 'v2d.presets';
  static const panelWidthKey = 'v2d.panelWidth';
  static const panelOpenKey = 'v2d.panelOpen';
  static const thumbsKey = 'v2d.thumbs';
  static String stateKey(RadModality m) => 'v2d.state.${m.name}';

  factory RadViewerPrefs.from(Map<String, dynamic> v) {
    final keys = v[keysKey];
    final mouse = v[mouseKey];
    final presets = v[presetsKey];
    final states = <String, Map<String, dynamic>>{};
    for (final e in v.entries) {
      if (e.key.startsWith('v2d.state.') && e.value is Map) {
        states[e.key.substring('v2d.state.'.length)] = Map<String, dynamic>.from(e.value as Map);
      }
    }
    final width = v[panelWidthKey];
    return RadViewerPrefs(
      keys: keys is Map ? {for (final e in keys.entries) '${e.key}': '${e.value}'} : const {},
      right: RadDragAction.fromName(mouse is Map ? mouse['right'] : null, RadDragAction.window),
      middle: RadDragAction.fromName(mouse is Map ? mouse['middle'] : null, RadDragAction.pan),
      wheel: RadWheelAction.fromName(mouse is Map ? mouse['wheel'] : null),
      presets: presets is List
          ? [for (final p in presets) ?RadWindowPreset.fromJson(p)]
          : const [],
      panelWidth: width is num
          ? width.toDouble().clamp(minPanelWidth, maxPanelWidth)
          : defaultPanelWidth,
      panelOpen: v[panelOpenKey] != false,
      thumbs: v[thumbsKey] != false,
      states: states,
    );
  }

  String keyFor(RadViewerAction a) => keys[a.name] ?? a.defaultKey;

  RadViewerAction? actionFor(String key) {
    for (final a in RadViewerAction.values) {
      if (keyFor(a).toUpperCase() == key.toUpperCase()) return a;
    }
    return null;
  }

  Map<String, dynamic> stateFor(RadModality m) => states[m.name] ?? const {};

  Map<String, dynamic> mouseJson({RadDragAction? right, RadDragAction? middle, RadWheelAction? wheel}) =>
      {
        'right': (right ?? this.right).name,
        'middle': (middle ?? this.middle).name,
        'wheel': (wheel ?? this.wheel).name,
      };

  RadViewerPrefs copyWith({
    Map<String, String>? keys,
    RadDragAction? right,
    RadDragAction? middle,
    RadWheelAction? wheel,
    List<RadWindowPreset>? presets,
    double? panelWidth,
    bool? panelOpen,
    bool? thumbs,
    Map<String, Map<String, dynamic>>? states,
  }) =>
      RadViewerPrefs(
        keys: keys ?? this.keys,
        right: right ?? this.right,
        middle: middle ?? this.middle,
        wheel: wheel ?? this.wheel,
        presets: presets ?? this.presets,
        panelWidth: panelWidth ?? this.panelWidth,
        panelOpen: panelOpen ?? this.panelOpen,
        thumbs: thumbs ?? this.thumbs,
        states: states ?? this.states,
      );
}
