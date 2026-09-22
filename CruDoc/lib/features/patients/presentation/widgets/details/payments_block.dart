import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The package panel (inset, radius 12): balance, what is due, and
/// Record payment. The amount paid and the package total are GAPs, so
/// the paid bar and "₹paid paid" are not shown.
class PackageBalancePanel extends StatelessWidget {
  const PackageBalancePanel({
    super.key,
    required this.summary,
    required this.onRecordPayment,
  });

  final PatientSummary summary;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final balance = summary.balance;
    final due = summary.hasBalance;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s18,
        vertical: CruSpace.s16,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Package balance',
                        style: CruType.subhead.w500.tint(c.label2),
                      ),
                    ),
                    Text(
                      PatientFormat.rupees(balance),
                      style: CruType.row.tabular.tint(c.label),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s8),
                if (due)
                  Text(
                    '${PatientFormat.rupees(balance)} due',
                    style: CruType.subhead.w600.tabular.tint(c.amberText),
                  )
                else
                  Row(
                    children: [
                      CruIcon(
                        CruIcons.check,
                        size: 15,
                        strokeWidth: 2.4,
                        color: c.greenText,
                      ),
                      const SizedBox(width: CruSpace.s4),
                      Text(
                        'No balance due',
                        style: CruType.subhead.w600.tint(c.greenText),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (due) ...[
            const SizedBox(width: CruSpace.s20),
            CruCapsuleButton(
              label: 'Record payment',
              kind: CruCapsuleKind.surface,
              height: CruSize.panelCapsule,
              semanticLabel: 'Record a payment from ${summary.name}',
              onPressed: onRecordPayment,
            ),
          ],
        ],
      ),
    );
  }
}

/// The package panel in its own card, for patients without a treatment
/// plan card to hold it.
class PaymentsCard extends StatelessWidget {
  const PaymentsCard({
    super.key,
    required this.summary,
    required this.onRecordPayment,
  });

  final PatientSummary summary;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      semanticLabel: 'Payments',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DetailsCardHeader(title: 'Payments'),
          const SizedBox(height: CruSpace.s16),
          PackageBalancePanel(
            summary: summary,
            onRecordPayment: onRecordPayment,
          ),
        ],
      ),
    );
  }
}
