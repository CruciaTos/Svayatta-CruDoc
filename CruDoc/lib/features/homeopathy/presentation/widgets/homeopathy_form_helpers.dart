import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart';

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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppColors.positiveGreen.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
          width: isComplete ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isComplete
                  ? AppColors.positiveGreen.withValues(alpha: 0.12)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isComplete
                  ? AppColors.positiveGreen
                  : const Color(0xFF64748B),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isComplete)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.positiveGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Filled',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.positiveGreen,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (enableVoice)
              InkWell(
                borderRadius: BorderRadius.circular(8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: Color(0xFF2E7D32),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Speak',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
            ),
            suffixIcon: enableVoice
                ? IconButton(
                    icon: const Icon(Icons.mic_none_rounded, size: 18),
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.8),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.style_outlined,
                  size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              const Text(
                'Case Sheet Questionnaire Type',
                style: TextStyle(
                  fontFamily: AppColors.headingFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (patientAge <= 16 &&
                  selectedCategory != HomeopathyCaseSheetCategory.children)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pediatric Age',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0284C7)),
                  ),
                )
              else if (isFemale &&
                  selectedCategory !=
                      HomeopathyCaseSheetCategory.femaleEndocrine)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Female / Thyroid',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDB2777)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildOption(
                  category: HomeopathyCaseSheetCategory.general,
                  label: 'General Case',
                  icon: Icons.assignment_outlined,
                  activeColor: const Color(0xFF2E7D32),
                ),
                const SizedBox(width: 8),
                _buildOption(
                  category: HomeopathyCaseSheetCategory.children,
                  label: 'Children Case',
                  icon: Icons.child_care_rounded,
                  activeColor: const Color(0xFF0284C7),
                ),
                const SizedBox(width: 8),
                _buildOption(
                  category: HomeopathyCaseSheetCategory.femaleEndocrine,
                  label: 'Female & Endocrine',
                  icon: Icons.female_rounded,
                  activeColor: const Color(0xFFDB2777),
                ),
                const SizedBox(width: 8),
                _buildOption(
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

  Widget _buildOption({
    required HomeopathyCaseSheetCategory category,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = selectedCategory == category;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onCategoryChanged(category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? activeColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
