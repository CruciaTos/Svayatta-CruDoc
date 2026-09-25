import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dates and times on the dental screens.
abstract final class DentalFormat {
  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  /// "Today", "Yesterday", "Mon 21 Sep".
  static String day(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(now.year, now.month, now.day);
    final diff = b.difference(a).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat(a.year == b.year ? 'EEE d MMM' : 'EEE d MMM yyyy')
        .format(d);
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Fill, ring and number colour of a tooth on the chart.
({Color fill, Color ring, Color text}) toothColors(CruColors c, ToothState s) =>
    switch (s) {
      ToothState.healthy => (fill: c.surface, ring: c.hairline, text: c.label2),
      ToothState.needsCare => (fill: c.amberTint, ring: c.amberTint, text: c.amberText),
      ToothState.treated => (fill: c.greenTint, ring: c.greenTint, text: c.greenText),
      ToothState.missing => (fill: c.inset, ring: c.inset, text: c.label3),
      ToothState.notErupted => (fill: c.inset, ring: c.hairline, text: c.label3),
    };

Widget toothStatePill(CruColors c, ToothState s) {
  final colors = toothColors(c, s);
  return CruPill(
    text: DentalChart.stateLabel(s),
    background: s == ToothState.healthy ? c.inset : colors.fill,
    foreground: s == ToothState.healthy ? c.label2 : colors.text,
  );
}

/// Proposed (grey), Accepted (blue), Done (green), Declined (quiet).
Widget planStatusPill(CruColors c, String status) {
  final s = TreatmentPlanItemStatus.fromString(status);
  return switch (s) {
    TreatmentPlanItemStatus.proposed =>
      CruPill(text: 'Proposed', background: c.inset, foreground: c.label2),
    TreatmentPlanItemStatus.accepted =>
      CruPill(text: 'Accepted', background: c.accentTint, foreground: c.accentText),
    TreatmentPlanItemStatus.invoiced =>
      CruPill(text: 'Invoiced', background: c.greenTint, foreground: c.greenText),
    TreatmentPlanItemStatus.declined =>
      CruPill(text: 'Declined', background: c.inset, foreground: c.label3),
  };
}

/// Planned (grey), In progress (amber), Completed (green).
Widget procedureStatusPill(CruColors c, String status) {
  final s = DentalProcedureStatus.fromString(status);
  return switch (s) {
    DentalProcedureStatus.planned =>
      CruPill(text: 'Planned', background: c.inset, foreground: c.label2),
    DentalProcedureStatus.inProgress =>
      CruPill(text: 'In progress', background: c.amberTint, foreground: c.amberText),
    DentalProcedureStatus.completed =>
      CruPill(text: 'Completed', background: c.greenTint, foreground: c.greenText),
  };
}

/// Pass (green), Fail (red: the load isn't safe to use), Incomplete (amber).
Widget sterilizationPill(CruColors c, String result) {
  final r = SterilizationResult.fromString(result);
  return switch (r) {
    SterilizationResult.pass =>
      CruPill(text: 'Passed', background: c.greenTint, foreground: c.greenText),
    SterilizationResult.fail =>
      CruPill(text: 'Failed', background: c.redTint, foreground: c.redText),
    SterilizationResult.incomplete =>
      CruPill(text: 'Incomplete', background: c.amberTint, foreground: c.amberText),
  };
}

/// "passed", "failed", "incomplete".
String sterilizationWord(String result) =>
    switch (SterilizationResult.fromString(result)) {
      SterilizationResult.pass => 'passed',
      SterilizationResult.fail => 'failed',
      SterilizationResult.incomplete => 'incomplete',
    };

/// A date picker in the app's colours.
Future<DateTime?> pickDentalDate(
  BuildContext context, {
  required DateTime initial,
  String? helpText,
  DateTime? last,
}) {
  final c = context.cru;
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2015),
    lastDate: last ?? DateTime.now().add(const Duration(days: 365)),
    helpText: helpText,
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: Theme.of(ctx).colorScheme.copyWith(
              primary: c.accent,
              onPrimary: c.onAccent,
              surface: c.surface,
              onSurface: c.label,
            ),
      ),
      child: child!,
    ),
  );
}

/// A selectable chip: inset, or ink with a tick when selected.
class DentalChoiceChip extends StatelessWidget {
  const DentalChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.tabular = false,
    this.onSurface = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// On a grey stage: a white chip with a hairline instead of inset.
  final bool onSurface;

