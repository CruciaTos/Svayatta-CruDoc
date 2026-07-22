import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';

/// How many rows the dashboard's "Recent Activity" card shows once
/// patient/visit/inventory/revenue activity is merged into one feed.
const int kRecentActivityDisplayLimit = 6;

/// Merges patient, visit, inventory, and revenue activity into one
/// chronological feed for the dashboard's "Recent Activity" card.
///
/// Each source stream is already capped/filtered at its own repository
/// (see [recentVisitsProvider], [recentStockTransactionsProvider],
/// [recentRevenueEntriesProvider]) — this just flattens them into
/// [ActivityItem]s, sorts by [ActivityItem.timestamp] descending, and
/// truncates to [kRecentActivityDisplayLimit].
final recentActivityProvider = Provider<AsyncValue<List<ActivityItem>>>((ref) {
  final patientsAsync = ref.watch(patientsStreamProvider);
  final visitsAsync = ref.watch(recentVisitsProvider);
  final transactionsAsync = ref.watch(recentStockTransactionsProvider);
  final medicinesAsync = ref.watch(medicinesStreamProvider);
  final revenueAsync = ref.watch(recentRevenueEntriesProvider);

  final asyncValues = [
    patientsAsync,
    visitsAsync,
    transactionsAsync,
    medicinesAsync,
    revenueAsync,
  ];

  for (final async in asyncValues) {
    if (async.isLoading) return const AsyncValue.loading();
  }
  for (final async in asyncValues) {
    if (async.hasError) {
      return AsyncValue.error(async.error!, async.stackTrace!);
    }
  }

  final patients = patientsAsync.value!;
  final visits = visitsAsync.value!;
  final transactions = transactionsAsync.value!;
  final medicines = medicinesAsync.value!;
  final revenueEntries = revenueAsync.value!;

  final patientsById = {for (final p in patients) p.id: p};
  final medicinesById = {for (final m in medicines) m.id: m};

  final items = <ActivityItem>[
    ...patients.map(_patientActivity),
    ...visits
        .map((v) => _visitActivity(v, patientsById))
        .whereType<ActivityItem>(),
    ...transactions
        .map((t) => _transactionActivity(t, medicinesById))
        .whereType<ActivityItem>(),
    ...revenueEntries.map(_revenueActivity),
  ];

  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return AsyncValue.data(items.take(kRecentActivityDisplayLimit).toList());
});

ActivityItem _patientActivity(Patient patient) {
  return ActivityItem(
    icon: Icons.person_add,
    text: 'New patient added — ${patient.fullName}',
    timestamp: patient.createdAt,
  );
}

/// Returns null if the visit's patient couldn't be resolved (e.g.
/// deleted/archived after the visit was made) — matches the existing
/// convention in TodaysVisitsCard of hiding unresolvable visits rather
/// than showing a blank name.
ActivityItem? _visitActivity(Visit visit, Map<String, Patient> patientsById) {
  final patient = patientsById[visit.patientId];
  if (patient == null) return null;

  // A visit's createdAt/updatedAt are stamped equal at creation time (see
  // VisitRepository.createVisit) — still equal means nothing has touched
  // it since, so this is the "new visit" event rather than a status change.
  final isNew = visit.createdAt == visit.updatedAt;

  final (String text, IconData icon) = isNew
      ? ('New visit scheduled with ${patient.fullName}', Icons.event_note)
      : switch (visit.status) {
          VisitStatus.completed => (
            'Visit with ${patient.fullName} completed',
            Icons.event_available,
          ),
          VisitStatus.cancelled => (
            'Visit with ${patient.fullName} cancelled',
            Icons.event_busy,
          ),
          VisitStatus.missed => (
            'Visit with ${patient.fullName} marked missed',
            Icons.event_busy,
          ),
          VisitStatus.scheduled => (
            'Visit with ${patient.fullName} rescheduled',
            Icons.event_repeat,
          ),
        };

  return ActivityItem(icon: icon, text: text, timestamp: visit.updatedAt);
}

/// Returns null if the transaction's medicine couldn't be resolved (e.g.
/// deleted after the transaction was recorded).
ActivityItem? _transactionActivity(
  StockTransactionModel transaction,
  Map<String, MedicineModel> medicinesById,
) {
  final medicine = medicinesById[transaction.medicineId];
  if (medicine == null) return null;

  final (String text, IconData icon) = switch (transaction.type) {
    StockTransactionType.restock => (
      'Restocked ${medicine.name} — +${transaction.quantity} units',
      Icons.inventory_2_outlined,
    ),
    StockTransactionType.dispense => (
      'Dispensed ${transaction.quantity} units of ${medicine.name}',
      Icons.medication_outlined,
    ),
    StockTransactionType.adjustment => (
      'Adjusted stock for ${medicine.name} (${transaction.quantity} units)',
      Icons.tune,
    ),
    StockTransactionType.expiredWriteoff => (
      'Wrote off ${transaction.quantity} units of ${medicine.name} (expired)',
      Icons.delete_outline,
    ),
  };

  return ActivityItem(icon: icon, text: text, timestamp: transaction.createdAt);
}

ActivityItem _revenueActivity(RevenueEntry entry) {
  final amountLabel = '₹${entry.amount.toStringAsFixed(0)}';

  if (entry.kind == TransactionKind.expense) {
    final description = entry.description.trim();
    final suffix = description.isEmpty ? '' : ' — $description';
    return ActivityItem(
      icon: Icons.trending_down,
      text: 'Expense logged — $amountLabel$suffix',
      timestamp: entry.createdAt,
    );
  }

  final payer = entry.payer?.trim();
  final suffix = (payer == null || payer.isEmpty) ? '' : ' from $payer';
  return ActivityItem(
    icon: Icons.payments_outlined,
    text: 'Payment received — $amountLabel$suffix',
    timestamp: entry.createdAt,
  );
}
