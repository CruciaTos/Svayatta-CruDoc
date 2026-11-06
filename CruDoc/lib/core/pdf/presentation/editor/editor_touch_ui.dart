import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/pdf/presentation/editor/editor_block_view.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the template editor needs that [CruIcons] doesn't have.
abstract final class EditorIcons {
  static const undo = CruIconData(
    'M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11',
  );
  static const redo = CruIconData(
    'm15 14 5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13',
  );
  static const eye = CruIconData(
    'M2.5 12C4.5 8 8 5.5 12 5.5S19.5 8 21.5 12C19.5 16 16 18.5 12 18.5'
    'S4.5 16 2.5 12z',
    circles: [(12, 12, 2.8)],
  );
  static const eyeOff = CruIconData(
    'M3.5 3.5l17 17M10.5 5.6A9 9 0 0 1 12 5.5c4 0 7.5 2.5 9.5 6.5a13 13 0 0 1'
    '-2.4 3.2M6.7 6.6C4.9 7.8 3.5 9.7 2.5 12c2 4 5.5 6.5 9.5 6.5 1.6 0 3.1-.4'
    ' 4.4-1.1M10 10a2.8 2.8 0 0 0 4 4',
  );
  static const lock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 8 0v2.5',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );
  static const unlock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 7.6-1.7',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );
  static const reset = CruIconData(
    'M3.5 12a8.5 8.5 0 1 0 8.5-8.5 9.2 9.2 0 0 0-6.4 2.6L3.5 8.2M3.5 3.5v4.7'
    'h4.7',
  );
  static const copy = CruIconData(
    'M15.5 8.5V6A2.5 2.5 0 0 0 13 3.5H6A2.5 2.5 0 0 0 3.5 6v7A2.5 2.5 0 0 0 6 '
    '15.5h2.5',
    rects: [(8.5, 8.5, 12, 12, 2.5)],
  );
  static const trash = CruIconData(
    'M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5',
  );
  static const layers = CruIconData(
    'M12 3.5 3.5 8 12 12.5 20.5 8zM3.5 12 12 16.5 20.5 12M3.5 16 12 20.5 '
    '20.5 16',
  );
  static const text = CruIconData('M5 7V5h14v2M12 5v14M9 19h6');
  static const image = CruIconData(
    'M20.5 15.5l-4.5-4.5-8.5 8.5',
    rects: [(3.5, 4.5, 17, 15, 2.5)],
    circles: [(9, 9.5, 1.6)],
  );
  static const line = CruIconData('M4 12h16');
  static const minus = CruIconData('M5 12h14');
  static const chevronUp = CruIconData('m6 14.5 6-6 6 6');
  static const zoomIn = CruIconData(
    'M11 8v6M8 11h6m6 9-4.2-4.2',
    circles: [(11, 11, 6.5)],
  );
  static const zoomOut = CruIconData(
    'M8 11h6m6 9-4.2-4.2',
    circles: [(11, 11, 6.5)],
  );
  static const fit = CruIconData(
    'M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9M20 15v3.5'
    'a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15',
  );
  static const grip = CruIconData(
    '',
    filled: true,
    circles: [
      (9, 6.5, 1.4),
      (15, 6.5, 1.4),
      (9, 12, 1.4),
      (15, 12, 1.4),
      (9, 17.5, 1.4),
      (15, 17.5, 1.4),
    ],
  );
  static const box = CruIconData(
    'M6 6h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z',
  );
  static const qr = CruIconData(
    'M14 14h2.5v2.5H14zM18 18h2.5v2.5H18zM18 14h2.5M14 20.5h1.5',
    rects: [
      (3.5, 3.5, 7, 7, 1.5),
      (13.5, 3.5, 7, 7, 1.5),
      (3.5, 13.5, 7, 7, 1.5),
    ],
  );
}

/// What a block is called in the editor ("Clinic name", "Logo"…).
String editorBlockTitle(DocBlock b) => switch (b.type) {
  DocBlockType.field => docFieldLabel(b.field),
  DocBlockType.text => b.text.trim().isNotEmpty ? b.text.trim() : 'Text',
  DocBlockType.image => switch (b.imageRole) {
    DocImageRole.logo => 'Logo',
    DocImageRole.signature => 'Signature',
    DocImageRole.stamp => 'Personal stamp',
    DocImageRole.clinicStamp => 'Clinic stamp',
    DocImageRole.custom => 'Picture',
  },
  DocBlockType.line => 'Line',
  DocBlockType.box => 'Box',
  DocBlockType.qr => b.qr == 'upi' ? 'UPI QR code' : 'QR code',
  DocBlockType.doctorList => 'All doctors',
};

CruIconData editorBlockIcon(DocBlock b) => switch (b.type) {
  DocBlockType.field || DocBlockType.text => EditorIcons.text,
  DocBlockType.image => EditorIcons.image,
  DocBlockType.line => EditorIcons.line,
  DocBlockType.box => EditorIcons.box,
  DocBlockType.qr => EditorIcons.qr,
  DocBlockType.doctorList => CruIcons.patients,
};

