import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';

import 'clinic_models.dart';
import 'clinic_team_api.dart';

/// Where the invite message sends someone who isn't on CruDoc yet.
const kPlayStoreLink =
    'https://play.google.com/store/apps/details?id=com.crudoc.app';

/// How long an invite lasts (the server sets the same).
const int kInviteDays = 7;

/// Invites still open at [now]: pending and not expired, soonest to expire
/// first (those without an expiry last).
List<ClinicInvite> pendingInvites(
  Iterable<ClinicInvite> invites,
  DateTime now,
) {
  final open = [
    for (final i in invites)
      if (i.status == 'pending' &&
          (i.expiresAt == null || i.expiresAt!.isAfter(now)))
        i,
  ];
  open.sort((a, b) {
    final ea = a.expiresAt;
    final eb = b.expiresAt;
    if (ea == null || eb == null) {
      return ea == eb ? 0 : (ea == null ? 1 : -1);
    }
    return ea.compareTo(eb);
  });
  return open;
}

/// The signed-in person's clinic invites (`users/{uid}/clinic_invites`,
/// written only by the server), open ones only.
final clinicInviteInboxProvider = StreamProvider<List<ClinicInvite>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('clinic_invites')
      .snapshots()
      .map(
        (snap) => pendingInvites([
          for (final d in snap.docs) ClinicInvite.fromMap(d.id, d.data()),
        ], DateTime.now()),
      );
});

/// Asks the server to copy invites sent to this account's phone number
/// before the account had it into the inbox. Never throws: the inbox
/// simply stays as it is.
Future<void> refreshClinicInvites() async {
  try {
    await ClinicTeamApi.instance.myInvites();
  } catch (_) {}
}

/// Whether clinics that have this person's number can find them on
/// CruDoc to invite them. On unless they turned it off.
bool isDiscoverable(Map<String, dynamic>? profile) =>
    profile?['discoverable'] != false;

Future<void> setDiscoverable(bool value) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    'discoverable': value,
  }, SetOptions(merge: true));
}

/// Raised while the live Join screen is up, so the invite pop-up doesn't
/// cover the list that already shows the same invites.
final ValueNotifier<int> clinicInvitePopupSuppressors = ValueNotifier(0);

String _laterKey(String uid) => 'clinic_invites.later.$uid';

/// Invites [uid] put off with Later; they stay in Settings → Clinic invites.
Future<Set<String>> snoozedClinicInvites(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return {...?prefs.getStringList(_laterKey(uid))};
  } catch (_) {
    return {};
  }
}

Future<void> snoozeClinicInvite(String uid, String inviteId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final ids = {...?prefs.getStringList(_laterKey(uid)), inviteId};
    await prefs.setStringList(_laterKey(uid), ids.toList());
  } catch (_) {}
}

/// [raw] as E.164, the way the server reads it: ten digits are an Indian
/// mobile number; a leading 0 or 91 is dropped first. Null if it isn't a
/// phone number.
String? invitePhoneE164(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^\+\d{10,15}$').hasMatch(s)) return s;
  final digits = s.startsWith('00') ? s.substring(2) : s;
  if (RegExp(r'^\d{10}$').hasMatch(digits)) return '+91$digits';
  if (RegExp(r'^0\d{10}$').hasMatch(digits)) return '+91${digits.substring(1)}';
  if (RegExp(r'^91\d{10}$').hasMatch(digits)) return '+$digits';
  return null;
}

/// The text to type into the invite form for a contact's number: the ten
/// digits after +91, else the number in E.164 (or as stored).
String invitePhoneForForm(String raw) {
  final e164 = invitePhoneE164(raw);
  if (e164 == null) return raw.trim();
  return e164.startsWith('+91') && e164.length == 13
      ? e164.substring(3)
      : e164;
}

/// The message an admin sends someone who isn't on CruDoc yet. Signing up
/// with [phone] is what finds the invite: there is no link or code.
String buildInviteMessage({
  required String inviteeName,
  required String inviterName,
  required String clinicName,
  required String phone,
  String storeLink = kPlayStoreLink,
}) {
  final hi = inviteeName.trim().isEmpty ? 'Hi' : 'Hi ${inviteeName.trim()}';
  final inviter = inviterName.trim().isEmpty
      ? 'Your clinic'
      : inviterName.trim();
  final clinic = clinicName.trim().isEmpty ? 'clinic' : clinicName.trim();
  return '$hi, $inviter has invited you to join the $clinic team on CruDoc.\n'
      '\n'
      '1. Download CruDoc: $storeLink\n'
      '2. Sign up with this number: $phone\n'
      '3. Your invite will be waiting. Tap Join clinic.\n'
      '\n'
      'This invite expires in $kInviteDays days.';
}
