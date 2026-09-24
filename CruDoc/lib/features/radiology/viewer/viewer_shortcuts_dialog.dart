import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_prefs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The shortcut cheat sheet (the ? key). Click a key to rebind it; the
/// mouse buttons and wheel can be remapped too. Every change is passed
/// to [onChanged] with the `settings.viewer` values to save.
Future<void> showRadShortcuts(
  BuildContext context, {
  required RadViewerPrefs prefs,
  required void Function(RadViewerPrefs next, Map<String, dynamic> save) onChanged,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShortcutsDialog(prefs: prefs, onChanged: onChanged),
    );

class _ShortcutsDialog extends StatefulWidget {
  const _ShortcutsDialog({required this.prefs, required this.onChanged});

  final RadViewerPrefs prefs;
  final void Function(RadViewerPrefs next, Map<String, dynamic> save) onChanged;

  @override
  State<_ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<_ShortcutsDialog> {
  late RadViewerPrefs _prefs = widget.prefs;
  RadViewerAction? _listening;
  String? _note;
  final _captureFocus = FocusNode(debugLabel: 'Shortcut capture');

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  void _apply(RadViewerPrefs next, Map<String, dynamic> save) {
    setState(() => _prefs = next);
    widget.onChanged(next, save);
  }

  void _listen(RadViewerAction a) {
    setState(() {
      _listening = _listening == a ? null : a;
      _note = null;
    });
    if (_listening != null) _captureFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final a = _listening;
    if (a == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _listening = null);
      return KeyEventResult.handled;
    }
    final name = radKeyName(e);
    if (name == null) return KeyEventResult.handled;
    final keys = {..._prefs.keys};
    String? note;
    for (final other in RadViewerAction.values) {
      if (other != a && _prefs.keyFor(other).toUpperCase() == name.toUpperCase()) {
        keys[other.name] = '';
        note = '“$name” was ${other.label}; that action has no key now.';
      }
    }
    keys[a.name] = name;
    _apply(_prefs.copyWith(keys: keys), {RadViewerPrefs.keysKey: keys});
    setState(() {
      _listening = null;
      _note = note;
    });
    return KeyEventResult.handled;
  }

  void _resetKeys() {
    _apply(_prefs.copyWith(keys: const {}), {RadViewerPrefs.keysKey: <String, String>{}});
    setState(() {
      _listening = null;
      _note = null;
    });
  }

  static const _groupTitles = {
    RadActionGroup.tools: 'Tools',
    RadActionGroup.view: 'View',
    RadActionGroup.image: 'Images',
    RadActionGroup.panels: 'Panels',
  };

  static const _fixed = [
    ('Pan while held', 'Space'),
    ('Undo', 'Ctrl Z'),
    ('Redo', 'Ctrl Y'),
    ('Delete the selected mark', 'Del'),
    ('Finish an area or path', 'Enter'),
    ('Cancel drawing · leave reading mode', 'Esc'),
    ('Fit to pane', 'Double-click'),
    ('Zoom at the cursor', 'Wheel'),
  ];

  Widget _group(BuildContext context, String title, List<Widget> rows) {
    final c = context.cru;
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s12, CruSpace.s8, CruSpace.s6),
            child: Text(title, style: CruType.groupLabel.tint(c.label3)),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, Widget key) {
    final c = context.cru;
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: CruType.text.tint(c.label)),
            ),
            key,
          ],
        ),
      ),
    );
  }

  Widget _keyButton(BuildContext context, RadViewerAction a) {
    final c = context.cru;
    final listening = _listening == a;
    final key = _prefs.keyFor(a);
    return CruPressable(
      onTap: () => _listen(a),
      semanticLabel: 'Change the key for ${a.label}',
      tooltip: 'Click, then press the new key',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        constraints: const BoxConstraints(minWidth: 32),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: listening ? c.accentTint : (hovered ? cruHoverShade(c.inset, c) : c.inset),
          shape: cruShape(CruRadius.keycap),
        ),
        child: Text(
          listening ? 'Press a key…' : (key.isEmpty ? 'None' : key),
          style: CruType.micro.tabular.tint(
            listening ? c.accentText : (key.isEmpty ? c.label3 : c.label),
          ),
        ),
      ),
    );
  }

  Widget _mouseRow<T>(
    BuildContext context,
    String label,
    List<CruSegment<T>> segments,
    T selected,
    ValueChanged<T> onChanged,
  ) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: CruType.text.tint(c.label))),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CruSegmentedControl<T>(
                segments: segments,
                selected: selected,
                onChanged: onChanged,
                semanticLabel: label,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final drag = [for (final a in RadDragAction.values) CruSegment(a, a.label)];
    return Focus(
      focusNode: _captureFocus,
      onKeyEvent: _onKey,
      child: DentalPanelDialog(
        title: 'Shortcuts and mouse',
        subtitle: 'Click a key to change it',
        leading: const CruIconTile(icon: RadViewerIcons.keyboard, tone: CruTileTone.neutral),
        width: CruSize.formDialog,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: CruSpace.s24,
              children: [
                for (final g in RadActionGroup.values)
                  _group(context, _groupTitles[g]!, [
                    for (final a in RadViewerAction.values.where((a) => a.group == g))
                      _row(context, a.label, _keyButton(context, a)),
                  ]),
                _group(context, 'Always', [
                  for (final (label, key) in _fixed) _row(context, label, CruKeycap(key)),
                ]),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            Padding(
              padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s12, CruSpace.s8, CruSpace.s6),
              child: Text('Mouse', style: CruType.groupLabel.tint(c.label3)),
            ),
            _mouseRow<RadDragAction>(context, 'Right drag', drag, _prefs.right, (v) {
              _apply(_prefs.copyWith(right: v), {RadViewerPrefs.mouseKey: _prefs.mouseJson(right: v)});
            }),
            _mouseRow<RadDragAction>(context, 'Middle drag', drag, _prefs.middle, (v) {
              _apply(_prefs.copyWith(middle: v), {RadViewerPrefs.mouseKey: _prefs.mouseJson(middle: v)});
            }),
            _mouseRow<RadWheelAction>(
              context,
              'Wheel',
              [for (final a in RadWheelAction.values) CruSegment(a, a.label)],
              _prefs.wheel,
              (v) {
                _apply(_prefs.copyWith(wheel: v), {RadViewerPrefs.mouseKey: _prefs.mouseJson(wheel: v)});
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s4, CruSpace.s8, 0),
              child: Text(
                'Left drag always uses the tool you picked. Ctrl + wheel does the other wheel action.',
                style: CruType.caption.tint(c.label2),
              ),
            ),
          ],
        ),
        footer: Row(
          children: [
            Expanded(
              child: Text(
                _note ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CruType.caption.tint(c.label2),
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: 'Reset keys',
              kind: CruButtonKind.secondary,
              onPressed: _prefs.keys.isEmpty ? null : _resetKeys,
            ),
            const SizedBox(width: CruSpace.s10),
            CruButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