/// One row in [showEditorActions].
class EditorAction {
  const EditorAction(this.label, this.icon, this.onTap);

  final String label;
  final CruIconData icon;
  final VoidCallback onTap;
}

/// A short sheet of actions for one element (from ⋯ or a long press).
Future<void> showEditorActions(
  BuildContext context, {
  required String title,
  required List<EditorAction> actions,
}) {
  final c = context.cru;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: c.surface,
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CruRadius.card)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s8,
          CruSpace.s8,
          CruSpace.s8,
          CruSpace.s12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s12,
                CruSpace.s16,
                CruSpace.s12,
                CruSpace.s8,
              ),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.headline.tint(c.label),
              ),
            ),
            for (final a in actions)
              CruPressable(
                scaleOnPress: false,
                semanticLabel: a.label,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  a.onTap();
                },
                builder: (context, hovered) => AnimatedContainer(
                  duration: CruMotion.of(context, CruMotion.fast),
                  height: CruSize.actionButton + CruSpace.s4,
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                  decoration: ShapeDecoration(
                    color: hovered
                        ? c.hoverFill
                        : c.surface.withValues(alpha: 0),
                    shape: cruShape(CruRadius.control),
                  ),
                  child: Row(
                    children: [
                      CruIcon(
                        a.icon,
                        size: 20,
                        strokeWidth: 1.7,
                        color: c.label2,
                      ),
                      const SizedBox(width: CruSpace.s16),
                      Expanded(
                        child: Text(
                          a.label,
                          style: CruType.row.w500.tint(c.label),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The selected element's panel, like a game's control-layout editor:
/// its name, Size and Transparency, ⋯ for everything else, and Done.
/// Drag the element on the page to move it.
class EditorTunePanel extends StatelessWidget {
  const EditorTunePanel({
    super.key,
    required this.controller,
    required this.onMore,
  });

  final TemplateEditorController controller;

  /// The element's actions (hide, lock, duplicate, settings…).
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final b = controller.selected;
    if (b == null) return const SizedBox.shrink();

    final locked = b.locked;
    final scale = controller.scaleOf(b);
    final maxScale = controller.maxScaleOf(b).clamp(0.5, 2.5).toDouble();
    final transparency = (1 - b.opacity).clamp(0.0, 0.8).toDouble();
    final changed = !locked && controller.isChanged(b);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        editorBlockTitle(b),
                        style: CruType.callout.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Only when there is something to undo for this element.
                    AnimatedSwitcher(
                      duration: CruMotion.of(context, CruMotion.fast),
                      child: changed
                          ? Padding(
                              key: const ValueKey('reset'),
                              padding: const EdgeInsets.only(
                                left: CruSpace.s12,
                              ),
                              child: CruLink(
                                label: 'Reset',
                                onPressed: () => controller.resetBlock(b.id),
                              ),
                            )
                          : locked
                          ? Padding(
                              key: const ValueKey('locked'),
                              padding: const EdgeInsets.only(left: CruSpace.s8),
                              child: Text(
                                'Locked',
                                style: CruType.caption.tint(c.label3),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ],
                ),
              ),
              CruIconButton(
                icon: CruIcons.more,
                size: CruSize.squareButton + CruSpace.s4,
                iconSize: 18,
                semanticLabel: 'More for ${editorBlockTitle(b)}',
                tooltip: 'More',
                onPressed: onMore,
              ),
              const SizedBox(width: CruSpace.s4),
              CruCapsuleButton(
                label: 'Done',
                kind: CruCapsuleKind.tinted,
                onPressed: () => controller.select(null),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s4),
          EditorSlider(
            label: 'Size',
            value: scale.clamp(0.3, maxScale).toDouble(),
            min: 0.3,
            max: maxScale,
            valueText: '${(scale * 100).round()}%',
            enabled: !locked,
            onStart: controller.beginLive,
            onChanged: (v) => controller.setScaleLive(b.id, v),
            onEnd: controller.endLive,
          ),
          EditorSlider(
            label: 'Transparency',
            value: transparency,
            min: 0,
            max: 0.8,
            valueText: '${(transparency * 100).round()}%',
            enabled: !locked,
            onStart: controller.beginLive,
            onChanged: (v) => controller.setTransparencyLive(b.id, v),
            onEnd: controller.endLive,
          ),
        ],
      ),
    );
  }
}

/// A labelled slider with its value at the right (tabular). One undo
/// step per slide: [onStart] checkpoints, [onChanged] updates live.
class EditorSlider extends StatelessWidget {
  const EditorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.enabled,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final bool enabled;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: CruType.subhead.w500.tint(enabled ? c.label2 : c.label3),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: c.accent,
              inactiveTrackColor: c.track,
              disabledActiveTrackColor: c.label3,
              disabledInactiveTrackColor: c.track,
              // White knob in both appearances, so it shows on the track.
              thumbColor: CruBrand.white,
              disabledThumbColor: c.inset,
              overlayColor: c.accent.withValues(alpha: 0.12),
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11,
                elevation: 2,
                pressedElevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Semantics(
              label: label,
              value: valueText,
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                onChangeStart: enabled ? (_) => onStart() : null,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? (_) => onEnd() : null,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: CruType.subhead.w600.tabular.tint(
              enabled ? c.label : c.label3,
            ),
          ),
        ),
        const SizedBox(width: CruSpace.s8),
      ],
    );
  }
}

