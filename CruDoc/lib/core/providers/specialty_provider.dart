import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/doctor_encryption_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';

// ────────────────── Selected specialty on the auth screen ──────────────────

/// Tracks which specialty the user has selected on the auth / onboarding screen.
/// This is a *pre-login* selection used for theming, demo fillers, etc.
class AuthSpecialtyNotifier extends Notifier<DoctorSpecialty> {
  @override
  DoctorSpecialty build() => DoctorSpecialty.defaultSpecialty;

  void select(DoctorSpecialty spec) => state = spec;
  void selectByType(DoctorSpecialtyType type) {
    state = DoctorSpecialty.ofType(type);
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
  if (user == null && !DemoSessionService.isDemoMode) {
    return Stream.value(DoctorSpecialty.defaultSpecialty);
  }

  // Staff have no specialty of their own: they see the clinic's.
  final clinicSpecialty = ref.watch(activeClinicProvider).value?.specialty;
  return DoctorProfileHelper.watchDoctorProfile(user).map((data) {
    final own = (data?['specialty'] ?? data?['specialization']) as String?;
    if ((own == null || own.trim().isEmpty) &&
        clinicSpecialty != null &&
        clinicSpecialty.isNotEmpty) {
      return DoctorSpecialty.fromString(clinicSpecialty);
    }
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

  final docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(currentUser.uid);

  final encryptedSpec = DoctorEncryptionService.encryptForDoctor(
    spec.label,
    currentUser.uid,
  );

  await docRef.set({
    'specialty': spec.label,
    'specialization': encryptedSpec,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Instant real-time specialty switch helper for development & demo accounts.
/// Persists the change to Firestore, updates providers, and displays an animated confirmation snackbar.
Future<void> switchDoctorSpecialty(
  BuildContext context,
  DoctorSpecialty newSpecialty, {
  WidgetRef? ref,
  bool showFeedback = true,
}) async {
  try {
    if (DemoSessionService.isDemoMode) {
      DemoSessionService.setSpecialty(newSpecialty);
    }
    try {
      await saveDoctorSpecialty(newSpecialty);
    } catch (_) {}

    if (ref != null) {
      ref.read(authSpecialtyProvider.notifier).select(newSpecialty);
      ref.invalidate(activeDoctorSpecialtyProvider);
    }

    if (showFeedback && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: newSpecialty.accentColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(newSpecialty.icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Specialty switched to ${newSpecialty.label}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      newSpecialty.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: newSpecialty.accentColor.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
        ),
      );
    }
  } catch (e) {
    debugPrint('Failed to switch specialty: $e');
    if (context.mounted && showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch specialty: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }
}

/// Physiotherapists hold several sessions at once (the queue lets more
/// than one patient be in a session) and see patients at home (the
/// Schedule's Visits view and home booking).
final isPhysiotherapyProvider = Provider<bool>(
  (ref) =>
      ref.watch(activeDoctorSpecialtyProvider).value?.type ==
      DoctorSpecialtyType.physiotherapy,
);

/// The signed-in doctor is a dentist (any dental features).
final isDentalProvider = Provider<bool>((ref) {
  final s = ref.watch(activeDoctorSpecialtyProvider).value;
  return s?.type == DoctorSpecialtyType.dentist;
});

/// This dentist's features: `users/{uid}.dentalFeatures`, or the legacy
/// mapping from their stored specialty, or the defaults. Empty for
/// non-dentists.
final dentalFeaturesProvider = Provider<Set<DentalFeature>>((ref) {
  final isDental = ref.watch(isDentalProvider);
  if (!isDental) return const {};
  if (!ref.watch(clinicCanProvider(ClinicPermission.clinicalView))) {
    return const {};
  }

  final profile = ref.watch(doctorProfileProvider).value;
  final rawFeatures = profile?['dentalFeatures'];
  final parsed = DentalFeature.parse(rawFeatures);
  if (parsed != null && parsed.isNotEmpty) {
    return parsed;
  }
  final rawSpecialty = profile?['specialty'] as String?;
  return DentalFeature.fromLegacySpecialty(rawSpecialty);
});

/// Saves the dentist's features to their own profile.
Future<void> saveDentalFeatures(Set<DentalFeature> features) async {
  if (DemoSessionService.isDemoMode) {
    DemoSessionService.setDentalFeatures(features);
    return;
  }

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  final docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(currentUser.uid);

  await docRef.set({
    'dentalFeatures': [for (final f in features) f.key],
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// The signed-in doctor is a dentist who does chairside dentistry.
final isDentistProvider = Provider<bool>((ref) {
  final isDental = ref.watch(isDentalProvider);
  if (!isDental) return false;
  final features = ref.watch(dentalFeaturesProvider);
  return features.contains(DentalFeature.chairside);
});

/// The signed-in doctor is a dentist who has dental radiology enabled.
final hasDentalRadiologyProvider = Provider<bool>((ref) {
  final isDental = ref.watch(isDentalProvider);
  if (!isDental) return false;
  final features = ref.watch(dentalFeaturesProvider);
  return features.contains(DentalFeature.radiology);
});
