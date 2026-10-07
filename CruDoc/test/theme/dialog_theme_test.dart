import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class _FakeQueueRepo implements QueueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<QueueEntry> checkIn({
    String? patientId,
    String? walkInName,
    String? walkInPhone,
    String? reason,
    QueuePriority priority = QueuePriority.normal,
    String? attendingDoctorUid,
    String? createdByUid,
  }) async {
    return QueueEntry(
      id: 'entry-1',
      tokenNumber: 1,
      queueDate: '2026-10-05',
      patientId: patientId,
      walkInName: walkInName,
      walkInPhone: walkInPhone,
      reason: reason,
      priority: priority,
      status: QueueStatus.waiting,
      checkedInAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

void main() {
  final samplePatient = Patient(
    id: 'p-1',
    firstName: 'Rahul',
    lastName: 'Gupta',
    phone: '9353914821',
    gender: 'Male',
    dateOfBirth: DateTime(1990, 1, 1),
    diagnosis: const ['Hypertension'],
    packageBalance: 0,
    isArchived: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('PatientPickerDialog', () {
    testWidgets('renders in Day mode with CruMonogram and search field', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filteredPatientsProvider.overrideWithValue(
              AsyncData([samplePatient]),
            ),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showPatientPickerDialog(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Select a patient'), findsOneWidget);
      expect(find.text('Rahul Gupta'), findsOneWidget);
      expect(find.byType(CruMonogram), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders in Evening mode with dark theme surface', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filteredPatientsProvider.overrideWithValue(
              AsyncData([samplePatient]),
            ),
          ],
          child: MaterialApp(
            theme: CruTheme.evening(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showPatientPickerDialog(context, title: 'Book a visit for'),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Book a visit for'), findsOneWidget);
      expect(find.text('Rahul Gupta'), findsOneWidget);
      expect(find.byType(CruMonogram), findsOneWidget);
    });
  });

  group('CheckInDialog', () {
    testWidgets('renders in Day mode with Registered & Walk-in options', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsStreamProvider.overrideWith((ref) => Stream.value([samplePatient])),
            queueRepositoryProvider.overrideWithValue(_FakeQueueRepo()),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => CheckInDialog.show(context),
                    child: const Text('Check In'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Check In'));
      await tester.pumpAndSettle();

      expect(find.text('Check In Patient'), findsOneWidget);
      expect(find.text('Registered Patient'), findsOneWidget);
      expect(find.text('Walk-in Guest'), findsOneWidget);
      expect(find.text('Queue Priority'), findsOneWidget);
      expect(find.text('Issue Token'), findsOneWidget);
    });

    testWidgets('renders in Evening mode cleanly without overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsStreamProvider.overrideWith((ref) => Stream.value([samplePatient])),
            queueRepositoryProvider.overrideWithValue(_FakeQueueRepo()),
          ],
          child: MaterialApp(
            theme: CruTheme.evening(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => CheckInDialog.show(context),
                    child: const Text('Check In'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Check In'));
      await tester.pumpAndSettle();

      expect(find.text('Check In Patient'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
      expect(find.text('Issue Token'), findsOneWidget);

      // Switch to Walk-in Guest
      await tester.tap(find.text('Walk-in Guest'));
      await tester.pumpAndSettle();

      expect(find.text('Patient Name *'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
    });
  });
}
