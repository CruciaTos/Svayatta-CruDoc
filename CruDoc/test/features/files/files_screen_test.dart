import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/add_files_dialog.dart';
import 'package:doctor_management_app/features/files/presentation/files_screen.dart';
import 'package:doctor_management_app/features/files/presentation/incoming_card.dart';
import 'package:doctor_management_app/features/files/presentation/patient_files_card.dart';
import 'package:doctor_management_app/features/files/presentation/transfers_sheet.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/clinic_drop_target.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_list.dart';
import 'package:doctor_management_app/features/mobile/mobile_notifications.dart';
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

List<Override> overrides({
  FilesState initial = const FilesState(),
  List<ClinicMember> members = const [],
}) => [
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
  clinicMembersProvider.overrideWith((ref) => Stream.value(members)),
  // The signed-in doctor owns their practice. (null used to stand in for
  // this, but an unresolved session now hides actions rather than
  // assuming the person may take them.)
  clinicAccessProvider.overrideWith(
    (ref) => Stream.value(ClinicAccess.owner('me')),
  ),
  authStateProvider.overrideWith((ref) => Stream.value(null)),
  doctorProfileProvider.overrideWith((ref) => Stream.value(null)),
  dashboardNowProvider.overrideWithValue(now),
  filesUidProvider.overrideWithValue('me'),
  filesControllerProvider.overrideWith(() => FilesController(initial: initial)),
];

