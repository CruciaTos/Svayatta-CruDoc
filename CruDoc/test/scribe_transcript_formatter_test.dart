import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_transcript_formatter.dart';

void main() {
  group('ScribeTranscriptFormatter', () {
    test('mergeLiveChunk cleanly merges overlapping streaming windows', () {
      var acc = '';

      acc = ScribeTranscriptFormatter.mergeLiveChunk(acc, 'Hello. Yeah, nothing just that.');
      expect(acc, 'Hello. Yeah, nothing just that.');

      // Rolling window arrives with overlap
      acc = ScribeTranscriptFormatter.mergeLiveChunk(
        acc,
        'nothing just that, I am feeling pain very severely on my right side.',
      );
      expect(
        acc,
        'Hello. Yeah, nothing just that. I am feeling pain very severely on my right side.',
      );

      // Next window arrives with partial repetition
      acc = ScribeTranscriptFormatter.mergeLiveChunk(
        acc,
        'very severely on my right side. It has been 10 days.',
      );
      expect(
        acc,
        'Hello. Yeah, nothing just that. I am feeling pain very severely on my right side. It has been 10 days.',
      );
    });

    test('deduplicates and formats the user raw stuttered transcript', () {
      const raw = '''
hello sue. yeah. hello, so, yeah, nothing just that. hello, so, yeah, nothing just that, i am feeling. yeah, i think just that i am feeling good. yeah, i think there's that. i'm feeling good. i'm feeling good. i think just that i am feeling in the room pain. i think just that i am feeling pain very severely. i think just that i am feeling very severely. just that, i am feeling very severely. i am feeling very severely my right side. i am feeling very severely my right side. i don't know. the group is very severely on my right side. i don't know, it's weird. patients are very severely on my right side. i don't know. it's been 10 days. very severely, my right side. i don't know, it's been 10 days. patients are severely my right side. i don't know it's been 10 days. my right side, i don't know, it's been 10 days. 10 days. so it's pending. okay, okay, so it's 10 days, what's that? okay, okay, so what's the intensity? so, what's the intensity of the pace? so, what's the intensity of the pain? patients, what's the intensity of the pain? what's the intensity of the pain? is it about five or... what's the intensity of the pain? is it about five or ten? intensity of the pain. is it about five or ten out of rick ten? is it 5 or 10 out of 10, what will you read? is it a 5 or 10 out of 10, what will you rate it? is it a 5 or 10, out of 10, what will you rate it? so, i think. 5 or 10 out of 10 what will you rate it. so i think i will say five or ten out of ten, what will you rate it? so i think i will say... so, i think i will say seven. so, i think i will say 7 on 10. so i think i will say 7 or 10, i haven't. so, i think i would say 7 on 10th, i haven't been able to walk. so i think i would say 7 or 10, i haven't been able to walk. i think i will say 7 on 10, i haven't been able to walk properly for. i haven't been able to walk properly for now. i haven't been able to walk properly for now. i have a limit for... patients have been able to walk properly for now. i have a limit for... walk properly for now. have a limit for now. properly for now. i have a lipid for a long time. have a little bit for a long time. patients have been a little bit for a long time. yeah.
''';

      final formatted = ScribeTranscriptFormatter.format(raw);

      // Verify clean structure with Doctor and Patient turns
      expect(formatted.contains('Doctor:'), isTrue);
      expect(formatted.contains('Patient:'), isTrue);
      expect(formatted.contains('7 out of 10'), isTrue);
      expect(formatted.contains('intensity of the pain'), isTrue);
      expect(formatted.contains('10 days'), isTrue);
      expect(formatted.contains('out of rick ten'), isFalse);
    });
  });
}
