import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Turns downloaded Firestore documents into SQLite rows for
/// FirestoreSyncService.
///
/// Pure and free of singletons so it can run on a worker isolate: decrypting
/// a page of documents (AES-GCM in pure Dart) used to run on the UI isolate,
/// one document at a time. Everything the mapping needs comes in the job: the
/// raw clinic key bytes, whether this person may hold clinical fields, and
/// the documents with their Timestamps already turned into milliseconds.

/// Which visit type each visit collection stamps on its rows. Mirrors
/// FirestoreSyncService's map of the same name.
const Map<String, String> syncVisitFirestoreToType = {
  'appointments': 'clinic',
  'visitations': 'home',
};

/// [value] as plain, isolate-sendable data: Timestamps and DateTimes become
/// epoch milliseconds (which the row mapping reads the same way), lists and
/// maps are copied, and anything else Firestore can hold (a reference, a
/// GeoPoint) becomes its text. Never needed by the mapping, but it keeps a
/// stray field from failing the hand-over to the worker.
Object? plainFirestoreValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is List) return [for (final v in value) plainFirestoreValue(v)];
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) '${e.key}': plainFirestoreValue(e.value),
    };
  }
  return value.toString();
}

/// Builds the message for [mapSyncRows].
Map<String, Object?> syncRowJob({
  required String collection,
  required String doctorId,
  required bool holdsClinicalFields,
  required Uint8List? keyBytes,
  required List<String> ids,
  required List<Map<String, Object?>> data,
}) => {
  'collection': collection,
  'doctorId': doctorId,
  'holdsClinicalFields': holdsClinicalFields,
  'key': keyBytes,
  'ids': ids,
  'data': data,
  'now': DateTime.now().millisecondsSinceEpoch,
};

/// Maps every document of a [syncRowJob]. Top-level so `compute` can send
/// it to a worker isolate. A document that fails to map comes back as null
/// (and is logged) rather than failing its whole page.
List<Map<String, Object?>?> mapSyncRows(Map<String, Object?> job) {
  final collection = job['collection']! as String;
  final doctorId = job['doctorId']! as String;
  final holds = job['holdsClinicalFields']! as bool;
  final keyBytes = job['key'] as Uint8List?;
  final ids = (job['ids']! as List).cast<String>();
  final data = (job['data']! as List).cast<Map<String, Object?>>();
  final now = job['now']! as int;
  final decrypt = FieldCipher.decryptorFor(
    keyBytes == null ? null : enc.Key(keyBytes),
  );
  return [
    for (var i = 0; i < ids.length; i++)
      _mapOne(collection, ids[i], data[i], doctorId, holds, decrypt, now),
  ];
}

Map<String, Object?>? _mapOne(
  String collection,
  String id,
  Map<String, Object?> data,
  String doctorId,
  bool holds,
  String Function(String?) decrypt,
  int now,
) {
  try {
    return syncSqliteRowFor(
      collection,
      id,
      data,
      doctorId,
      holdsClinicalFields: holds,
      decrypt: decrypt,
      now: now,
    );
  } catch (e) {
    debugPrint('[FirestoreSync] could not read $collection/$id: $e');
    return null;
  }
}

int _millis(Object? value, {int? fallback}) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is num) return value.toInt();
  return fallback ?? 0;
}

String _diagnosisForSqlite(Object? raw, String Function(String?) decrypt) {
  if (raw == null) return '';
  if (raw is String) return decrypt(raw);
  if (raw is List) {
    final decryptedList = raw
        .map((d) => decrypt(d.toString()))
        .where((d) => d.isNotEmpty)
        .toList();
    return Patient.diagnosisToStored(decryptedList);
  }
  return raw.toString();
}

