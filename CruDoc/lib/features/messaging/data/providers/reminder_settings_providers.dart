import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';

/// The one setting a clinic has for WhatsApp appointment reminders.
///
/// Reminders are on unless a clinic turns them off. There is no switch to turn
/// them on, no per-appointment choice and no button to press: CruDoc sends one
/// reminder the evening before, and the doctor does nothing.
///
/// The server reads the same field when it sweeps tomorrow's appointments, so
/// this switch is the whole of the clinic-side control.

/// The field on `users/{uid}`. Absent means on, so an existing clinic starts
/// receiving reminders without having to opt in.
const String kWhatsAppRemindersField = 'whatsappRemindersEnabled';

/// The paid module that includes messaging.
const String kMessagingModule = 'omnichannel_messaging';

/// Whether this clinic's plan includes messaging at all.
final whatsAppRemindersAvailableProvider = Provider<bool>((ref) {
  final profile = ref.watch(doctorProfileProvider).value;
  if (profile == null) return false;

  final modules = (profile['enabledModules'] as List?)
          ?.map((m) => m.toString().toLowerCase())
          .toList() ??
      const <String>[];

  return DoctorFeatureGuard.isEnabled(modules, kMessagingModule);
});

/// Whether reminders are switched on. Defaults to true when unset.
final whatsAppRemindersEnabledProvider = Provider<bool>((ref) {
  final profile = ref.watch(doctorProfileProvider).value;
  return profile?[kWhatsAppRemindersField] != false;
});

/// Turns reminders on or off for this clinic.
///
/// Writes to the doctor's own profile document, which `firestore.rules`
/// already lets them update.
Future<void> setWhatsAppRemindersEnabled(bool enabled) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) return;

  await FirebaseFirestore.instance.collection('users').doc(uid).set({
    kWhatsAppRemindersField: enabled,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
