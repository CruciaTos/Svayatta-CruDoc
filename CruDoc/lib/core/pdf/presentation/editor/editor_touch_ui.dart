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

/// The selected element's panel, like a game's control-layout editor:
/// its name, a Size and a Transparency slider, and quick actions. Drag
/// the element on the page to move it.
class EditorTunePanel extends StatelessWidget {
  const EditorTunePanel({
    super.key,
    required this.controller,
    required this.onMore,
    required this.onHide,
  });

  final TemplateEditorController controller;

  /// Every other setting (field, text, bold, colour, nudge…).
  final VoidCallback onMore;

  /// Hidden elements come back from the Elements list.
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final b = controller.selected;
    if (b == null) return const SizedBox.shrink();

    final locked = b.locked;
    final isText =
        b.type == DocBlockType.field ||
        b.type == DocBlockType.text ||
        b.type == DocBlockType.doctorList;
    final zone = b.zone == DocZone.header ? 'Header' : 'Footer';
    final subtitle = [
      zone,
      if (isText) '${b.fontPt.toStringAsFixed(b.fontPt % 1 == 0 ? 0 : 1)} pt',
      if (locked) 'Locked',
    ].join(' · ');

    final scale = controller.scaleOf(b);
    final maxScale = controller.maxScaleOf(b).clamp(0.5, 2.5).toDouble();
    final transparency = (1 - b.opacity).clamp(0.0, 0.8).toDouble();
    final custom =
        !b.id.startsWith('builtin.') && !controller.template.isBuiltin;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s12,
        CruSpace.s8,
        CruSpace.s12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIconTile(icon: editorBlockIcon(b), tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editorBlockTitle(b),
                      style: CruType.callout.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      subtitle,
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruIconButton(
                icon: CruIcons.more,
                size: CruSize.squareButton + CruSpace.s4,
                iconSize: 18,
                semanticLabel: 'More settings',
                tooltip: 'More settings',
                onPressed: onMore,
              ),
              const SizedBox(width: CruSpace.s4),
              CruCapsuleButton(
                label: 'Done',
                kind: CruCapsuleKind.tinted,
                onPressed: () => controller.select(null),
              ),
              const SizedBox(width: CruSpace.s8),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          _TuneSlider(
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
          _TuneSlider(
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
          const SizedBox(height: CruSpace.s8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Action(
                  label: 'Hide',
                  icon: EditorIcons.eyeOff,
                  onPressed: onHide,
                ),
                const SizedBox(width: CruSpace.s8),
                _Action(
                  label: locked ? 'Unlock' : 'Lock',
                  icon: locked ? EditorIcons.unlock : EditorIcons.lock,
                  onPressed: () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(locked: !o.locked),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                _Action(
                  label: 'Reset',
                  icon: EditorIcons.reset,
                  onPressed: !locked && controller.isChanged(b)
                      ? () => controller.resetBlock(b.id)
                      : null,
                ),
                const SizedBox(width: CruSpace.s8),
                _Action(
                  label: 'Duplicate',
                  icon: EditorIcons.copy,
                  onPressed: controller.duplicateSelected,
                ),
                if (custom) ...[
                  const SizedBox(width: CruSpace.s8),
                  _Action(
                    label: 'Delete',
                    icon: EditorIcons.trash,
                    onPressed: controller.deleteSelected,
                  ),
                ],
                const SizedBox(width: CruSpace.s8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A capsule action, dimmed when it can't be used right now.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final CruIconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: onPressed == null ? 0.4 : 1,
      child: CruCapsuleButton(
        label: label,
        icon: icon,
        large: true,
        height: CruSize.filterChip,
        onPressed: onPressed,
      ),
    );
  }
}

class _TuneSlider extends StatelessWidget {
  const _TuneSlider({
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
              thumbColor: c.surface,
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
