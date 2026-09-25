import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/facts_strip.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/payments_block.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_stepper.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dental plan line items as the details screen reads them: declined and
/// deleted items dropped, in plan order. Invoiced = done.
abstract final class DentalPlan {
  static List<TreatmentPlanLineItemModel> active(
    List<TreatmentPlanLineItemModel> all,
  ) =>
      all
          .where((i) =>
              !i.isDeleted &&
              TreatmentPlanItemStatus.fromString(i.status) !=
                  TreatmentPlanItemStatus.declined)
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  static bool isDone(TreatmentPlanLineItemModel i) =>
      TreatmentPlanItemStatus.fromString(i.status) ==
      TreatmentPlanItemStatus.invoiced;

  /// Null when there are no active items.
  static PlanProgress? progress(List<TreatmentPlanLineItemModel> items) =>
      items.isEmpty
          ? null
          : PlanProgress(
              done: items.where(isDone).length,
              total: items.length,
            );

  /// "Tooth 13" / "Teeth 13, 14"; null when no teeth are recorded.
  static String? teeth(Iterable<String> numbers) {
    final list = numbers
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) {
        final x = int.tryParse(a);
        final y = int.tryParse(b);
        if (x != null && y != null) return x.compareTo(y);
        return a.compareTo(b);
      });
    if (list.isEmpty) return null;
    return '${list.length == 1 ? 'Tooth' : 'Teeth'} ${list.join(', ')}';
  }

  static List<TreatmentStep> steps(List<TreatmentPlanLineItemModel> items) {
    final steps = <TreatmentStep>[];
    var currentTaken = false;
    for (final i in items) {
      final TreatmentStepState state;
      if (isDone(i)) {
        state = TreatmentStepState.done;
      } else if (!currentTaken) {
        currentTaken = true;
        state = TreatmentStepState.current;
      } else {
        state = TreatmentStepState.future;
      }
      final name = i.procedureName.trim();
      steps.add(TreatmentStep(
        title: name.isEmpty ? 'Procedure' : name,
        subtitle: _stepSubtitle(i),
        state: state,
      ));
    }
    return steps;
  }

  static String? _stepSubtitle(TreatmentPlanLineItemModel i) {
    final t = teeth(i.toothNumbers);
    final parts = [
      ?t,
      if (i.estimatedPrice > 0) PatientFormat.rupees(i.estimatedPrice),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Treatment plan card (dentists with plan items): heading, stepper and
/// the package panel.
class TreatmentPlanCard extends StatelessWidget {
  const TreatmentPlanCard({
    super.key,
    required this.summary,
    required this.items,
    required this.onEditPlan,
    required this.onBook,
    required this.onRecordPayment,
  });

  final PatientSummary summary;

  /// Active items in plan order (see [DentalPlan.active]); not empty.
  final List<TreatmentPlanLineItemModel> items;
  final VoidCallback onEditPlan;
  final VoidCallback onBook;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final title = summary.condition ?? 'Dental treatment plan';
    final teeth = DentalPlan.teeth(items.expand((i) => i.toothNumbers));
    return CruCard(
      semanticLabel: 'Treatment plan',
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Treatment plan',
                      style: CruType.subhead.w600.tint(c.accentText),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Semantics(
                      header: true,
                      child: Text(title, style: CruType.headline.tint(c.label)),
                    ),
                    if (teeth != null) ...[
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        teeth,
                        style: CruType.subhead.tabular.tint(c.label2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              CruCapsuleButton(label: 'Edit plan', onPressed: onEditPlan),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          TreatmentStepper(steps: DentalPlan.steps(items), onBook: onBook),
          const SizedBox(height: CruSpace.s20),
          PackageBalancePanel(
            summary: summary,
            onRecordPayment: onRecordPayment,
          ),
        ],
      ),
    );
  }
}
