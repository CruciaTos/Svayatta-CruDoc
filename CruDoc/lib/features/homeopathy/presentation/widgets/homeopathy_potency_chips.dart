import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _presets = [
  '6C',
  '30C',
  '200C',
  '1M',
  '10M',
  '50M',
  'LM1',
  'LM2',
  'LM3',
  'LM4',
  'LM5',
  'LM6',
];

/// Potency picker: common potencies as chips plus "Other" for any typed
/// value. The controller holds the plain potency string, as before.
class HomeopathyPotencyChips extends StatefulWidget {
  const HomeopathyPotencyChips({
    super.key,
    required this.controller,
    this.label = 'Potency',
  });

  final TextEditingController controller;
  final String label;

  @override
  State<HomeopathyPotencyChips> createState() => _HomeopathyPotencyChipsState();
}

class _HomeopathyPotencyChipsState extends State<HomeopathyPotencyChips> {
  bool _otherOpen = false;

  bool _isPreset(String t) =>
      _presets.any((p) => p.toUpperCase() == t.trim().toUpperCase());

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final text = value.text.trim();
        final custom = text.isNotEmpty && !_isPreset(text);
        final otherSelected = custom || _otherOpen;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: CruType.subhead.w500.tint(c.label2)),
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _presets)
                  HomeopathyChoiceChip(
                    label: p,
                    selected: text.toUpperCase() == p.toUpperCase(),
                    onSelected: (sel) {
                      setState(() => _otherOpen = false);
                      widget.controller.text = sel ? p : '';
                    },
                  ),
                HomeopathyChoiceChip(
                  label: 'Other',
                  selected: otherSelected,
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => _otherOpen = true);
                    } else {
                      setState(() => _otherOpen = false);
                      if (custom) widget.controller.clear();
                    }
                  },
                ),
              ],
            ),
            if (otherSelected) ...[
              const SizedBox(height: CruSpace.s8),
              TextField(
                controller: widget.controller,
                autofocus: _otherOpen && !custom,
                style: CruType.input.tint(c.label),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  hintText: '0/1 LM, 12C, CM',
                  hintStyle: CruType.input.tint(c.label3),
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
          ],
        );
      },
    );
  }
}
