import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/discharge_summary.dart';
import 'package:doctor_management_app/features/therapy/presentation/progress_report.dart';

/// A discharge summary leaves the clinic, and the referrer copy is handed to
/// the patient. So the thing worth pinning is what travels on it: the
/// referring doctor is named, and nothing else about them goes along.
void main() {
  ReferralContact contact({
    String name = 'Dr Anjali Deshpande',
    String clinic = 'Sahyadri Orthopaedics',
    String phone = '9876543210',
    String email = 'anjali@example.com',
    String city = 'Pune',
    String notes = 'Prefers reports by email',
  }) => ReferralContact(
    id: 'c1',
    name: name,
    clinic: clinic,
    specialty: 'Orthopaedics',
    phone: phone,
    email: email,
    city: city,
    notes: notes,
  );

  group('referrerLabel', () {
    test('names the doctor and their clinic', () {
      expect(
        referrerLabel(contact()),
        'Dr Anjali Deshpande, Sahyadri Orthopaedics',
      );
    });

    test('carries no phone, e-mail, city or private note', () {
      // The patient is handed this letter, so anything the clinic keeps for
      // its own use must stay out of it.
      final label = referrerLabel(contact());
      expect(label, isNot(contains('9876543210')));
      expect(label, isNot(contains('@')));
      expect(label, isNot(contains('Pune')));
      expect(label, isNot(contains('Prefers reports')));
    });

    test('a contact with no clinic is just the name', () {
      expect(referrerLabel(contact(clinic: '')), 'Dr Anjali Deshpande');
    });

    test('blank either side does not leave a stray comma', () {
      expect(referrerLabel(contact(name: '', clinic: 'Sahyadri')), 'Sahyadri');
      expect(referrerLabel(contact(name: '', clinic: '')), isEmpty);
    });

    test('whitespace is trimmed, not preserved into the letter', () {
      expect(referrerLabel(contact(name: '  Dr Rao  ', clinic: '  KEM  ')),
          'Dr Rao, KEM');
    });
  });

  group('DischargeNote', () {
    final on = DateTime(2026, 6, 15);

    test('with no addressee it is the patient own copy, not a letter', () {
      final n = DischargeNote(on: on, outcome: 'Full recovery', advice: '');
      expect(n.isLetter, isFalse);
    });

    test('with an addressee it is a letter', () {
      final n = DischargeNote(
        on: on,
        outcome: '',
        advice: '',
        addressedTo: 'Dr Rao, KEM',
      );
      expect(n.isLetter, isTrue);
    });

    test('whitespace alone is not an addressee', () {
      final n = DischargeNote(
        on: on,
        outcome: '',
        advice: '',
        addressedTo: '   ',
      );
      expect(n.isLetter, isFalse);
    });
  });
}
