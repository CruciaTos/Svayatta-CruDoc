import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/services/revenue_local_service.dart';

/// Clean API the presentation layer talks to for anything revenue-related.
///
/// Reads and writes go through SQLite. Writes are marked pending locally
/// and the central sync engine is triggered in the background — the same
/// local-first pattern as `PatientRepository` and `VisitRepository`.
class RevenueRepository {
  RevenueRepository({
    RevenueLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? RevenueLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final RevenueLocalService _localService;
  final FirestoreSyncService _syncService;

  // ---------------- revenue entries ----------------

  /// Records a new payment and returns its newly assigned id.
  Future<String> createRevenueEntry(RevenueEntry entry) async {
    _validateEntry(entry);

    final now = DateTime.now();
    final id = entry.id.trim().isEmpty ? const Uuid().v4() : entry.id;
    final entryWithId = RevenueEntry(
      id: id,
      date: entry.date,
      description: entry.description,
      amount: entry.amount,
      type: entry.type,
      payer: entry.payer,
      patientId: entry.patientId,
      visitId: entry.visitId,
      isDeleted: entry.isDeleted,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertRevenueEntry(entryWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Updates arbitrary fields on an existing revenue entry. `updatedAt`
  /// is stamped automatically regardless of what's passed here.
  Future<void> updateRevenueEntry(
    String entryId,
    Map<String, dynamic> data,
  ) async {
    if (data.containsKey('description')) {
      final description = data['description'] as String? ?? '';
      if (description.trim().isEmpty) {
        throw const RevenueValidationException(
          'A revenue entry must have a description.',
        );
      }
    }
    if (data.containsKey('amount')) {
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) {
        throw const RevenueValidationException(
          'A revenue entry amount must be greater than zero.',
        );
      }
    }

    final localData = Map<String, dynamic>.from(data)
      ..['updatedAt'] = DateTime.now();

    await _localService.updateRevenueEntry(entryId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Soft-deletes a revenue entry (e.g. it was recorded by mistake). The
  /// document is never removed from Firestore — only excluded from
  /// every default query — so history is fully preserved.
  Future<void> softDeleteRevenueEntry(String entryId) async {
    await _localService.softDeleteRevenueEntry(entryId);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Fetches a single revenue entry by id.
  Future<RevenueEntry?> getRevenueEntry(String entryId) {
    return _localService.getRevenueEntry(entryId);
  }

  /// Streams the live list of active (non-deleted) revenue entries,
  /// most recent first. The presentation layer applies its own
  /// weekly/monthly/yearly filter on top of this stream.
  Stream<List<RevenueEntry>> watchRevenueEntries() {
    return _localService.watchRevenueEntries();
  }

  // ---------------- pending payments ----------------

  /// Records a new amount owed and returns its newly assigned id.
  Future<String> createPendingPayment(PendingPayment payment) async {
    _validatePendingPayment(payment);

    final now = DateTime.now();
    final id = payment.id.trim().isEmpty ? const Uuid().v4() : payment.id;
    final paymentWithId = PendingPayment(
      id: id,
      date: payment.date,
      description: payment.description,
      amount: payment.amount,
      isPaid: false,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertPendingPayment(paymentWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Marks a pending payment as collected: flips `PendingPayment.isPaid`
  /// and creates the matching [RevenueEntry] (type
  /// [RevenueType.miscellaneous], description prefixed `"Paid: "`) in one
  /// step. The pending payment document itself is never deleted — only
  /// marked paid — so what was owed and when it was settled stays in
  /// the history.
  ///
  /// Throws [PendingPaymentNotFoundException] if [pendingPaymentId]
  /// doesn't resolve to an existing, still-unpaid pending payment.
  Future<String> markPendingPaymentAsPaid(String pendingPaymentId) async {
    final pending = await _localService.getPendingPayment(pendingPaymentId);
    if (pending == null || pending.isPaid) {
      throw PendingPaymentNotFoundException(pendingPaymentId);
    }

    final now = DateTime.now();
    await _localService.updatePendingPayment(pendingPaymentId, {
      'isPaid': true,
      'updatedAt': now,
    });

    final entryId = await createRevenueEntry(
      RevenueEntry(
        id: '',
        date: now,
        description: 'Paid: ${pending.description}',
        amount: pending.amount,
        type: RevenueType.miscellaneous,
        createdAt: now,
        updatedAt: now,
      ),
    );

    return entryId;
  }

  /// Fetches a single pending payment by id.
  Future<PendingPayment?> getPendingPayment(String paymentId) {
    return _localService.getPendingPayment(paymentId);
  }

  /// Streams the live list of still-unpaid pending payments, most
  /// recent first.
  Stream<List<PendingPayment>> watchPendingPayments() {
    return _localService.watchPendingPayments();
  }

  // ---------------- internal helpers ----------------

  void _validateEntry(RevenueEntry entry) {
    if (entry.description.trim().isEmpty) {
      throw const RevenueValidationException(
        'A revenue entry must have a description.',
      );
    }
    if (entry.amount <= 0) {
      throw const RevenueValidationException(
        'A revenue entry amount must be greater than zero.',
      );
    }
  }

  void _validatePendingPayment(PendingPayment payment) {
    if (payment.description.trim().isEmpty) {
      throw const RevenueValidationException(
        'A pending payment must have a description.',
      );
    }
    if (payment.amount <= 0) {
      throw const RevenueValidationException(
        'A pending payment amount must be greater than zero.',
      );
    }
  }
}