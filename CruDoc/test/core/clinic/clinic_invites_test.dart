import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';

ClinicInvite _invite(String id, {String status = 'pending', DateTime? expires}) =>
    ClinicInvite(
      id: id,
      clinicId: 'c1',
      clinicName: 'Joshi Clinic',
      name: 'Asha',
      phone: '+919800000000',
      email: '',
      kind: MemberKind.staff,
      roleId: 'receptionist',
      roleName: 'Receptionist',
      specialty: '',
      status: status,
      expiresAt: expires,
      invitedByName: 'Dr. Joshi',
    );

void main() {
  group('pendingInvites', () {
    final now = DateTime(2026, 10, 17, 12);

    test('keeps pending, unexpired invites, soonest expiry first', () {
      final list = pendingInvites([
        _invite('late', expires: now.add(const Duration(days: 5))),
        _invite('none'),
        _invite('declined', status: 'declined',
            expires: now.add(const Duration(days: 1))),
        _invite('expired', expires: now.subtract(const Duration(minutes: 1))),
        _invite('soon', expires: now.add(const Duration(hours: 2))),
      ], now);
      expect([for (final i in list) i.id], ['soon', 'late', 'none']);
    });

    test('empty in, empty out', () {
      expect(pendingInvites(const [], now), isEmpty);
    });
  });

  group('buildInviteMessage', () {
    test('names the clinic, the store link and the number', () {
      final text = buildInviteMessage(
        inviteeName: 'Asha',
        inviterName: 'Dr. Joshi',
        clinicName: 'Joshi Clinic',
        phone: '+919800000000',
        storeLink: 'https://example.test/app',
      );
      expect(
        text,
        'Hi Asha, Dr. Joshi has invited you to join the Joshi Clinic team '
        'on CruDoc.\n\n'
        '1. Download CruDoc: https://example.test/app\n'
        '2. Sign up with this number: +919800000000\n'
        '3. Your invite will be waiting. Tap Join clinic.\n\n'
        'This invite expires in 7 days.',
      );
    });

    test('uses the Play Store link by default', () {
      final text = buildInviteMessage(
        inviteeName: '',
        inviterName: 'Dr. Joshi',
        clinicName: 'Joshi Clinic',
        phone: '+919800000000',
      );
      expect(text, startsWith('Hi, Dr. Joshi'));
      expect(text, contains(kPlayStoreLink));
    });
  });

  group('invite phone numbers', () {
    test('reads Indian numbers the way the server does', () {
      expect(invitePhoneE164('98000 00000'), '+919800000000');
      expect(invitePhoneE164('098000-00000'), '+919800000000');
      expect(invitePhoneE164('+91 98000 00000'), '+919800000000');
      expect(invitePhoneE164('919800000000'), '+919800000000');
      expect(invitePhoneE164('+1 (415) 555-0100'), '+14155550100');
      expect(invitePhoneE164('12345'), isNull);
    });

    test('fills the form with ten digits for +91 numbers', () {
      expect(invitePhoneForForm('+91 98000 00000'), '9800000000');
      expect(invitePhoneForForm('+1 415 555 0100'), '+14155550100');
    });
  });
}
