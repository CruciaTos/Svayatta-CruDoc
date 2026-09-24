// Chrome around the image stage for the ceph and subtraction screens: the
// slim top bar, resizable side panels, stage toolbars and sliders.

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/radiology/viewer_plus/plus_canvas.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Fixed sizes of the viewer-plus screens.
abstract final class PlusSize {
  static const double topBar = 60;
  static const double panelMin = 240;
  static const double panelMax = 520;

  /// The grab strip on a panel's inner edge.
  static const double panelHandle = 8;
  static const double stageButton = 34;
  static const double landmarkDot = 22;
  static const double deviationBar = 60;
  static const double deviationBarHeight = 10;
}

/// Tool icons (24-unit viewBox, stroke).
abstract final class PlusIcons {
  static const fit = CruIconData(
    'M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9'
    'M20 15v3.5a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15',
  );

  /// Invert: a circle split in half.
  static const invert = CruIconData('M12 3.5v17', circles: [(12, 12, 8.5)]);

  /// Planes: crossing lines.
  static const planes = CruIconData('M3.5 8.5 20.5 6M3.5 15.5l17 3.5M8.5 3.5l3 17');

  /// Labels: a tag.
  static const labels = CruIconData('M4 4.5h7.5l8 8-7 7-8-8zM8.5 8.5h.01');

  static const ruler = CruIconData(
    'M3.5 16.5 16.5 3.5l4 4-13 13zM7.5 12.5l2 2M10.5 9.5l2 2M13.5 6.5l2 2',
  );

  /// Reset the window.
  static const resetWindow = CruIconData(
    'M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v4h4',
  );

  static const undo = CruIconData('M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11');
  static const redo = CruIconData('M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13');

  /// Key image: a bookmark.
  static const keyImage = CruIconData('M7 3.5h10v17l-5-3.5-5 3.5z');

  /// Skip a landmark.
  static const skip = CruIconData('M6 6l7 6-7 6zM17 6v12');
}

/// Full-screen page header: back, title and subtitle, then [actions]
/// (at most one primary).
class PlusTopBar extends StatelessWidget {
  const PlusTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: PlusSize.topBar,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          CruSquareButton(
            icon: CruIcons.chevronLeft,
            semanticLabel: 'Back',
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.headline.tint(c.label)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: CruSpace.s8), a],
        ],
      ),
    );
  }
}

/// A side panel the doctor can widen or narrow by dragging its inner edge.
/// [onResized] gets the width when the drag ends (to remember it).
class PlusSidePanel extends StatefulWidget {
  const PlusSidePanel({
    super.key,
    required this.width,
    required this.onResized,
    required this.child,
    this.left = false,
  });

  final double width;
  final ValueChanged<double> onResized;
  final Widget child;

  /// On the left of the stage (the handle is on its right edge).
  final bool left;

  @override
  State<PlusSidePanel> createState() => _PlusSidePanelState();
}

class _PlusSidePanelState extends State<PlusSidePanel> {
  late double _width = widget.width;
  bool _dragging = false;

  @override
  void didUpdateWidget(PlusSidePanel old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.width != widget.width) _width = widget.width;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragging = true,
        onHorizontalDragUpdate: (d) => setState(() {
          final delta = widget.left ? d.delta.dx : -d.delta.dx;
          _width = (_width + delta).clamp(PlusSize.panelMin, PlusSize.panelMax);
        }),
        onHorizontalDragEnd: (_) {
          _dragging = false;
          widget.onResized(_width);
        },
        child: SizedBox(
          width: PlusSize.panelHandle,
          child: Center(
            child: Container(width: 1, color: c.separator),
          ),
        ),
      ),
    );
    final body = ColoredBox(
      color: c.surface,
      child: SizedBox(width: _width, child: widget.child),
    );
    return ColoredBox(
      color: c.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: widget.left ? [body, handle] : [handle, body],
      ),
    );
  }
}

/// A group of stage buttons on a dark scrim.
class PlusStageBar extends StatelessWidget {
  const PlusStageBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s4),
      decoration: ShapeDecoration(
        color: PlusStage.scrim,
        shape: cruShape(CruRadius.control, side: BorderSide(color: PlusStage.ink.hairline)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A thin divider between groups on a [PlusStageBar].
class PlusStageDivider extends StatelessWidget {
  const PlusStageDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: CruSpace.s20,
        margin: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
        color: PlusStage.ink.separator,
      );
}

/// An icon button on the stage. [active] marks a toggle that is on.
class PlusStageButton extends StatelessWidget {
  const PlusStageButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final CruIconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const ink = PlusStage.ink;
    final enabled = onTap != null;
    return Semantics(
      toggled: active,
      child: CruPressable(
        onTap: onTap,
        tooltip: tooltip,
        semanticLabel: tooltip,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: PlusSize.stageButton,
          height: PlusSize.stageButton,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: active
                ? ink.track
                : hovered
                    ? ink.inset
                    : ink.inset.withValues(alpha: 0),
            shape: cruShape(CruRadius.iconTile),
          ),
          child: CruIcon(
            icon,
            size: 18,
            strokeWidth: 1.8,
            color: !enabled ? ink.label3.withValues(alpha: 0.5) : (active ? ink.label : ink.label2),
          ),
        ),
      ),
    );
  }
}

/// Text on the stage (readouts, prompts), in a scrim box.
class PlusStageNote extends StatelessWidget {
  const PlusStageNote({super.key, required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    const ink = PlusStage.ink;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s8),
      decoration: ShapeDecoration(
        color: PlusStage.scrim,
        shape: cruShape(CruRadius.control, side: BorderSide(color: ink.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CruType.subhead.w600.tabular.tint(ink.label)),
          if (body != null && body!.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s2),
            Text(body!, style: CruType.caption.tint(ink.label2)),
          ],
        ],
      ),
    );
  }
}

/// A plain readout in a stage corner ("W 2400 · C 1200 · 85%").
class PlusStageReadout extends StatelessWidget {
  const PlusStageReadout(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CruType.micro.tabular.copyWith(
          color: PlusStage.ink.label2,
          shadows: PlusStage.textShadow,
        ),
      );
}

/// Centre-of-stage state: loading, or why the image can't be shown.
class PlusStageMessage extends StatelessWidget {
  const PlusStageMessage({super.key, required this.title, this.body, this.loading = false});

  final String title;
  final String? body;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const ink = PlusStage.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              SizedBox(
                width: CruSpace.s24,
                height: CruSpace.s24,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink.label2),
              ),
              const SizedBox(height: CruSpace.s12),
            ],
            Text(title, textAlign: TextAlign.center, style: CruType.callout.tint(ink.label)),
            if (body != null) ...[
              const SizedBox(height: CruSpace.s4),
              Text(body!, textAlign: TextAlign.center, style: CruType.caption.tint(ink.label2)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section heading inside a side panel.
class PlusPanelLabel extends StatelessWidget {
  const PlusPanelLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s20, bottom: CruSpace.s8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: CruType.groupLabel.tint(c.label2))),
          ?trailing,
        ],
      ),
    );
  }
}

/// A labelled slider with its value on the right.
class PlusSlider extends StatelessWidget {
  const PlusSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double v) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: CruType.subhead.tint(c.label))),
            Text(format(value), style: CruType.subhead.w500.tabular.tint(c.label2)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: c.label2,
            inactiveTrackColor: c.track,
            thumbColor: c.label,
            overlayColor: c.label.withValues(alpha: 0.08),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}
