import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const Color _accentEmerald = Color(0xFF059669);

/// Reusable accordion card for homeopathic case taking sections.
class HomeopathyAccordionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isComplete;
  final IconData icon;
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
    return Container(
      margin: const EdgeInsets.only(bottom: CruSpace.s12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(
          color: isComplete
              ? c.green.withValues(alpha: 0.35)
              : c.separator,
          width: isComplete ? 1.5 : 1,
        ),
        boxShadow: const [],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s16,
            vertical: CruSpace.s4,
          ),
          leading: Container(
            width: CruSize.iconTile,
            height: CruSize.iconTile,
            decoration: BoxDecoration(
              color: isComplete ? c.greenTint : c.inset,
              borderRadius: BorderRadius.circular(CruRadius.iconTile),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isComplete ? c.greenText : c.label3,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(title, style: CruType.callout.w700.tint(c.label)),
              ),
              if (isComplete)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                    vertical: CruSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    color: c.greenTint,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                  ),
                  child: Text(
                    'Filled',
                    style: CruType.dateMonth.w700.tint(c.greenText),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            subtitle,
            style: CruType.micro.tint(c.label2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                0,
                CruSpace.s16,
                CruSpace.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable text field with optional voice-to-text dictation.
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

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: CruType.caption.w600.tint(c.label)),
            ),
            if (enableVoice)
              InkWell(
                borderRadius: BorderRadius.circular(CruSpace.s8),
                onTap: () async {
                  final text = await HomeopathyVoiceDictationSheet.show(
                    context,
                    fieldName: label,
                    initialText: controller.text,
                  );
                  if (text != null && text.trim().isNotEmpty) {
                    if (controller.text.trim().isEmpty) {
                      controller.text = text.trim();
                    } else {
                      controller.text =
                          '${controller.text.trim()}\n${text.trim()}';
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s6,
                    vertical: CruSpace.s2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: _accentEmerald,
                      ),
                      const SizedBox(width: CruSpace.s4),
                      Text(
                        'Speak',
                        style: CruType.micro.w700.tint(_accentEmerald),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: CruType.subhead.tint(c.label),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: CruType.caption.tint(c.label3),
            suffixIcon: enableVoice
                ? IconButton(
                    icon: const Icon(Icons.mic_none_rounded, size: 18),
                    color: _accentEmerald.withValues(alpha: 0.8),
                    tooltip: 'Speak to fill $label',
                    onPressed: () async {
                      final text = await HomeopathyVoiceDictationSheet.show(
                        context,
                        fieldName: label,
                        initialText: controller.text,
                      );
                      if (text != null && text.trim().isNotEmpty) {
                        if (controller.text.trim().isEmpty) {
                          controller.text = text.trim();
                        } else {
                          controller.text =
                              '${controller.text.trim()}\n${text.trim()}';
                        }
                      }
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s10,
            ),
            filled: true,
            fillColor: c.inset,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              borderSide: const BorderSide(
                color: _accentEmerald,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Category Selector Header for the 4 Homeopathy Questionnaires.
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

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      margin: const EdgeInsets.only(bottom: CruSpace.s16),
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: c.separator),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.style_outlined,
                size: 16,
                color: _accentEmerald,
              ),
              const SizedBox(width: CruSpace.s6),
              Text(
                'Case Sheet Questionnaire Type',
                style: CruType.caption.w700.tint(c.label),
              ),
              const Spacer(),
              if (patientAge <= 16 &&
                  selectedCategory != HomeopathyCaseSheetCategory.children)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s6,
                    vertical: CruSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    color: c.tealTint,
                    borderRadius: BorderRadius.circular(CruRadius.bar),
                  ),
                  child: Text(
                    'Pediatric Age',
                    style: CruType.dateMonth.w700.tint(c.tealText),
                  ),
                )
              else if (isFemale &&
                  selectedCategory !=
                      HomeopathyCaseSheetCategory.femaleEndocrine)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s6,
                    vertical: CruSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(CruRadius.bar),
                  ),
                  child: const Text(
                    'Female / Thyroid',
                    style: TextStyle(
                      fontFamily: CruType.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDB2777),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildOption(
                  context,
                  category: HomeopathyCaseSheetCategory.general,
                  label: 'General Case',
                  icon: Icons.assignment_outlined,
                  activeColor: _accentEmerald,
                ),
                const SizedBox(width: CruSpace.s8),
                _buildOption(
                  context,
                  category: HomeopathyCaseSheetCategory.children,
                  label: 'Children Case',
                  icon: Icons.child_care_rounded,
                  activeColor: const Color(0xFF0284C7),
                ),
                const SizedBox(width: CruSpace.s8),
                _buildOption(
                  context,
                  category: HomeopathyCaseSheetCategory.femaleEndocrine,
                  label: 'Female & Endocrine',
                  icon: Icons.female_rounded,
                  activeColor: const Color(0xFFDB2777),
                ),
                const SizedBox(width: CruSpace.s8),
                _buildOption(
                  context,
                  category: HomeopathyCaseSheetCategory.acute,
                  label: 'Acute Short-Form',
                  icon: Icons.flash_on_rounded,
                  activeColor: const Color(0xFFD97706),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required HomeopathyCaseSheetCategory category,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final c = context.cru;
    final isSelected = selectedCategory == category;
    return InkWell(
      borderRadius: BorderRadius.circular(CruRadius.control),
      onTap: () => onCategoryChanged(category),
      child: AnimatedContainer(
        duration: CruMotion.fast,
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : c.inset,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(
            color: isSelected ? activeColor : c.separator,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? activeColor : c.label3),
            const SizedBox(width: CruSpace.s6),
            Text(
              label,
              style: isSelected
                  ? CruType.caption.w700.tint(activeColor)
                  : CruType.caption.w500.tint(c.label2),
            ),
          ],
        ),
      ),
    );
  }
}
