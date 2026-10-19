// Referrals between doctors in CruDoc: the app's side of
// functions/src/referrals.ts.
//
// The share key test decrypts a value the server made (with the real app
// pepper), so if the two derivations drift a received referral would show
// ciphertext, and this fails.
import 'package:doctor_management_app/core/services/encryption_key_manager.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network_watcher.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_share_flows.dart';
import 'package:doctor_management_app/features/dental/referrals/referrals_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Made by functions/src/referrals.ts: encryptField('Ravi Kumar · ASA II',
// shareKey('share_compat_0001', <app pepper>)).
const _nodeShareValue =
    'enc:v1:Hh+mXcbAex/ulr3I.eyuyfqa/ZdnsV9Os5t9AIW8fAVjZA9p98RBXqZ3KYBdsDz+T';

/// Encrypts [plain] the way the server does for share [id].
String _seal(String id, String plain) {
  final iv = enc.IV.fromSecureRandom(12);
  final out = enc.Encrypter(
    enc.AES(EncryptionKeyManager.shareKey(id), mode: enc.AESMode.gcm),
  ).encrypt(plain, iv: iv);
  return 'enc:v1:${iv.base64}.${out.base64}';
}

Map<String, dynamic> _shareDoc(
  String id, {
  String status = 'sent',
  String sender = 'dr-a',
  String recipient = 'dr-smit',
  String reply = '',
  int at = 1760000000000,
}) => {
  'senderUid': sender,
  'senderName': 'Asha Rao',
  'senderSpecialty': 'General Surgery',
  'senderClinicName': 'Rao Surgical',
  'recipientUid': recipient,
  'recipientName': 'Smit Patil',
  'recipientSpecialty': 'Anaesthesiology',
  'localReferralId': 'local-1',
  'status': status,
  'urgency': 'urgent',
  'teeth': <String>[],
  'patient': {
    'name': _seal(id, 'Ravi Kumar'),
    'phone': _seal(id, '9811111111'),
    'gender': 'male',
    'age': 54,
  },
  'reason': _seal(id, 'GA for cholecystectomy'),
  'findings': _seal(id, 'ASA II'),
  'question': _seal(id, 'Fit for GA?'),
  'reply': reply.isEmpty ? '' : _seal(id, reply),
  'attachments': [
    {'name': 'ecg.pdf', 'size': 2048, 'contentType': 'application/pdf'},
  ],
  'history': [
    {'status': 'sent', 'at': at, 'by': sender, 'note': _seal(id, 'Sent')},
  ],
};

DentalReferral _local({
  required String id,
  required String patientId,
  String direction = 'out',
  String status = 'draft',
  String shareId = '',
  DateTime? at,
}) => DentalReferral.fromRecord(
  DentalRecord(
    id: id,
    patientId: patientId,
    kind: RecKind.referral,
    data: {
      'direction': direction,
      'contactName': 'Smit Patil',
      'reason': 'GA for cholecystectomy',
      'status': status,
      'history': const [],
      'shareId': ?(shareId.isEmpty ? null : shareId),
    },
    recordedAt: at ?? DateTime(2026, 10, 1),
    createdAt: at ?? DateTime(2026, 10, 1),
    updatedAt: at ?? DateTime(2026, 10, 1),
  ),
);

