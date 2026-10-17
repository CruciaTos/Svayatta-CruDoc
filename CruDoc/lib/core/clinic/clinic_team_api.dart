import 'package:cloud_functions/cloud_functions.dart';

import 'clinic_models.dart';
import 'clinic_permission.dart';

/// What happened when the admin added someone with [ClinicTeamApi.createMember].
enum CreateMemberResult {
  /// Their account was created; they can sign in.
  created,

  /// That phone or email already has a CruDoc account. Nothing was changed;
  /// invite them instead, and they join when they next sign in.
  alreadyHasAccount,
}

/// What [ClinicTeamApi.invite] did.
class InviteResult {
  const InviteResult({required this.inviteId, required this.onCruDoc});

  final String inviteId;

  /// That number belongs to a CruDoc account that can be found: the person
  /// sees the invite in the app. Otherwise the admin sends the invite
  /// message themselves.
  final bool onCruDoc;
}

/// What CruDoc knows about one of the admin's phone contacts.
enum ContactMatchStatus {
  /// Already in this clinic.
  member,

  /// Has a pending invite to this clinic.
  invited,

  /// On CruDoc and can be invited in the app.
  available;

  static ContactMatchStatus? fromString(String? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}

/// How many numbers one `matchContacts` call may carry (the server's limit).
const int kMatchContactsPerCall = 1000;

/// A clinic team action the server refused, with a message to show.
class ClinicTeamException implements Exception {
  const ClinicTeamException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The `clinicTeam` Cloud Function (functions/src/clinic.ts): one callable,
/// one method per action. Every method throws [ClinicTeamException].
class ClinicTeamApi {
  ClinicTeamApi({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  static final ClinicTeamApi instance = ClinicTeamApi();

  final FirebaseFunctions _functions;

  /// Creates the signed-in owner's clinic (once) and returns its id.
  ///
  /// [ownerIsDoctor] false sets the clinic up for a manager who runs it but
  /// does not treat patients: they never open medical records. It only
  /// counts when the clinic is first created; an existing clinic keeps how it
  /// was set up.
  Future<String> ensureClinic({
    required String clinicName,
    required String ownerName,
    required String specialty,
    bool ownerIsDoctor = true,
  }) async {
    final data = await _call('ensureClinic', {
      'clinicName': clinicName,
      'ownerName': ownerName,
      'specialty': specialty,
      'ownerIsDoctor': ownerIsDoctor,
    });
    return data['clinicId'] as String;
  }

  /// Creates a login for a new member of the clinic, rather than inviting
  /// them to make one. Exactly one of [phone] or [email].
  ///
  /// Returns [CreateMemberResult.created] once the account exists, or
  /// [CreateMemberResult.alreadyHasAccount] when that phone or email already
  /// belongs to someone — they are left untouched, and the caller should
  /// invite them instead. Throws [ClinicTeamException].
  Future<CreateMemberResult> createMember({
    required String clinicId,
    required String name,
    String? phone,
    String? email,
    required MemberKind kind,
    required String roleId,
    String? specialty,
    List<String>? modules,
    List<String>? dentalFeatures,
  }) async {
    final data = await _call('createMember', {
      'clinicId': clinicId,
      'name': name,
      'phone': ?phone,
      'email': ?email,
      'kind': kind.value,
      'roleId': roleId,
      if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
      'modules': ?modules,
      'dentalFeatures': ?dentalFeatures,
    });
    return data['mode'] == 'exists'
        ? CreateMemberResult.alreadyHasAccount
        : CreateMemberResult.created;
  }

  /// Invites waiting for the signed-in phone number or verified email.
  Future<List<ClinicInvite>> myInvites() async {
    final data = await _call('myInvites');
    final raw = data['invites'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          ClinicInvite.fromMap(
            '${item['id']}',
            Map<String, dynamic>.from(item),
          ),
    ];
  }

  /// Joins [clinicId] through [inviteId]; returns the clinic id.
  Future<String> acceptInvite({
    required String clinicId,
    required String inviteId,
  }) async {
    final data = await _call('acceptInvite', {
      'clinicId': clinicId,
      'inviteId': inviteId,
    });
    return data['clinicId'] as String? ?? clinicId;
  }

  /// Turns down an invite; the clinic sees it as declined.
  Future<void> declineInvite({
    required String clinicId,
    required String inviteId,
  }) => _call('declineInvite', {'clinicId': clinicId, 'inviteId': inviteId});

  /// Invites someone by [phone] or [email] (exactly one). [modules] null
  /// means no personal limit.
  Future<InviteResult> invite({
    required String clinicId,
    required String name,
    String? phone,
    String? email,
    required MemberKind kind,
    required String roleId,
    String? specialty,
    List<String>? modules,
    List<String>? dentalFeatures,
  }) async {
    final data = await _call('invite', {
      'clinicId': clinicId,
      'name': name,
      'phone': ?phone,
      'email': ?email,
      'kind': kind.value,
      'roleId': roleId,
      if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
      'modules': ?modules,
      'dentalFeatures': ?dentalFeatures,
    });
    return InviteResult(
      inviteId: data['inviteId'] as String,
      onCruDoc: data['onCruDoc'] == true,
    );
  }

  /// Which of [phones] (as read from the admin's contacts) are on CruDoc,
  /// keyed by the number exactly as sent. Numbers not on CruDoc, or whose
  /// owners turned off being found, are left out. Sent in chunks of
  /// [kMatchContactsPerCall]; the server stores none of them.
  Future<Map<String, ContactMatchStatus>> matchContacts({
    required String clinicId,
    required List<String> phones,
  }) async {
    final out = <String, ContactMatchStatus>{};
    for (var i = 0; i < phones.length; i += kMatchContactsPerCall) {
      final end = i + kMatchContactsPerCall < phones.length
          ? i + kMatchContactsPerCall
          : phones.length;
      final data = await _call('matchContacts', {
        'clinicId': clinicId,
        'phones': phones.sublist(i, end),
      });
      final raw = data['matches'];
      if (raw is! List) continue;
      for (final m in raw) {
        if (m is! Map) continue;
        final phone = m['phone'];
        final status = ContactMatchStatus.fromString(m['status'] as String?);
        if (phone is String && status != null) out[phone] = status;
      }
    }
    return out;
  }

  Future<void> cancelInvite({
    required String clinicId,
    required String inviteId,
  }) => _call('cancelInvite', {'clinicId': clinicId, 'inviteId': inviteId});

  /// Changes another member. Leave a field out to keep it; pass
  /// [clearModules] to remove their personal feature limit.
  Future<void> updateMember({
    required String clinicId,
    required String uid,
    String? roleId,
    MemberKind? kind,
    String? specialty,
    List<String>? modules,
    bool clearModules = false,
  }) => _call('updateMember', {
    'clinicId': clinicId,
    'uid': uid,
    'roleId': ?roleId,
    if (kind != null) 'kind': kind.value,
    'specialty': ?specialty,
    if (clearModules)
      'modules': null
    else
      'modules': ?modules,
  });

  /// Removes [uid] from the clinic and signs them out everywhere.
  Future<void> removeMember({required String clinicId, required String uid}) =>
      _call('removeMember', {'clinicId': clinicId, 'uid': uid});

  /// Creates ([roleId] null) or edits a role; returns its id.
  Future<String> saveRole({
    required String clinicId,
    String? roleId,
    required String name,
    required MemberKind kind,
    required Set<ClinicPermission> perms,
  }) async {
    final data = await _call('saveRole', {
      'clinicId': clinicId,
      'roleId': ?roleId,
      'name': name,
      'kind': kind.value,
      'perms': [for (final p in perms) p.key],
    });
    return data['roleId'] as String;
  }

  Future<void> deleteRole({required String clinicId, required String roleId}) =>
      _call('deleteRole', {'clinicId': clinicId, 'roleId': roleId});

  /// Turns clinical-record access for this clinic's admins on or off.
  /// Refused for anyone but the clinic owner, and audited either way.
  Future<void> setAdminClinicalAccess({
    required String clinicId,
    required bool enabled,
  }) => _call('setAdminClinicalAccess', {
    'clinicId': clinicId,
    'enabled': enabled,
  });

  /// Whether doctors see every patient (`'clinic'`) or only the ones assigned
  /// to them (`'assigned'`). Owner only, and audited.
  Future<void> setClinicalAccessScope({
    required String clinicId,
    required String scope,
  }) => _call('setClinicalAccessScope', {
    'clinicId': clinicId,
    'scope': scope,
  });

  /// Sets which doctors treat [patientId]. An empty list means nobody in
  /// particular, which leaves the patient readable by every doctor.
  /// Needs `patients.edit`, so the front desk can do it.
  Future<List<String>> assignPatient({
    required String clinicId,
    required String patientId,
    required List<String> doctorUids,
  }) async {
    final data = await _call('assignPatient', {
      'clinicId': clinicId,
      'patientId': patientId,
      'doctorUids': doctorUids,
    });
    final raw = data['assignedDoctorUids'];
    return raw is List ? raw.map((e) => e.toString()).toList() : doctorUids;
  }

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      final result = await _functions.httpsCallable('clinicTeam').call<dynamic>(
        {'action': action, ...data},
      );
      final raw = result.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw ClinicTeamException(_messageFor(e));
    } catch (_) {
      throw const ClinicTeamException("Couldn't reach CruDoc. Try again.");
    }
  }

  static String _messageFor(FirebaseFunctionsException e) => switch (e.code) {
    'resource-exhausted' ||
    'already-exists' ||
    'failed-precondition' ||
    'invalid-argument' ||
    'not-found' => e.message ?? "That didn't work. Try again.",
    'permission-denied' => "You don't have permission to do that.",
    'unauthenticated' => 'Sign in again to continue.',
    _ => "Couldn't reach CruDoc. Try again.",
  };
}