  /// A small colour dot before the label (tooth states).
  final Color? dot;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    var style = selected ? CruType.subhead.w600 : CruType.subhead.w500;
    if (tabular) style = style.tabular;
    return Semantics(
      selected: selected,
      button: true,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.chip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
          decoration: ShapeDecoration(
            color: selected
                ? c.label
                : hovered
                    ? cruHoverShade(onSurface ? c.surface : c.inset, c)
                    : onSurface
                        ? c.surface
                        : c.inset,
            shape: StadiumBorder(
              side: onSurface && !selected
                  ? BorderSide(color: c.hairline)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                CruIcon(CruIcons.check,
                    size: 14, strokeWidth: 2.2, color: c.surface),
                const SizedBox(width: CruSpace.s6),
              ] else if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: ShapeDecoration(
                    color: dot,
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: CruSpace.s6),
              ],
              Text(
                label,
                maxLines: 1,
                style: style.tint(selected ? c.surface : c.label2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips that wrap, one per option.
class DentalChipWrap<T> extends StatelessWidget {
  const DentalChipWrap({
    super.key,
    required this.options,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.tabular = false,
  });

  final List<T> options;
  final String Function(T) label;
  final bool Function(T) isSelected;
  final ValueChanged<T> onTap;
  final bool tabular;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: CruSpace.s8,
        runSpacing: CruSpace.s8,
        children: [
          for (final o in options)
            DentalChoiceChip(
              label: label(o),
              selected: isSelected(o),
              tabular: tabular,
              onTap: () => onTap(o),
            ),
        ],
      );
}

/// Page title, one-line subtitle and the header buttons.
class DentalPageHeader extends StatelessWidget {
  const DentalPageHeader({
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: CruType.largeTitle.tint(c.label)),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(
                subtitle,
                style: CruType.text.tabular.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(width: i == 0 ? CruSpace.s24 : CruSpace.s10),
          actions[i],
        ],
      ],
    );
  }
}

/// A search box that sits on the canvas beside the filters.
class DentalSearchField extends StatelessWidget {
  const DentalSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.control,
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, 0, CruSpace.s6, 0),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: c.cardShadow,
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.search, size: 16, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: CruType.subhead.tint(c.label),
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hint: Text(
                  hint,
                  style: CruType.subhead.tint(c.label3),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            CruIconButton(
              icon: CruIcons.close,
              size: CruSize.rowCapsule,
              iconSize: 14,
              semanticLabel: 'Clear search',
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            )
          else
            const SizedBox(width: CruSpace.s8),
        ],
      ),
    );
  }
}

/// A quiet empty state inside a card: icon, what's missing, what to do.
class DentalEmptyState extends StatelessWidget {
  const DentalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final CruIconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s24,
        vertical: CruSpace.s32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.accent),
          const SizedBox(height: CruSpace.s14),
          Text(title,
              style: CruType.headline.tint(c.label),
              textAlign: TextAlign.center),
          const SizedBox(height: CruSpace.s6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              body,
              style: CruType.subhead.tint(c.label2),
              textAlign: TextAlign.center,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s18),
            Wrap(
              spacing: CruSpace.s10,
              runSpacing: CruSpace.s10,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// A group label inside a list card ("Today", "Restorative").
class DentalGroupLabel extends StatelessWidget {
  const DentalGroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s16,
        CruSpace.s12,
        CruSpace.s6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: CruType.groupLabel.tint(c.label3)),
          ),
          if (trailing != null)
            Text(trailing!, style: CruType.caption.tabular.tint(c.label3)),
        ],
      ),
    );
  }
}

/// A tappable list row with hover, like the Transactions rows.
class DentalListRow extends StatelessWidget {
  const DentalListRow({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.minHeight = 56,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: semanticLabel,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        alignment: Alignment.centerLeft,
        decoration: ShapeDecoration(
          color: hovered && onTap != null
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: child,
      ),
    );
  }
}

/// A dialog in the form dialogs' frame for things that save as you go
/// (a treatment plan): header with close, scrolling body, optional footer.
class DentalPanelDialog extends StatelessWidget {
  const DentalPanelDialog({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.leading,
    this.footer,
    this.width = CruSize.formDialog,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget body;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final maxHeight = MediaQuery.sizeOf(context).height - CruSpace.s32 * 2;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      insetPadding: const EdgeInsets.all(CruSpace.s32),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s24,
                CruSpace.s20,
                CruSpace.s16,
                CruSpace.s20,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: CruSpace.s14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: CruType.title2.tint(c.label)),
                        if (subtitle != null) ...[
                          const SizedBox(height: CruSpace.s2),
                          Text(
                            subtitle!,
                            style: CruType.subhead.tint(c.label2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  CruIconButton(
                    icon: CruIcons.close,
                    size: CruSize.squareButton,
                    iconSize: 18,
                    semanticLabel: 'Close',
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const CruSeparator(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s8,
                  CruSpace.s16,
                  CruSpace.s12,
                ),
                child: body,
              ),
            ),
            if (footer != null) ...[
              const CruSeparator(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s24,
                  vertical: CruSpace.s16,
                ),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Delete this cycle?" with Cancel and a quiet destructive action.
Future<bool> confirmDental(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.cru;
      return DentalPanelDialog(
        title: title,
        width: CruSize.dialog + 60,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s8,
            CruSpace.s8,
            CruSpace.s8,
            CruSpace.s4,
          ),
          child: Text(body, style: CruType.text.tint(c.label2)),
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: CruSpace.s10),
            CruButton(
              label: action,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
    },
  );
  return ok == true;
}
