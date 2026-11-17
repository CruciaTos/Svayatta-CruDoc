import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/data/homeopathy_remedies.dart';
import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/materia_medica_screen.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Remedy text field with suggestions from the remedy list (full name or
/// abbreviation, from two letters). Any other text is kept as typed; the
/// controller always holds the plain remedy string. When the text matches a
/// Materia medica entry, a "View" link opens it.
class HomeopathyRemedyField extends StatefulWidget {
  const HomeopathyRemedyField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  State<HomeopathyRemedyField> createState() => _HomeopathyRemedyFieldState();
}

class _HomeopathyRemedyFieldState extends State<HomeopathyRemedyField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // Same dictation path as HomeopathyFormField (the old remedy field's mic).
  Future<void> _dictate(BuildContext context) async {
    final controller = widget.controller;
    final text = await HomeopathyVoiceDictationSheet.show(
      context,
      fieldName: widget.label,
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
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: CruType.subhead.w500.tint(c.label2),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final entry = materiaMedicaFor(value.text);
                if (entry == null) return const SizedBox.shrink();
                return CruPressable(
                  onTap: () => MateriaMedicaDetailScreen.open(context, entry),
                  semanticLabel: 'View ${entry.name} in Materia medica',
                  builder: (context, hovered) => Text(
                    'View',
                    style: CruType.subhead.w600.tint(c.accentText),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s6),
        RawAutocomplete<RemedyName>(
          textEditingController: widget.controller,
          focusNode: _focus,
          displayStringForOption: (r) => r.name,
          optionsBuilder: (value) => searchRemedies(value.text),
          fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
              TextField(
                controller: controller,
                focusNode: focusNode,
                style: CruType.input.tint(c.label),
                cursorColor: c.accent,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: CruType.input.tint(c.label3),
                  suffixIcon: CruIconButton(
                    icon: CruIcons.mic,
                    iconSize: 16,
                    onPressed: () => _dictate(context),
                    semanticLabel: 'Dictate ${widget.label}',
                    tooltip: 'Dictate',
                  ),
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
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: CruSpace.s4),
              child: Material(
                color: c.surface,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  side: BorderSide(color: c.cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 280,
                    maxWidth: 420,
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final r in options)
                        InkWell(
                          onTap: () => onSelected(r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CruSpace.s12,
                              vertical: CruSpace.s12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.name,
                                    style: CruType.text.tint(c.label),
                                  ),
                                ),
                                const SizedBox(width: CruSpace.s8),
                                Text(
                                  r.abbr,
                                  style: CruType.caption.tint(c.label3),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
