import 'package:cloud_functions/cloud_functions.dart';

import 'clinic_models.dart';
import 'clinic_permission.dart';

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
  Future<String> ensureClinic({
    required String clinicName,
    required String ownerName,
    required String specialty,
  }) async {
    final data = await _call('ensureClinic', {
      'clinicName': clinicName,
      'ownerName': ownerName,
      'specialty': specialty,
    });
    return data['clinicId'] as String;
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

  /// Invites someone by [phone] or [email] (exactly one). [modules] null
  /// means no personal limit.
  Future<String> invite({
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
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      'kind': kind.value,
      'roleId': roleId,
      if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
      if (modules != null) 'modules': modules,
      if (dentalFeatures != null) 'dentalFeatures': dentalFeatures,
    });
    return data['inviteId'] as String;
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
    if (roleId != null) 'roleId': roleId,
    if (kind != null) 'kind': kind.value,
    if (specialty != null) 'specialty': specialty,
    if (clearModules)
      'modules': null
    else if (modules != null)
      'modules': modules,
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
      if (roleId != null) 'roleId': roleId,
      'name': name,
      'kind': kind.value,
      'perms': [for (final p in perms) p.key],
    });
    return data['roleId'] as String;
  }

  Future<void> deleteRole({required String clinicId, required String roleId}) =>
      _call('deleteRole', {'clinicId': clinicId, 'roleId': roleId});

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
