import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/therapy/data/soap_phrases.dart';

/// Quick-tap phrases write straight into a clinical note, so what matters is
/// that a tap puts in exactly the sentence on the chip, never a number the
/// physio did not type, and never on top of what is already written.
void main() {
  const plain = SoapPhrase(SoapSection.plan, 'Continue the current plan.');
  const gapped = SoapPhrase(SoapSection.plan, 'Review in $blank days.');

  group('a phrase with a gap', () {
    test('puts the caret on the gap so it gets typed over', () {
      expect(gapped.hasBlank, isTrue);
      expect(gapped.caretOffset, 'Review in '.length);
      final r = insertSoapPhrase('', 0, gapped);
      expect(r.text, 'Review in … days.');
      expect(r.caret, 'Review in '.length);
      expect(r.text.substring(r.caret, r.caret + 1), blank);
    });

    test('a phrase without one ends with the caret after it', () {
      expect(plain.hasBlank, isFalse);
      final r = insertSoapPhrase('', 0, plain);
      expect(r.caret, plain.text.length);
    });
  });

  group('where the phrase lands', () {
    test('an empty note does not open with a blank line', () {
      expect(insertSoapPhrase('', 0, plain).text, plain.text);
    });

    test('a phrase goes on its own line after existing text', () {
      final r = insertSoapPhrase('Seen for knee pain.', 19, plain);
      expect(r.text, 'Seen for knee pain.\nContinue the current plan.');
      expect(r.caret, r.text.length);
    });

    test('no second newline when the note already ends with one', () {
      final r = insertSoapPhrase('Line one.\n', 10, plain);
      expect(r.text, 'Line one.\nContinue the current plan.');
    });

    test('inserting mid-note keeps the text that follows, on its own line', () {
      final r = insertSoapPhrase('Before.\nAfter.', 8, plain);
      expect(r.text, 'Before.\nContinue the current plan.\nAfter.');
      // The caret stays with the phrase just inserted, not at the end.
      expect(r.caret, 'Before.\n'.length + plain.text.length);
    });

    test('an unfocused field appends rather than overwriting the start', () {
      final r = insertSoapPhrase('Already written.', -1, plain);
      expect(r.text, 'Already written.\nContinue the current plan.');
    });

    test('a caret past the end of the note is treated as the end', () {
      final r = insertSoapPhrase('Short.', 999, plain);
      expect(r.text, 'Short.\nContinue the current plan.');
    });

    test('two phrases in a row each get their own line', () {
      final first = insertSoapPhrase('', 0, plain);
      final second = insertSoapPhrase(first.text, first.caret, gapped);
      expect(second.text, 'Continue the current plan.\nReview in … days.');
    });
  });

  group('the phrase list', () {
    test('every section has phrases, so no section opens empty', () {
      for (final s in SoapSection.values) {
        expect(soapPhrasesOf(s), isNotEmpty, reason: s.title);
      }
    });

    test('phrases are only ever filed under their own section', () {
      for (final s in SoapSection.values) {
        for (final p in soapPhrasesOf(s)) {
          expect(p.section, s);
        }
      }
    });

    test('any phrase carrying a number leaves a gap to type it into', () {
      // "Reports pain …/10 today." may name the scale, because /10 is the
      // scale and not a reading. What it may never do is state the reading,
      // so a digit anywhere obliges the phrase to have a gap in it.
      for (final p in kSoapPhrases) {
        if (p.text.contains(RegExp(r'\d'))) {
          expect(
            p.hasBlank,
            isTrue,
            reason: 'states a number outright: ${p.text}',
          );
        }
      }
    });

    test('no phrase is duplicated', () {
      final seen = <String>{};
      for (final p in kSoapPhrases) {
        expect(seen.add(p.text), isTrue, reason: 'twice: ${p.text}');
      }
    });

    test('every phrase is a finished sentence', () {
      for (final p in kSoapPhrases) {
        expect(p.text.trim(), p.text, reason: 'padded: ${p.text}');
        expect(p.text.endsWith('.'), isTrue, reason: 'unfinished: ${p.text}');
      }
    });
  });
}