/// One tool in [EditorToolBar].
class EditorTool {
  const EditorTool(this.label, this.icon, this.onTap);

  final String label;
  final CruIconData icon;

  /// Null shows the tool dimmed.
  final VoidCallback? onTap;
}

/// The bottom bar when nothing is selected: icon over label, like a tab bar.
class EditorToolBar extends StatelessWidget {
  const EditorToolBar({super.key, required this.tools});

  final List<EditorTool> tools;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: EdgeInsets.only(
        top: CruSpace.s6,
        bottom: CruSpace.s6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          for (final tool in tools)
            Expanded(
              child: CruPressable(
                onTap: tool.onTap,
                semanticLabel: tool.label,
                builder: (context, hovered) {
                  final fg = tool.onTap == null ? c.label3 : c.label2;
                  return AnimatedContainer(
                    duration: CruMotion.of(context, CruMotion.fast),
                    curve: CruMotion.curve,
                    margin: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
                    padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                    decoration: ShapeDecoration(
                      color: hovered ? c.hoverFill : c.surface,
                      shape: cruShape(CruRadius.control),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CruIcon(
                          tool.icon,
                          size: 22,
                          strokeWidth: 1.7,
                          color: fg,
                        ),
                        const SizedBox(height: CruSpace.s4),
                        Text(tool.label, style: CruType.micro.tint(fg)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A quiet floating tip over the page.
class EditorHint extends StatelessWidget {
  const EditorHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s14,
        vertical: CruSpace.s8,
      ),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: StadiumBorder(side: BorderSide(color: c.hairline)),
        shadows: c.isEvening ? const [] : c.cardShadow,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: CruType.subhead.w500.tint(c.label2),
      ),
    );
  }
}

/// A small heading over a group of settings in a panel.
class EditorSectionLabel extends StatelessWidget {
  const EditorSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: CruType.groupLabel.tint(c.label3)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// − value + : for millimetres and points.
class EditorStepper extends StatelessWidget {
  const EditorStepper({
    super.key,
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String valueText;

  /// Null dims that side (at its limit, or locked).
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget step(CruIconData icon, VoidCallback? onTap, String semantic) =>
        AnimatedOpacity(
          duration: CruMotion.of(context, CruMotion.fast),
          opacity: onTap == null ? 0.35 : 1,
          child: CruSquareButton(
            icon: icon,
            semanticLabel: semantic,
            onPressed: onTap,
          ),
        );
    return Row(
      children: [
        Expanded(
          child: Text(label, style: CruType.subhead.w500.tint(c.label2)),
        ),
        step(EditorIcons.minus, onMinus, 'Less $label'),
        SizedBox(
          width: 72,
          child: Text(
            valueText,
            textAlign: TextAlign.center,
            style: CruType.callout.tabular.tint(c.label),
          ),
        ),
        step(CruIcons.plus, onPlus, 'More $label'),
      ],
    );
  }
}

/// A chip that is on or off (filters, "applies to").
class EditorChoiceChip extends StatelessWidget {
  const EditorChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = selected ? c.accentText : c.label;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) {
          final fill = selected ? c.accentTint : c.surface;
          return AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            height: CruSize.filterChip,
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
            decoration: ShapeDecoration(
              color: hovered ? cruHoverShade(fill, c) : fill,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected
                      ? c.hairline.withValues(alpha: 0)
                      : c.separator,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  CruIcon(
                    CruIcons.check,
                    size: 14,
                    strokeWidth: 2.2,
                    color: fg,
                  ),
                  const SizedBox(width: CruSpace.s6),
                ],
                Text(
                  label,
                  style: (selected ? CruType.chip.w600 : CruType.chip).tint(fg),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A round colour choice for the printed document (not app colour).
class EditorSwatch extends StatelessWidget {
  const EditorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          width: CruSize.capsule + CruSpace.s2,
          height: CruSize.capsule + CruSpace.s2,
          padding: const EdgeInsets.all(CruSpace.s2 + 1),
          decoration: ShapeDecoration(
            shape: CircleBorder(
              side: BorderSide(
                color: selected ? c.accent : c.inset.withValues(alpha: 0),
                width: 2,
              ),
            ),
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: color,
              shape: CircleBorder(side: BorderSide(color: c.separator)),
            ),
          ),
        ),
      ),
    );
  }
}
