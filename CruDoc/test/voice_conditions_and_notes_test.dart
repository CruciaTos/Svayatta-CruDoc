import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/voice/domain/medical_conditions.dart';
import 'package:doctor_management_app/features/voice/domain/voice_command.dart';

void main() {
  group('Medical Conditions Content-Aware Extraction', () {
    test('extracts only actual condition from "He is suffering from migraine"', () {
      final cmd = VoiceCommand.parse('He is suffering from migraine', DateTime.now());
      expect(cmd.conditions, ['Migraine']);
      expect(cmd.conditions, isNot(contains('He is')));
      expect(cmd.conditions, isNot(contains('He serving')));
      expect(cmd.conditions, isNot(contains('My')));
    });

    test('extracts only actual condition from "Condition he is suffering from migraine"', () {
      final cmd = VoiceCommand.parse('Condition he is suffering from migraine', DateTime.now());
      expect(cmd.conditions, ['Migraine']);
      expect(cmd.conditions.length, 1);
    });

    test('extracts multi-word and multiple conditions accurately', () {
      final cmd = VoiceCommand.parse(
        'Patient has type 2 diabetes, high blood pressure, and dental caries',
        DateTime.now(),
      );
      expect(cmd.conditions, containsAll(['Type 2 Diabetes', 'Hypertension', 'Dental caries']));
    });

    test('discards non-medical conversational filler like "he serving", "my"', () {
      final tokens = ['he', 'serving', 'he', 'is', 'my'];
      final detected = extractMedicalConditions(tokens);
      expect(detected, isEmpty);
    });

    test('extracts dental conditions content-aware', () {
      final cmd = VoiceCommand.parse(
        'Diagnosed with gingivitis, tooth decay and pericoronitis',
        DateTime.now(),
      );
      expect(cmd.conditions, containsAll(['Gingivitis', 'Dental caries', 'Pericoronitis']));
    });

    test('extracts gastro, respiratory and neuro conditions', () {
      final cmd = VoiceCommand.parse(
        'Suffering from acid reflux, asthma, and chronic migraine',
        DateTime.now(),
      );
      expect(cmd.conditions, containsAll(['GERD', 'Asthma', 'Migraine']));
    });
  });

  group('Clinical Notes Cleaning & Bullet Formatting', () {
    test('cleans "Add that he has allergies for apple seeds" into bullet note', () {
      final clean = cleanNoteText('Add that he has allergies for apple seeds');
      expect(clean, 'Has allergy for apple seeds');

      final bullet = formatBulletNote('Add that he has allergies for apple seeds');
      expect(bullet, '• Has allergy for apple seeds');
    });

    test('VoiceCommand formats notes with bullets and clean phrasing', () {
      final cmd = VoiceCommand.parse(
        'Add that he has allergies for apple seeds',
        DateTime.now(),
      );
      expect(cmd.notes, contains('Has allergy for apple seeds'));
      expect(cmd.notes, startsWith('• '));
    });

    test('cleans "Note: prefers evening appointments"', () {
      final clean = cleanNoteText('Note: prefers evening appointments');
      expect(clean, 'Prefers evening appointments');
      expect(formatBulletNote(clean), '• Prefers evening appointments');
    });

    test('joins multiple notes line-by-line into clean bullet points', () {
      final joined = joinBulletNotes(
        '• Prefers morning appointments',
        'Add that he has allergies for apple seeds',
      );
      expect(
        joined,
        '• Prefers morning appointments\n• Has allergy for apple seeds',
      );
    });

    test('does not duplicate existing bullets when joining notes', () {
      final joined = joinBulletNotes(
        '• Has allergy for apple seeds',
        'has allergies for apple seeds',
      );
      expect(joined, '• Has allergy for apple seeds');
    });

    test('splits compound observations and rejects "Has an" fragments', () {
      const input = 'Note that he has an allergy for cucumbers and also he is sensitive to light and loud sounds';
      final cmd = VoiceCommand.parse(input, DateTime.now());

      expect(cmd.notes, isNotNull);
      expect(cmd.notes, isNot(contains('• Has an\n')));
      expect(cmd.notes, isNot(equals('• Has an')));
      expect(cmd.notes, contains('• Has allergy for cucumbers'));
      expect(cmd.notes, contains('• Sensitive to light and loud sounds'));
      expect(cmd.notes, equals('• Has allergy for cucumbers\n• Sensitive to light and loud sounds'));
    });

    test('isIncompleteNoteFragment rejects dangling fragments', () {
      expect(isIncompleteNoteFragment('Has an'), isTrue);
      expect(isIncompleteNoteFragment('He has an'), isTrue);
      expect(isIncompleteNoteFragment('Allergic to'), isTrue);
      expect(isIncompleteNoteFragment('Note for'), isTrue);
      expect(isIncompleteNoteFragment('Has allergy for cucumbers'), isFalse);
      expect(isIncompleteNoteFragment('Sensitive to light and loud sounds'), isFalse);
    });
  });
}