/// The SQLite row for one downloaded document of [collection]. The same
/// mapping FirestoreSyncService has always used, plus `remoteGone = 0`: the
/// document was just seen on the server.
Map<String, Object?> syncSqliteRowFor(
  String collection,
  String id,
  Map<String, Object?> data,
  String doctorId, {
  required bool holdsClinicalFields,
  required String Function(String?) decrypt,
  required int now,
}) {
  switch (collection) {
    case 'patients':
      return {
        'id': id,
        'doctorId': doctorId,
        'firstName': decrypt(data['firstName'] as String? ?? ''),
        'lastName': decrypt(data['lastName'] as String? ?? ''),
        'phone': decrypt(data['phone'] as String? ?? ''),
        'email': data['email'] as String? ?? '',
        'gender': data['gender'] as String? ?? '',
        'dateOfBirth': _millis(data['dateOfBirth'], fallback: now),
        // Kept off the device of anyone without clinical access.
        'diagnosis': holdsClinicalFields
            ? _diagnosisForSqlite(data['diagnosis'], decrypt)
            : '[]',
        'notes': holdsClinicalFields
            ? decrypt(data['notes'] as String? ?? '')
            : '',
        'packageBalance': (data['packageBalance'] as num?)?.toDouble() ?? 0,
        'isArchived': (data['isArchived'] as bool? ?? false) ? 1 : 0,
        'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
        // Without this the device always believed every patient was
        // unassigned, whatever the server said.
        'assignedDoctorUids': Patient.assignedToStored(
          Patient.assignedFromStored(data['assignedDoctorUids']),
        ),
      };
    // appointments → visits table with visitType = 'clinic'
    // visitations  → visits table with visitType = 'home'
    // visitType is authoritative from the collection name, not the document
    // field, so a misfiled document is corrected on download.
    case 'appointments':
    case 'visitations':
      return {
        'id': id,
        'doctorId': doctorId,
        'patientId': data['patientId'] as String? ?? '',
        'scheduledStart': _millis(data['scheduledStart'], fallback: now),
        'durationMinutes': (data['durationMinutes'] as num?)?.toInt() ?? 30,
        'address': decrypt(data['address'] as String? ?? ''),
        'latitude': (data['latitude'] as num?)?.toDouble(),
        'longitude': (data['longitude'] as num?)?.toDouble(),
        'mapsLink': data['mapsLink'] as String?,
        'visitType': syncVisitFirestoreToType[collection]!,
        'status': data['status'] as String? ?? 'scheduled',
        'isPaid': (data['isPaid'] as bool? ?? false) ? 1 : 0,
        'amountCharged': (data['amountCharged'] as num?)?.toDouble(),
        'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
        'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
        'invoiceId': data['invoiceId'] as String?,
        'packageId': data['packageId'] as String?,
        'groupId': data['groupId'] as String?,
        'treatmentType': data['treatmentType'] as String?,
        'therapistNotes': data['therapistNotes'] == null
            ? null
            : decrypt(data['therapistNotes'] as String?),
        'reminderStatus': data['reminderStatus'] as String?,
        'calendarEventId': data['calendarEventId'] as String?,
        'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
        'createdByUid': data['createdByUid'] as String? ?? '',
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'revenue_entries':
      return {
        'id': id,
        'doctorId': doctorId,
        'date': _millis(data['date'], fallback: now),
        'description': decrypt(data['description'] as String? ?? ''),
        'amount': data['amount'] is String
            ? (double.tryParse(decrypt(data['amount'] as String)) ?? 0)
            : ((data['amount'] as num?)?.toDouble() ?? 0),
        'type': data['type'] as String? ?? 'miscellaneous',
        'kind': data['kind'] as String? ?? 'income',
        'payer': data['payer'] == null
            ? null
            : decrypt(data['payer'] as String?),
        'patientId': data['patientId'] as String?,
        'visitId': data['visitId'] as String?,
        'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
        'isActive': 1,
        'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
        'createdByUid': data['createdByUid'] as String? ?? '',
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'pending_payments':
      return {
        'id': id,
        'doctorId': doctorId,
        'date': _millis(data['date'], fallback: now),
        'description': decrypt(data['description'] as String? ?? ''),
        'amount': data['amount'] is String
            ? (double.tryParse(decrypt(data['amount'] as String)) ?? 0)
            : ((data['amount'] as num?)?.toDouble() ?? 0),
        'isPaid': (data['isPaid'] as bool? ?? false) ? 1 : 0,
        'payer': data['payer'] == null
            ? null
            : decrypt(data['payer'] as String?),
        'patientId': data['patientId'] as String?,
        'visitId': data['visitId'] as String?,
        'notes': data['notes'] == null
            ? null
            : decrypt(data['notes'] as String?),
        'isActive': 1,
        'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
        'createdByUid': data['createdByUid'] as String? ?? '',
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'medicines':
      return {
        'id': id,
        'doctorId': doctorId,
        'name': data['name'] as String? ?? '',
        'category': data['category'] as String? ?? '',
        'unit': data['unit'] as String? ?? '',
        'currentStock': (data['currentStock'] as num?)?.toInt() ?? 0,
        'reorderThreshold': (data['reorderThreshold'] as num?)?.toInt() ?? 10,
        'goodStockLevel': (data['goodStockLevel'] as num?)?.toInt(),
        'unitPrice': (data['unitPrice'] as num?)?.toDouble(),
        'supplierName': data['supplierName'] as String?,
        'batchNumber': data['batchNumber'] as String?,
        'receiptStoragePath': data['receiptStoragePath'] as String?,
        'expiryDate': data['expiryDate'] == null
            ? null
            : _millis(data['expiryDate'], fallback: now),
        'lowStockNotifiedAt': data['lowStockNotifiedAt'] == null
            ? null
            : _millis(data['lowStockNotifiedAt'], fallback: now),
        'expiryNotifiedAt': data['expiryNotifiedAt'] == null
            ? null
            : _millis(data['expiryNotifiedAt'], fallback: now),
        'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'stock_transactions':
      return {
        'id': id,
        'medicineId': data['medicineId'] as String? ?? '',
        'doctorId': doctorId,
        'type': data['type'] as String? ?? 'restock',
        'quantity': (data['quantity'] as num?)?.toInt() ?? 0,
        'resultingStock': (data['resultingStock'] as num?)?.toInt() ?? 0,
        'note': data['note'] as String?,
        'linkedVisitId': data['linkedVisitId'] as String?,
        'batchNumber': data['batchNumber'] as String?,
        'expiryDate': data['expiryDate'] == null
            ? null
            : _millis(data['expiryDate'], fallback: now),
        'unitCost': (data['unitCost'] as num?)?.toDouble(),
        'supplierName': data['supplierName'] as String?,
        'billKey': data['billKey'] as String?,
        'groupId': data['groupId'] as String?,
        'isActive': (data['isActive'] as bool? ?? true) ? 1 : 0,
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'walk_in_queue':
      return {
        'id': id,
        'doctorId': doctorId,
        'patientId': data['patientId'] as String?,
        'walkInName': data['walkInName'] as String?,
        'walkInPhone': data['walkInPhone'] as String?,
        'tokenNumber': (data['tokenNumber'] as num?)?.toInt() ?? 0,
        'queueDate': data['queueDate'] as String? ?? '',
        'status': data['status'] as String? ?? 'waiting',
        'priority': data['priority'] as String? ?? 'normal',
        'reason': data['reason'] as String?,
        'checkedInAt': _millis(data['checkedInAt'], fallback: now),
        'calledAt': data['calledAt'] == null
            ? null
            : _millis(data['calledAt'], fallback: now),
        'consultationStartedAt': data['consultationStartedAt'] == null
            ? null
            : _millis(data['consultationStartedAt'], fallback: now),
        'completedAt': data['completedAt'] == null
            ? null
            : _millis(data['completedAt'], fallback: now),
        'linkedVisitId': data['linkedVisitId'] as String?,
        'groupId': data['groupId'] as String?,
        'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
        'attendingDoctorUid': data['attendingDoctorUid'] as String? ?? '',
        'createdByUid': data['createdByUid'] as String? ?? '',
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'dental_records':
      return {
        'id': id,
        'doctorId': doctorId,
        'patientId': data['patientId'] as String? ?? '',
        'kind': data['kind'] as String? ?? '',
        'data': decrypt(data['data'] as String? ?? '{}'),
        'recordedAt': _millis(data['recordedAt'], fallback: now),
        'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    case 'radiology_docs':
      return {
        'id': id,
        'doctorId': doctorId,
        'kind': data['kind'] as String? ?? '',
        'patientId': data['patientId'] as String? ?? '',
        'data': decrypt(data['data'] as String? ?? '{}'),
        'isDeleted': (data['isDeleted'] as bool? ?? false) ? 1 : 0,
        'createdAt': _millis(data['createdAt'], fallback: now),
        'updatedAt': _millis(data['updatedAt'], fallback: now),
        'syncStatus': 'synced',
        'pendingDelete': 0,
        'lastSyncedAt': now,
        'remoteGone': 0,
      };
    default:
      throw ArgumentError('Unsupported sync collection: $collection');
  }
}
