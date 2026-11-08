import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/wrap_up_builder.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/side_cards.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shows what the records support: AI Scribe drafts still to review,
/// tomorrow's bookings, and a "Day summary" close-the-day action.
class WrapUpCard extends ConsumerWidget {
  const WrapUpCard({super.key, required this.data, required this.navigate});

  final WrapUpData data;
  final ValueChanged<int> navigate;

  void _showDaySummary(BuildContext context, WidgetRef ref) {
    final now = ref.read(dashboardNowProvider);
    final dashData = ref.read(dashboardDataProvider);
    final revenueEntries = ref.read(recentRevenueEntriesProvider).value;
    final pendingPayments = ref.read(pendingPaymentsProvider).value;
    final lowStock = ref.read(lowStockMedicinesProvider).value;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final seen = dashData.glance?.seen;
    final missed = dashData.schedule
        ?.where((i) => i.status == ScheduleStatus.missed)
        .length;
    final collectedToday = dashData.collected?.today;

    double? expensesToday;
    if (revenueEntries != null) {
      expensesToday = revenueEntries
          .where(
            (e) =>
                !e.isDeleted &&
                e.kind == TransactionKind.expense &&
                (sameDay(e.date, now) || sameDay(e.createdAt, now)),
          )
          .fold<double>(0.0, (sum, e) => sum + e.amount);
    }

    double? pendingToday;
    if (pendingPayments != null) {
      pendingToday = pendingPayments
          .where(
            (p) =>
                !p.isPaid &&
                (sameDay(p.date, now) || sameDay(p.createdAt, now)),
          )
          .fold<double>(0.0, (sum, p) => sum + p.amount);
    }

    final lowStockCount = lowStock?.length;

    final rows = <(String, String)>[];
    if (seen != null) {
      rows.add(('Patients seen', '$seen'));
    }
    if (missed != null) {
      rows.add(('Booked patients who did not come', '$missed'));
    }
    if (collectedToday != null) {
      rows.add(('Collected today', DashFormat.rupees(collectedToday)));
    }
    if (expensesToday != null) {
      rows.add(('Expenses today', DashFormat.rupees(expensesToday)));
    }
    if (pendingToday != null) {
      rows.add(('New pending dues today', DashFormat.rupees(pendingToday)));
    }
    if (lowStockCount != null) {
      rows.add(('Low-stock medicines', '$lowStockCount'));
    }

    final dateStr = DateFormat('d MMM yyyy').format(now);
    final plainText = [
      'Day summary · $dateStr',
      for (final (label, value) in rows) '$label: $value',
    ].join('\n');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final c = dialogCtx.cru;
        return PatientDialog(
          title: 'Day summary',
          cancelLabel: 'Close',
          confirmLabel: 'Copy summary',
          onConfirm: () async {
            await Clipboard.setData(ClipboardData(text: plainText));
            if (dialogCtx.mounted) {
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showIsland(
                const SnackBar(
                  content: Text('Day summary copied to clipboard'),
                ),
              );
            }
          },
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dateStr, style: CruType.callout.tabular.tint(c.label2)),
              const SizedBox(height: CruSpace.s16),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: CruType.subhead.tint(c.label2)),
                      Text(
                        value,
                        style: CruType.callout.w600.tabular.tint(c.label),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final left = data.patientsLeft;
    return CruCard(
      semanticLabel: 'Wrap up the day',
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Wrap up the day',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  left == 0
                      ? 'Everyone on the list has been seen'
                      : '${DashFormat.plural(left, 'patient')} left',
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          ...withSeparators([
            if (data.draftNames.isNotEmpty)
              ActionRow(
                icon: CruIcons.pen,
                tone: CruTileTone.accent,
                title:
                    '${DashFormat.plural(data.draftNames.length, 'scribe note')}'
                    ' to review',
                subtitle: DashFormat.names(data.draftNames, max: 3),
                actionLabel: 'Review',
                onAction: () => navigate(DesktopTab.scribe),
              ),
            if (data.tomorrowCount > 0)
              ActionRow(
                icon: CruIcons.calendar,
                // Teal is reserved for lab results, so this stays neutral.
                tone: CruTileTone.neutral,
                title: 'Tomorrow · ${data.tomorrowCount} booked',
                subtitle: 'First at ${DashFormat.time(data.tomorrowFirst!)}',
                actionLabel: 'View',
                onAction: () => navigate(DesktopTab.appointments),
              ),
          ]),
          const SizedBox(height: CruSpace.s12),
          CruButton(
            label: 'Day summary',
            kind: CruButtonKind.tinted,
            icon: CruIcons.fileText,
            expand: true,
            onPressed: () => _showDaySummary(context, ref),
          ),
        ],
      ),
    );
  }
}
