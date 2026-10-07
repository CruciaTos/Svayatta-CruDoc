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
import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_header.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/widgets/overview/revenue_by_doctor_card.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/team/presentation/join_clinic_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'patients/patients_fixtures.dart' show fixturePlan;
import 'revenue/revenue_fixtures.dart' show buildRevenueEntries, revenueNow;

void main() {
  const clinicId = 'clinic-dev-owner-001';
  const ownerUid = 'owner-uid-sameer';
  const receptionistUid = 'receptionist-uid-101';
  const doctor2Uid = 'doctor-uid-202';

  // Test numbers provided by user
  const receptionistPhone = '+91<number>';
  const doctor2Phone = '+91<number>';

  final ownerMember = ClinicMember(
    uid: ownerUid,
    name: 'Dr. Sameer Joshi',
    phone: '+919876543200',
    email: 'sameer@crudoc.dev',
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

  final receptionistMember = ClinicMember(
    uid: receptionistUid,
    name: 'Pooja Receptionist',
    phone: receptionistPhone,
    email: '',
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

  final doctor2Member = ClinicMember(
    uid: doctor2Uid,
    name: 'Dr. Priya Sharma',
    phone: doctor2Phone,
    email: 'priya@crudoc.dev',
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
    registrationNo: 'MH-98765',
  );

  final receptionistInvite = ClinicInvite(
    id: 'inv-rec-1',
    clinicId: clinicId,
    clinicName: 'Joshi Dental & Medical Clinic',
    name: 'Pooja Receptionist',
    phone: receptionistPhone,
    email: '',
    kind: MemberKind.staff,
    roleId: 'receptionist',
    roleName: 'Receptionist',
    specialty: '',
    status: 'pending',
    invitedByName: 'Dr. Sameer Joshi',
    expiresAt: DateTime.now().add(const Duration(days: 7)),
  );

  final doctor2Invite = ClinicInvite(
    id: 'inv-doc-2',
    clinicId: clinicId,
    clinicName: 'Joshi Dental & Medical Clinic',
    name: 'Dr. Priya Sharma',
    phone: doctor2Phone,
    email: 'priya@crudoc.dev',
    kind: MemberKind.doctor,
    roleId: 'doctor',
    roleName: 'Doctor',
    specialty: 'Dermatology',
    status: 'pending',
    invitedByName: 'Dr. Sameer Joshi',
    expiresAt: DateTime.now().add(const Duration(days: 7)),
  );

  final testClinic = Clinic(
    id: clinicId,
    name: 'Joshi Dental & Medical Clinic',
    specialty: 'Dental surgery',
    ownerUid: ownerUid,
    seatsDoctor: 5,
    seatsStaff: 10,
    enabledModules: const [
      'patients',
      'appointments',
      'queue',
      'revenue',
      'omnichannel_messaging',
      'inventory',
    ],
  );

  setUp(() {
    ClinicSession.instance.setAccessForTesting(ClinicAccess.owner(clinicId));
  });

  tearDown(() {
    ClinicSession.instance.setAccessForTesting(null);
  });

  group('End-to-End Clinic Team Flow Tests (Dev Project & Test Phones)', () {
    testWidgets(
      '1. Test Phone 1 (Receptionist) sees invite, joins clinic, and accesses only receptionist tabs',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Step 1: Receptionist arrives at JoinClinicScreen
        await tester.pumpWidget(
          MaterialApp(
            theme: CruTheme.day(),
            home: JoinClinicScreen(
              invites: [receptionistInvite],
              onJoined: () {},
              onSetUpOwn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify invite card content
        expect(find.text("You've been invited"), findsOneWidget);
        expect(find.text('Joshi Dental & Medical Clinic'), findsOneWidget);
        expect(find.text('as Receptionist'), findsOneWidget);
        expect(find.text('Invited by Dr. Sameer Joshi'), findsOneWidget);
        expect(find.text('Join'), findsOneWidget);

        // Step 2: Test receptionist access & sidebar gating
        final receptionistAccess = ClinicAccess(
          clinicId: clinicId,
          uid: receptionistUid,
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

        // Assert permission rules
        expect(receptionistAccess.isOwner, isFalse);
        expect(receptionistAccess.can(ClinicPermission.schedule), isTrue);
        expect(receptionistAccess.can(ClinicPermission.patientsView), isTrue);
        expect(receptionistAccess.can(ClinicPermission.billing), isTrue);
        expect(receptionistAccess.can(ClinicPermission.clinicalView), isFalse);
        expect(receptionistAccess.can(ClinicPermission.clinicalEdit), isFalse);
        expect(receptionistAccess.can(ClinicPermission.team), isFalse);
        expect(receptionistAccess.allowsModule('appointments'), isTrue);
        expect(receptionistAccess.allowsModule('revenue'), isTrue);
        expect(receptionistAccess.allowsModule('ai_assistant'), isFalse);

        final recIdentity = const DoctorIdentity(
          fullName: 'Pooja Receptionist',
          specialty: '',
          clinicName: 'Joshi Dental & Medical Clinic',
          isDoctor: false,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clinicAccessProvider.overrideWith(
                (ref) => Stream.value(receptionistAccess),
              ),
              doctorIdentityProvider.overrideWithValue(recIdentity),
              subscriptionInfoProvider.overrideWith(
                (ref) => Stream.value(fixturePlan),
              ),
              waitingNowCountProvider.overrideWithValue(0),
              activeDoctorSpecialtyProvider.overrideWith(
                (ref) => Stream.value(DoctorSpecialty.defaultSpecialty),
              ),
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

        // Receptionist should see operational tabs:
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Schedule'), findsOneWidget);
        expect(find.text('Patients'), findsWidgets);
        expect(find.text('Revenue'), findsOneWidget);

        // Receptionist should NOT see clinical, dental, or inventory/team tabs:
        expect(find.text('Dental chart'), findsNothing);
        expect(find.text('Perio'), findsNothing);
        expect(find.text('Biopsies'), findsNothing);
        expect(find.text('Lesions'), findsNothing);
        expect(find.text('Camps'), findsNothing);
        expect(find.text('Team'), findsNothing);
      },
    );

    testWidgets(
      '2. Test Phone 2 (Doctor with Dermatology) sees invite, joins clinic, and sees clinical tabs',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Step 1: Doctor arrives at JoinClinicScreen
        await tester.pumpWidget(
          MaterialApp(
            theme: CruTheme.day(),
            home: JoinClinicScreen(
              invites: [doctor2Invite],
              onJoined: () {},
              onSetUpOwn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("You've been invited"), findsOneWidget);
        expect(find.text('Joshi Dental & Medical Clinic'), findsOneWidget);
        expect(find.text('as Doctor'), findsOneWidget);
        expect(find.text('Join'), findsOneWidget);

        // Step 2: Test doctor access & sidebar
        final doctor2Access = ClinicAccess(
          clinicId: clinicId,
          uid: doctor2Uid,
          roleId: 'doctor',
          roleName: 'Doctor',
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
        );

        expect(doctor2Access.isOwner, isFalse);
        expect(doctor2Access.kind, equals(MemberKind.doctor));
        expect(doctor2Access.can(ClinicPermission.clinicalView), isTrue);
        expect(doctor2Access.can(ClinicPermission.clinicalEdit), isTrue);
        expect(doctor2Access.can(ClinicPermission.schedule), isTrue);
        expect(doctor2Access.can(ClinicPermission.team), isFalse);

        final doc2Identity = const DoctorIdentity(
          fullName: 'Dr. Priya Sharma',
          specialty: 'Dermatology',
          clinicName: 'Joshi Dental & Medical Clinic',
          isDoctor: true,
        );

        final dermSpecialty = DoctorSpecialty.all.firstWhere(
          (s) => s.type == DoctorSpecialtyType.dermatologist,
          orElse: () => DoctorSpecialty.defaultSpecialty,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clinicAccessProvider.overrideWith(
                (ref) => Stream.value(doctor2Access),
              ),
              doctorIdentityProvider.overrideWithValue(doc2Identity),
              subscriptionInfoProvider.overrideWith(
                (ref) => Stream.value(fixturePlan),
              ),
              waitingNowCountProvider.overrideWithValue(1),
              activeDoctorSpecialtyProvider.overrideWith(
                (ref) => Stream.value(dermSpecialty),
              ),
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

        // Doctor sees operational tabs
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Schedule'), findsOneWidget);
        expect(find.text('Patients'), findsWidgets);
      },
    );

    testWidgets(
      '3. Doctor filter in schedule header lists both doctors and switches selection',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 300));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final doctors = [ownerMember, doctor2Member];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clinicDoctorsProvider.overrideWith(
                (ref) => Stream.value(doctors),
              ),
              scheduleDoctorFilterProvider.overrideWith(
                (ref) => null,
              ), // All doctors
              clinicAccessProvider.overrideWith(
                (ref) => Stream.value(ClinicAccess.owner(clinicId)),
              ),
              activeClinicProvider.overrideWith(
                (ref) => Stream.value(testClinic),
              ),
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
        await tester.pump();
        await tester.pumpAndSettle();

        // The filter dropdown button should be visible showing 'All doctors'
        expect(find.byType(ScheduleDoctorFilter), findsOneWidget);
        expect(find.text('All doctors'), findsOneWidget);

        // Open popup menu
        await tester.tap(find.byType(ScheduleDoctorFilter));
        await tester.pumpAndSettle();

        // Both doctors and 'All doctors' should appear in menu items
        expect(find.text('All doctors'), findsWidgets);
        expect(find.text('Dr. Sameer Joshi'), findsOneWidget);
        expect(find.text('Dr. Priya Sharma'), findsOneWidget);

        // Tap second doctor
        await tester.tap(find.text('Dr. Priya Sharma').last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '4. Revenue by Doctor card breaks down revenue across doctors',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final doctors = [ownerMember, doctor2Member];
        final entries = buildRevenueEntries();
        final overview = RevenueBuilder.overview(
          entries: entries,
          period: RevenuePeriod.month,
          filter: TxnFilter.all,
          now: revenueNow,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clinicDoctorsProvider.overrideWith(
                (ref) => Stream.value(doctors),
              ),
              clinicAccessProvider.overrideWith(
                (ref) => Stream.value(ClinicAccess.owner(clinicId)),
              ),
              revenueOverviewProvider.overrideWithValue(overview),
              recentRevenueEntriesProvider.overrideWith(
                (ref) => Stream.value(entries),
              ),
            ],
            child: MaterialApp(
              theme: CruTheme.day(),
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(CruSpace.s16),
                  child: RevenueByDoctorCard(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.text('By doctor'), findsOneWidget);
        expect(find.text('Dr. Sameer Joshi'), findsOneWidget);
        expect(find.text('Dr. Priya Sharma'), findsOneWidget);
      },
    );
  });
}
