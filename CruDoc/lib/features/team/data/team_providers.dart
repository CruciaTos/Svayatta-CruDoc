import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';

DocumentReference<Map<String, dynamic>> _clinic(String id) =>
    FirebaseFirestore.instance.collection('clinics').doc(id);

/// Everyone in the active clinic, removed members included (screens filter
/// on [ClinicMember.active]). Owner first, then by name.
final clinicMembersProvider = StreamProvider<List<ClinicMember>>((ref) {
  final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
  if (clinicId == null) return Stream.value(const []);
  return _clinic(clinicId).collection('members').snapshots().map((snap) {
    final members = [
      for (final d in snap.docs) ClinicMember.fromMap(d.id, d.data()),
    ];
    members.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return members;
  });
});

/// The active clinic's roles: Admin first, then by name.
final clinicRolesProvider = StreamProvider<List<ClinicRole>>((ref) {
  final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
  if (clinicId == null) return Stream.value(const []);
  return _clinic(clinicId).collection('roles').snapshots().map((snap) {
    final roles = [
      for (final d in snap.docs) ClinicRole.fromMap(d.id, d.data()),
    ];
    roles.sort((a, b) {
      if ((a.id == 'admin') != (b.id == 'admin'))
        return a.id == 'admin' ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return roles;
  });
});

/// Invites still waiting to be accepted (needs the `team` permission).
final clinicInvitesProvider = StreamProvider<List<ClinicInvite>>((ref) {
  final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
  if (clinicId == null) return Stream.value(const []);
  return _clinic(clinicId)
      .collection('invites')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snap) {
        final now = DateTime.now();
        return [
          for (final d in snap.docs)
            if (ClinicInvite.fromMap(d.id, d.data()) case final invite
                when invite.expiresAt == null || invite.expiresAt!.isAfter(now))
              invite,
        ];
      });
});

/// Features a person can be given, in the order the checklist shows them,
/// with their labels. Dashboard and devices are always on, so not listed.
const Map<String, String> kTeamModuleLabels = {
  'patients': 'Patients',
  'appointments': 'Appointments',
  'queue': 'Walk-in queue',
  'home_visits': 'Home visits',
  'revenue': 'Revenue and invoices',
  'inventory': 'Inventory',
  'omnichannel_messaging': 'WhatsApp and messages',
  'campaigns': 'Campaigns',
  'ai_assistant': 'AI assistant and scribe',
  'ai_agentic_calling': 'AI phone receptionist',
};

/// The features of [clinic]'s plan that [role] allows, for the checklist.
List<String> choosableModules(Clinic? clinic, ClinicRole role) {
  final plan = (clinic?.enabledModules ?? DoctorFeatureGuard.defaultModules)
      .map((m) => m.toLowerCase())
      .toSet();
  final access = accessForRole(role);
  return [
    for (final key in kTeamModuleLabels.keys)
      if (plan.contains(key) && access.allowsModule(key)) key,
  ];
}

/// What someone holding [role] may do (no personal feature limit).
ClinicAccess accessForRole(ClinicRole role) => ClinicAccess(
  clinicId: '',
  uid: '_',
  roleId: role.id,
  roleName: role.name,
  kind: role.kind,
  perms: role.perms,
);

/// Whether [me] may give [role] to someone: the owner and admins may give
/// any; anyone else only roles without admin or team rights whose
/// permissions they all hold (the server checks the same).
bool canGiveRole(ClinicAccess me, ClinicRole role) {
  if (me.isAdmin) return true;
  if (role.id == 'admin' || role.perms.contains(ClinicPermission.team)) {
    return false;
  }
  return role.perms.every(me.perms.contains);
}
