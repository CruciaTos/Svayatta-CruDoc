import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/field_cipher.dart';

/// The lifecycle status of a file offer sent to a colleague.
enum FileOfferStatus {
  sent,
  accepted,
  declined,
  cancelled;

  static FileOfferStatus fromName(String? name) => switch (name) {
    'accepted' => FileOfferStatus.accepted,
    'declined' => FileOfferStatus.declined,
    'cancelled' => FileOfferStatus.cancelled,
    _ => FileOfferStatus.sent,
  };
}

/// The transport path chosen for delivering the offer / file bytes.
enum FileOfferVia {
  cloud,
  lan;

  static FileOfferVia fromName(String? name) => switch (name) {
    'lan' => FileOfferVia.lan,
    _ => FileOfferVia.cloud,
  };
}

/// An offer to send a file to a colleague within the clinic.
/// Stored in Firestore at `clinics/{clinicId}/file_offers/{offerId}`.
@immutable
class FileOffer {
  const FileOffer({
    required this.id,
    required this.clinicId,
    required this.from,
    required this.to,
    required this.batchId,
    required this.fileId,
    required this.sha256,
    required this.sizeBytes,
    required this.contentType,
    required this.patientId,
    required this.name,
    required this.thumb,
    required this.status,
    required this.via,
    required this.createdAt,
    required this.expireAt,
    this.updatedAt,
    this.fromDoctorName = '',
  });

  final String id;
  final String clinicId;

  /// Sender uid.
  final String from;

  /// Recipient uid.
  final String to;

  /// Groups files sent together in one action.
  final String batchId;

  /// The sender's original file record id.
  final String fileId;

  /// SHA-256 fingerprint of the file.
  final String sha256;
  final int sizeBytes;
  final String contentType;

  /// Patient id. Patient notes and conditions never travel with the offer.
  final String patientId;

  /// File name (plain locally, encrypted in Firestore).
  final String name;

  /// Base64 thumbnail (plain locally, encrypted in Firestore).
  final String thumb;

  final FileOfferStatus status;
  final FileOfferVia via;
  final DateTime createdAt;
  final DateTime expireAt;
  final DateTime? updatedAt;

  /// Name of the sender for display in the Incoming card.
  final String fromDoctorName;

  FileOffer copyWith({
    FileOfferStatus? status,
    FileOfferVia? via,
    DateTime? updatedAt,
    String? fromDoctorName,
  }) => FileOffer(
    id: id,
    clinicId: clinicId,
    from: from,
    to: to,
    batchId: batchId,
    fileId: fileId,
    sha256: sha256,
    sizeBytes: sizeBytes,
    contentType: contentType,
    patientId: patientId,
    name: name,
    thumb: thumb,
    status: status ?? this.status,
    via: via ?? this.via,
    createdAt: createdAt,
    expireAt: expireAt,
    updatedAt: updatedAt ?? this.updatedAt,
    fromDoctorName: fromDoctorName ?? this.fromDoctorName,
  );

  /// Converts to Firestore map with encrypted PHI fields (name, thumb).
  Map<String, Object?> toFirestore() => {
    'from': from,
    'to': to,
    'batchId': batchId,
    'fileId': fileId,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'contentType': contentType,
    'patientId': patientId,
    'name': FieldCipher.encrypt(name),
    'thumb': FieldCipher.encrypt(thumb),
    'status': status.name,
    'via': via.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'expireAt': Timestamp.fromDate(expireAt),
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
  };

  /// [toFirestore] as plain JSON (dates in milliseconds, which
  /// [FileOffer.fromFirestore] reads too) plus the id, for sending over
  /// Wi-Fi and for the offline queue. A Firestore Timestamp can't be
  /// JSON-encoded.
  Map<String, Object?> toJson() => {
    ...toFirestore(),
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'expireAt': expireAt.millisecondsSinceEpoch,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
  };

  /// Constructs a FileOffer from a Firestore snapshot, decrypting name and thumb.
  factory FileOffer.fromFirestore({
    required String id,
    required String clinicId,
    required Map<String, dynamic> data,
    String fromDoctorName = '',
  }) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    final created = parseDate(data['createdAt'], DateTime.now());
    final expire = parseDate(
      data['expireAt'],
      created.add(const Duration(days: 30)),
    );
    final updated = data['updatedAt'] != null
        ? parseDate(data['updatedAt'], created)
        : null;

    final encName = data['name'] as String? ?? '';
    final encThumb = data['thumb'] as String? ?? '';

    return FileOffer(
      id: id,
      clinicId: clinicId,
      from: data['from'] as String? ?? '',
      to: data['to'] as String? ?? '',
      batchId: data['batchId'] as String? ?? '',
      fileId: data['fileId'] as String? ?? '',
      sha256: data['sha256'] as String? ?? '',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
      contentType: data['contentType'] as String? ?? '',
      patientId: data['patientId'] as String? ?? '',
      name: FieldCipher.decrypt(encName),
      thumb: FieldCipher.decrypt(encThumb),
      status: FileOfferStatus.fromName(data['status'] as String?),
      via: FileOfferVia.fromName(data['via'] as String?),
      createdAt: created,
      expireAt: expire,
      updatedAt: updated,
      fromDoctorName: fromDoctorName,
    );
  }
}
