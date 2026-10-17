import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/demo_session_service.dart';

import 'clinic_access.dart';
import 'clinic_models.dart';
import 'clinic_permission.dart';

/// Which clinic the signed-in person works in and what they may do there.
///
/// [tenantId] is the value stamped into every record's `doctorId` field and
/// used in `doctors/{id}/` storage paths. For a clinic owner, or a doctor
/// working alone, it equals their own uid.
class ClinicSession {
  ClinicSession._();
  static final ClinicSession instance = ClinicSession._();

  ClinicAccess? _access;
  ClinicMember? _member;
  String? _previousClinicId;
  String? _lastLoadedUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _memberSubscription;

  final StreamController<ClinicAccess?> _streamController =
      StreamController<ClinicAccess?>.broadcast();
  final StreamController<void> _removedController =
      StreamController<void>.broadcast();

  ClinicAccess? get access => _access;
  ClinicMember? get member =>
      _member; // last loaded member doc; null for a solo owner
  Stream<ClinicAccess?> get stream =>
      _streamController.stream; // emits on load, role change, removal, clear

  /// Tenant for data. Falls back to the signed-in uid (solo doctor).
  String? get tenantId {
    final fromAccess = access?.clinicId;
    if (fromAccess != null && fromAccess.isNotEmpty) return fromAccess;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void setAccessForTesting(ClinicAccess? access) {
    _access = access;
  }

  /// Emits once when the member doc goes inactive or disappears.
  Stream<void> get removed => _removedController.stream;

  /// The cached `clinic.activeId.<uid>` from before the last [load], when it
  /// differs from the clinic just loaded (used by T21 to clean up).
  String? get previousClinicId => _previousClinicId;

  /// 1. users/{uid}.clinicId (missing/empty → uid).
  /// 2. clinicId == uid → ClinicAccess.owner(uid).
  ///    Else read clinics/{clinicId}/members/{uid}: active → fromMember;
  ///    missing or inactive → ClinicAccess.owner(uid) and emit removed.
  /// 3. Cache clinicId and access.toJson() in SharedPreferences
  ///    (`clinic.activeId.<uid>`, `clinic.access.<uid>`). If Firestore is
  ///    unreachable, use the cache; no cache → owner(uid).
  /// 4. Keep a snapshot listener on the member doc (non-owners) and re-emit
  ///    when perms/role/active change.
  Future<ClinicAccess> load(String uid) async {
    _lastLoadedUid = uid;
    await _memberSubscription?.cancel();
    _memberSubscription = null;

    final prefs = await SharedPreferences.getInstance();
    final cachedActiveBefore = prefs.getString('clinic.activeId.$uid');
    // Whether this person, as owner, may open medical records. Read from the
    // token (no Firestore read), so a solo doctor's start-up is unchanged.
    final ownerClinical = !await _carriesNonClinicalOwnerClaim();

    try {
      // 1. users/{uid}.clinicId (missing/empty → uid).
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final userData = userSnap.data();
      final rawClinicId = userData?['clinicId'] as String?;
      final clinicId = (rawClinicId != null && rawClinicId.trim().isNotEmpty)
          ? rawClinicId.trim()
          : uid;

      // 2. clinicId == uid → ClinicAccess.owner(uid).
      if (clinicId == uid) {
        _member = null;
        final access = ClinicAccess.owner(uid, clinical: ownerClinical);
        _access = access;

        _setPreviousClinicId(cachedActiveBefore, clinicId);
        await _saveCache(prefs, uid, clinicId, access);

        _streamController.add(access);
        return access;
      }

      // Else read clinics/{clinicId}/members/{uid}
      final memberSnap = await FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('members')
          .doc(uid)
          .get();

      if (!memberSnap.exists || memberSnap.data() == null) {
        _member = null;
        final access = ClinicAccess.owner(uid);
        _access = access;

        _setPreviousClinicId(cachedActiveBefore, uid);
        await _saveCache(prefs, uid, uid, access);

        _streamController.add(access);
        _removedController.add(null);
        return access;
      }

      final memberData = memberSnap.data()!;
      final member = ClinicMember.fromMap(uid, memberData);

      if (!member.active) {
        _member = null;
        final access = ClinicAccess.owner(uid);
        _access = access;

        _setPreviousClinicId(cachedActiveBefore, uid);
        await _saveCache(prefs, uid, uid, access);

        _streamController.add(access);
        _removedController.add(null);
        return access;
      }

      // active → fromMember
      _member = member;
      final settings = await _readClinicSettings(clinicId);
      final access = ClinicAccess.fromMember(
        clinicId,
        member,
        adminClinicalAccess: settings.adminClinicalAccess,
        clinicalAccessScope: settings.clinicalAccessScope,
      );
      _access = access;

      _setPreviousClinicId(cachedActiveBefore, clinicId);
      await _saveCache(prefs, uid, clinicId, access);

      _streamController.add(access);

      // 4. Keep a snapshot listener on the member doc (non-owners) and re-emit
      //    when perms/role/active change.
      _listenToMemberDoc(clinicId, uid);

      return access;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        return _loadFromCache(prefs, uid, cachedActiveBefore, ownerClinical);
      }
      // The rules hide a member doc once it is inactive or gone, so a
      // denied read means this person was removed from the clinic. Falling
      // back to the cache here would hand them their old role.
      _member = null;
      final access = ClinicAccess.owner(uid);
      _access = access;
      _setPreviousClinicId(cachedActiveBefore, uid);
      await _saveCache(prefs, uid, uid, access);
      _streamController.add(access);
      _removedController.add(null);
      return access;
    } catch (_) {
      return _loadFromCache(prefs, uid, cachedActiveBefore, ownerClinical);
    }
  }

