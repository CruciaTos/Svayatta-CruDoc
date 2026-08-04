import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/revenue_exceptions.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/services/revenue_local_service.dart';

/// Clean API the presentation layer talks to for anything revenue-related.
class RevenueRepository {
  RevenueRepository({
    RevenueLocalService? localService,
    FirestoreSyncService? syncService,
  }) : _localService = localService ?? RevenueLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance;

  final RevenueLocalService _localService;
  final FirestoreSyncService _syncService;

  /// The signed-in doctor's UID — see PatientRepository for why this
  /// matters and what it guards against.
  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
  }

  Map<String, dynamic> _encryptedForFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['description'] is String) {
      out['description'] = FieldCipher.encrypt(out['description'] as String);
    }
    if (out['payer'] is String) {
      out['payer'] = FieldCipher.encrypt(out['payer'] as String);
    }
    if (out['notes'] is String) {
      out['notes'] = FieldCipher.encrypt(out['notes'] as String);
    }
    if (out['amount'] is num) {
      out['amount'] = FieldCipher.encrypt(out['amount'].toString());
    }
    if (out['doctorId'] is String) {
      out['doctorId'] = FieldCipher.encrypt(out['doctorId'] as String);
    }
    return out;
  }

  Map<String, dynamic> _decryptedFromFirestore(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['description'] is String) {
      out['description'] = FieldCipher.decrypt(out['description'] as String);
    }
    if (out['payer'] is String) {
      out['payer'] = FieldCipher.decrypt(out['payer'] as String);
    }
    if (out['notes'] is String) {
      out['notes'] = FieldCipher.decrypt(out['notes'] as String);
    }
    if (out['amount'] is String) {
      final parsed = double.tryParse(FieldCipher.decrypt(out['amount'] as String));
      out['amount'] = parsed ?? 0.0;
    }
    if (out['doctorId'] is String) {
      out['doctorId'] = FieldCipher.decrypt(out['doctorId'] as String);
    }
    return out;
  }

  // ---------------- revenue entries ----------------

  /// Records a new payment and returns its newly assigned id.
  Future<String> createRevenueEntry(RevenueEntry entry) async {
    _validateEntry(entry);

    final now = DateTime.now();
    final id = entry.id.trim().isEmpty ? const Uuid().v4() : entry.id;
    final entryWithId = RevenueEntry(
      id: id,
      doctorId: _currentDoctorId,
      date: entry.date,
      description: entry.description,
      amount: entry.amount,
      type: entry.type,
      kind: entry.kind, 
      payer: entry.payer,
      patientId: entry.patientId,
      visitId: entry.visitId,
      isDeleted: entry.isDeleted,
      createdAt: now,
      updatedAt: now,
    );

    if (kIsWeb) {
      await FirebaseFirestore.instance
          .collection('revenue_entries')
          .doc(id)
          .set(_encryptedForFirestore(entryWithId.toMap()));
      return id;
    }

    await _localService.upsertRevenueEntry(entryWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Streams the live list of active (non-deleted) revenue entries.
  Stream<List<RevenueEntry>> watchRevenueEntries() {
    final doctorId = FirebaseAuth.instance.currentUser?.uid;
    if (doctorId == null || doctorId.isEmpty) {
      return Stream.value(const <RevenueEntry>[]);
    }
    if (kIsWeb) {
      return FirebaseFirestore.instance
          .collection('revenue_entries')
          .where('doctorId', isEqualTo: doctorId)
          .snapshots()
          .map((snapshot) {
        final list = snapshot.docs
            .map((doc) => RevenueEntry.fromMap(_decryptedFromFirestore(doc.data()), id: doc.id))
            .where((e) => !e.isDeleted)
            .toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      });
    }
    return _localService.watchRevenueEntries();
  }

  /// Streams the live list of still-unpaid pending payments.
  Stream<List<PendingPayment>> watchPendingPayments() {
    if (kIsWeb) {
      return FirebaseFirestore.instance
          .collection('pending_payments')
          .where('doctorId', isEqualTo: _currentDoctorId)
          .snapshots()
          .map((snapshot) {
        final list = snapshot.docs
            .map((doc) => PendingPayment.fromMap(_decryptedFromFirestore(doc.data()), id: doc.id))
            .where((p) => !p.isPaid)
            .toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      });
    }
    return _localService.watchPendingPayments();
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

  // ---------------- pending payments ----------------

  /// Records a new amount owed and returns its newly assigned id.
  Future<String> createPendingPayment(PendingPayment payment) async {
    _validatePendingPayment(payment);

    final now = DateTime.now();
    final id = payment.id.trim().isEmpty ? const Uuid().v4() : payment.id;
    final paymentWithId = PendingPayment(
      id: id,
      doctorId: _currentDoctorId,
      date: payment.date,
      description: payment.description,
      amount: payment.amount,
      isPaid: false,
      payer: payment.payer,
      patientId: payment.patientId,
      visitId: payment.visitId,
      notes: payment.notes,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertPendingPayment(paymentWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Updates arbitrary fields on an existing pending payment — e.g. from
  /// its details sheet, which lets the amount, description, notes, and
  /// date be edited. `payer`/`patientId`/`visitId` are never passed
  /// here: they're set once at creation and stay in sync with the
  /// patient/visit that generated the payment, exactly like
  /// [PendingPayment.payer] documents. `updatedAt` is stamped
  /// automatically regardless of what's passed here.
  Future<void> updatePendingPayment(
    String paymentId,
    Map<String, dynamic> data,
  ) async {
    if (data.containsKey('description')) {
      final description = data['description'] as String? ?? '';
      if (description.trim().isEmpty) {
        throw const RevenueValidationException(
          'A pending payment must have a description.',
        );
      }
    }
    if (data.containsKey('amount')) {
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) {
        throw const RevenueValidationException(
          'A pending payment amount must be greater than zero.',
        );
      }
    }

    final localData = Map<String, dynamic>.from(data)
      ..['updatedAt'] = DateTime.now();

    await _localService.updatePendingPayment(paymentId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Marks a pending payment as collected: flips `PendingPayment.isPaid`
  /// and creates the matching [RevenueEntry] in one step, carrying over
  /// the pending payment's current — possibly edited — amount,
  /// description, date, payer, patientId, and visitId. Tagged
  /// [RevenueType.visit] when it's linked to a visit (e.g. a completed
  /// visitation), or [RevenueType.miscellaneous] otherwise (e.g. a
  /// manually-added, standalone pending payment like a lab test). The
  /// pending payment document itself is never deleted — only marked
  /// paid — so what was owed and when it was settled stays in the
  /// history.
  ///
  /// This only settles the pending payment and revenue ledger. If it's
  /// linked to a visit, prefer `VisitRepository.markVisitationPaymentPaid`
  /// instead, which also flips that visit's own paid status so its
  /// Session History entry stays in sync.
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
        date: pending.date,
        description: pending.description,
        amount: pending.amount,
        type: pending.visitId != null
            ? RevenueType.visit
            : RevenueType.miscellaneous,
        payer: pending.payer,
        patientId: pending.patientId,
        visitId: pending.visitId,
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

  /// Fetches the pending payment linked to [visitId], if one exists —
  /// used by `VisitRepository.updateStatus` so completing the same
  /// visitation twice (e.g. Completed -> Reopen -> Completed) never
  /// creates a duplicate pending payment.
  Future<PendingPayment?> getPendingPaymentForVisit(String visitId) {
    return _localService.getPendingPaymentForVisit(visitId);
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