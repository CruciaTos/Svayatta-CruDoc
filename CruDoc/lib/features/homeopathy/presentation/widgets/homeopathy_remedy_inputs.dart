import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/homeopathy/data/homeopathy_dispensing.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens [builder] as the standard rounded bottom sheet.
Future<T?> showHomeoSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.cru.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CruRadius.card)),
    ),
    builder: builder,
  );
}

/// Sheet body: grabber, title, scrolling [children].
class HomeoSheetBody extends StatelessWidget {
  const HomeoSheetBody({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: EdgeInsets.only(
        left: CruSpace.s20,
        right: CruSpace.s20,
        top: CruSpace.s14,
        bottom: MediaQuery.of(context).viewInsets.bottom + CruSpace.s20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: CruSpace.s32 + CruSpace.s12,
                height: CruSpace.s4,
                margin: const EdgeInsets.only(bottom: CruSpace.s16),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Text(title, style: CruType.title2.tint(c.label)),
            const SizedBox(height: CruSpace.s16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The six remedy forms as single-choice chips.
class RemedyFormChips extends StatelessWidget {
  const RemedyFormChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RemedyForm selected;
  final ValueChanged<RemedyForm> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Form', style: CruType.subhead.w500.tint(c.label2)),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in RemedyForm.values)
              HomeopathyChoiceChip(
                label: f.label,
                selected: selected == f,
                onSelected: (_) => onChanged(f),
              ),
          ],
        ),
      ],
    );
  }
}

/// Whole-number stepper with the unit beside it. [min] is the lowest value
/// the minus button reaches.
class RemedyQtyStepper extends StatelessWidget {
  const RemedyQtyStepper({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.min = 1,
  });

  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  final int min;

  static const int _max = 9999;

  Future<void> _type(BuildContext context) async {
    final controller = TextEditingController(text: '$value');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: label,
        submitLabel: 'Set',
        onSubmit: () => Navigator.of(ctx).pop(int.tryParse(controller.text)),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: CruType.input.tabular.tint(ctx.cru.label),
          ),
        ),
      ),
    );
    if (n != null) onChanged(n.clamp(min, _max));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CruType.subhead.w500.tint(c.label2)),
        const SizedBox(height: CruSpace.s6),
        Row(
          children: [
            Container(
              decoration: ShapeDecoration(
                color: c.inset,
                shape: cruShape(CruRadius.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruPressable(
                    onTap: value > min ? () => onChanged(value - 1) : null,
                    semanticLabel: 'Decrease',
                    builder: (context, hovered) => SizedBox(
                      width: CruSize.actionButton,
                      height: CruSize.actionButton,
                      child: Center(
                        child: Container(
                          width: CruSpace.s12,
                          height: CruSpace.s2,
                          color: value > min ? c.label2 : c.label3,
                        ),
                      ),
                    ),
                  ),
                  CruPressable(
                    onTap: () => _type(context),
                    semanticLabel: '$label, $value. Tap to type',
                    builder: (context, hovered) => SizedBox(
                      width: CruSize.actionButton + CruSpace.s8,
                      child: Center(
                        child: Text(
                          '$value',
                          style: CruType.headline.tabular.tint(c.label),
                        ),
                      ),
                    ),
                  ),
                  CruIconButton(
                    icon: CruIcons.plus,
                    onPressed: value < _max ? () => onChanged(value + 1) : null,
                    semanticLabel: 'Increase',
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Text(unit, style: CruType.text.tint(c.label2)),
          ],
        ),
      ],
    );
  }
}
