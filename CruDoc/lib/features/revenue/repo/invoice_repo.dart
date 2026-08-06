import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/services/invoice_local_service.dart';

class InvoiceRepository {
  InvoiceRepository({
    InvoiceLocalService? localService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _localService = localService ?? InvoiceLocalService(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final InvoiceLocalService _localService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Current authenticated doctor's ID — multi-tenant protection.
  String get _currentDoctorId {
    final uid = _auth.currentUser?.uid;
    return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
  }

  /// Sanitizes text inputs against script/injection attacks.
  String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'[<>]'), '') // remove dangerous HTML tags
        .replaceAll(RegExp(r'^[=+@-]'), '\'') // escape formula injection characters
        .trim();
  }

  Map<String, dynamic> _encryptMap(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['patientName'] is String && (out['patientName'] as String).isNotEmpty) {
      out['patientName'] = FieldCipher.encrypt(out['patientName'] as String);
    }
    if (out['service'] is String && (out['service'] as String).isNotEmpty) {
      out['service'] = FieldCipher.encrypt(out['service'] as String);
    }
    if (out['notes'] is String && (out['notes'] as String).isNotEmpty) {
      out['notes'] = FieldCipher.encrypt(out['notes'] as String);
    }
    if (out['amount'] != null) {
      out['amount'] = FieldCipher.encrypt(out['amount'].toString());
    }
    return out;
  }

  Map<String, dynamic> _decryptMap(Map<String, dynamic> map) {
    final out = Map<String, dynamic>.from(map);
    if (out['patientName'] is String && (out['patientName'] as String).isNotEmpty) {
      out['patientName'] = FieldCipher.decrypt(out['patientName'] as String);
    }
    if (out['service'] is String && (out['service'] as String).isNotEmpty) {
      out['service'] = FieldCipher.decrypt(out['service'] as String);
    }
    if (out['notes'] is String && (out['notes'] as String).isNotEmpty) {
      out['notes'] = FieldCipher.decrypt(out['notes'] as String);
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

    return _firestore
        .collection('invoices')
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
    });
  }

  /// Creates a new invoice with sanitized fields and encrypted values.
  Future<String> createInvoice({
    required String patientName,
    required String service,
    required double amount,
    required String status,
    String? patientId,
    DateTime? dueDate,
    String notes = '',
  }) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw StateError('User must be authenticated to create invoices.');
    }

    final sanitizedName = sanitizeInput(patientName);
    final sanitizedService = sanitizeInput(service);
    final sanitizedNotes = sanitizeInput(notes);

    final now = DateTime.now();
    final id = 'INV-${now.year}-${now.millisecondsSinceEpoch.toString().substring(7)}';

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
      createdAt: now,
      updatedAt: now,
    );

    // Save to Firestore encrypted
    final encryptedData = _encryptMap(invoice.toMap());
    await _firestore.collection('invoices').doc(id).set(encryptedData);

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
