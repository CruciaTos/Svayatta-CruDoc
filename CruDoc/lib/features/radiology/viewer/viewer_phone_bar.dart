import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_prefs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Short names and one-line "how to use it" hints, for the phone bar where
/// there is no hover to show a tooltip.
extension RadToolText on RadTool {
  String get short => switch (this) {
    RadTool.select => 'Move',
    RadTool.pan => 'Pan',
    RadTool.zoom => 'Zoom',
    RadTool.window => 'Contrast',
    RadTool.length => 'Length',
    RadTool.angle => 'Angle',
    RadTool.polygon => 'Area',
    RadTool.ellipse => 'Circle',
    RadTool.rect => 'Box',
    RadTool.polyline => 'Path',
    RadTool.arrow => 'Arrow',
    RadTool.text => 'Note',
    RadTool.freehand => 'Pen',
    RadTool.tooth => 'Tooth',
    RadTool.calibrate => 'Calibrate',
  };

  String get hint => switch (this) {
    RadTool.select =>
      'Drag to move · pinch to zoom · tap a mark to select it · '
          'double-tap to fit',
    RadTool.pan => 'Drag to move the image',
    RadTool.zoom => 'Drag up to zoom in, down to zoom out',
    RadTool.window => 'Drag up or down for brightness, sideways for contrast',
    RadTool.length => 'Drag from one end to the other',
    RadTool.angle => 'Drag the first arm, then tap where the second ends',
    RadTool.polygon => 'Tap around the area · tap the first point to close',
    RadTool.ellipse => 'Drag across the area',
    RadTool.rect => 'Drag across the area',
    RadTool.polyline => 'Tap each point · double-tap to finish',
    RadTool.arrow => 'Drag from the tail to the tip',
    RadTool.text => 'Tap where the note goes',
    RadTool.freehand => 'Draw with one finger',
    RadTool.tooth => 'Tap a tooth to number it',
    RadTool.calibrate => 'Drag along something of known length',
  };
}

/// One button on the phone bar: an icon with its name under it.
class RadPhoneBarItem {
  const RadPhoneBarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final CruIconData icon;
  final String label;

  /// Null when it can't be used right now (greyed out).
  final VoidCallback? onTap;
  final bool selected;
}

/// The viewer's tools on a phone, laid out like a photo editor: a row of
/// labelled buttons along the bottom; a group (Measure, Draw…) opens its
/// own labelled row above it. Over both, a line saying how to use the
/// current tool, with undo and redo.
class RadPhoneToolBar extends StatelessWidget {
  const RadPhoneToolBar({
    super.key,
    required this.hint,
    required this.items,
    this.subItems,
    required this.onUndo,
    required this.onRedo,
  });

  final String hint;
  final List<RadPhoneBarItem> items;

  /// The open group's tools, or null when no group is open.
  final List<RadPhoneBarItem>? subItems;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final sub = subItems;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.separator)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s16,
              CruSpace.s8,
              CruSpace.s8,
              CruSpace.s4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hint,
                    style: CruType.caption.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                CruIconButton(
                  icon: RadViewerIcons.undo,
                  size: CruSize.squareButton,
                  iconSize: 18,
                  semanticLabel: 'Undo',
                  tooltip: 'Undo',
                  onPressed: onUndo,
                ),
                CruIconButton(
                  icon: RadViewerIcons.redo,
                  size: CruSize.squareButton,
                  iconSize: 18,
                  semanticLabel: 'Redo',
                  tooltip: 'Redo',
                  onPressed: onRedo,
                ),
              ],
            ),
          ),
          if (sub != null) ...[
            _Row(items: sub, compact: true),
            Divider(height: 1, thickness: 1, color: c.separator),
          ],
          _Row(items: items, compact: false),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.items, required this.compact});

  final List<RadPhoneBarItem> items;

  /// The open group's row: a little shorter than the main one.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 64 : 68,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        children: [for (final i in items) _Button(item: i)],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.item});

  final RadPhoneBarItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = item.onTap != null;
    final on = item.selected;
    return Semantics(
      selected: on,
      button: true,
      child: CruPressable(
        onTap: item.onTap,
        semanticLabel: item.label,
        scaleOnPress: false,
        builder: (context, _) => SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: CruMotion.of(context, CruMotion.fast),
                curve: CruMotion.curve,
                width: 40,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: on ? c.label : c.label.withValues(alpha: 0),
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: CruIcon(
                  item.icon,
                  size: 20,
                  strokeWidth: 1.8,
                  color: !enabled
                      ? c.label3
                      : on
                      ? c.surface
                      : c.label,
                ),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                item.label,
                style: (on ? CruType.caption.w600 : CruType.caption).tint(
                  enabled ? (on ? c.label : c.label2) : c.label3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
