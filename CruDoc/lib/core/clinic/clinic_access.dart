import 'clinic_models.dart';
import 'clinic_permission.dart';

/// Reading or writing a patient's clinical record, as opposed to running the
/// clinic. Keep in sync with CLINICAL_PERMS in functions/src/clinic.ts and
/// clinicalPerm() in firestore.rules / storage.rules.
const Set<ClinicPermission> kClinicalPermissions = {
  ClinicPermission.clinicalView,
  ClinicPermission.clinicalEdit,
};

/// What the signed-in person may do in the active clinic.
class ClinicAccess {
  const ClinicAccess({
    required this.clinicId,
    required this.uid,
    required this.roleId,
    required this.roleName,
    required this.kind,
    required this.perms,
    this.modules,
    this.clinicalAccessScope = 'clinic',
  });

  /// A doctor working alone, or before a clinic exists: owner of their own data.
  ///
  /// [clinical] is false for a manager who owns the clinic (set up as "I
  /// manage the clinic"): they run everything but never open medical records,
  /// matching the nonClinicalOwner check in the rules. Every solo doctor, and
  /// every doctor-owner, gets the default and so exactly what they had before.
  factory ClinicAccess.owner(String uid, {bool clinical = true}) {
    final all = ClinicPermission.values.toSet();
    return ClinicAccess(
      clinicId: uid,
      uid: uid,
      roleId: 'admin',
      roleName: 'Owner',
      kind: clinical ? MemberKind.doctor : MemberKind.staff,
      perms: clinical ? all : all.difference(kClinicalPermissions),
      modules: null,
    );
  }

  /// [adminClinicalAccess] is `clinics/{id}.adminClinicalAccess`. The admin
  /// role's member document stores every permission, so when a clinic has
  /// withdrawn clinical access from its admins it has to be taken off here
  /// too — otherwise the app would offer chart buttons the rules refuse.
  /// Defaults to `true` to match how the rules read an absent field.
  /// [clinicalAccessScope] is `clinics/{id}.clinicalAccessScope`.
  factory ClinicAccess.fromMember(
    String clinicId,
    ClinicMember m, {
    bool adminClinicalAccess = true,
    String clinicalAccessScope = 'clinic',
  }) {
    final perms = (m.roleId == 'admin' && !adminClinicalAccess)
        ? m.perms.difference(kClinicalPermissions)
        : m.perms;
    return ClinicAccess(
      clinicId: clinicId,
      uid: m.uid,
      roleId: m.roleId,
      roleName: m.roleName,
      kind: m.kind,
      perms: perms,
      modules: m.modules?.toSet(),
      clinicalAccessScope: clinicalAccessScope,
    );
  }

  final String clinicId;
  final String uid;
  final String roleId;
  final String roleName;
  final MemberKind kind;
  final Set<ClinicPermission> perms;

  /// This person's own feature choice (module keys); null = no personal limit.
  final Set<String>? modules;

  /// `'clinic'` (the default) or `'assigned'`; see [Clinic].
  final String clinicalAccessScope;

  bool get isOwner => uid == clinicId;
  bool get isAdmin => isOwner || roleId == 'admin';

  /// Whether this person only reaches the patients assigned to them.
  ///
  /// Applies to doctors in a clinic that asked for it. The front desk is
  /// never scoped — it needs the whole appointment book — and neither is the
  /// owner. Mirrors `callerIsScopedDoctor` in firestore.rules; when true, a
  /// patient query has to narrow to
  /// `assignedDoctorUids array-contains uid` or the rules refuse it.
  bool get scopedToAssignedPatients =>
      clinicalAccessScope == 'assigned' &&
      !isOwner &&
      kind == MemberKind.doctor;

  /// Whether this person holds [p].
  ///
  /// There is deliberately no admin shortcut: [perms] already holds
  /// everything an admin is entitled to (an owner holds all of them), so a
  /// shortcut would hand back clinical access a clinic has withdrawn.
  bool can(ClinicPermission p) => perms.contains(p);

  /// Whether a shell module (DoctorFeatureGuard keys) is open to this person.
  bool allowsModule(String moduleKey) {
    final allowedByRole = switch (moduleKey) {
      'dashboard' || 'multi_device_access' => true,
      'patients' => can(ClinicPermission.patientsView),
      'inventory' => can(ClinicPermission.inventory),
      'revenue' =>
        can(ClinicPermission.billing) || can(ClinicPermission.revenue),
      'appointments' ||
      'queue' ||
      'home_visits' => can(ClinicPermission.schedule),
      'omnichannel_messaging' => can(ClinicPermission.messaging),
      'campaigns' => isOwner,
      'ai_assistant' || 'ai_agentic_calling' => can(ClinicPermission.ai),
      _ => isAdmin,
    };

    if (!allowedByRole) return false;

    if (modules != null &&
        moduleKey != 'dashboard' &&
        moduleKey != 'multi_device_access') {
      return modules!.contains(moduleKey);
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
    'clinicId': clinicId,
    'uid': uid,
    'roleId': roleId,
    'roleName': roleName,
    'kind': kind.value,
    'perms': perms.map((p) => p.key).toList(),
    if (modules != null) 'modules': modules!.toList(),
    'clinicalAccessScope': clinicalAccessScope,
  };

  factory ClinicAccess.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['perms'];
    final permsSet = <ClinicPermission>{};
    if (rawPerms is Iterable) {
      for (final p in rawPerms) {
        final cp = ClinicPermission.fromKey(p.toString());
        if (cp != null) permsSet.add(cp);
      }
    }
    Set<String>? modulesSet;
    if (json.containsKey('modules') && json['modules'] is Iterable) {
      modulesSet = (json['modules'] as Iterable)
          .map((e) => e.toString())
          .toSet();
    }
    return ClinicAccess(
      clinicId: json['clinicId'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      roleId: json['roleId'] as String? ?? '',
      roleName: json['roleName'] as String? ?? '',
      kind: MemberKind.fromString(json['kind'] as String?),
      perms: normalizePermissions(permsSet.map((p) => p.key)),
      modules: modulesSet,
      clinicalAccessScope: json['clinicalAccessScope'] == 'assigned'
          ? 'assigned'
          : 'clinic',
    );
  }
}
