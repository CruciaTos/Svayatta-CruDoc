import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';

void main() {
  group('FileOffer Model & Serialization', () {
    test('roundtrips toFirestore and fromFirestore with encryption', () {
      final now = DateTime.utc(2026, 10, 27, 10, 0, 0);
      final expire = now.add(const Duration(days: 7));

      final original = FileOffer(
        id: 'offer_123',
        clinicId: 'clinic_abc',
        from: 'uid_sender',
        to: 'uid_recipient',
        batchId: 'batch_xyz',
        fileId: 'file_orig_789',
        sha256: 'a' * 64,
        sizeBytes: 1048576,
        contentType: 'image/jpeg',
        patientId: 'patient_456',
        name: 'chest_xray.jpg',
        thumb: 'base64thumbnaildata==',
        status: FileOfferStatus.sent,
        via: FileOfferVia.cloud,
        createdAt: now,
        expireAt: expire,
      );

      final firestoreMap = original.toFirestore();

      // Check unencrypted metadata fields
      expect(firestoreMap['from'], 'uid_sender');
      expect(firestoreMap['to'], 'uid_recipient');
      expect(firestoreMap['batchId'], 'batch_xyz');
      expect(firestoreMap['fileId'], 'file_orig_789');
      expect(firestoreMap['sha256'], 'a' * 64);
      expect(firestoreMap['sizeBytes'], 1048576);
      expect(firestoreMap['contentType'], 'image/jpeg');
      expect(firestoreMap['patientId'], 'patient_456');
      expect(firestoreMap['status'], 'sent');
      expect(firestoreMap['via'], 'cloud');

      // Deserialize and verify
      final recovered = FileOffer.fromFirestore(
        id: 'offer_123',
        clinicId: 'clinic_abc',
        data: firestoreMap,
      );

      expect(recovered.id, 'offer_123');
      expect(recovered.clinicId, 'clinic_abc');
      expect(recovered.name, 'chest_xray.jpg');
      expect(recovered.thumb, 'base64thumbnaildata==');
      expect(recovered.sha256, 'a' * 64);
      expect(recovered.sizeBytes, 1048576);
      expect(recovered.contentType, 'image/jpeg');
      expect(recovered.status, FileOfferStatus.sent);
      expect(recovered.via, FileOfferVia.cloud);
    });

    test('handles fallback when encrypted fields are missing or plain', () {
      final now = DateTime.utc(2026, 10, 27, 10, 0, 0);
      final rawMap = {
        'from': 'uid_sender',
        'to': 'uid_recipient',
        'batchId': 'batch_1',
        'fileId': 'file_1',
        'sha256': 'b' * 64,
        'sizeBytes': 500,
        'contentType': 'application/pdf',
        'patientId': 'patient_1',
        'name': 'plain_report.pdf',
        'thumb': '',
        'status': 'accepted',
        'via': 'lan',
        'createdAt': now.toIso8601String(),
        'expireAt': now.add(const Duration(days: 7)).toIso8601String(),
      };

      final offer = FileOffer.fromFirestore(
        id: 'offer_999',
        clinicId: 'clinic_1',
        data: rawMap,
      );
      expect(offer.name, 'plain_report.pdf');
      expect(offer.status, FileOfferStatus.accepted);
      expect(offer.via, FileOfferVia.lan);
    });

    test('copyWith updates status and via properly', () {
      final offer = FileOffer(
        id: '1',
        clinicId: 'c1',
        from: 'u1',
        to: 'u2',
        batchId: 'b1',
        fileId: 'f1',
        sha256: 'c' * 64,
        sizeBytes: 100,
        contentType: 'text/plain',
        patientId: 'p1',
        name: 'notes.txt',
        thumb: '',
        status: FileOfferStatus.sent,
        via: FileOfferVia.cloud,
        createdAt: DateTime.now(),
        expireAt: DateTime.now(),
      );

      final accepted = offer.copyWith(
        status: FileOfferStatus.accepted,
        via: FileOfferVia.lan,
      );

      expect(accepted.status, FileOfferStatus.accepted);
      expect(accepted.via, FileOfferVia.lan);
      expect(accepted.id, '1');
      expect(accepted.name, 'notes.txt');
    });

    test('toJson survives jsonEncode and keeps the id (Wi-Fi and offline queue)', () {
      final offer = FileOffer(
        id: 'offer_lan_1',
        clinicId: 'clinic_abc',
        from: 'uid_sender',
        to: 'uid_recipient',
        batchId: 'b1',
        fileId: 'f1',
        sha256: 'b' * 64,
        sizeBytes: 10,
        contentType: 'application/pdf',
        patientId: 'p1',
        name: 'referral.pdf',
        thumb: '',
        status: FileOfferStatus.sent,
        via: FileOfferVia.lan,
        createdAt: DateTime.utc(2026, 10, 27, 10),
        expireAt: DateTime.utc(2026, 11, 26, 10),
      );

      final decoded =
          jsonDecode(jsonEncode(offer.toJson())) as Map<String, dynamic>;
      final back = FileOffer.fromFirestore(
        id: decoded['id'] as String,
        clinicId: 'clinic_abc',
        data: decoded,
      );

      expect(back.id, 'offer_lan_1');
      expect(back.to, 'uid_recipient');
      expect(
        back.createdAt.millisecondsSinceEpoch,
        offer.createdAt.millisecondsSinceEpoch,
      );
      expect(
        back.expireAt.millisecondsSinceEpoch,
        offer.expireAt.millisecondsSinceEpoch,
      );
    });
  });
}
