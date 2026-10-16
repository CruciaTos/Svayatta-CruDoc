import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

/// How many more times the doctor may change their name right now, and
/// when the next change opens once none are left.
class NameChangeAllowance {
  const NameChangeAllowance({required this.left, this.nextAt});

  final int left;

  /// Null while [left] > 0.
  final DateTime? nextAt;

  bool get allowed => left > 0;
}

/// Thrown when a change would go past [DoctorNameChangePolicy.maxChanges].
class NameChangeLimitException implements Exception {
  const NameChangeLimitException(this.nextAt);

  final DateTime nextAt;
}

/// A doctor's name can change at most twice in any 6 months: it is on
/// prescriptions, bills and the loyalty card. Change times are kept on
/// `users/{uid}.nameChanges`. Setting a first name, or saving the same
/// name, is not a change.
abstract final class DoctorNameChangePolicy {
  static const int maxChanges = 2;
  static const Duration window = Duration(days: 183);

  /// The change times stored on the profile, oldest first.
  static List<DateTime> changesOf(Map<String, dynamic>? profile) {
    final raw = profile?['nameChanges'];
    if (raw is! List) return const [];
    return [
      for (final v in raw)
        if (v is Timestamp)
          v.toDate()
        else if (v is DateTime)
          v
        else if (v is String && DateTime.tryParse(v) != null)
          DateTime.parse(v),
    ]..sort();
  }

  static NameChangeAllowance allowance(List<DateTime> changes, DateTime now) {
    final recent = [
      for (final c in changes)
        if (now.difference(c) < window) c,
    ]..sort();
    final left = math.max(0, maxChanges - recent.length);
    return NameChangeAllowance(
      left: left,
      // The oldest change in the window drops out first.
      nextAt: left > 0 ? null : recent.first.add(window),
    );
  }

  /// Saves [name], counting it against the limit when it replaces another
  /// name. Throws [NameChangeLimitException] when none are left.
  static Future<void> save({
    required String name,
    required Map<String, dynamic>? profile,
    User? user,
  }) async {
    final current = user ?? FirebaseAuth.instance.currentUser;
    if (current == null) return;
    final trimmed = name.trim();
    final previous = DoctorProfileHelper.tryFormatDoctorName(current, profile);
    if (previous?.trim() == trimmed) return;
    final counts = previous != null && previous.trim().isNotEmpty;
    final now = DateTime.now();
    final changes = changesOf(profile);
    if (counts) {
      final allowed = allowance(changes, now);
      if (!allowed.allowed) throw NameChangeLimitException(allowed.nextAt!);
    }
    await DoctorProfileHelper.updateProfile(
      doctorName: trimmed,
      specialty: DoctorProfileHelper.formatSpecialty(profile, current),
      user: current,
    );
    if (!counts) return;
    final kept = [...changes, now];
    await FirebaseFirestore.instance.collection('users').doc(current.uid).set({
      'nameChanges': [
        for (final c in kept.skip(math.max(0, kept.length - 4)))
          Timestamp.fromDate(c),
      ],
    }, SetOptions(merge: true));
  }
}
