import 'package:doctor_management_app/core/services/voice_transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VoiceTranscriptionException holds readable error message', () {
    const exception = VoiceTranscriptionException('Microphone not available');
    expect(exception.toString(), equals('Microphone not available'));
  });
}
