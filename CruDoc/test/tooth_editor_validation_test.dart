import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/repositories/dental_repository.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/tooth_condition_editor_sheet.dart';

class FakeDentalRepository extends DentalRepository {
  final List<ToothChartEntryModel> savedEntries = [];

  @override
  Future<void> saveToothChartEntry(ToothChartEntryModel entry) async {
    savedEntries.add(entry);
  }

  @override
  Future<List<ToothChartEntryModel>> getToothChartForPatient(String patientId) async {
    return savedEntries.where((e) => e.patientId == patientId).toList();
  }
}

void main() {
  group('ToothConditionEditorSheet Validation & Form Tests', () {
    late FakeDentalRepository fakeRepository;

    setUp(() {
      fakeRepository = FakeDentalRepository();
    });

    testWidgets('renders tooth header, surface, condition, and treatment chips', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(fakeRepository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ToothConditionEditorSheet(
                doctorId: 'doc-1',
                patientId: 'pat-1',
                toothNumber: '36',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Tooth 36'), findsOneWidget);
      expect(find.text('OCCLUSAL'), findsOneWidget);
      expect(find.text('caries'), findsOneWidget);
      expect(find.text('filling'), findsOneWidget);
      expect(find.text('Save Entry'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancels without saving', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(fakeRepository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ToothConditionEditorSheet(
                doctorId: 'doc-1',
                patientId: 'pat-1',
                toothNumber: '11',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(fakeRepository.savedEntries, isEmpty);
    });

    testWidgets('validates and saves tooth entry when condition and surface are chosen', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalRepositoryProvider.overrideWithValue(fakeRepository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ToothConditionEditorSheet(
                doctorId: 'doc-1',
                patientId: 'pat-1',
                toothNumber: '36',
              ),
            ),
          ),
        ),
      );

      // Select Surface
      await tester.tap(find.text('OCCLUSAL'));
      await tester.pump();

      // Select Condition
      await tester.tap(find.text('caries'));
      await tester.pump();

      // Ensure Save button is visible and tap
      await tester.ensureVisible(find.text('Save Entry'));
      await tester.pump();
      await tester.tap(find.text('Save Entry'));
      await tester.pump();

      // Verify entry was saved to repository
      expect(fakeRepository.savedEntries, hasLength(1));
      final saved = fakeRepository.savedEntries.first;
      expect(saved.toothNumber, equals('36'));
      expect(saved.surface, equals('occlusal'));
      expect(saved.condition, equals('caries'));
      expect(saved.doctorId, equals('doc-1'));
      expect(saved.patientId, equals('pat-1'));
    });
  });
}