void main() {
  group('share encryption', () {
    test('reads a value the server encrypted', () {
      expect(
        FieldCipher.decryptWith(
          _nodeShareValue,
          EncryptionKeyManager.shareKey('share_compat_0001'),
        ),
        'Ravi Kumar · ASA II',
      );
    });

    test('each share has its own key', () {
      expect(
        FieldCipher.decryptWith(
          _nodeShareValue,
          EncryptionKeyManager.shareKey('share_compat_0002'),
        ),
        _nodeShareValue,
        reason: 'the wrong key leaves the ciphertext rather than throwing',
      );
    });

    test('a share document decrypts into the model', () {
      final s = ReferralShare.fromMap(
        'share_x',
        _shareDoc('share_x', reply: 'Fit'),
      );
      expect(s.patientName, 'Ravi Kumar');
      expect(s.patientPhone, '9811111111');
      expect(s.patientAge, 54);
      expect(s.reason, 'GA for cholecystectomy');
      expect(s.findings, 'ASA II');
      expect(s.question, 'Fit for GA?');
      expect(s.reply, 'Fit');
      expect(s.status, ReferralStatus.sent);
      expect(s.urgency, ReferralUrgency.urgent);
      expect(s.attachments.single.name, 'ecg.pdf');
      expect(s.history.single.note, 'Sent');
      // No server timestamp yet: the first history entry stands in.
      expect(s.createdAt.millisecondsSinceEpoch, 1760000000000);
    });

    test('a withdrawn share has no patient left to show', () {
      final doc = _shareDoc('share_w', status: 'withdrawn')
        ..['patient'] = {'name': '', 'phone': '', 'gender': '', 'age': null}
        ..['findings'] = ''
        ..['attachments'] = <Object>[];
      final s = ReferralShare.fromMap('share_w', doc);
      expect(s.patientName, '');
      expect(s.attachments, isEmpty);
      expect(s.status.isOpen, isFalse);
    });
  });

  group('merging shared referrals into the list', () {
    final incoming = ReferralShare.fromMap('in_1', _shareDoc('in_1'));
    final outgoing = ReferralShare.fromMap(
      'out_1',
      _shareDoc('out_1', status: 'completed', reply: 'GA uneventful'),
    );

    test('a sent referral takes the other doctor\'s progress', () {
      final merged = mergeSharedReferrals(
        [_local(id: 'r1', patientId: 'p-1', status: 'sent', shareId: 'out_1')],
        outgoing: [outgoing],
        incoming: const [],
      );
      expect(merged.single.status, ReferralStatus.completed);
      expect(merged.single.reply, 'GA uneventful');
      expect(merged.single.patientId, 'p-1');
      expect(merged.single.isUnfiledShare, isFalse);
    });

    test('a received referral shows before it is filed, once', () {
      final unfiled = mergeSharedReferrals(
        const [],
        outgoing: const [],
        incoming: [incoming],
      );
      expect(unfiled.single.isUnfiledShare, isTrue);
      expect(unfiled.single.direction, ReferralDirection.inbound);
      expect(unfiled.single.patientId, '');
      expect(unfiled.single.contactName, 'Asha Rao');
      expect(unfiled.single.share?.patientName, 'Ravi Kumar');

      final filed = mergeSharedReferrals(
        [_local(id: 'r2', patientId: 'p-9', direction: 'in', shareId: 'in_1')],
        outgoing: const [],
        incoming: [incoming],
      );
      expect(filed, hasLength(1));
      expect(filed.single.isUnfiledShare, isFalse);
      expect(filed.single.patientId, 'p-9');
      expect(filed.single.status, ReferralStatus.sent);
    });

    test('local referrals without a share are untouched; newest first', () {
      final merged = mergeSharedReferrals(
        [
          _local(id: 'old', patientId: 'p-1', at: DateTime(2020)),
          _local(id: 'new', patientId: 'p-2', at: DateTime(2030)),
        ],
        outgoing: [outgoing],
        incoming: [incoming],
      );
      expect(merged.map((r) => r.id).toList(), ['new', 'share:in_1', 'old']);
      expect(merged.last.status, ReferralStatus.draft);
      expect(merged.last.share, isNull);
    });

    test('copyWith keeps the link to the share', () {
      final r = _local(id: 'r1', patientId: 'p-1', shareId: 'out_1');
      expect(r.copyWith(reason: 'changed').shareId, 'out_1');
    });
  });

  group('labels and news', () {
    test('a referral without a local patient never crashes its label', () {
      final unfiled = DentalReferral.fromShare(
        ReferralShare.fromMap('in_2', _shareDoc('in_2')),
      );
      expect(referralPatientLabel(unfiled, null), 'Ravi Kumar');
      expect(referralPatientLabel(_local(id: 'x', patientId: ''), null), 'Patient');
      expect(
        referralPatientLabel(_local(id: 'x', patientId: 'abcdef'), null),
        'Patient #abcd',
      );
    });

    test('withdrawn is closed', () {
      expect(ReferralStatus.withdrawn.isOpen, isFalse);
      expect(ReferralStatus.fromName('withdrawn'), ReferralStatus.withdrawn);
    });

    test('names get one "Dr."', () {
      expect(drName('Smit Patil'), 'Dr. Smit Patil');
      expect(drName('Dr. Smit'), 'Dr. Smit');
      expect(drName(''), 'Dr. Doctor');
    });

    test('notifications say who and what, for the right side', () {
      final sent = ReferralShare.fromMap('n1', _shareDoc('n1'));
      expect(
        referralNews(sent, incoming: true)?.title,
        'Urgent: New referral from Dr. Asha Rao',
      );
      expect(referralNews(sent, incoming: false), isNull);

      final done = ReferralShare.fromMap(
        'n2',
        _shareDoc('n2', status: 'completed', reply: 'GA uneventful'),
      );
      expect(
        referralNews(done, incoming: false)?.title,
        'Dr. Smit Patil completed your referral',
      );
      expect(referralNews(done, incoming: false)?.body, 'GA uneventful');
      expect(referralNews(done, incoming: true), isNull);

      final gone = ReferralShare.fromMap(
        'n3',
        _shareDoc('n3', status: 'withdrawn'),
      );
      expect(
        referralNews(gone, incoming: true)?.title,
        'Dr. Asha Rao withdrew a referral',
      );
    });

    test('contacts keep their CruDoc link', () {
      final c = ReferralContact.fromRecord(
        DentalRecord.create('', RecKind.referralContact, {
          'name': 'Smit',
          'phone': '9876543210',
          'crudocUid': 'dr-smit',
          'crudocName': 'Smit Patil',
          'crudocSpecialty': 'Anaesthesiology',
        }),
      );
      expect(c.onCruDoc, isTrue);
      expect(c.toData()['crudocUid'], 'dr-smit');
      expect(
        ReferralContact.fromRecord(
          DentalRecord.create('', RecKind.referralContact, {'name': 'X'}),
        ).onCruDoc,
        isFalse,
      );
    });
  });

  group('Referrals screen', () {
    testWidgets('shows a referral another doctor sent, and opens it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final share = ReferralShare.fromMap('in_ui', _shareDoc('in_ui'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clinicRecordsProvider(
              RecKind.referral,
            ).overrideWith((ref) async => const <DentalRecord>[]),
            clinicRecordsProvider(
              RecKind.referralContact,
            ).overrideWith((ref) async => const <DentalRecord>[]),
            incomingSharesProvider.overrideWith((ref) => Stream.value([share])),
            outgoingSharesProvider.overrideWith(
              (ref) => Stream.value(const <ReferralShare>[]),
            ),
            patientsStreamProvider.overrideWith(
              (ref) => Stream.value(const <Patient>[]),
            ),
          ],
          child: MaterialApp(
            theme: CruTheme.of(CruAppearance.day),
            home: const ReferralsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Counted as received, and listed on the Received tab.
      expect(find.text('1 open · 1 urgent'), findsOneWidget);
      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('From: Asha Rao'), findsOneWidget);
      expect(find.text('CruDoc'), findsOneWidget);

      await tester.tap(find.text('Ravi Kumar'));
      await tester.pumpAndSettle();
      expect(find.text('From Dr. Asha Rao'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Add to my patients'), findsOneWidget);
      expect(find.text('ecg.pdf'), findsOneWidget);
      expect(find.text('Fit for GA?'), findsOneWidget);
    });
  });
}
