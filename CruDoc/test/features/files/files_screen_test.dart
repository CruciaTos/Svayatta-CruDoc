import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_screen.dart';
import 'package:doctor_management_app/features/files/presentation/patient_files_card.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

final now = DateTime(2026, 10, 8, 12);

Patient patient(String id, String first, String last) => Patient(
  id: id,
  doctorId: 'clinic',
  firstName: first,
  lastName: last,
  phone: '',
  gender: '',
  dateOfBirth: DateTime(1990),
  diagnosis: const [],
  packageBalance: 0,
  isArchived: false,
  createdAt: now,
  updatedAt: now,
);

final patients = [
  patient('p1', 'Asha', 'Rao'),
  patient('p2', 'Vikram', 'Shah'),
];

final folders = [
  FileFolder(
    id: 'xr',
    doctorId: 'clinic',
    ownerUid: 'me',
    parentId: '',
    rootId: 'xr',
    name: 'X-rays',
    sharing: FolderSharing.team,
    visibleTo: const ['me', kFilesTeam],
    createdAt: now,
    updatedAt: now,
  ),
];

PatientFile file(
  String id,
  String name,
  String type, {
  String patientId = 'p1',
  String folderId = '',
  int daysAgo = 0,
}) => PatientFile(
  id: id,
  doctorId: 'clinic',
  ownerUid: 'me',
  patientId: patientId,
  folderId: folderId,
  rootId: folderId,
  name: name,
  contentType: type,
  sizeBytes: 2400000,
  visibleTo: const ['me'],
  createdAt: now.subtract(Duration(days: daysAgo)),
  updatedAt: now,
);

final files = [
  file('a', 'OPG full mouth.jpg', 'image/jpeg', folderId: 'xr'),
  file('b', 'Blood report.pdf', 'application/pdf', patientId: 'p2', daysAgo: 1),
  file('c', 'CBCT study.dcm', 'application/dicom', daysAgo: 30),
  file(
    'd',
    'Referral letter with a very long name that must not overflow.docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    daysAgo: 400,
  ),
];

List<Override> overrides({FilesState initial = const FilesState()}) => [
  filesDataProvider.overrideWith(
    (ref) async => (folders: folders, files: files),
  ),
  patientFilesProvider.overrideWith(
    (ref, id) async => [
      for (final f in files)
        if (f.patientId == id) f,
    ],
  ),
  patientsStreamProvider.overrideWith((ref) => Stream.value(patients)),
  clinicMembersProvider.overrideWith((ref) => Stream.value(const [])),
  clinicAccessProvider.overrideWith((ref) => Stream.value(null)),
  authStateProvider.overrideWith((ref) => Stream.value(null)),
  dashboardNowProvider.overrideWithValue(now),
  filesUidProvider.overrideWithValue('me'),
  filesControllerProvider.overrideWith(() => FilesController(initial: initial)),
];

Widget app(Widget child, {FilesState initial = const FilesState()}) =>
    ProviderScope(
      overrides: overrides(initial: initial),
      child: MaterialApp(
        theme: CruTheme.day(),
        home: Scaffold(
          backgroundColor: CruColors.of(CruAppearance.day).canvas,
          body: child,
        ),
      ),
    );

void setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop list: newest first, patient names, panel', (
    tester,
  ) async {
    setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(app(const FilesScreen()));
    await settle(tester);

    expect(find.text('Files'), findsWidgets);
    expect(find.textContaining('4 files', findRichText: true), findsOneWidget);
    expect(find.text('Asha Rao'), findsWidgets);
    expect(find.text('Vikram Shah'), findsWidgets);
    // The panel shows the newest file.
    expect(find.text('Saved to the cloud'), findsNothing);
    expect(find.text('Uploading…'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop grid and folders tab render', (tester) async {
    setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(
      app(
        const FilesScreen(),
        initial: const FilesState(
          viewMode: FilesViewMode.grid,
          tab: FilesTab.folders,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('All folders'), findsOneWidget);
    expect(find.text('X-rays'), findsWidgets);
    expect(find.text('Shared with the clinic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inside a folder: breadcrumbs and its file', (tester) async {
    setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      app(
        const FilesScreen(),
        initial: const FilesState(tab: FilesTab.folders, folderId: 'xr'),
      ),
    );
    await settle(tester);
    expect(find.text('OPG full mouth.jpg'), findsWidgets);
    expect(find.text('Blood report.pdf'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient filter from "See all"', (tester) async {
    setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(
      app(const FilesScreen(), initial: const FilesState(patientId: 'p2')),
    );
    await settle(tester);
    expect(find.text('Blood report.pdf'), findsWidgets);
    expect(find.text('OPG full mouth.jpg'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout renders without overflow', (tester) async {
    setSize(tester, const Size(390, 844));
    await tester.pumpWidget(app(const FilesScreen()));
    await settle(tester);
    expect(find.text('Asha Rao · Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient card lists their files with See all', (tester) async {
    setSize(tester, const Size(500, 900));
    await tester.pumpWidget(
      app(SingleChildScrollView(child: PatientFilesCard(patient: patients[0]))),
    );
    await settle(tester);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('OPG full mouth.jpg'), findsOneWidget);
    expect(find.text('Add files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
