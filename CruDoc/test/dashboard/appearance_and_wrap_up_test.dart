import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_builder.dart';
import 'package:doctor_management_app/features/dashboard/domain/wrap_up_builder.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';

import 'dashboard_fixtures.dart';

ConsultationNote _note(String patientId, ConsultationNoteStatus status) =>
    ConsultationNote(
      id: 'n_$patientId',
      doctorId: '',
      patientId: patientId,
      visitId: 'v_$patientId',
      transcript: '',
      chiefComplaint: '',
      symptoms: const [],
      diagnosisSuggestions: const [],
      medicines: const [],
      advice: '',
      vitals: const {},
      confidenceNote: '',
      consentGiven: true,
      status: status,
      createdAt: DateTime(2026, 9, 23, 17),
    );

void main() {
  group('resolveAppearance', () {
    test('Auto follows the evening session (17:00) until morning', () {
      DateTime at(int h, int m) => DateTime(2026, 9, 23, h, m);
      expect(resolveAppearance(AppearanceMode.auto, at(16, 59)),
          CruAppearance.day);
      expect(resolveAppearance(AppearanceMode.auto, at(17, 0)),
          CruAppearance.evening);
      expect(resolveAppearance(AppearanceMode.auto, at(23, 30)),
          CruAppearance.evening);
      expect(resolveAppearance(AppearanceMode.auto, at(4, 59)),
          CruAppearance.evening);
      expect(resolveAppearance(AppearanceMode.auto, at(5, 0)),
          CruAppearance.day);
    });

    test('Day and Evening are fixed choices', () {
      final night = DateTime(2026, 9, 23, 21);
      final noon = DateTime(2026, 9, 23, 12);
      expect(resolveAppearance(AppearanceMode.day, night), CruAppearance.day);
      expect(resolveAppearance(AppearanceMode.evening, noon),
          CruAppearance.evening);
    });

    test('stored names parse, unknown falls back to Auto', () {
      expect(AppearanceMode.fromName('evening'), AppearanceMode.evening);
      expect(AppearanceMode.fromName(null), AppearanceMode.auto);
      expect(AppearanceMode.fromName('dusk'), AppearanceMode.auto);
    });
  });

  group('buildWrapUp', () {
    final data = buildDashboard(
      now: eveningNow,
      queue: eveningQueue,
      visits: [...eveningVisits, ...tomorrowVisits],
      patients: fixturePatients,
    );

    test('counts patients left, tomorrow and draft notes', () {
      final wrap = buildWrapUp(
        now: eveningNow,
        schedule: data.schedule!,
        visits: [...eveningVisits, ...tomorrowVisits],
        notes: [
          _note('sneha', ConsultationNoteStatus.draft),
          _note('rohan', ConsultationNoteStatus.draft),
          _note('kavya', ConsultationNoteStatus.confirmed),
        ],
        patients: fixturePatients,
      );
      // Anil (in consultation) and Farah (waiting).
      expect(wrap.patientsLeft, 2);
      expect(wrap.draftNames, ['Rohan Mehta', 'Sneha Kulkarni']);
      expect(wrap.tomorrowCount, 9);
      expect(wrap.tomorrowFirst, DateTime(2026, 9, 24, 9, 30));
      expect(wrap.hasRows, isTrue);
    });

    test('no drafts and no bookings tomorrow means no rows', () {
      final wrap = buildWrapUp(
        now: eveningNow,
        schedule: data.schedule!,
        visits: eveningVisits,
        notes: const [],
        patients: fixturePatients,
      );
      expect(wrap.hasRows, isFalse);
    });
  });
}
