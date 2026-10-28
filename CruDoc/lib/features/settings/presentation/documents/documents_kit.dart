import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the Documents page needs that [CruIcons] doesn't have.
abstract final class DocIcons {
  static const image = CruIconData(
    'M20.5 15.5l-4.5-4.5-8.5 8.5',
    rects: [(3.5, 4.5, 17, 15, 2.5)],
    circles: [(9, 9.5, 1.6)],
  );

  /// A rubber stamp.
  static const stamp = CruIconData(
    'M10.5 10v4.5M13.5 10v4.5M5 16.5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2V18H5z'
    'M6.5 20.5h11',
    circles: [(12, 7, 3)],
  );

  static const trash = CruIconData(
    'M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5',
  );

  static const lock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 8 0v2.5',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );
}

/// A card's title, a short line under it and an optional control at the
/// right (below the text on a phone).
class DocCardHeader extends StatelessWidget {
  const DocCardHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: CruType.headline.tint(c.label)),
        ),
        if (description != null) ...[
          const SizedBox(height: CruSpace.s4),
          Text(description!, style: CruType.subhead.tint(c.label2)),
        ],
      ],
    );
    if (trailing == null) return text;
    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [text, const SizedBox(height: CruSpace.s16), trailing!],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: CruSpace.s16),
        trailing!,
      ],
    );
  }
}

/// Two fields side by side, stacked on a phone so labels aren't cut off.
/// Without [second] the first keeps half the width on wider screens.
class DocFieldPair extends StatelessWidget {
  const DocFieldPair({super.key, required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          if (second != null) ...[const SizedBox(height: CruSpace.s16), second!],
        ],
      );
    }
    return CruFieldRow(children: [first, second ?? const SizedBox.shrink()]);
  }
}

/// Two items side by side on wider screens, one above the other on a
/// phone with a separator between them.
class DocSplit extends StatelessWidget {
  const DocSplit({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (cruIsPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CruSpace.s16),
            child: CruSeparator(),
          ),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: CruSpace.s24),
        Expanded(child: second),
      ],
    );
  }
}

/// Fields in as many equal columns as fit (one on a phone, up to three).
class DocFieldGrid extends StatelessWidget {
  const DocFieldGrid({
    super.key,
    required this.children,
    this.minColumnWidth = 240,
  });

  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    final phone = cruIsPhone(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = CruSpace.s12;
        final fit = ((constraints.maxWidth + gap) / (minColumnWidth + gap))
            .floor();
        final columns = phone ? 1 : fit.clamp(1, 3);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          if (i > 0) rows.add(const SizedBox(height: CruSpace.s16));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(
                    child: i + j < children.length
                        ? children[i + j]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// A setting that is on or off: title and a short explanation, with the
/// switch at the right. The whole row toggles it.
class DocToggleRow extends StatelessWidget {
  const DocToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null makes it read-only.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        child: CruPressable(
          onTap: enabled ? () => onChanged!(!value) : null,
          scaleOnPress: false,
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: CruType.callout.tint(
                          enabled ? c.label : c.label2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: CruSpace.s2),
                        Text(
                          subtitle!,
                          style: CruType.subhead.tint(c.label2),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s16),
                _Switch(value: value, enabled: enabled, hovered: hovered),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.value,
    required this.enabled,
    required this.hovered,
  });

  final bool value;
  final bool enabled;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final track = value ? c.accent : c.track;
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: CruSpace.s32 + CruSpace.s12,
        height: CruSpace.s24 + CruSpace.s2,
        padding: const EdgeInsets.all(CruSpace.s2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(track, c) : track,
          shape: const StadiumBorder(),
        ),
        child: Container(
          width: CruSpace.s22,
          height: CruSpace.s22,
          decoration: ShapeDecoration(
            color: c.surface,
            shape: const CircleBorder(),
            shadows: c.isEvening ? const [] : c.cardShadow,
          ),
        ),
      ),
    );
  }
}

/// A logo, stamp or signature: a preview on paper (or an empty tile with
/// [emptyIcon]), its name and what it's for, and the actions under them.
class DocImageSlot extends StatelessWidget {
  const DocImageSlot({
    super.key,
    required this.title,
    required this.caption,
    required this.bytes,
    required this.emptyIcon,
    required this.actions,
    this.onRemove,
    this.previewWidth = 88,
  });

  final String title;
  final String caption;
  final Uint8List? bytes;
  final CruIconData emptyIcon;

  /// Upload, Replace, Draw… Inset buttons.
  final List<Widget> actions;

