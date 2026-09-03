import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

// ────────────────── Selected specialty on the auth screen ──────────────────

/// Tracks which specialty the user has selected on the auth / onboarding screen.
/// This is a *pre-login* selection used for theming, demo fillers, etc.
class AuthSpecialtyNotifier extends Notifier<DoctorSpecialty> {
  @override
  DoctorSpecialty build() => DoctorSpecialty.defaultSpecialty;

  void select(DoctorSpecialty spec) => state = spec;
  void selectByType(DoctorSpecialtyType type) {
    state = DoctorSpecialty.all.firstWhere((s) => s.type == type,
        orElse: () => DoctorSpecialty.defaultSpecialty);
  }
}

final authSpecialtyProvider =
    NotifierProvider<AuthSpecialtyNotifier, DoctorSpecialty>(
  AuthSpecialtyNotifier.new,
);

// ────────────────── Active specialty (post-login) ──────────────────

/// Streams the logged-in doctor's specialty from Firestore, resolved via
/// [DoctorSpecialty.fromString] for full metadata access.
final activeDoctorSpecialtyProvider = StreamProvider<DoctorSpecialty>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(DoctorSpecialty.defaultSpecialty);

  return DoctorProfileHelper.watchDoctorProfile(user).map((data) {
    final rawSpecialty = DoctorProfileHelper.formatSpecialty(data, user);
    return DoctorSpecialty.fromString(rawSpecialty);
  });
});

// ────────────────── Save specialty to Firestore ──────────────────

/// Persists a selected specialty to the user's Firestore profile.
/// Call this during onboarding or when the doctor changes their specialty.
Future<void> saveDoctorSpecialty(DoctorSpecialty spec, {User? user}) async {
  final currentUser = user ?? FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  final docRef =
      FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

  await docRef.set({
    'specialty': spec.label,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
