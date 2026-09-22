import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_search_bar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Bring your existing patients into CruDoc": shown below the list
/// while the clinic has only a handful of patients.
class PatientsFirstWeekPanel extends StatelessWidget {
  const PatientsFirstWeekPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Import and the template are a GAP: both say so when pressed.
    void unavailable() => PatientActions.importUnavailable(context);

    return Container(
      padding: CruSpace.firstWeekPanel,
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        children: [
          Container(
            width: CruSize.largeTile,
            height: CruSize.largeTile,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.accentTint,
              shape: cruShape(CruRadius.largeTile),
            ),
            child: CruIcon(
              CruIcons.download,
              size: 26,
              strokeWidth: 1.8,
              color: c.accentText,
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Semantics(
            header: true,
            child: Text(
              'Bring your existing patients into CruDoc',
              style: CruType.title2.tint(c.label),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: CruSpace.s6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: CruSize.leadMaxWidth),
            child: Text(
              'Import an Excel or CSV file from your old software or '
              'register. Names, phones, ages and conditions come across '
              'together.',
              style: CruType.lead.tint(c.label2),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: CruSpace.s20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: CruSpace.s16,
            runSpacing: CruSpace.s12,
            children: [
              _ImportButton(onPressed: unavailable),
              CruLink(
                label: 'Download the template',
                style: CruType.callout,
                onPressed: unavailable,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s32),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: CruSize.hintGridMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hints = [
                  const _HintCard(
                    title: 'Add at the front desk',
                    body: 'New walk-ins added from the Queue appear here '
                        'automatically.',
                  ),
                  const _HintCard(
                    title: 'Filters fill in as you go',
                    body: 'Overdue follow-ups and balances due show up once '
                        "there's data.",
                  ),
                  _HintCard(
                    title: 'Find anyone fast',
                    body: 'Press ${patientsSearchShortcut()} and type a name, '
                        'phone or patient ID.',
                  ),
                ];
                if (constraints.maxWidth < CruSize.hintGridColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < hints.length; i++) ...[
                        if (i > 0) const SizedBox(height: CruSpace.s12),
                        hints[i],
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < hints.length; i++) ...[
                        if (i > 0) const SizedBox(width: CruSpace.s12),
                        Expanded(child: hints[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Surface + hairline ring, accent text: the panel's main action without
/// competing with the header's filled "Add patient".
class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'Import from Excel',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.actionButton,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.surface, c) : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.hairline),
          ),
          shadows: c.cardShadow,
        ),
        child: Text(
          'Import from Excel',
          style: CruType.row.tint(c.accentText),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CruType.chip.w600.tint(c.label)),
          const SizedBox(height: CruSpace.s2),
          Text(body, style: CruType.subhead.tint(c.label2)),
        ],
      ),
    );
  }
}
