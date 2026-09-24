import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Height of the tool row under the top bar.
const radToolbarHeight = 52.0;

enum RadBarButtonStyle {
  /// A tool: filled dark when it's the active tool.
  tool,

  /// An on/off switch (loupe, link, panels): inset fill when on.
  toggle,

  /// A one-shot action.
  action,
}

/// A 36 px square icon button for the viewer toolbar.
class RadBarButton extends StatelessWidget {
  const RadBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.style = RadBarButtonStyle.action,
  });

  final CruIconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final RadBarButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = onPressed != null;
    final toolOn = selected && style == RadBarButtonStyle.tool;
    final toggleOn = selected && style == RadBarButtonStyle.toggle;
    return Semantics(
      selected: selected,
      button: true,
      child: CruPressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        tooltip: tooltip,
        scaleOnPress: false,
        builder: (context, hovered) {
          final fill = toolOn
              ? c.label
              : toggleOn
                  ? c.inset
                  : hovered
                      ? c.hoverFill
                      : c.hoverFill.withValues(alpha: 0);
          return AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            width: CruSize.squareButton,
            height: CruSize.squareButton,
            alignment: Alignment.center,
            decoration: ShapeDecoration(color: fill, shape: cruShape(CruRadius.iconTile)),
            child: CruIcon(
              icon,
              size: 18,
              strokeWidth: 1.8,
              color: !enabled
                  ? c.label3
                  : toolOn
                      ? c.surface
                      : toggleOn || hovered
                          ? c.label
                          : c.label2,
            ),
          );
        },
      ),
    );
  }
}

/// A toolbar icon button that opens a menu below itself.
class RadMenuButton<T> extends StatelessWidget {
  const RadMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.selected = false,
    this.enabled = true,
  });

  final CruIconData icon;
  final String tooltip;
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;
  final bool selected;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset(0, box.size.height + CruSpace.s4), ancestor: overlay);
    final v = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        overlay.size.height - topLeft.dy,
      ),
      items: items(),
    );
    if (v != null) onSelected(v);
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) => RadBarButton(
          icon: icon,
          tooltip: tooltip,
          selected: selected,
          style: RadBarButtonStyle.toggle,
          onPressed: enabled ? () => _open(context) : null,
        ),
      );
}

/// One row of a toolbar menu: icon, label and an optional key hint.
PopupMenuItem<T> radMenuItem<T>(
  BuildContext context,
  T value,
  String label, {
  CruIconData? icon,
  String? hint,
  bool checked = false,
  bool enabled = true,
}) {
  final c = context.cru;
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: 40,
    child: Row(
      children: [
        if (icon != null) ...[
          CruIcon(icon, size: 17, strokeWidth: 1.8, color: enabled ? c.label2 : c.label3),
          const SizedBox(width: CruSpace.s10),
        ],
        Expanded(
          child: Text(label, style: CruType.text.tint(enabled ? c.label : c.label3)),
        ),
        if (hint != null) ...[
          const SizedBox(width: CruSpace.s12),
          Text(hint, style: CruType.caption.tabular.tint(c.label3)),
        ],
        if (checked) ...[
          const SizedBox(width: CruSpace.s12),
          CruIcon(CruIcons.check, size: 16, strokeWidth: 2.2, color: c.label),
        ],
      ],
    ),
  );
}

/// A thin divider between toolbar groups.
class RadBarDivider extends StatelessWidget {
  const RadBarDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        child: SizedBox(
          width: 1,
          height: 22,
          child: ColoredBox(color: context.cru.separator),
        ),
      );
}

/// The slim top bar: back, who and what the study is, and the Report
/// button (the page's one primary action).
class RadViewerTopBar extends StatelessWidget {
  const RadViewerTopBar({
    super.key,
    required this.study,
    required this.referrer,
    required this.report,
    required this.onBack,
    required this.onReport,
    required this.onShortcuts,
    required this.shortcutsKey,
    this.onOpen3d,
  });

  final RadStudy study;
  final String? referrer;
  final RadReport? report;
  final VoidCallback onBack;
  final VoidCallback onReport;
  final VoidCallback onShortcuts;
  final String shortcutsKey;

  /// Opens the 3D view; null hides the button (not a volume).
  final VoidCallback? onOpen3d;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = study;
    final who = RadFormat.patientLine(s, DateTime.now());
    final meta = [
      RadFormat.date(s.studyDate),
      if (referrer != null && referrer!.isNotEmpty) 'Referred by $referrer',
    ].join(' · ');
    final r = report;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          CruIconButton(
            icon: CruIcons.chevronLeft,
            size: CruSize.control,
            semanticLabel: 'Back',
            tooltip: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: CruSpace.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.patientName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: CruType.headline.tint(c.label)),
                if (who.isNotEmpty)
                  Text(who, maxLines: 1, style: CruType.caption.tabular.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          RadModalityBadge(s.modality),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: CruType.caption.tabular.tint(c.label2)),
                if (s.clinicalQuestion.isNotEmpty)
                  Text(
                    s.clinicalQuestion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.w500.tint(c.label),
                  ),
              ],
            ),
          ),
          if (s.critical) ...[
            CruPill(text: 'Critical finding', background: c.redTint, foreground: c.redText),
            const SizedBox(width: CruSpace.s8),
          ],
          if (r != null) ...[
            radReportStatusPill(c, r.status),
            const SizedBox(width: CruSpace.s8),
          ],
          if (onOpen3d != null) ...[
            CruButton(
              label: '3D',
              icon: RadIcons.cube,
              kind: CruButtonKind.secondary,
              onPressed: onOpen3d,
            ),
            const SizedBox(width: CruSpace.s8),
          ],
          CruIconButton(
            icon: RadViewerIcons.keyboard,
            size: CruSize.control,
            iconSize: 19,
            semanticLabel: 'Shortcuts',
            tooltip: shortcutsKey.isEmpty ? 'Shortcuts' : 'Shortcuts ($shortcutsKey)',
            onPressed: onShortcuts,
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(label: 'Report', icon: RadIcons.report, onPressed: onReport),
        ],
      ),
    );
  }
}
