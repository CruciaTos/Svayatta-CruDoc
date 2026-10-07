import 'clinic_models.dart';
import 'clinic_permission.dart';

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
  });

  /// A doctor working alone, or before a clinic exists: owner of their own data.
  factory ClinicAccess.owner(String uid) {
    return ClinicAccess(
      clinicId: uid,
      uid: uid,
      roleId: 'admin',
      roleName: 'Owner',
      kind: MemberKind.doctor,
      perms: ClinicPermission.values.toSet(),
      modules: null,
    );
  }

  factory ClinicAccess.fromMember(String clinicId, ClinicMember m) {
    return ClinicAccess(
      clinicId: clinicId,
      uid: m.uid,
      roleId: m.roleId,
      roleName: m.roleName,
      kind: m.kind,
      perms: m.perms,
      modules: m.modules?.toSet(),
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

  bool get isOwner => uid == clinicId;
  bool get isAdmin => isOwner || roleId == 'admin';
  bool can(ClinicPermission p) => isAdmin || perms.contains(p);

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
    );
  }
}