Widget app(
  Widget child, {
  FilesState initial = const FilesState(),
  List<ClinicMember> members = const [],
}) =>
    ProviderScope(
      overrides: overrides(initial: initial, members: members),
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

  testWidgets(
    'desktop defaults to grid view: newest first, patient names, panel',
    (tester) async {
      setSize(tester, const Size(1440, 900));
      await tester.pumpWidget(app(const FilesScreen()));
      await settle(tester);

      expect(find.byType(FilesGrid), findsOneWidget);
      expect(find.byType(FilesList), findsNothing);
      expect(find.text('Files'), findsWidgets);
      expect(
        find.textContaining('4 files', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Asha Rao'), findsWidgets);
      expect(find.text('Vikram Shah'), findsWidgets);
      // The panel shows the newest file.
      expect(find.text('Saved to the cloud'), findsNothing);
      expect(find.text('Uploading…'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop files can be displayed in list view', (tester) async {
    setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(
      app(
        const FilesScreen(),
        initial: const FilesState(viewMode: FilesViewMode.list),
      ),
    );
    await settle(tester);

    expect(find.byType(FilesList), findsOneWidget);
    expect(find.byType(FilesGrid), findsNothing);
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
    // The phone row names the patient only; the date is no longer joined on.
    expect(find.text('Vikram Shah'), findsWidgets);
    expect(find.text('Vikram Shah · Yesterday'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone layout places clinic icon in parallel with filter chips below search bar',
    (tester) async {
      const colleague = ClinicMember(
        uid: 'other_doc',
        name: 'Dr. Colleague',
        phone: '',
        email: '',
        kind: MemberKind.doctor,
        roleId: 'doctor',
        roleName: 'Doctor',
        perms: {ClinicPermission.clinicalEdit},
        active: true,
        isOwner: false,
        specialty: 'Dental',
        qualification: 'BDS',
        registrationNo: '123',
      );
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(members: const [colleague]),
            hasColleaguesProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: const Scaffold(
              body: FilesScreen(),
            ),
          ),
        ),
      );
      await settle(tester);

      final searchField = find.byType(TextField);
      final clinicIcon = find.byType(ClinicDropTarget);
      final allChip = find.text('All');

      expect(searchField, findsOneWidget);
      expect(clinicIcon, findsOneWidget);
      expect(allChip, findsOneWidget);

      final searchBottom = tester.getBottomLeft(searchField).dy;
      final clinicTop = tester.getTopLeft(clinicIcon).dy;
      final chipTop = tester.getTopLeft(allChip).dy;

      // Clinic icon is below search bar
      expect(clinicTop, greaterThan(searchBottom));
      // Clinic icon is in parallel with filters (vertically centered/aligned)
      expect((clinicTop - chipTop).abs(), lessThan(15));
      // Clinic icon is to the right of filter chips
      final clinicLeft = tester.getTopLeft(clinicIcon).dx;
      final chipRight = tester.getBottomRight(allChip).dx;
      expect(clinicLeft, greaterThan(chipRight));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incoming offer does not appear on files screen but appears in notifications screen',
    (tester) async {
      final offer = FileOffer(
        id: 'offer_1',
        clinicId: 'clinic',
        from: 'other_doc',
        to: 'me',
        batchId: 'batch_1',
        fileId: 'file_1',
        sha256: 'abc',
        sizeBytes: 1024,
        contentType: 'image/jpeg',
        patientId: 'p1',
        name: 'Photo 2026-11-06.jpg',
        thumb: '',
        status: FileOfferStatus.sent,
        via: FileOfferVia.cloud,
        createdAt: now,
        expireAt: now.add(const Duration(days: 7)),
      );

      // 1. FilesScreen: IncomingOffersCard does not appear
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(),
            incomingOffersProvider.overrideWith((ref) => Stream.value([offer])),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: const Scaffold(body: FilesScreen()),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(IncomingOffersCard), findsNothing);

      // 2. MobileNotificationsScreen: IncomingOffersCard appears
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(),
            incomingOffersProvider.overrideWith((ref) => Stream.value([offer])),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: const Scaffold(body: MobileNotificationsScreen()),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(IncomingOffersCard), findsOneWidget);
      expect(find.textContaining('Photo 2026-11-06.jpg'), findsOneWidget);
    },
  );

  testWidgets(
    'showAddFilesDialog allows adding file without a patient under doctor id',
    (tester) async {
      setSize(tester, const Size(800, 600));
      final source = FileSource(
        name: 'UnassignedReport.pdf',
        sizeBytes: 2048,
        bytes: Uint8List(2048),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAddFilesDialog(context, sources: [source]),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);

      expect(find.text('UnassignedReport.pdf'), findsOneWidget);
      expect(find.text('No patient'), findsOneWidget);
      expect(find.text('Add file'), findsNWidgets(2));
    },
  );

  testWidgets(
    'incoming offer does not appear on files screen but appears in notifications screen',
    (tester) async {
      final offer = FileOffer(
        id: 'offer_1',
        clinicId: 'clinic',
        from: 'other_doc',
        to: 'me',
        batchId: 'batch_1',
        fileId: 'file_1',
        sha256: 'abc',
        sizeBytes: 1024,
        contentType: 'image/jpeg',
        patientId: 'p1',
        name: 'Photo 2026-11-06.jpg',
        thumb: '',
        status: FileOfferStatus.sent,
        via: FileOfferVia.cloud,
        createdAt: now,
        expireAt: now.add(const Duration(days: 7)),
      );

      // 1. FilesScreen: IncomingOffersCard does not appear
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(),
            incomingOffersProvider.overrideWith((ref) => Stream.value([offer])),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: const Scaffold(body: FilesScreen()),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(IncomingOffersCard), findsNothing);

      // 2. MobileNotificationsScreen: IncomingOffersCard appears
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(),
            incomingOffersProvider.overrideWith((ref) => Stream.value([offer])),
          ],
          child: MaterialApp(
            theme: CruTheme.day(),
            home: const Scaffold(body: MobileNotificationsScreen()),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(IncomingOffersCard), findsOneWidget);
      expect(find.textContaining('Photo 2026-11-06.jpg'), findsOneWidget);
    },
  );

  testWidgets(
    'showAddFilesDialog allows adding file without a patient under doctor id',
    (tester) async {
      setSize(tester, const Size(800, 600));
      final source = FileSource(
        name: 'UnassignedReport.pdf',
        sizeBytes: 2048,
        bytes: Uint8List(2048),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAddFilesDialog(context, sources: [source]),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);

      expect(find.text('UnassignedReport.pdf'), findsOneWidget);
      expect(find.text('No patient'), findsOneWidget);
      expect(find.text('Add file'), findsNWidgets(2));
    },
  );

  testWidgets('patient card lists their files with Add files in the header', (
    tester,
  ) async {
    setSize(tester, const Size(500, 900));
    await tester.pumpWidget(
      app(SingleChildScrollView(child: PatientFilesCard(patient: patients[0]))),
    );
    await settle(tester);
    // The list expands in place with "Show N more"; no See all link.
    expect(find.text('See all'), findsNothing);
    expect(find.text('OPG full mouth.jpg'), findsOneWidget);
    expect(find.byTooltip('Add files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort icon inside search bar opens sort menu and updates sort', (
    tester,
  ) async {
    setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(app(const FilesScreen()));
    await settle(tester);

    // The sort icon button is present with its tooltip/semantics.
    final sortButton = find.byTooltip('Sort: Newest first');
    expect(sortButton, findsOneWidget);

    // Tap to open the sort menu.
    await tester.tap(sortButton);
    await tester.pumpAndSettle();

    // Menu options are displayed.
    expect(find.text('Oldest first'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);

    // Select 'Oldest first' sort.
    await tester.tap(find.text('Oldest first'));
    await tester.pumpAndSettle();

    // Tooltip / semantic label updates to reflect new sort.
    expect(find.byTooltip('Sort: Oldest first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
