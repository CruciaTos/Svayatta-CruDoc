import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Separators start after the monogram: 36 + gap 12.
const double _textInset = CruSize.monogramList + CruSpace.s12;

/// Card showing revenue collections broken down by doctor for the selected period.
/// Only shown when the clinic has more than one doctor.
class RevenueByDoctorCard extends ConsumerWidget {
  const RevenueByDoctorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorsAsync = ref.watch(clinicDoctorsProvider);
    final doctors = doctorsAsync.value ?? const [];
    if (doctors.length <= 1) {
      return const SizedBox.shrink();
    }

    final overview = ref.watch(revenueOverviewProvider);
    if (overview == null) {
      return const SkeletonCard(rows: 3, rowHeight: CruSize.scheduleRow);
    }

    final entriesAsync = ref.watch(recentRevenueEntriesProvider);
    final entries = entriesAsync.value ?? const <RevenueEntry>[];
    final span = overview.window.toDate;
    final ownerUid = ClinicSession.instance.tenantId ?? '';

    // Calculate collections per doctor in the active period.
    // Records with empty attendingDoctorUid count as the owner's.
    final doctorTotals = <String, double>{for (final doc in doctors) doc.uid: 0.0};
    var totalPeriodIncome = 0.0;

    for (final e in entries) {
      if (e.isDeleted || e.kind != TransactionKind.income) continue;
      if (!span.contains(RevenueBuilder.when(e))) continue;

      final docUid = e.attendingDoctorUid.isEmpty ? ownerUid : e.attendingDoctorUid;
      if (doctorTotals.containsKey(docUid)) {
        doctorTotals[docUid] = (doctorTotals[docUid] ?? 0.0) + e.amount;
      } else if (doctorTotals.containsKey(ownerUid)) {
        doctorTotals[ownerUid] = (doctorTotals[ownerUid] ?? 0.0) + e.amount;
      }
      totalPeriodIncome += e.amount;
    }

    final c = context.cru;

    return CruCard(
      semanticLabel: 'Collections by doctor',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s24,
        CruSpace.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'By doctor',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
              ),
              Text(
                DashFormat.rupees(totalPeriodIncome),
                style: CruType.row.tabular.tint(c.label),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          Text(
            '${DashFormat.plural(doctors.length, 'doctor')} · this period',
            style: CruType.subhead.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s8),
          for (var i = 0; i < doctors.length; i++) ...[
            if (i > 0) const CruSeparator(indent: _textInset),
            _DoctorRevenueRow(
              doctorName: doctors[i].name,
              specialty: doctors[i].specialty.isNotEmpty
                  ? doctors[i].specialty
                  : doctors[i].roleName,
              amount: doctorTotals[doctors[i].uid] ?? 0.0,
              totalAmount: totalPeriodIncome,
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorRevenueRow extends StatelessWidget {
  const _DoctorRevenueRow({
    required this.doctorName,
    required this.specialty,
    required this.amount,
    required this.totalAmount,
  });

  final String doctorName;
  final String specialty;
  final double amount;
  final double totalAmount;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final share = totalAmount > 0 ? (amount / totalAmount) : 0.0;
    final percentText = totalAmount > 0 ? '${(share * 100).round()}%' : '0%';

    return Semantics(
      container: true,
      label: '$doctorName, $specialty, ${DashFormat.rupees(amount)}, $percentText of collections',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CruMonogram(
                  name: doctorName,
                  size: CruSize.monogramList,
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctorName,
                        style: CruType.callout.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (specialty.isNotEmpty)
                        Text(
                          specialty,
                          style: CruType.caption.tint(c.label2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DashFormat.rupees(amount),
                      style: CruType.callout.tabular.tint(c.label),
                    ),
                    Text(
                      percentText,
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),
            ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.full),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  backgroundColor: c.inset,
                  valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