  /// 3. Firestore unreachable: use the cache; no cache → owner(uid).
  ClinicAccess _loadFromCache(
    SharedPreferences prefs,
    String uid,
    String? cachedActiveBefore, [
    bool ownerClinical = true,
  ]) {
    final cachedJsonStr = prefs.getString('clinic.access.$uid');
    if (cachedJsonStr != null) {
      try {
        final decoded = jsonDecode(cachedJsonStr) as Map<String, dynamic>;
        final access = ClinicAccess.fromJson(decoded);
        _access = access;
        _member = null;
        _setPreviousClinicId(cachedActiveBefore, access.clinicId);
        _streamController.add(access);
        return access;
      } catch (_) {}
    }

    final fallback = ClinicAccess.owner(uid, clinical: ownerClinical);
    _access = fallback;
    _member = null;
    _setPreviousClinicId(cachedActiveBefore, uid);
    _streamController.add(fallback);
    return fallback;
  }

  /// The nonClinicalOwner claim ensureClinic puts on a manager who owns the
  /// clinic. Uses the cached token, so it works offline; anything unreadable
  /// counts as no claim, the same as every solo doctor.
  Future<bool> _carriesNonClinicalOwnerClaim() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      return token?.claims?['nonClinicalOwner'] == true;
    } catch (_) {
      return false;
    }
  }

  /// The two clinic-level access settings, read in one fetch.
  ///
  /// An absent `adminClinicalAccess` or an unreachable clinic reads as
  /// `true`, the same permissive default the rules use for a clinic whose
  /// backfill has not run; an absent scope reads as `'clinic'`, which is
  /// what every clinic did before the setting existed.
  Future<({bool adminClinicalAccess, String clinicalAccessScope})>
  _readClinicSettings(String clinicId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .get();
      final data = snap.data();
      return (
        adminClinicalAccess: data?['adminClinicalAccess'] != false,
        clinicalAccessScope: data?['clinicalAccessScope'] == 'assigned'
            ? 'assigned'
            : 'clinic',
      );
    } catch (_) {
      return (adminClinicalAccess: true, clinicalAccessScope: 'clinic');
    }
  }

  void _listenToMemberDoc(String clinicId, String uid) {
    _memberSubscription = FirebaseFirestore.instance
        .collection('clinics')
        .doc(clinicId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) async {
            if (!snap.exists || snap.data() == null) {
              _member = null;
              final fallback = ClinicAccess.owner(uid);
              _access = fallback;
              _streamController.add(fallback);
              _removedController.add(null);
              return;
            }

            final m = ClinicMember.fromMap(uid, snap.data()!);
            if (!m.active) {
              _member = null;
              final fallback = ClinicAccess.owner(uid);
              _access = fallback;
              _streamController.add(fallback);
              _removedController.add(null);
              return;
            }

            _member = m;
            final s = await _readClinicSettings(clinicId);
            final newAccess = ClinicAccess.fromMember(
              clinicId,
              m,
              adminClinicalAccess: s.adminClinicalAccess,
              clinicalAccessScope: s.clinicalAccessScope,
            );
            _access = newAccess;
            _streamController.add(newAccess);
          },
          onError: (_) {
            _removedController.add(null);
          },
        );
  }

  void _setPreviousClinicId(String? cachedBefore, String loadedClinicId) {
    if (cachedBefore != null &&
        cachedBefore.isNotEmpty &&
        cachedBefore != loadedClinicId) {
      _previousClinicId = cachedBefore;
    } else {
      _previousClinicId = null;
    }
  }

  Future<void> _saveCache(
    SharedPreferences prefs,
    String uid,
    String clinicId,
    ClinicAccess access,
  ) async {
    await prefs.setString('clinic.activeId.$uid', clinicId);
    await prefs.setString('clinic.access.$uid', jsonEncode(access.toJson()));
  }

  /// Re-runs [load] for the current user (after joining a clinic).
  Future<ClinicAccess?> reload() async {
    final uid = _lastLoadedUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return load(uid);
  }

  void clear() {
    _memberSubscription?.cancel();
    _memberSubscription = null;
    _access = null;
    _member = null;
    _previousClinicId = null;
    _lastLoadedUid = null;
    _streamController.add(null);
  }
}

final clinicAccessProvider = StreamProvider<ClinicAccess?>((ref) async* {
  yield ClinicSession.instance.access;
  yield* ClinicSession.instance.stream;
});

/// clinics/{tenantId} as a [Clinic]; null when the doc doesn't exist (solo).
final activeClinicProvider = StreamProvider<Clinic?>((ref) {
  final access = ref.watch(clinicAccessProvider).value;
  final tenantId = access?.clinicId ?? ClinicSession.instance.tenantId;
  if (tenantId == null) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('clinics')
      .doc(tenantId)
      .snapshots()
      .map((snap) {
        if (!snap.exists || snap.data() == null) {
          return null;
        }
        return Clinic.fromMap(snap.id, snap.data()!);
      });
});

/// Whether the signed-in person may do [ClinicPermission] in their clinic.
/// Always true for an owner or a doctor working alone (their access grants
/// every permission).
///
/// Denies while no clinic access has resolved. [ResponsiveShell] holds the
/// app on a loading screen until it has, so the only case that reaches here
/// is the demo session, which has no clinic of its own and is allowed
/// everything. Defaulting to allow instead would briefly offer actions the
/// person may not have, and in a medical app the wrong default is the
/// permissive one.
final clinicCanProvider = Provider.family<bool, ClinicPermission>((ref, p) {
  final access = ref.watch(clinicAccessProvider).value;
  if (access != null) return access.can(p);
  return DemoSessionService.isDemoMode;
});
