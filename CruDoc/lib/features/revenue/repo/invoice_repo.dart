import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';
import 'package:doctor_management_app/features/revenue/data/services/invoice_local_service.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/pdf/data/doc_numbering.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context_builder.dart';

class InvoiceRepository {
  InvoiceRepository({
    InvoiceLocalService? localService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _localService = localService ?? InvoiceLocalService(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final InvoiceLocalService _localService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Current authenticated doctor's ID — multi-tenant protection.
  String get _currentDoctorId {
    final uid =
        ClinicSession.instance.access?.clinicId ?? _auth.currentUser?.uid;
    return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
  }

  /// Sanitizes text inputs against script/injection attacks.
  String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'[<>]'), '') // remove dangerous HTML tags
        .replaceAll(
          RegExp(r'^[=+@-]'),
          '\'',
        ) // escape formula injection characters
        .trim();
  }

  Map<String, dynamic> _encryptMap(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['patientName'] is String &&
        (out['patientName'] as String).isNotEmpty) {
      out['patientName'] = FieldCipher.encrypt(out['patientName'] as String);
    }
    if (out['service'] is String && (out['service'] as String).isNotEmpty) {
      out['service'] = FieldCipher.encrypt(out['service'] as String);
    }
    if (out['notes'] is String && (out['notes'] as String).isNotEmpty) {
      out['notes'] = FieldCipher.encrypt(out['notes'] as String);
    }
    if (out['billJson'] is String && (out['billJson'] as String).isNotEmpty) {
      out['billJson'] = FieldCipher.encrypt(out['billJson'] as String);
    }
    if (out['amount'] != null) {
      out['amount'] = FieldCipher.encrypt(out['amount'].toString());
    }
    return out;
  }

  Map<String, dynamic> _decryptMap(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['patientName'] is String &&
        (out['patientName'] as String).isNotEmpty) {
      out['patientName'] = FieldCipher.decrypt(out['patientName'] as String);
    }
    if (out['service'] is String && (out['service'] as String).isNotEmpty) {
      out['service'] = FieldCipher.decrypt(out['service'] as String);
    }
    if (out['notes'] is String && (out['notes'] as String).isNotEmpty) {
      out['notes'] = FieldCipher.decrypt(out['notes'] as String);
    }
    if (out['billJson'] is String && (out['billJson'] as String).isNotEmpty) {
      out['billJson'] = FieldCipher.decrypt(out['billJson'] as String);
    }
    if (out['amount'] is String) {
      final decStr = FieldCipher.decrypt(out['amount'] as String);
      out['amount'] = double.tryParse(decStr) ?? 0.0;
    } else if (out['amount'] is num) {
      out['amount'] = (out['amount'] as num).toDouble();
    }
    return out;
  }

  /// Watches invoices belonging to the signed-in doctor directly from Cloud Firestore.
  Stream<List<InvoiceModel>> watchInvoices() {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous' || _auth.currentUser == null) {
      return Stream.value(<InvoiceModel>[]);
    }

    return _firestore
        .collection('invoices')
        .where('doctorId', isEqualTo: doctorId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['id'] = doc.id;

                // Multi-tenant protection: verify doctorId matching
                final docDoctorId = (data['doctorId'] ?? '').toString();
                if (docDoctorId.isNotEmpty &&
                    doctorId != 'anonymous' &&
                    docDoctorId != doctorId) {
                  return null;
                }

                final decrypted = _decryptMap(data);
                return InvoiceModel.fromMap(decrypted);
              })
              .whereType<InvoiceModel>()
              .toList();

          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        })
        .handleError((error) {
          return <InvoiceModel>[];
        });
  }

  /// Start of today, for "overdue".
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// A Firestore write only completes once the server has it, so offline it
  /// would hold the bill form forever. Firestore keeps the write and sends
  /// it when the connection is back; after a few seconds we stop waiting.
  /// Real errors (permission denied) still surface.
  static Future<void> _settle(Future<void> write) =>
      write.timeout(const Duration(seconds: 5), onTimeout: () {});

  /// Creates a new billed invoice with line items.
  Future<InvoiceModel> createBilledInvoice({
    required String patientName,
    String? patientId,
    required InvoiceBill bill,
    required DateTime date,
    DateTime? dueDate,
    String notes = '',
    String? attendingDoctorUid,
    String? invoiceNumber,
  }) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw StateError('User must be authenticated to create invoices.');
    }

    final trimmedNumber = (invoiceNumber ?? '').trim();
    final String number;
    if (trimmedNumber.isNotEmpty) {
      final dup = await _firestore
          .collection('invoices')
          .where('doctorId', isEqualTo: doctorId)
          .where('invoiceNumber', isEqualTo: trimmedNumber)
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty) {
        throw StateError('Invoice number $trimmedNumber is already used');
      }
      number = trimmedNumber;
    } else {
      number = await DocNumbering.next(DocKind.invoice, date);
    }

    final totals = InvoiceTotals.of(bill);
    final amount = totals.grand / 100.0;

    final String status;
    if (totals.balance <= 0) {
      status = 'Paid';
    } else if (dueDate != null && dueDate.isBefore(_today())) {
      status = 'Overdue';
    } else {
      status = 'Pending';
    }

    final treatments = bill.items
        .where((i) => i.kind == 'treatment')
        .map((i) => i.name.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
    final medicines = bill.items
        .where((i) => i.kind == 'medicine')
        .map((i) => i.name.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
    final service = [
      if (treatments.isNotEmpty) 'Treatments: $treatments',
      if (medicines.isNotEmpty) 'Medicines: $medicines',
      if (treatments.isEmpty && medicines.isEmpty && bill.items.isNotEmpty)
        bill.items
            .map((i) => i.name.trim())
            .where((s) => s.isNotEmpty)
            .join(', '),
    ].join(' | ');

    final currentAuthUid = _auth.currentUser?.uid ?? '';
    final isDoctor = ClinicSession.instance.access?.kind == MemberKind.doctor;
    final attending =
        (attendingDoctorUid != null && attendingDoctorUid.trim().isNotEmpty)
        ? attendingDoctorUid.trim()
        : (isDoctor ? currentAuthUid : '');

    var resolvedTemplateId = bill.templateId;
    if (resolvedTemplateId.isEmpty) {
      final t = await DocRepository.instance.resolveTemplate(
        DocKind.invoice,
        issuingDoctorUid: attending.isNotEmpty ? attending : null,
      );
      resolvedTemplateId = t.id;
    }

    final signedBy =
        docSignerFor(attending.isNotEmpty ? attending : null) ?? '';
    final updatedBill = bill.copyWith(
      signedByUid: signedBy,
      templateId: resolvedTemplateId,
    );

    final now = DateTime.now();
    final id =
        'INV-${now.year}-${now.millisecondsSinceEpoch.toString().substring(7)}';

    final invoice = InvoiceModel(
      id: id,
      doctorId: doctorId,
      patientId: patientId,
      patientName: sanitizeInput(patientName),
      service: sanitizeInput(
        service.isNotEmpty ? service : 'Medical Consultation',
      ),
      amount: amount,
      status: status,
      date: date,
      dueDate: dueDate,
      notes: sanitizeInput(notes),
      attendingDoctorUid: attending,
      createdByUid: currentAuthUid,
      createdAt: now,
      updatedAt: now,
      invoiceNumber: number,
      billJson: updatedBill.toJson(),
    );

    final encryptedData = _encryptMap(invoice.toMap());
    await _settle(_firestore.collection('invoices').doc(id).set(encryptedData));

    if (!kIsWeb) {
      await _localService.upsertInvoice(invoice);
    }

    return invoice;
  }

  /// Updates an existing billed invoice.
  Future<InvoiceModel> updateBilledInvoice(
    InvoiceModel inv, {
    required String patientName,
    String? patientId,
    required InvoiceBill bill,
    required DateTime date,
    DateTime? dueDate,
    String notes = '',
    String? attendingDoctorUid,
    String? invoiceNumber,
  }) async {
    if (inv.isCancelled) {
      throw StateError('Cannot edit a cancelled invoice');
    }

    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw StateError('User must be authenticated to update invoices.');
    }

    final trimmedNumber = (invoiceNumber ?? inv.invoiceNumber).trim();
    if (trimmedNumber.isNotEmpty && trimmedNumber != inv.invoiceNumber) {
      final dup = await _firestore
          .collection('invoices')
          .where('doctorId', isEqualTo: doctorId)
          .where('invoiceNumber', isEqualTo: trimmedNumber)
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty && dup.docs.first.id != inv.id) {
        throw StateError('Invoice number $trimmedNumber is already used');
      }
    }

    final totals = InvoiceTotals.of(bill);
    final amount = totals.grand / 100.0;

    final String status;
    if (totals.balance <= 0) {
      status = 'Paid';
    } else if (dueDate != null && dueDate.isBefore(_today())) {
      status = 'Overdue';
    } else {
      status = 'Pending';
    }

    final treatments = bill.items
        .where((i) => i.kind == 'treatment')
        .map((i) => i.name.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
    final medicines = bill.items
        .where((i) => i.kind == 'medicine')
        .map((i) => i.name.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
    final service = [
      if (treatments.isNotEmpty) 'Treatments: $treatments',
      if (medicines.isNotEmpty) 'Medicines: $medicines',
      if (treatments.isEmpty && medicines.isEmpty && bill.items.isNotEmpty)
        bill.items
            .map((i) => i.name.trim())
            .where((s) => s.isNotEmpty)
            .join(', '),
    ].join(' | ');

    final currentAuthUid = _auth.currentUser?.uid ?? '';
    final isDoctor = ClinicSession.instance.access?.kind == MemberKind.doctor;
    final attending =
        (attendingDoctorUid != null && attendingDoctorUid.trim().isNotEmpty)
        ? attendingDoctorUid.trim()
        : (inv.attendingDoctorUid.isNotEmpty
              ? inv.attendingDoctorUid
              : (isDoctor ? currentAuthUid : ''));

    final signedBy =
        docSignerFor(attending.isNotEmpty ? attending : null) ?? '';
    final updatedBill = bill.copyWith(
      signedByUid: signedBy,
      templateId: bill.templateId.isNotEmpty
          ? bill.templateId
          : inv.bill.templateId,
    );

    final now = DateTime.now();
    final updatedInvoice = inv.copyWith(
      patientId: patientId,
      patientName: sanitizeInput(patientName),
      service: sanitizeInput(service.isNotEmpty ? service : inv.service),
      amount: amount,
      status: status,
      date: date,
      dueDate: dueDate,
      notes: sanitizeInput(notes),
      attendingDoctorUid: attending,
      updatedAt: now,
      invoiceNumber: trimmedNumber.isNotEmpty
          ? trimmedNumber
          : inv.invoiceNumber,
      billJson: updatedBill.toJson(),
    );

    final encryptedData = _encryptMap(updatedInvoice.toMap());
    await _settle(
      _firestore
          .collection('invoices')
          .doc(inv.id)
          .set(encryptedData, SetOptions(merge: true)),
    );

    if (!kIsWeb) {
      await _localService.upsertInvoice(updatedInvoice);
    }

    return updatedInvoice;
  }

  /// Cancels an invoice without deleting it.
  Future<void> cancelInvoice(String id) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return;

    final now = DateTime.now();
    final docRef = _firestore.collection('invoices').doc(id);
    final doc = await docRef.get();
    if (doc.exists && doc.data()?['doctorId'] == doctorId) {
      await _settle(
        docRef.update({
          'status': 'Cancelled',
          'updatedAt': now.millisecondsSinceEpoch,
        }),
      );

      if (!kIsWeb) {
        final existing = await _localService.getInvoicesForDoctor(doctorId);
        final match = existing.where((i) => i.id == id).firstOrNull;
        if (match != null) {
          await _localService.upsertInvoice(
            match.copyWith(status: 'Cancelled', updatedAt: now),
          );
        }
      }
    }
  }

  /// Updates the template associated with an invoice bill.
  Future<void> setInvoiceTemplate(InvoiceModel inv, String templateId) async {
    final updatedBill = inv.bill.copyWith(templateId: templateId);
    final now = DateTime.now();
    final updatedInvoice = inv.copyWith(
      billJson: updatedBill.toJson(),
      updatedAt: now,
    );
    final encryptedData = _encryptMap(updatedInvoice.toMap());
    await _settle(
      _firestore
          .collection('invoices')
          .doc(inv.id)
          .set(encryptedData, SetOptions(merge: true)),
    );
    if (!kIsWeb) {
      await _localService.upsertInvoice(updatedInvoice);
    }
  }

  /// Creates a new invoice with sanitized fields and encrypted values (legacy caller).
  Future<String> createInvoice({
    required String patientName,
    required String service,
    required double amount,
    required String status,
    String? patientId,
    DateTime? dueDate,
    String notes = '',
    String? attendingDoctorUid,
    String? createdByUid,
  }) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw StateError('User must be authenticated to create invoices.');
    }

    final sanitizedName = sanitizeInput(patientName);
    final sanitizedService = sanitizeInput(service);
    final sanitizedNotes = sanitizeInput(notes);

    final now = DateTime.now();
    final id =
        'INV-${now.year}-${now.millisecondsSinceEpoch.toString().substring(7)}';

    final currentAuthUid = _auth.currentUser?.uid ?? '';
    final isDoctor = ClinicSession.instance.access?.kind == MemberKind.doctor;
    final attending =
        (attendingDoctorUid != null && attendingDoctorUid.trim().isNotEmpty)
        ? attendingDoctorUid.trim()
        : (isDoctor ? currentAuthUid : '');
    final creator = (createdByUid != null && createdByUid.trim().isNotEmpty)
        ? createdByUid.trim()
        : currentAuthUid;

    final invoice = InvoiceModel(
      id: id,
      doctorId: doctorId,
      patientId: patientId,
      patientName: sanitizedName,
      service: sanitizedService,
      amount: amount,
      status: status,
      date: now,
      dueDate: dueDate,
      notes: sanitizedNotes,
      attendingDoctorUid: attending,
      createdByUid: creator,
      createdAt: now,
      updatedAt: now,
    );

    // Save to Firestore encrypted
    final encryptedData = _encryptMap(invoice.toMap());
    await _settle(_firestore.collection('invoices').doc(id).set(encryptedData));

    // Save to local database (mobile)
    if (!kIsWeb) {
      await _localService.upsertInvoice(invoice);
    }

    return id;
  }

  /// Updates invoice status (e.g. Pending -> Paid) safely.
  Future<void> updateInvoiceStatus(String invoiceId, String newStatus) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return;

    final sanitizedStatus = sanitizeInput(newStatus);
    final now = DateTime.now();

    await _firestore.collection('invoices').doc(invoiceId).update({
      'status': sanitizedStatus,
      'updatedAt': now.millisecondsSinceEpoch,
    });
  }

  /// Deletes an invoice with multi-tenant check.
  Future<void> deleteInvoice(String invoiceId) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return;

    final docRef = _firestore.collection('invoices').doc(invoiceId);
    final doc = await docRef.get();

    if (doc.exists && doc.data()?['doctorId'] == doctorId) {
      await docRef.delete();
      if (!kIsWeb) {
        await _localService.deleteInvoice(invoiceId, doctorId);
      }
    }
  }
}
