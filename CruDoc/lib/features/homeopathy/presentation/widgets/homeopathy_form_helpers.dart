import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One collapsible section of the case sheet, on the standard card.
/// Green only marks a section as done; nothing else on it is coloured.
class HomeopathyAccordionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isComplete;
  final CruIconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const HomeopathyAccordionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isComplete,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CruRadius.card),
      side: BorderSide(color: c.cardBorder),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s12),
      child: Material(
        color: c.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: c.surface.withValues(alpha: 0),
            splashFactory: NoSplash.splashFactory,
            hoverColor: c.hoverFill,
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            shape: shape,
            collapsedShape: shape,
            backgroundColor: c.surface,
            collapsedBackgroundColor: c.surface,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s20,
              vertical: CruSpace.s8,
            ),
            leading: Container(
              width: CruSize.iconTile,
              height: CruSize.iconTile,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: c.inset,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
              ),
              child: CruIcon(icon, size: 18, color: c.label2),
            ),
            title: Text(title, style: CruType.headline.tint(c.label)),
            subtitle: Text(
              subtitle,
              style: CruType.caption.tint(c.label2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isComplete) ...[
                  const CruDoneBadge(size: 18),
                  const SizedBox(width: CruSpace.s8),
                ],
                CruIcon(CruIcons.chevronDown, size: 16, color: c.label2),
              ],
            ),
            // ExpansionTile centres its children by default.
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            childrenPadding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              0,
              CruSpace.s20,
              CruSpace.s20,
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A labelled case-sheet text field with one neutral dictation mic.
class HomeopathyFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final bool enableVoice;

  const HomeopathyFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.enableVoice = true,
  });

  Future<void> _dictate(BuildContext context) async {
    final text = await HomeopathyVoiceDictationSheet.show(
      context,
      fieldName: label,
      initialText: controller.text,
    );
    if (text != null && text.trim().isNotEmpty) {
      controller.text = controller.text.trim().isEmpty
          ? text.trim()
          : '${controller.text.trim()}\n${text.trim()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CruType.subhead.w500.tint(c.label2)),
        const SizedBox(height: CruSpace.s6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          style: CruType.input.tint(c.label),
          cursorColor: c.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: CruType.input.tint(c.label3),
            // Dictation is recording, not AI, so the mic stays neutral.
            suffixIcon: enableVoice
                ? CruIconButton(
                    icon: CruIcons.mic,
                    iconSize: 16,
                    onPressed: () => _dictate(context),
                    semanticLabel: 'Dictate $label',
                    tooltip: 'Dictate',
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s12,
            ),
            filled: true,
            fillColor: c.inset,
            border: ring(c.inset.withValues(alpha: 0)),
            enabledBorder: ring(c.inset.withValues(alpha: 0)),
            focusedBorder: ring(c.accent),
          ),
        ),
      ],
    );
  }
}

/// A heading above a group of chips inside a section ("Thirst pattern").
class HomeopathyGroupLabel extends StatelessWidget {
  const HomeopathyGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CruType.subhead.w600.tint(context.cru.label));
}

/// Selectable option chip. It sits inside a card, so it uses the inset fill
/// (as anything inset in a card does); accent tint and a tick when picked.
class HomeopathyChoiceChip extends StatelessWidget {
  const HomeopathyChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: () => onSelected(!selected),
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? cruHoverShade(c.inset, c) : c.inset),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                CruIcon(
                  CruIcons.check,
                  size: 14,
                  strokeWidth: 2.2,
                  color: c.accentText,
                ),
                const SizedBox(width: CruSpace.s6),
              ],
              Text(
                label,
                style: selected
                    ? CruType.chip.w600.tint(c.accentText)
                    : CruType.chip.tint(c.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks which questionnaire the sheet shows: General, Children, Female &
/// endocrine or Acute. Suggests one from the patient's age and sex.
class HomeopathyCategorySelector extends StatelessWidget {
  final HomeopathyCaseSheetCategory selectedCategory;
  final ValueChanged<HomeopathyCaseSheetCategory> onCategoryChanged;
  final int patientAge;
  final bool isFemale;

  const HomeopathyCategorySelector({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.patientAge,
    required this.isFemale,
  });

  static const _labels = {
    HomeopathyCaseSheetCategory.general: 'General',
    HomeopathyCaseSheetCategory.children: 'Children',
    HomeopathyCaseSheetCategory.femaleEndocrine: 'Female & endocrine',
    HomeopathyCaseSheetCategory.acute: 'Acute',
  };

  /// A questionnaire worth suggesting for this patient, if it isn't the
  /// one already picked.
  HomeopathyCaseSheetCategory? get _suggestion {
    if (patientAge > 0 &&
        patientAge <= 16 &&
        selectedCategory != HomeopathyCaseSheetCategory.children) {
      return HomeopathyCaseSheetCategory.children;
    }
    if (isFemale &&
        patientAge > 16 &&
        selectedCategory != HomeopathyCaseSheetCategory.femaleEndocrine) {
      return HomeopathyCaseSheetCategory.femaleEndocrine;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final suggestion = _suggestion;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: CruCard(
        padding: const EdgeInsets.all(CruSpace.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Questionnaire',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
                if (suggestion != null)
                  CruLink(
                    label: 'Suggested: ${_labels[suggestion]}',
                    onPressed: () => onCategoryChanged(suggestion),
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CruSegmentedControl<HomeopathyCaseSheetCategory>(
                semanticLabel: 'Questionnaire',
                segments: [
                  for (final entry in _labels.entries)
                    CruSegment(entry.key, entry.value),
                ],
                selected: selectedCategory,
                onChanged: onCategoryChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
