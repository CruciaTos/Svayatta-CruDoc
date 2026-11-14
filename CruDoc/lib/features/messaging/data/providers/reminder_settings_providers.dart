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

// -----------------------------------------------------------------------------
// Channels, recalls and wording (Campaigns > Reminders)
// -----------------------------------------------------------------------------
//
// All of this sits on the same `users/{uid}` profile the server already reads
// when it sweeps (functions/src/reminders/settings.ts reads these exact field
// names), so there is nothing to sync: the server is the sender, and these
// providers only edit what it will read at 6 pm and 10 am.

/// Recalls on or off. Absent means off: unlike reminders, a clinic opts in.
const String kRecallsField = 'recallsEnabled';

/// `["whatsapp", "email"]` in the order the clinic prefers.
const String kChannelOrderField = 'reminderChannelOrder';

/// `{reminder: {emailSubject, emailBody}, recall: {...}}`.
const String kEmailTemplatesField = 'reminderTemplates';

enum ReminderChannel {
  whatsapp('WhatsApp'),
  email('Email');

  const ReminderChannel(this.label);
  final String label;
}

enum ReminderKind {
  reminder('Appointment reminder'),
  recall('Recall');

  const ReminderKind(this.label);
  final String label;
}

/// The variables a template may use, as the server fills them in.
const List<String> kReminderVariables = [
  'patient',
  'date',
  'time',
  'clinic',
  'doctor',
];

/// Mirrors the server's defaults (functions/src/reminders/settings.ts), shown
/// until the clinic writes its own.
const Map<ReminderKind, ({String subject, String body})>
kDefaultEmailTemplates = {
  ReminderKind.reminder: (
    subject: 'Appointment reminder from {clinic}',
    body:
        'Hi {patient},\n\n'
        'This is a reminder of your appointment with {doctor} at {clinic} '
        'on {date} at {time}.\n\n'
        'If you need to reschedule, please call the clinic.\n\n'
        'See you soon,\n{clinic}',
  ),
  ReminderKind.recall: (
    subject: 'Time for your next visit to {clinic}',
    body:
        'Hi {patient},\n\n'
        'It is time to book your next visit with {doctor} at {clinic}. '
        'Your recall is due on {date}.\n\n'
        'Please call the clinic to pick a time that suits you.\n\n'
        'Thank you,\n{clinic}',
  ),
};

/// Added to every email by the server, not editable.
const String kEmailFooter =
    "You're receiving this because you're a patient of {clinic}. "
    'To stop these reminders, reply to this email or let the clinic know.';

final recallsEnabledProvider = Provider<bool>((ref) {
  final profile = ref.watch(doctorProfileProvider).value;
  return profile?[kRecallsField] == true;
});

final reminderChannelOrderProvider = Provider<List<ReminderChannel>>((ref) {
  final profile = ref.watch(doctorProfileProvider).value;
  final raw = profile?[kChannelOrderField];
  final order = <ReminderChannel>[
    if (raw is List)
      for (final v in raw)
        for (final c in ReminderChannel.values)
          if (c.name == '$v') c,
  ];
  for (final c in ReminderChannel.values) {
    if (!order.contains(c)) order.add(c);
  }
  return order.toSet().toList();
});

/// The clinic's email wording for [kind], or the default.
final reminderEmailTemplateProvider =
    Provider.family<({String subject, String body}), ReminderKind>((ref, kind) {
      final profile = ref.watch(doctorProfileProvider).value;
      final all = profile?[kEmailTemplatesField];
      final mine = all is Map ? all[kind.name] : null;
      final def = kDefaultEmailTemplates[kind]!;
      String pick(String key, String fallback) {
        final v = mine is Map ? mine[key] : null;
        return v is String && v.trim().isNotEmpty ? v : fallback;
      }

      return (
        subject: pick('emailSubject', def.subject),
        body: pick('emailBody', def.body),
      );
    });

DocumentReference<Map<String, dynamic>>? _profileRef() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) return null;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

Future<void> setRecallsEnabled(bool enabled) async {
  await _profileRef()?.set({
    kRecallsField: enabled,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> setReminderChannelOrder(List<ReminderChannel> order) async {
  await _profileRef()?.set({
    kChannelOrderField: [for (final c in order) c.name],
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> saveReminderEmailTemplate(
  ReminderKind kind, {
  required String subject,
  required String body,
}) async {
  await _profileRef()?.set({
    kEmailTemplatesField: {
      kind.name: {'emailSubject': subject.trim(), 'emailBody': body.trim()},
    },
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Back to the default wording.
Future<void> resetReminderEmailTemplate(ReminderKind kind) async {
  await _profileRef()?.update({
    '$kEmailTemplatesField.${kind.name}': FieldValue.delete(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
