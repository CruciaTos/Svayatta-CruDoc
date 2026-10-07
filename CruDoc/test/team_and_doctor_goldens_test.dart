import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_header.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/invite_sheet.dart';
import 'package:doctor_management_app/features/team/presentation/role_editor_sheet.dart';
import 'package:doctor_management_app/features/team/presentation/team_section.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'patients/patients_fixtures.dart' show fixturePlan, loadGeist;

void main() {
  setUpAll(loadGeist);

  final ownerMember = ClinicMember(
    uid: 'owner-1',
    name: 'Dr. Sameer Joshi',
    phone: '+919876543210',
    email: 'sameer@example.com',
    kind: MemberKind.doctor,
    roleId: 'admin',
    roleName: 'Owner',
    perms: ClinicPermission.values.toSet(),
    active: true,
    isOwner: true,
    specialty: 'Dental surgery',
    qualification: 'BDS, MDS',
    registrationNo: 'MH-12345',
  );

  final doctorMember = ClinicMember(
    uid: 'doc-2',
    name: 'Dr. Ananya Rao',
    phone: '+919876543211',
    email: 'ananya@example.com',
    kind: MemberKind.doctor,
    roleId: 'doctor',
    roleName: 'Doctor',
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.patientsEdit,
      ClinicPermission.clinicalView,
      ClinicPermission.clinicalEdit,
      ClinicPermission.schedule,
      ClinicPermission.billing,
      ClinicPermission.messaging,
      ClinicPermission.ai,
    },
    active: true,
    isOwner: false,
    specialty: 'Dermatology',
    qualification: 'MBBS, MD',
    registrationNo: 'KA-67890',
  );

  final receptionistMember = ClinicMember(
    uid: 'staff-1',
    name: 'Pooja Patil',
    phone: '+919876543212',
    email: 'pooja@example.com',
    kind: MemberKind.staff,
    roleId: 'receptionist',
    roleName: 'Receptionist',
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.patientsEdit,
      ClinicPermission.schedule,
      ClinicPermission.billing,
      ClinicPermission.messaging,
    },
    active: true,
    isOwner: false,
    specialty: '',
    qualification: '',
    registrationNo: '',
  );

  final testRoles = [
    ClinicRole(
      id: 'admin',
      name: 'Admin',
      kind: MemberKind.doctor,
      perms: ClinicPermission.values.toSet(),
      isSystem: true,
    ),
    ClinicRole(
      id: 'doctor',
      name: 'Doctor',
      kind: MemberKind.doctor,
      perms: {
        ClinicPermission.patientsView,
        ClinicPermission.patientsEdit,
        ClinicPermission.clinicalView,
        ClinicPermission.clinicalEdit,
        ClinicPermission.schedule,
        ClinicPermission.billing,
        ClinicPermission.messaging,
        ClinicPermission.ai,
      },
      isSystem: true,
    ),
    ClinicRole(
      id: 'receptionist',
      name: 'Receptionist',
      kind: MemberKind.staff,
      perms: {
        ClinicPermission.patientsView,
        ClinicPermission.patientsEdit,
        ClinicPermission.schedule,
        ClinicPermission.billing,
        ClinicPermission.messaging,
      },
      isSystem: true,
    ),
  ];

  final testInvites = <ClinicInvite>[
    ClinicInvite(
      id: 'inv-1',
      clinicId: 'owner-1',
      clinicName: 'Joshi Dental & Medical Clinic',
      name: 'Dr. Rohit Sharma',
      phone: '+919876543213',
      email: '',
      kind: MemberKind.doctor,
      roleId: 'doctor',
      roleName: 'Doctor',
      specialty: 'Orthodontics',
      status: 'pending',
      invitedByName: 'Dr. Sameer Joshi',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    ),
  ];

  final testClinic = Clinic(
    id: 'owner-1',
    name: 'Joshi Dental & Medical Clinic',
    specialty: 'Dental surgery',
    ownerUid: 'owner-1',
    seatsDoctor: 5,
    seatsStaff: 10,
    enabledModules: const ['patients', 'appointments', 'queue', 'revenue', 'omnichannel_messaging', 'inventory'],
  );

  final ownerAccess = ClinicAccess.owner('owner-1');

  final receptionistAccess = ClinicAccess(
    clinicId: 'owner-1',
    uid: 'staff-1',
    roleId: 'receptionist',
    roleName: 'Receptionist',
    kind: MemberKind.staff,
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.patientsEdit,
      ClinicPermission.schedule,
      ClinicPermission.billing,
      ClinicPermission.messaging,
    },
  );

  final ownerIdentity = const DoctorIdentity(
    fullName: 'Dr. Sameer Joshi',
    specialty: 'Dental surgery',
    clinicName: 'Joshi Dental & Medical Clinic',
    isDoctor: true,
  );

  final receptionistIdentity = const DoctorIdentity(
    fullName: 'Pooja Patil',
    specialty: '',
    clinicName: 'Joshi Dental & Medical Clinic',
    isDoctor: false,
  );

  // 1. Team Screen
  testWidgets('Team screen golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicMembersProvider.overrideWith((ref) => Stream.value([ownerMember, doctorMember, receptionistMember])),
          clinicRolesProvider.overrideWith((ref) => Stream.value(testRoles)),
          clinicInvitesProvider.overrideWith((ref) => Stream.value(testInvites)),
          clinicAccessProvider.overrideWith((ref) => Stream.value(ownerAccess)),
          activeClinicProvider.overrideWith((ref) => Stream.value(testClinic)),
          doctorIdentityProvider.overrideWithValue(ownerIdentity),
          activeDoctorSpecialtyProvider.overrideWith((ref) => Stream.value(DoctorSpecialty.ofType(DoctorSpecialtyType.dentist))),
          clinicDoctorsProvider.overrideWith((ref) => Stream.value([ownerMember, doctorMember])),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: const Scaffold(
            body: TeamSection(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/team_screen.png'),
    );
  });

  // 2. Invite Dialog
  testWidgets('Invite dialog golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicAccessProvider.overrideWith((ref) => Stream.value(ownerAccess)),
          clinicRolesProvider.overrideWith((ref) => Stream.value(testRoles)),
          activeClinicProvider.overrideWith((ref) => Stream.value(testClinic)),
          doctorIdentityProvider.overrideWithValue(ownerIdentity),
          activeDoctorSpecialtyProvider.overrideWith((ref) => Stream.value(DoctorSpecialty.ofType(DoctorSpecialtyType.dentist))),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showInviteDialog(context),
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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/invite_dialog.png'),
    );
  });

  // 3. Role Editor Dialog
  testWidgets('Role editor golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicAccessProvider.overrideWith((ref) => Stream.value(ownerAccess)),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showRoleEditor(
                    context,
                    role: ClinicRole(
                      id: 'custom-tech',
                      name: 'Lab technician',
                      kind: MemberKind.staff,
                      perms: {ClinicPermission.patientsView, ClinicPermission.clinicalView, ClinicPermission.inventory},
                      isSystem: false,
                    ),
                  ),
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

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/role_editor.png'),
    );
  });

  // 4. Receptionist Sidebar
  testWidgets('Receptionist sidebar golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicAccessProvider.overrideWith((ref) => Stream.value(receptionistAccess)),
          doctorIdentityProvider.overrideWithValue(receptionistIdentity),
          subscriptionInfoProvider.overrideWith((ref) => Stream.value(fixturePlan)),
          waitingNowCountProvider.overrideWithValue(2),
          activeDoctorSpecialtyProvider.overrideWith((ref) => Stream.value(DoctorSpecialty.defaultSpecialty)),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Scaffold(
            body: Row(
              children: [
                CruSidebar(
                  currentTab: DesktopTab.appointments,
                  collapsed: false,
                  callbacks: SidebarCallbacks(
                    onNavigate: (_) {},
                    onClinicSwitcher: () {},
                    onUpgrade: () {},
                    onSettings: () {},
                    onHelp: () {},
                    onLogout: () {},
                    onToggleCollapsed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/receptionist_sidebar.png'),
    );
  });

  // 5. Doctor Filter in Header
  testWidgets('Doctor filter in schedule header golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicDoctorsProvider.overrideWith((ref) => Stream.value([ownerMember, doctorMember])),
          scheduleDoctorFilterProvider.overrideWith((ref) => null),
          clinicAccessProvider.overrideWith((ref) => Stream.value(ownerAccess)),
          activeClinicProvider.overrideWith((ref) => Stream.value(testClinic)),
        ],
        child: MaterialApp(
          theme: CruTheme.day(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: ScheduleHeaderFrame(
                stepLabel: 'day',
                onToday: () {},
                onStep: (_) {},
                title: Text(
                  'Today · Wednesday, 23 Sep',
                  style: CruType.title2.tint(CruColors.day.label),
                ),
                primary: CruButton(
                  label: 'Book appointment',
                  expand: true,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/doctor_filter.png'),
    );
  });
}
