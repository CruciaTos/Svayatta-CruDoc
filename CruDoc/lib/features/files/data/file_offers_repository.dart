import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/access_audit_service.dart';
import 'file_models.dart';
import 'file_offer_model.dart';
import 'files_repository.dart';
import '../lan/device_registry_service.dart';
import '../lan/lan_client.dart';

/// Manages sending and receiving file offers between colleagues in a clinic.
class FileOffersRepository {
  FileOffersRepository._();

  static final FileOffersRepository instance = FileOffersRepository._();

  static const _uuid = Uuid();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _offersCollection(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('file_offers');

  /// Creates and sends file offers for [files] to [recipientUid].
  ///
  /// Each file gets an offer doc with its fingerprint, size, patientId,
  /// and encrypted name/thumb. Writes an audit entry for each sent file.
  Future<List<FileOffer>> createOffers({
    required String clinicId,
    required String recipientUid,
    required List<PatientFile> files,
    FileOfferVia via = FileOfferVia.cloud,
  }) async {
    final senderUid = _currentUid;
    if (senderUid == null || senderUid.isEmpty) {
      throw StateError('Must be signed in to send files.');
    }
    if (files.isEmpty) return const [];

    final batchId = _uuid.v4();
    final now = DateTime.now();
    final expire = now.add(const Duration(days: 30));
    final batch = _firestore.batch();
    final collection = _offersCollection(clinicId);
    final created = <FileOffer>[];

    for (final file in files) {
      final offerId = _uuid.v4();
      final offer = FileOffer(
        id: offerId,
        clinicId: clinicId,
        from: senderUid,
        to: recipientUid,
        batchId: batchId,
        fileId: file.id,
        sha256: file.sha256,
        sizeBytes: file.sizeBytes,
        contentType: file.contentType,
        patientId: file.patientId,
        name: file.name,
        thumb: file.thumb,
        status: FileOfferStatus.sent,
        via: via,
        createdAt: now,
        expireAt: expire,
      );

      created.add(offer);
      final docRef = collection.doc(offerId);
      batch.set(docRef, offer.toFirestore());

      // Audit log
      AccessAuditService.instance.fileSent(
        fileId: file.id,
        recipientUid: recipientUid,
        patientId: file.patientId,
      );
    }

    await batch.commit();
    return created;
  }

  /// Streams incoming waiting offers for [myUid] in [clinicId].
  Stream<List<FileOffer>> watchIncomingOffers({
    required String clinicId,
    required String myUid,
  }) {
    if (clinicId.isEmpty || myUid.isEmpty) {
      return Stream.value(const []);
    }

    return _offersCollection(clinicId)
        .where('to', isEqualTo: myUid)
        .where('status', isEqualTo: 'sent')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              return FileOffer.fromFirestore(
                id: doc.id,
                clinicId: clinicId,
                data: doc.data(),
              );
            }).toList());
  }

  /// Accepts an incoming offer: creates recipient's record and updates status.
  Future<void> acceptOffer(FileOffer offer) async {
    final myUid = _currentUid;
    if (myUid == null || myUid != offer.to) {
      throw StateError('Only the recipient may accept this offer.');
    }

    // Try direct LAN pull if offer was sent via LAN
    if (offer.via == FileOfferVia.lan) {
      try {
        final senderDevice = await DeviceRegistryService.instance.findColleagueDevice(
          clinicId: offer.clinicId,
          colleagueUid: offer.from,
        );
        if (senderDevice != null) {
          final probe = await LanClient.instance.probePeer(senderDevice);
          if (probe != null) {
            final sessionToken = await LanClient.instance.createSession(
              peerIp: probe.ip,
              peerPort: probe.port,
              peerCertSha256: senderDevice.certSha256,
              peerDeviceId: probe.deviceId,
              nonce: probe.nonce,
            );
            if (sessionToken != null) {
              await for (final progress in LanClient.instance.pullBlob(
                senderIp: probe.ip,
                senderPort: probe.port,
                senderCertSha256: senderDevice.certSha256,
                sessionToken: sessionToken,
                offer: offer,
              )) {
                if (progress.isDone) {
                  await _offersCollection(offer.clinicId).doc(offer.id).update({
                    'status': FileOfferStatus.accepted.name,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  return;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[FileOffers] LAN pull failed, falling back to cloud reference: $e');
      }
    }

    // Cloud reference path (or LAN fallback)
    // 1. Update status on Firestore
    await _offersCollection(offer.clinicId).doc(offer.id).update({
      'status': FileOfferStatus.accepted.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Create recipient's own file record pointing to the shared blob
    final newFileId = await FilesRepository.instance.createReceivedFile(offer: offer);

    // 3. Audit log
    AccessAuditService.instance.fileReceived(
      fileId: newFileId,
      senderUid: offer.from,
      patientId: offer.patientId,
    );
  }

  /// Declines an incoming offer.
  Future<void> declineOffer(FileOffer offer) async {
    final myUid = _currentUid;
    if (myUid == null || myUid != offer.to) {
      throw StateError('Only the recipient may decline this offer.');
    }

    await _offersCollection(offer.clinicId).doc(offer.id).update({
      'status': FileOfferStatus.declined.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancels an outgoing offer by sender.
  Future<void> cancelOffer(FileOffer offer) async {
    final myUid = _currentUid;
    if (myUid == null || myUid != offer.from) {
      throw StateError('Only the sender may cancel this offer.');
    }

    await _offersCollection(offer.clinicId).doc(offer.id).update({
      'status': FileOfferStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
