import 'clinic_models.dart';
import 'clinic_permission.dart';

/// The five built-in roles seeded into every clinic.
const List<ClinicRole> builtInRoles = [
  ClinicRole(
    id: 'admin',
    name: 'Admin',
    kind: MemberKind.staff,
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.patientsEdit,
      ClinicPermission.clinicalView,
      ClinicPermission.clinicalEdit,
      ClinicPermission.schedule,
      ClinicPermission.billing,
      ClinicPermission.revenue,
      ClinicPermission.inventory,
      ClinicPermission.messaging,
      ClinicPermission.ai,
      ClinicPermission.team,
      ClinicPermission.settings,
    },
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
    isSystem: false,
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
    isSystem: false,
  ),
  ClinicRole(
    id: 'assistant',
    name: 'Assistant / Nurse',
    kind: MemberKind.staff,
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.clinicalView,
      ClinicPermission.schedule,
      ClinicPermission.inventory,
    },
    isSystem: false,
  ),
  ClinicRole(
    id: 'accountant',
    name: 'Accountant',
    kind: MemberKind.staff,
    perms: {
      ClinicPermission.patientsView,
      ClinicPermission.billing,
      ClinicPermission.revenue,
    },
    isSystem: false,
  ),
];
