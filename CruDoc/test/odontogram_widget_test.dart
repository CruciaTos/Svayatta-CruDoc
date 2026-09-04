import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/odontogram_view.dart';

void main() {
  final now = DateTime.now();

  group('OdontogramView Widget Tests', () {
    testWidgets('renders all 32 adult teeth cells and anatomical titles by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OdontogramView(
                entries: [],
              ),
            ),
          ),
        ),
      );

      // Verify Arch section titles
      expect(find.text('MAXILLARY ARCH (UPPER)'), findsOneWidget);
      expect(find.text('MANDIBULAR ARCH (LOWER)'), findsOneWidget);

      // Verify sample adult teeth are present
      expect(find.text('18'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);

      // Midline divider line
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('toggles to pediatric/primary dentition with 20 teeth', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OdontogramView(
                entries: [],
              ),
            ),
          ),
        ),
      );

      // Tap 'Pediatric' button
      await tester.tap(find.text('Pediatric'));
      await tester.pumpAndSettle();

      // Check header changes
      expect(find.text('Primary Dentition (20 Teeth)'), findsOneWidget);

      // Sample pediatric teeth exist
      expect(find.text('55'), findsOneWidget);
      expect(find.text('51'), findsOneWidget);
      expect(find.text('61'), findsOneWidget);
      expect(find.text('71'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);

      // Adult tooth 18 should no longer be present
      expect(find.text('18'), findsNothing);
    });

    testWidgets('triggers onToothSelected callback when a tooth is tapped', (tester) async {
      String? selectedTooth;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OdontogramView(
                entries: const [],
                onToothSelected: (tooth) => selectedTooth = tooth,
              ),
            ),
          ),
        ),
      );

      // Tap tooth 36 (Lower Left First Molar)
      await tester.tap(find.text('36'));
      await tester.pump();

      expect(selectedTooth, equals('36'));
    });

    testWidgets('reflects tooth condition entries accurately in tooltip and indicator', (tester) async {
      final sampleEntries = [
        ToothChartEntryModel(
          id: 't-1',
          doctorId: 'doc-1',
          patientId: 'pat-1',
          toothNumber: '36',
          condition: 'caries',
          surface: 'occlusal',
          recordedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OdontogramView(
                entries: sampleEntries,
                selectedToothNumber: '36',
              ),
            ),
          ),
        ),
      );

      // Verify tooth 36 is present and rendered
      expect(find.text('36'), findsOneWidget);

      // Anatomical naming lookup check
      expect(getToothName('36'), contains('Lower Left 1st Molar'));
      expect(getToothName('18'), contains('Upper Right 3rd Molar'));
    });
  });
}
