import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/voice/domain/voice_command.dart';

void main() {
  group('Voice Confirmation & Enter Key Workflow', () {
    test('"confirm" or "save" parses to VoiceIntent.confirm', () {
      final cmdConfirm = VoiceCommand.parse('confirm', DateTime(2026, 9, 27));
      expect(cmdConfirm.intent, VoiceIntent.confirm);

      final cmdSave = VoiceCommand.parse('save', DateTime(2026, 9, 27));
      expect(cmdSave.intent, VoiceIntent.confirm);

      final cmdConfirmed = VoiceCommand.parse('confirmed', DateTime(2026, 9, 27));
      expect(cmdConfirmed.intent, VoiceIntent.confirm);

      final cmdYes = VoiceCommand.parse('yes', DateTime(2026, 9, 27));
      expect(cmdYes.intent, VoiceIntent.confirm);
    });

    test('Regular commands do not have confirmAtEnd', () {
      final cmd = VoiceCommand.parse(
        'Add patient Rahul Patel 28 male migraine',
        DateTime(2026, 9, 27),
      );
      expect(cmd.intent, VoiceIntent.addPatient);
      expect(cmd.confirmAtEnd, isFalse);
    });

    test('Commands ending with "...and confirm" have confirmAtEnd set to true', () {
      final cmd = VoiceCommand.parse(
        'Add patient Rahul Patel 28 male and confirm',
        DateTime(2026, 9, 27),
      );
      expect(cmd.intent, VoiceIntent.addPatient);
      expect(cmd.confirmAtEnd, isTrue);
    });

    test('Appointment command ending with "...and confirm"', () {
      final cmd = VoiceCommand.parse(
        'Book Rahul tomorrow at 5 pm and confirm',
        DateTime(2026, 9, 27),
      );
      expect(cmd.intent, VoiceIntent.addAppointment);
      expect(cmd.confirmAtEnd, isTrue);
    });

    test('Appointment command without confirm does not auto-confirm', () {
      final cmd = VoiceCommand.parse(
        'Book Rahul tomorrow at 5 pm',
        DateTime(2026, 9, 27),
      );
      expect(cmd.intent, VoiceIntent.addAppointment);
      expect(cmd.confirmAtEnd, isFalse);
    });
  });
}
