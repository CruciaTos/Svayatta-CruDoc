import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One tickable line in a [CheckListCard].
class CheckItem {
  const CheckItem({
    required this.label,
    required this.checked,
    this.detail,
    this.enabled = true,
    this.onToggle,
  });

  final String label;
  final String? detail;
  final bool checked;

  /// Shown but not changeable (implied, or not yours to give).
  final bool enabled;
  final VoidCallback? onToggle;
}

/// A card of tickable lines, as the dental features picker.
class CheckListCard extends StatelessWidget {
  const CheckListCard({super.key, required this.items});

  final List<CheckItem> items;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const CruSeparator(indent: CruSpace.s16),
            _CheckRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.item});

  final CheckItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = item.enabled && item.onToggle != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: CruType.row.tint(active ? c.label : c.label3),
                ),
                if (item.detail != null) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(item.detail!, style: CruType.caption.tint(c.label3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Checkbox(
            value: item.checked,
            onChanged: active ? (_) => item.onToggle!() : null,
            activeColor: c.accent,
            checkColor: c.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: BorderSide(color: c.separator, width: 1.5),
          ),
        ],
      ),
    );
    return CruPressable(
      onTap: active ? item.onToggle : null,
      builder: (_, _) => row,
    );
  }
}

/// A person or role in a list: grey monogram, name, one detail line, and
/// an optional trailing widget. Tappable when [onTap] is set.
class TeamRow extends StatelessWidget {
  const TeamRow({
    super.key,
    required this.title,
    this.detail,
    this.monogram,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? detail;

  /// Name for the grey monogram; none when null.
  final String? monogram;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      child: Row(
        children: [
          if (monogram != null) ...[
            CruMonogram(
              name: monogram!,
              background: c.inset,
              foreground: c.label2,
            ),
            const SizedBox(width: CruSpace.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.row.tint(c.label)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(detail!, style: CruType.caption.tint(c.label3)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CruSpace.s12),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return CruPressable(onTap: onTap, builder: (_, _) => row);
  }
}

/// A titled card of [TeamRow]s.
class TeamGroupCard extends StatelessWidget {
  const TeamGroupCard({
    super.key,
    required this.title,
    required this.rows,
    this.trailing,
  });

  final String title;
  final List<Widget> rows;

  /// An action right of the title ("New role").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.only(top: CruSpace.s16, bottom: CruSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: CruType.headline.tint(c.label)),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const CruSeparator(indent: CruSpace.s16),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The amber "waiting" pill (an invite not accepted yet).
class WaitingPill extends StatelessWidget {
  const WaitingPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPill(
      text: text,
      background: c.amberTint,
      foreground: c.amberText,
    );
  }
}

void showTeamToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
