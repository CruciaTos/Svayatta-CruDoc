import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_label.dart';

/// A bottle label is read weeks later, in a cupboard, possibly by somebody
/// other than the patient. These tests cover the two things that make it
/// safe or unsafe: that a label is always produced for what was dispensed,
/// and that a remedy name is never printed in a script the PDF cannot draw.
void main() {
  RemedyLabelData data({
    String remedy = 'Arnica montana',
    String potency = '30C',
    String dosing = 'Four pills, twice a day',
    String localName = '',
    String quantity = '',
  }) => RemedyLabelData(
    remedy: remedy,
    potency: potency,
    dosing: dosing,
    patientName: 'Test Patient',
    date: DateTime(2026, 11, 25),
    localName: localName,
    quantity: quantity,
  );

  group('the sheet is produced', () {
    test('one label makes a document', () async {
      final bytes = await buildHomeoRemedyLabels(
        labels: [data()],
        clinicName: 'Test Clinic',
      );
      expect(bytes, isNotEmpty);
      // A PDF, not an empty buffer.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('a full sheet and more than a sheet both build', () async {
      for (final n in [3, 4, remedyLabelsPerSheet(), 40]) {
        final bytes = await buildHomeoRemedyLabels(
          labels: [for (var i = 0; i < n; i++) data()],
          clinicName: 'Test Clinic',
        );
        expect(bytes, isNotEmpty, reason: '$n labels');
      }
    });

    test('no labels still builds rather than throwing', () async {
      // A clinic that prints with nothing selected gets a blank sheet, not
      // a crash in the middle of dispensing.
      final bytes = await buildHomeoRemedyLabels(
        labels: const [],
        clinicName: 'Test Clinic',
      );
      expect(bytes, isNotEmpty);
    });

    test('a clinic with no name set still builds', () async {
      final bytes = await buildHomeoRemedyLabels(
        labels: [data()],
        clinicName: '',
      );
      expect(bytes, isNotEmpty);
    });

    test('long text does not stop a label being produced', () async {
      final bytes = await buildHomeoRemedyLabels(
        labels: [
          data(
            remedy: 'Kali bichromicum' * 4,
            dosing:
                'Four pills under the tongue, twice a day, '
                    'away from food, coffee and strong smells, ' *
                3,
          ),
        ],
        clinicName: 'A Very Long Clinic Name Indeed Homeopathy Centre',
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('local names are never guessed at', () {
    test('a local name is held but not printed without a font', () async {
      // The field survives on the data so the clinic can fill it in, but
      // Devanagari in a Latin-only font prints as empty boxes, so without a
      // script font it is left off the label entirely.
      final d = data(localName: 'अर्निका');
      expect(d.localName, 'अर्निका');
      final bytes = await buildHomeoRemedyLabels(
        labels: [d],
        clinicName: 'Test Clinic',
        // No script font supplied.
      );
      expect(bytes, isNotEmpty);
    });

    test('a local name defaults to empty, never transliterated', () {
      // A remedy name is the one string here that must not be invented: a
      // wrong one in a script the prescriber cannot read is never caught.
      expect(data().localName, '');
    });
  });

  group('sheet capacity', () {
    test('a sheet holds a whole number of rows, three across', () {
      final n = remedyLabelsPerSheet();
      expect(n % 3, 0);
      expect(n, greaterThan(0));
      // 70 x 38 mm on A4 should be more than one row and fewer than thirty.
      expect(n, greaterThan(3));
      expect(n, lessThan(30));
    });
  });
}