  /// Shows a quiet remove button when there is an image.
  final VoidCallback? onRemove;
  final double previewWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final has = bytes != null;
    final preview = Container(
      width: previewWidth,
      height: CruSize.largeTile + CruSpace.s20,
      padding: const EdgeInsets.all(CruSpace.s6),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        // Printed on white paper in both appearances.
        color: has ? CruBrand.white : c.inset,
        shape: cruShape(
          CruRadius.control,
          side: has ? BorderSide(color: c.separator) : BorderSide.none,
        ),
      ),
      child: has
          ? Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true)
          : CruIcon(emptyIcon, size: 24, strokeWidth: 1.6, color: c.label3),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          image: true,
          label: has ? title : '$title, none yet',
          child: preview,
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: CruType.callout.tint(c.label)),
                  ),
                  if (has && onRemove != null)
                    CruIconButton(
                      icon: DocIcons.trash,
                      size: CruSize.capsule,
                      iconSize: 17,
                      semanticLabel: 'Remove ${title.toLowerCase()}',
                      tooltip: 'Remove',
                      onPressed: onRemove,
                    ),
                ],
              ),
              const SizedBox(height: CruSpace.s2),
              Text(caption, style: CruType.subhead.tint(c.label2)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: CruSpace.s12),
                Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The tab's save action: right-aligned on desktop, full width and
/// thumb-sized on a phone.
class DocSaveBar extends StatelessWidget {
  const DocSaveBar({
    super.key,
    required this.label,
    required this.saving,
    required this.onSave,
  });

  final String label;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final phone = cruIsPhone(context);
    final button = CruButton(
      label: saving ? 'Saving…' : label,
      large: phone,
      expand: phone,
      onPressed: saving ? null : onSave,
    );
    return phone
        ? button
        : Align(alignment: Alignment.centerRight, child: button);
  }
}

/// One entry in a [DocMenu].
class DocMenuItem {
  const DocMenuItem(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

/// A small on-token menu that opens under its button, lined up with the
/// button's right edge so it stays inside the card.
class DocMenu extends StatelessWidget {
  const DocMenu({super.key, required this.items, required this.builder});

  final List<DocMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  static const double _width = 176;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MenuAnchor(
      alignmentOffset: const Offset(-_width, CruSpace.s6),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(
          c.surface.withValues(alpha: 0),
        ),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: item.onSelected,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(_width - CruSpace.s12, CruSize.control),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: CruSpace.s12),
              ),
              shape: WidgetStatePropertyAll(
                RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(
                    CruRadius.control - CruSpace.s6,
                  ),
                ),
              ),
              overlayColor: WidgetStatePropertyAll(
                c.hoverFill.withValues(alpha: 0),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused) ||
                        states.contains(WidgetState.pressed)
                    ? c.hoverFill
                    : c.surface,
              ),
            ),
            child: Text(item.label, style: CruType.text.w500.tint(c.label)),
          ),
      ],
      builder: (context, menu, _) =>
          builder(context, () => menu.isOpen ? menu.close() : menu.open()),
    );
  }
}

/// A quiet note at the top of a tab ("Only clinic admins can change…").
class DocNotice extends StatelessWidget {
  const DocNotice(this.text, {super.key, this.icon = DocIcons.lock});

  final String text;
  final CruIconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          CruIcon(icon, size: 16, strokeWidth: 1.8, color: c.label2),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Text(text, style: CruType.subhead.w500.tint(c.label2)),
          ),
        ],
      ),
    );
  }
}

/// A rendered page on an inset tray: white paper with a hairline edge,
/// at the page's own shape. Empty tray while it renders.
class DocPaperThumb extends StatelessWidget {
  const DocPaperThumb({
    super.key,
    required this.bytes,
    required this.aspectRatio,
    this.radius = CruRadius.control,
    this.padding = CruSpace.s16,
    this.hovered = false,
  });

  final Uint8List? bytes;

  /// Page width ÷ height.
  final double aspectRatio;
  final double radius;
  final double padding;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final page = bytes;
    return AnimatedContainer(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      decoration: ShapeDecoration(
        color: hovered ? cruHoverShade(c.inset, c) : c.inset,
        shape: cruShape(radius),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Center(
          child: AnimatedOpacity(
            duration: CruMotion.of(context, CruMotion.standard),
            curve: CruMotion.curve,
            opacity: page == null ? 0 : 1,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: c.separator),
                ),
                child: ColoredBox(
                  color: CruBrand.white,
                  child: page == null
                      ? const SizedBox.expand()
                      : Image.memory(
                          page,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
