import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/role_templates.dart';

void main() {
  group('ClinicAccess and Permissions Tests', () {
    test('1. ClinicAccess.owner: isOwner, can(team), allowsModule(revenue)', () {
      final ownerAccess = ClinicAccess.owner('u1');
      expect(ownerAccess.isOwner, isTrue);
      expect(ownerAccess.can(ClinicPermission.team), isTrue);
      expect(ownerAccess.allowsModule('revenue'), isTrue);
    });

    test('2. Receptionist (perms from template): can schedule, cannot clinicalView, allowsModule revenue, disallows ai_assistant', () {
      final recepRole = builtInRoles.firstWhere((r) => r.id == 'receptionist');
      final recepAccess = ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_recep',
        roleId: recepRole.id,
        roleName: recepRole.name,
        kind: recepRole.kind,
        perms: recepRole.perms,
      );

      expect(recepAccess.can(ClinicPermission.schedule), isTrue);
      expect(recepAccess.can(ClinicPermission.clinicalView), isFalse);
      expect(recepAccess.allowsModule('revenue'), isTrue); // billing permission unlocks revenue
      expect(recepAccess.allowsModule('ai_assistant'), isFalse);
    });

    test('3. Accountant: allowsModule(appointments) is false', () {
      final acctRole = builtInRoles.firstWhere((r) => r.id == 'accountant');
      final acctAccess = ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_acct',
        roleId: acctRole.id,
        roleName: acctRole.name,
        kind: acctRole.kind,
        perms: acctRole.perms,
      );

      expect(acctAccess.allowsModule('appointments'), isFalse);
    });

    test('4. Member with roleId admin: can() follows perms, not the role (no admin shortcut)', () {
      // An admin's entitlement is resolved on the server and arrives in
      // `perms`, so can() must not shortcut on the role: that is what used
      // to hand admins clinical access a clinic had withdrawn.
      final adminMemberAccess = const ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_admin2',
        roleId: 'admin',
        roleName: 'Admin',
        kind: MemberKind.staff,
        perms: {},
      );

      expect(adminMemberAccess.can(ClinicPermission.team), isFalse);
      expect(adminMemberAccess.isAdmin, isTrue);
      expect(adminMemberAccess.isOwner, isFalse);
      expect(adminMemberAccess.allowsModule('campaigns'), isFalse);

      // With the administrative permissions it is actually granted, it runs
      // the clinic as before.
      final realAdmin = ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_admin2',
        roleId: 'admin',
        roleName: 'Admin',
        kind: MemberKind.staff,
        perms: ClinicPermission.values
            .where((p) => !kClinicalPermissions.contains(p))
            .toSet(),
      );
      expect(realAdmin.can(ClinicPermission.team), isTrue);
      expect(realAdmin.can(ClinicPermission.settings), isTrue);
      expect(realAdmin.can(ClinicPermission.revenue), isTrue);
      expect(realAdmin.can(ClinicPermission.clinicalView), isFalse);
      expect(realAdmin.can(ClinicPermission.clinicalEdit), isFalse);
    });

    group('4b. fromMember applies the clinic\'s adminClinicalAccess', () {
      ClinicMember adminMember() => ClinicMember(
        uid: 'user_admin2',
        name: 'Practice Manager',
        phone: '',
        email: '',
        kind: MemberKind.staff,
        roleId: 'admin',
        roleName: 'Admin',
        // The stored member document holds every permission; whether the
        // clinical ones survive is the clinic's call.
        perms: ClinicPermission.values.toSet(),
        active: true,
        isOwner: false,
        specialty: '',
        qualification: '',
        registrationNo: '',
      );

      test('strips clinical permissions when the clinic says no', () {
        final access = ClinicAccess.fromMember(
          'clinic_123',
          adminMember(),
          adminClinicalAccess: false,
        );
        expect(access.can(ClinicPermission.clinicalView), isFalse);
        expect(access.can(ClinicPermission.clinicalEdit), isFalse);
        // Everything administrative is untouched.
        expect(access.can(ClinicPermission.team), isTrue);
        expect(access.can(ClinicPermission.settings), isTrue);
        expect(access.can(ClinicPermission.billing), isTrue);
        expect(access.can(ClinicPermission.patientsView), isTrue);
      });

      test('keeps them when the clinic says yes', () {
        final access = ClinicAccess.fromMember(
          'clinic_123',
          adminMember(),
          adminClinicalAccess: true,
        );
        expect(access.can(ClinicPermission.clinicalView), isTrue);
        expect(access.can(ClinicPermission.clinicalEdit), isTrue);
      });

      test('defaults to keeping them, matching how the rules read an absent field', () {
        final access = ClinicAccess.fromMember('clinic_123', adminMember());
        expect(access.can(ClinicPermission.clinicalEdit), isTrue);
      });

      test('leaves a non-admin member alone', () {
        final doctor = ClinicMember(
          uid: 'user_doc',
          name: 'Dr Two',
          phone: '',
          email: '',
          kind: MemberKind.doctor,
          roleId: 'doctor',
          roleName: 'Doctor',
          perms: {
            ClinicPermission.patientsView,
            ClinicPermission.clinicalView,
            ClinicPermission.clinicalEdit,
          },
          active: true,
          isOwner: false,
          specialty: '',
          qualification: '',
          registrationNo: '',
        );
        final access = ClinicAccess.fromMember(
          'clinic_123',
          doctor,
          adminClinicalAccess: false,
        );
        expect(access.can(ClinicPermission.clinicalEdit), isTrue,
            reason: 'a doctor holds clinical access in their own right');
      });

      test('an owner is never affected', () {
        final access = ClinicAccess.owner('u1');
        expect(access.can(ClinicPermission.clinicalEdit), isTrue);
        expect(access.can(ClinicPermission.team), isTrue);
      });

      test('the stripped set survives a toJson/fromJson round trip', () {
        final access = ClinicAccess.fromMember(
          'clinic_123',
          adminMember(),
          adminClinicalAccess: false,
        );
        final restored = ClinicAccess.fromJson(access.toJson());
        expect(restored.can(ClinicPermission.clinicalView), isFalse,
            reason: 'the cached access must not restore clinical permissions');
        expect(restored.can(ClinicPermission.team), isTrue);
      });
    });

    group('4c. scopedToAssignedPatients', () {
      ClinicAccess member({
        required MemberKind kind,
        required String scope,
        String uid = 'user-1',
        String clinicId = 'clinic-1',
        String roleId = 'doctor',
      }) => ClinicAccess(
        clinicId: clinicId,
        uid: uid,
        roleId: roleId,
        roleName: roleId,
        kind: kind,
        perms: {ClinicPermission.patientsView, ClinicPermission.clinicalView},
        clinicalAccessScope: scope,
      );

      test('a doctor in a scoped clinic is scoped', () {
        expect(
          member(kind: MemberKind.doctor, scope: 'assigned')
              .scopedToAssignedPatients,
          isTrue,
        );
      });

      test('a doctor in a clinic-wide clinic is not', () {
        expect(
          member(kind: MemberKind.doctor, scope: 'clinic')
              .scopedToAssignedPatients,
          isFalse,
        );
      });

      test('the front desk is never scoped, even in a scoped clinic', () {
        // Reception needs the whole appointment book.
        expect(
          member(kind: MemberKind.staff, scope: 'assigned', roleId: 'receptionist')
              .scopedToAssignedPatients,
          isFalse,
        );
      });

      test('the owner is never scoped', () {
        expect(
          member(
            kind: MemberKind.doctor,
            scope: 'assigned',
            uid: 'clinic-1',
          ).scopedToAssignedPatients,
          isFalse,
        );
        expect(ClinicAccess.owner('u1').scopedToAssignedPatients, isFalse);
      });

      test('defaults to unscoped when the clinic says nothing', () {
        final access = ClinicAccess.fromMember(
          'clinic-1',
          ClinicMember(
            uid: 'u2',
            name: 'Dr Two',
            phone: '',
            email: '',
            kind: MemberKind.doctor,
            roleId: 'doctor',
            roleName: 'Doctor',
            perms: {ClinicPermission.clinicalView},
            active: true,
            isOwner: false,
            specialty: '',
            qualification: '',
            registrationNo: '',
          ),
        );
        expect(access.scopedToAssignedPatients, isFalse);
        expect(access.clinicalAccessScope, equals('clinic'));
      });

      test('survives a toJson/fromJson round trip', () {
        final access = member(kind: MemberKind.doctor, scope: 'assigned');
        final restored = ClinicAccess.fromJson(access.toJson());
        expect(restored.clinicalAccessScope, equals('assigned'));
        expect(restored.scopedToAssignedPatients, isTrue,
            reason: 'the cached access must keep scoping the doctor offline');
      });

      test('an unknown scope value is treated as clinic-wide', () {
        final restored = ClinicAccess.fromJson({
          ...member(kind: MemberKind.doctor, scope: 'assigned').toJson(),
          'clinicalAccessScope': 'nonsense',
        });
        expect(restored.scopedToAssignedPatients, isFalse);
      });
    });

    test('5. normalizePermissions drops unknown and adds implied', () {
      final perms = normalizePermissions(['clinical.edit', 'bogus']);
      expect(
        perms,
        equals({
          ClinicPermission.clinicalEdit,
          ClinicPermission.clinicalView,
          ClinicPermission.patientsView,
        }),
      );
    });

    test('6. toJson -> fromJson round-trip keeps every field (with and without modules)', () {
      final accessWithoutModules = const ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_1',
        roleId: 'receptionist',
        roleName: 'Receptionist',
        kind: MemberKind.staff,
        perms: {
          ClinicPermission.patientsView,
          ClinicPermission.schedule,
        },
      );
      final json1 = accessWithoutModules.toJson();
      final restored1 = ClinicAccess.fromJson(json1);
      expect(restored1.clinicId, equals('clinic_123'));
      expect(restored1.uid, equals('user_1'));
      expect(restored1.roleId, equals('receptionist'));
      expect(restored1.roleName, equals('Receptionist'));
      expect(restored1.kind, equals(MemberKind.staff));
      expect(restored1.perms, equals(accessWithoutModules.perms));
      expect(restored1.modules, isNull);

      final accessWithModules = const ClinicAccess(
        clinicId: 'clinic_456',
        uid: 'user_2',
        roleId: 'doctor',
        roleName: 'Doctor',
        kind: MemberKind.doctor,
        perms: {
          ClinicPermission.patientsView,
          ClinicPermission.clinicalView,
        },
        modules: {'patients', 'inventory'},
      );
      final json2 = accessWithModules.toJson();
      final restored2 = ClinicAccess.fromJson(json2);
      expect(restored2.clinicId, equals('clinic_456'));
      expect(restored2.uid, equals('user_2'));
      expect(restored2.roleId, equals('doctor'));
      expect(restored2.roleName, equals('Doctor'));
      expect(restored2.kind, equals(MemberKind.doctor));
      expect(restored2.perms, equals(accessWithModules.perms));
      expect(restored2.modules, equals({'patients', 'inventory'}));
    });

    test('7. Doctor role with modules: allows turned on module, disallows turned off module, allows dashboard', () {
      final docRole = builtInRoles.firstWhere((r) => r.id == 'doctor');
      final doctorAccess = ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'doc_1',
        roleId: docRole.id,
        roleName: docRole.name,
        kind: docRole.kind,
        perms: docRole.perms,
        modules: const {'patients', 'appointments'},
      );

      expect(doctorAccess.allowsModule('appointments'), isTrue);
      // ai_assistant is permitted by role, but turned off in personal modules
      expect(doctorAccess.allowsModule('ai_assistant'), isFalse);
      // dashboard is always allowed regardless of modules
      expect(doctorAccess.allowsModule('dashboard'), isTrue);
    });
  });
}
