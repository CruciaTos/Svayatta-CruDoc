import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';

/// Payments taken for a logged dental procedure. Each one is an ordinary
/// income [RevenueEntry] for the patient, so it shows in Revenue like any
/// other payment. Its id carries the procedure's id ("proc_<log id>_<n>"),
/// which links it back to the procedure without a new column.
abstract final class ProcedurePayments {
  static const String _prefix = 'proc_';

  /// A fresh entry id for another payment towards [procedureLogId].
  static String newEntryId(String procedureLogId) =>
      '$_prefix${procedureLogId}_${DateTime.now().microsecondsSinceEpoch}';

  /// The procedure [entry] was paid towards, or null for other income.
  static String? procedureIdOf(RevenueEntry entry) {
    if (!entry.id.startsWith(_prefix)) return null;
    final rest = entry.id.substring(_prefix.length);
    final cut = rest.lastIndexOf('_');
    return cut <= 0 ? null : rest.substring(0, cut);
  }

  /// Records [amount] received from the patient towards a procedure.
  static Future<void> record(
    RevenueRepository repository, {
    required String procedureLogId,
    required String patientId,
    required String patientName,
    required double amount,
    required String description,
    required DateTime date,
    String? visitId,
  }) async {
    final now = DateTime.now();
    await repository.createRevenueEntry(
      RevenueEntry(
        id: newEntryId(procedureLogId),
        date: date,
        description: description,
        amount: amount,
        // Like settled pending payments: a visit's money when it has one.
        type: visitId == null ? RevenueType.miscellaneous : RevenueType.visit,
        payer: patientName,
        patientId: patientId,
        visitId: visitId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// What has been received for each of a patient's logged procedures, by
/// procedure id. Null while revenue loads. Live: it follows the revenue
/// stream, so a payment (or a deleted one) shows straight away.
final procedurePaymentsProvider =
    Provider.family<Map<String, double>?, String>((ref, patientId) {
      final entries = ref.watch(recentRevenueEntriesProvider).value;
      if (entries == null) return null;
      final paid = <String, double>{};
      for (final e in entries) {
        if (e.kind != TransactionKind.income || e.patientId != patientId) {
          continue;
        }
        final id = ProcedurePayments.procedureIdOf(e);
        if (id != null) paid[id] = (paid[id] ?? 0) + e.amount;
      }
      return paid;
    });
