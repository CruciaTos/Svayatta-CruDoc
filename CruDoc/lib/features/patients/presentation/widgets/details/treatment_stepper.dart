import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum TreatmentStepState { done, current, future }

/// One step of a treatment plan, already resolved for display.
class TreatmentStep {
  const TreatmentStep({
    required this.title,
    required this.state,
    this.subtitle,
  });

  final String title;

  /// Real data only ("Tooth 13 · ₹4,000"); null hides the line.
  final String? subtitle;
  final TreatmentStepState state;
}

/// A vertical stepper: done steps carry a green check, the current step
/// an accent ring and a "Next" pill, future steps are hollow with a
/// "Book" capsule.
class TreatmentStepper extends StatelessWidget {
  const TreatmentStepper({super.key, required this.steps, required this.onBook});

  final List<TreatmentStep> steps;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: CruSize.stepperNode,
                  child: Column(
                    children: [
                      _Node(steps[i].state),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: CruSize.stepperConnector,
                            margin: const EdgeInsets.symmetric(
                              vertical: CruSpace.s4,
                            ),
                            decoration: BoxDecoration(
                              color: steps[i].state == TreatmentStepState.done &&
                                      steps[i + 1].state ==
                                          TreatmentStepState.done
                                  ? c.green
                                  : c.track,
                              borderRadius: BorderRadius.circular(
                                CruSize.stepperConnector / 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < steps.length - 1 ? CruSpace.s20 : 0,
                    ),
                    child: _StepBody(step: steps[i], onBook: onBook),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node(this.state);
  final TreatmentStepState state;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    switch (state) {
      case TreatmentStepState.done:
        return const CruDoneBadge(size: CruSize.stepperNode);
      case TreatmentStepState.current:
        return Container(
          width: CruSize.stepperNode,
          height: CruSize.stepperNode,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.accent, width: 2.5),
          ),
          child: Container(
            width: CruSize.stepperDot,
            height: CruSize.stepperDot,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
          ),
        );
      case TreatmentStepState.future:
        return Container(
          width: CruSize.stepperNode,
          height: CruSize.stepperNode,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.label3, width: 2),
          ),
        );
    }
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({required this.step, required this.onBook});
  final TreatmentStep step;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final lineHeight = CruSize.stepperNode / CruType.subhead.fontSize!;
    final Widget trailing = switch (step.state) {
      TreatmentStepState.done => Text(
          'Done',
          style: CruType.subhead.w600
              .tint(c.greenText)
              .copyWith(height: lineHeight),
        ),
      TreatmentStepState.current => Container(
          height: CruSize.nextPill,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: c.accentTint,
            shape: const StadiumBorder(),
          ),
          child: Text('Next', style: CruType.caption.w600.tint(c.accentText)),
        ),
      TreatmentStepState.future => CruCapsuleButton(
          label: 'Book',
          height: CruSize.rowCapsule,
          semanticLabel: 'Book ${step.title}',
          onPressed: onBook,
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(step.title, style: CruType.step.tint(c.label)),
              if (step.subtitle != null)
                Text(
                  step.subtitle!,
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s12),
        trailing,
      ],
    );
  }
}
