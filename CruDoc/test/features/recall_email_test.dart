import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/recalls.dart';

/// The one line email adds that WhatsApp and SMS do not have.
///
/// It is worth pinning because a subject line is the part of a reminder that
/// shows on a lock screen, possibly to somebody other than the patient. It
/// must say enough to be opened and nothing about why.
void main() {
  group('recallEmailSubject', () {
    test('names the clinic so the patient knows who it is from', () {
      expect(
        recallEmailSubject(clinic: 'Smile Dental', fromPackage: false),
        'A reminder from Smile Dental',
      );
    });

    test('a stalled package asks about the sessions already paid for', () {
      expect(
        recallEmailSubject(clinic: 'Smile Dental', fromPackage: true),
        'Your remaining sessions at Smile Dental',
      );
    });

    test('a clinic with no name set still reads as a sentence', () {
      expect(
        recallEmailSubject(clinic: '', fromPackage: false),
        'A reminder from our clinic',
      );
      expect(
        recallEmailSubject(clinic: '   ', fromPackage: true),
        'Your remaining sessions at our clinic',
      );
    });

    test('a padded clinic name is trimmed, not shown with its spaces', () {
      expect(
        recallEmailSubject(clinic: '  Smile Dental  ', fromPackage: false),
        'A reminder from Smile Dental',
      );
    });

    test('the clinical reason never reaches the subject line', () {
      // Whatever the recall is for, the subject says only that there is a
      // reminder. The reason belongs in the body, which needs the mail to be
      // opened first.
      for (final fromPackage in [true, false]) {
        final subject = recallEmailSubject(
          clinic: 'Smile Dental',
          fromPackage: fromPackage,
        );
        for (final private in [
          'scaling',
          'root canal',
          'physiotherapy',
          'knee rehab package',
        ]) {
          expect(
            subject.toLowerCase(),
            isNot(contains(private)),
            reason: 'subject leaked "$private"',
          );
        }
      }
    });
  });
}
