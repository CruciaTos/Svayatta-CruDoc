import 'package:cloud_firestore/cloud_firestore.dart';
import 'clinic_permission.dart';

/// Kind of member in a clinic: doctor or staff.
enum MemberKind {
  doctor('doctor'),
  staff('staff');

  const MemberKind(this.value);
  final String value;

  static MemberKind fromString(String? val) {
    if (val == 'doctor') return MemberKind.doctor;
    return MemberKind.staff;
  }
}

/// A named role with permissions in a clinic.
class ClinicRole {
  final String id;
  final String name;
  final MemberKind kind;
  final Set<ClinicPermission> perms;
  final bool isSystem;

  const ClinicRole({
    required this.id,
    required this.name,
    required this.kind,
    required this.perms,
    this.isSystem = false,
  });

  factory ClinicRole.fromMap(String id, Map<String, dynamic> map) {
    final rawPerms = map['perms'];
    final permsSet = <ClinicPermission>{};
    if (rawPerms is Iterable) {
      for (final p in rawPerms) {
        final cp = ClinicPermission.fromKey(p.toString());
        if (cp != null) permsSet.add(cp);
      }
    }
    return ClinicRole(
      id: id,
      name: map['name'] as String? ?? '',
      kind: MemberKind.fromString(map['kind'] as String?),
      perms: normalizePermissions(permsSet.map((p) => p.key)),
      isSystem: map['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'kind': kind.value,
    'perms': perms.map((p) => p.key).toList(),
    'isSystem': isSystem,
  };
}

/// A member of a clinic (doctor, owner, or staff).
class ClinicMember {
  final String uid;
  final String name;
  final String phone;
  final String email;
  final MemberKind kind;
  final String roleId;
  final String roleName;
  final Set<ClinicPermission> perms;
  final bool active;
  final bool isOwner;
  final String specialty;
  final String qualification;
  final String registrationNo;
  final List<String>? modules;

  /// A joining dentist's starting dental features (copied to their own
  /// profile once, by their app).
  final List<String>? dentalFeatures;
  final DateTime? joinedAt;

  const ClinicMember({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
    required this.kind,
    required this.roleId,
    required this.roleName,
    required this.perms,
    required this.active,
    required this.isOwner,
    required this.specialty,
    required this.qualification,
    required this.registrationNo,
    this.modules,
    this.dentalFeatures,
    this.joinedAt,
  });

  factory ClinicMember.fromMap(String id, Map<String, dynamic> map) {
    final rawPerms = map['perms'];
    final permsSet = <ClinicPermission>{};
    if (rawPerms is Iterable) {
      for (final p in rawPerms) {
        final cp = ClinicPermission.fromKey(p.toString());
        if (cp != null) permsSet.add(cp);
      }
    }
    List<String>? modulesList;
    if (map.containsKey('modules') && map['modules'] is Iterable) {
      modulesList = (map['modules'] as Iterable)
          .map((e) => e.toString())
          .toList();
    }
    final rawDental = map['dentalFeatures'];
    final dentalList = rawDental is Iterable
        ? rawDental.map((e) => e.toString()).toList()
        : null;
    DateTime? joined;
    final rawJoined = map['joinedAt'];
    if (rawJoined is Timestamp) {
      joined = rawJoined.toDate();
    } else if (rawJoined is String) {
      joined = DateTime.tryParse(rawJoined);
    }
    return ClinicMember(
      uid: id,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      kind: MemberKind.fromString(map['kind'] as String?),
      roleId: map['roleId'] as String? ?? '',
      roleName: map['roleName'] as String? ?? '',
      perms: normalizePermissions(permsSet.map((p) => p.key)),
      active: map['active'] as bool? ?? true,
      isOwner: map['isOwner'] as bool? ?? false,
      specialty: map['specialty'] as String? ?? '',
      qualification: map['qualification'] as String? ?? '',
      registrationNo: map['registrationNo'] as String? ?? '',
      modules: modulesList,
      dentalFeatures: dentalList,
      joinedAt: joined,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'email': email,
    'kind': kind.value,
    'roleId': roleId,
    'roleName': roleName,
    'perms': perms.map((p) => p.key).toList(),
    'active': active,
    'isOwner': isOwner,
    'specialty': specialty,
    'qualification': qualification,
    'registrationNo': registrationNo,
    if (modules != null) 'modules': modules,
    if (joinedAt != null) 'joinedAt': Timestamp.fromDate(joinedAt!),
  };
}

/// An invite to join a clinic.
class ClinicInvite {
  final String id;
  final String clinicId;
  final String clinicName;
  final String name;
  final String phone;
  final String email;
  final MemberKind kind;
  final String roleId;
  final String roleName;
  final String specialty;
  final String status;
  final DateTime? expiresAt;
  final String invitedByName;

  /// Set when the invite was sent by CruDoc ID: the ID ("K7Q9-2XMB") and
  /// the account it belongs to. Such invites carry no phone or email.
  final String? crudocId;
  final String? inviteeUid;

  const ClinicInvite({
    required this.id,
    required this.clinicId,
    required this.clinicName,
    required this.name,
    required this.phone,
    required this.email,
    required this.kind,
    required this.roleId,
    required this.roleName,
    required this.specialty,
    required this.status,
    this.expiresAt,
    required this.invitedByName,
    this.crudocId,
    this.inviteeUid,
  });

  factory ClinicInvite.fromMap(String id, Map<String, dynamic> map) {
    DateTime? exp;
    final rawExp = map['expiresAt'];
    if (rawExp is Timestamp) {
      exp = rawExp.toDate();
    } else if (rawExp is String) {
      exp = DateTime.tryParse(rawExp);
    }
    return ClinicInvite(
      id: id,
      clinicId: map['clinicId'] as String? ?? '',
      clinicName: map['clinicName'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      kind: MemberKind.fromString(map['kind'] as String?),
      roleId: map['roleId'] as String? ?? '',
      roleName: map['roleName'] as String? ?? '',
      specialty: map['specialty'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      expiresAt: exp,
      invitedByName: map['invitedByName'] as String? ?? '',
      crudocId: switch (map['crudocId']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
      inviteeUid: switch (map['inviteeUid']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toMap() => {
    'clinicId': clinicId,
    'clinicName': clinicName,
    'name': name,
    'phone': phone,
    'email': email,
    'kind': kind.value,
    'roleId': roleId,
    'roleName': roleName,
    'specialty': specialty,
    'status': status,
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    'invitedByName': invitedByName,
    'crudocId': ?crudocId,
    'inviteeUid': ?inviteeUid,
  };
}

/// Clinic account owning the data.
class Clinic {
  final String id;
  final String name;
  final String specialty;
  final String ownerUid;
  final int seatsDoctor;
  final int seatsStaff;
  final List<String>? enabledModules;
  final String status;
  final DateTime? expiresDate;

  /// Whether this clinic's admins may open clinical records. Running the
  /// clinic and treating its patients are separate kinds of authority, so an
  /// admin gets no clinical access until the owner grants it. An absent
  /// field reads as `true` (a clinic predating the setting), matching the
  /// rules and the backfill migration.
  final bool adminClinicalAccess;

  /// `'clinic'` (the default) means every doctor sees every patient, which is
  /// how a small practice covers walk-ins and absences. `'assigned'` scopes
  /// each doctor to the patients in their `assignedDoctorUids`.
  ///
  /// Not settable from the app yet: a scoped doctor's patient queries have to
  /// narrow to `assignedDoctorUids array-contains <uid>` for the rules to
  /// allow them, and that filtering is not wired up. Read-only here so the
  /// value is visible once it is.
  final String clinicalAccessScope;

  bool get scopesDoctorsToAssignedPatients => clinicalAccessScope == 'assigned';

  const Clinic({
    required this.id,
    required this.name,
    required this.specialty,
    required this.ownerUid,
    this.seatsDoctor = 5,
    this.seatsStaff = 10,
    this.enabledModules,
    this.status = 'active',
    this.expiresDate,
    this.adminClinicalAccess = true,
    this.clinicalAccessScope = 'clinic',
  });

  factory Clinic.fromMap(String id, Map<String, dynamic> map) {
    DateTime? exp;
    final rawExpires = map['expiresDate'];
    if (rawExpires is Timestamp) {
      exp = rawExpires.toDate();
    } else if (rawExpires is String) {
      exp = DateTime.tryParse(rawExpires);
    }

    final seats = map['seats'] as Map<String, dynamic>?;
    final docSeats =
        (seats != null ? seats['doctor'] as num? : map['seatsDoctor'] as num?)
            ?.toInt() ??
        5;
    final staffSeats =
        (seats != null ? seats['staff'] as num? : map['seatsStaff'] as num?)
            ?.toInt() ??
        10;

    List<String>? modules;
    if (map['enabledModules'] is Iterable) {
      modules = (map['enabledModules'] as Iterable)
          .map((e) => e.toString())
          .toList();
    }

    return Clinic(
      id: id,
      name: map['name'] as String? ?? '',
      specialty: map['specialty'] as String? ?? '',
      ownerUid: map['ownerUid'] as String? ?? id,
      seatsDoctor: docSeats,
      seatsStaff: staffSeats,
      enabledModules: modules,
      status: map['status'] as String? ?? 'active',
      expiresDate: exp,
      adminClinicalAccess: map['adminClinicalAccess'] != false,
      clinicalAccessScope: map['clinicalAccessScope'] == 'assigned'
          ? 'assigned'
          : 'clinic',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'specialty': specialty,
    'ownerUid': ownerUid,
    'seats': {'doctor': seatsDoctor, 'staff': seatsStaff},
    if (enabledModules != null) 'enabledModules': enabledModules,
    'adminClinicalAccess': adminClinicalAccess,
    'clinicalAccessScope': clinicalAccessScope,
    'status': status,
    if (expiresDate != null) 'expiresDate': Timestamp.fromDate(expiresDate!),
  };
}
