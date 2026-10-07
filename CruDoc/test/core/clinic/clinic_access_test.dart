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

    test('4. Member with roleId admin and empty perms: can(team) is true, isOwner is false, allowsModule(campaigns) is false', () {
      final adminMemberAccess = const ClinicAccess(
        clinicId: 'clinic_123',
        uid: 'user_admin2',
        roleId: 'admin',
        roleName: 'Admin',
        kind: MemberKind.staff,
        perms: {},
      );

      expect(adminMemberAccess.can(ClinicPermission.team), isTrue);
      expect(adminMemberAccess.isOwner, isFalse);
      expect(adminMemberAccess.allowsModule('campaigns'), isFalse);
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
