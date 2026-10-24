# Antigravity brief: Notifications = recent activity (like Instagram)

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Task 1 to Task 8 in order, then run the Checks once at the end. Stop after the Checks and report.

**GATE: never deploy anything** (no `firebase deploy`, no Cloud Functions, rules or index deploys). Task 7 changes server files; the user deploys them later.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end.
- Only create or change the files named below. Do not rename, move or reformat anything else.
- Do not run `flutter run` or a release build. Do not commit.
- If a step doesn't match the code you see (a name or a field is different), make the smallest fix that keeps the same meaning, write down what you changed, and carry on. If you can't, skip that one line, note it, carry on.
- Paths starting with `lib/`, `functions/`, `firestore.*` are relative to the `CruDoc/` folder. The Dart package name is `doctor_management_app`.
- Dart in this repo already uses null-aware list elements like `[?a, ?b, c]`. That's fine to use.
- Server TypeScript (`functions/`) uses double quotes and lines of at most 80 characters (eslint google style).

## What we're building

The bell on the phone home screen opens `MobileNotificationsScreen` (`lib/features/mobile/mobile_notifications.dart`). Today it is an empty page. Turn it into an Instagram-style activity page:

1. **Pick up where you left off**: the last patient whose consultation was started or finished. Tap → open that patient.
2. **Needs attention** (on top while true): medicines running low, medicines expiring soon, unpaid bills total, clinic invites not accepted yet, radiology studies overdue, CruDoc's storage on this phone nearly full.
3. **Birthdays today**: each patient with a **Send wishes** button that opens WhatsApp with a ready message.
4. **Activity**, newest first, grouped **Today / Yesterday / This week / Earlier**, last 14 days, at most 80 rows:
   - New patient added
   - File added for a patient (says X-ray, Scan, PDF, Photo or File)
   - Consultation finished
   - Appointment / home visit booked (with the date and time it's booked for)
   - Appointment cancelled, or patient missed it
   - Home visit finished
   - Payment received, expense added, bill left unpaid
   - Stock added (restock)
   - Consultation notes saved (today only)
   - Team member joined the clinic
   - Radiology: new study arrived from PACS, report signed
   - WhatsApp: reminder failed to send, patient replied, patient turned reminders off/on
5. Each row shows **who did it** when known (a team member's name, or "You") and how long ago.
6. Rows newer than the last time Notifications was opened get a small blue dot. The home bell gets a dot when **someone else** did something new (a team member, or a patient replying).

Patient check-ins are deliberately **not** shown.

---

## Task 1: recent files provider

File: `lib/features/files/data/files_providers.dart`

Add at the end of the file:

```dart

/// The newest files across all patients, for Notifications.
final recentFilesProvider = FutureProvider<List<PatientFile>>((ref) {
  ref.watch(filesVersionProvider);
  ref.watch(clinicAccessProvider);
  return FilesRepository.instance.files(limit: 40);
});
```

(Everything it uses is already imported there, because `patientFilesProvider` uses the same names.)

---

## Task 2: "last seen" store

Create file: `lib/features/mobile/activity/activity_seen.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'activity_last_seen_ms';

/// When Notifications was last opened. Null until loaded, or if never
/// opened.
final activitySeenProvider = NotifierProvider<ActivitySeen, DateTime?>(
  ActivitySeen.new,
);

class ActivitySeen extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key);
    if (ms != null) state = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markSeen() async {
    final now = DateTime.now();
    state = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, now.millisecondsSinceEpoch);
  }
}
```

---

## Task 3: WhatsApp reply model

Create file: `lib/features/messaging/data/models/whatsapp_reply.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A message a patient sent back to the reminder number. The server writes
/// these (collection `whatsapp_replies`); the app only reads them.
class WhatsAppReply {
  const WhatsAppReply({
    required this.id,
    required this.patientId,
    required this.name,
    required this.phone,
    required this.kind,
    required this.text,
    required this.receivedAt,
  });

  final String id;
  final String patientId;
  final String name;
  final String phone;

  /// 'text', 'stop' (turned reminders off) or 'start' (turned them on).
  final String kind;
  final String text;
  final DateTime receivedAt;

  factory WhatsAppReply.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final at = d['receivedAt'];
    return WhatsAppReply(
      id: doc.id,
      patientId: d['patientId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      kind: d['kind'] as String? ?? 'text',
      text: d['text'] as String? ?? '',
      receivedAt: at is Timestamp ? at.toDate() : DateTime.now(),
    );
  }
}
```

---

## Task 4: read failed reminders and replies

### 4a. Repository

File: `lib/features/messaging/data/repo/whatsapp_repository.dart`

1. Add with the other imports:

```dart
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_reply.dart';
```

2. Add these two methods inside class `WhatsAppRepository`, right after the method `watchVisitWhatsAppStatus`:

```dart
  /// Reminders that failed to send, newest first (for Notifications).
  Stream<List<WhatsAppNotificationLog>> watchFailedLogs({int limit = 20}) {
    final firestore = _firestore;
    if (firestore == null) return Stream.value(const []);
    return firestore
        .collection(_collection)
        .where('doctorId', isEqualTo: _currentDoctorId)
        .where('status', isEqualTo: WhatsAppNotificationStatus.failed.value)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => [for (final d in s.docs) WhatsAppNotificationLog.fromFirestore(d)],
        )
        .handleError((_) {});
  }

  /// What patients wrote back to the reminder number, newest first.
  Stream<List<WhatsAppReply>> watchRecentReplies({int limit = 30}) {
    final firestore = _firestore;
    if (firestore == null) return Stream.value(const []);
    return firestore
        .collection('whatsapp_replies')
        .where('doctorId', isEqualTo: _currentDoctorId)
        .orderBy('receivedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [for (final d in s.docs) WhatsAppReply.fromFirestore(d)])
        .handleError((_) {});
  }
```

### 4b. Providers

File: `lib/features/messaging/data/providers/whatsapp_providers.dart`

1. Add with the other imports:

```dart
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_reply.dart';
```

2. Add at the end of the file:

```dart

/// Reminders that failed to send (Notifications).
final failedRemindersProvider = StreamProvider<List<WhatsAppNotificationLog>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(whatsappRepositoryProvider).watchFailedLogs();
  },
);

/// Patients' replies to the reminder number (Notifications).
final whatsAppRepliesProvider = StreamProvider<List<WhatsAppReply>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(whatsappRepositoryProvider).watchRecentReplies();
});
```

---

## Task 5: the activity feed

Create file: `lib/features/mobile/activity/activity_feed.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/wrap_up_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_reply.dart';
import 'package:doctor_management_app/features/messaging/data/providers/reminder_settings_providers.dart';
import 'package:doctor_management_app/features/messaging/data/providers/whatsapp_providers.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_seen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';

/// How far back the feed goes, and how many rows it keeps.
const activityDays = 14;
const activityMax = 80;

/// Actor id for things a patient did (a WhatsApp reply): counts as
/// "someone else" for the bell dot, but shows no name.
const patientActor = '_patient';

enum ActivityKind {
  patientAdded,
  fileAdded,
  consultDone,
  booked,
  cancelled,
  missed,
  homeVisitDone,
  paid,
  expense,
  unpaid,
  restocked,
  noteSaved,
  memberJoined,
  radStudy,
  radSigned,
  reminderFailed,
  replied,
  optedOut,
  optedIn,
}

/// One row in Notifications: something that happened.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    this.detail,
    this.actorUid = '',
    this.patient,
    this.desktopTab,
  });

  final String id;
  final DateTime at;
  final ActivityKind kind;
  final String title;
  final String? detail;

  /// Who did it; empty when unknown, [patientActor] for a patient.
  final String actorUid;

  /// The patient it's about; tapping the row opens them.
  final Patient? patient;

  /// When there's no patient: the screen a tap opens (a [DesktopTab]).
  final int? desktopTab;
}

enum AttentionKind { lowStock, expiring, unpaid, invites, overdueStudies }

/// Something that needs doing, pinned above the activity.
class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.title,
    required this.detail,
  });

  final AttentionKind kind;
  final String title;
  final String detail;
}

class ActivityFeed {
  const ActivityFeed({
    required this.items,
    required this.attention,
    required this.birthdays,
    required this.names,
    required this.me,
    this.lastPatient,
    this.lastPatientAt,
  });

  /// Newest first.
  final List<ActivityItem> items;
  final List<AttentionItem> attention;

  /// Patients whose birthday is today.
  final List<Patient> birthdays;

  /// Team member names by uid.
  final Map<String, String> names;

  /// The signed-in person's uid.
  final String me;

  final Patient? lastPatient;
  final DateTime? lastPatientAt;

  /// "You", a team member's name, or null when unknown.
  String? actorName(ActivityItem i) {
    if (i.actorUid.isEmpty || i.actorUid == patientActor) return null;
    if (i.actorUid == me) return 'You';
    return names[i.actorUid];
  }
}

final activityFeedProvider = Provider<ActivityFeed>((ref) {
  final now = ref.watch(dashboardNowProvider);
  final from = now.subtract(const Duration(days: activityDays));
  bool recent(DateTime? t) =>
      t != null &&
      t.isAfter(from) &&
      t.isBefore(now.add(const Duration(minutes: 5)));

  final me = ref.watch(currentUserProvider)?.uid ?? '';

  final patients =
      ref.watch(patientsStreamProvider).value ?? const <Patient>[];
  final byId = {for (final p in patients) p.id: p};
  String nameOf(String? id, [String fallback = 'A patient']) {
    final n = byId[id]?.fullName.trim() ?? '';
    return n.isEmpty ? fallback : n;
  }

  final members =
      ref.watch(clinicMembersProvider).value ?? const <ClinicMember>[];
  final names = {
    for (final m in members)
      if (m.uid.isNotEmpty && m.name.trim().isNotEmpty) m.uid: m.name.trim(),
  };

  final items = <ActivityItem>[];

  // New patients.
  for (final p in patients) {
    if (!recent(p.createdAt)) continue;
    items.add(
      ActivityItem(
        id: 'p_${p.id}',
        at: p.createdAt,
        kind: ActivityKind.patientAdded,
        title: '${nameOf(p.id)} was added as a new patient',
        patient: p,
      ),
    );
  }

  // Files (X-rays, scans, photos, PDFs).
  for (final f
      in ref.watch(recentFilesProvider).value ?? const <PatientFile>[]) {
    if (!recent(f.createdAt)) continue;
    final word = _fileWord(f);
    items.add(
      ActivityItem(
        id: 'f_${f.id}',
        at: f.createdAt,
        kind: ActivityKind.fileAdded,
        title: f.patientId.isEmpty
            ? '$word added to Files'
            : '$word added for ${nameOf(f.patientId)}',
        detail: f.name,
        actorUid: f.ownerUid,
        patient: byId[f.patientId],
      ),
    );
  }

  // Queue: finished consultations, and the last patient worked on.
  // (Check-ins are left out on purpose.)
  Patient? lastPatient;
  DateTime? lastPatientAt;
  for (final e in ref.watch(allQueueProvider).value ?? const <QueueEntry>[]) {
    final walkIn = e.walkInName?.trim() ?? '';
    final who = nameOf(e.patientId, walkIn.isEmpty ? 'A walk-in' : walkIn);
    final p = byId[e.patientId];
    final done = e.completedAt;
    if (done != null && recent(done)) {
      items.add(
        ActivityItem(
          id: 'qd_${e.id}',
          at: done,
          kind: ActivityKind.consultDone,
          title: 'Consultation finished with $who',
          patient: p,
        ),
      );
    }
    final worked = e.completedAt ?? e.consultationStartedAt;
    if (p != null &&
        worked != null &&
        (lastPatientAt == null || worked.isAfter(lastPatientAt))) {
      lastPatient = p;
      lastPatientAt = worked;
    }
  }

  // Appointments and home visits.
  for (final v in ref.watch(allVisitsProvider).value ?? const <Visit>[]) {
    final who = nameOf(v.patientId);
    final home = v.visitType == VisitType.home;
    final p = byId[v.patientId];
    // Walk-ins make a visit for "now": that's not a booking.
    final booking =
        v.scheduledStart.difference(v.createdAt) > const Duration(minutes: 10);
    if (recent(v.createdAt) && booking) {
      items.add(
        ActivityItem(
          id: 'vb_${v.id}',
          at: v.createdAt,
          kind: ActivityKind.booked,
          title: home
              ? 'Home visit booked for $who'
              : 'Appointment booked for $who',
          detail:
              '${DashFormat.shortDate(v.scheduledStart)}, '
              '${DashFormat.time(v.scheduledStart)}',
          actorUid: v.createdByUid,
          patient: p,
        ),
      );
    }
    final changed =
        recent(v.updatedAt) &&
        v.updatedAt.difference(v.createdAt) > const Duration(minutes: 1);
    if (!changed) continue;
    final ActivityKind? kind = switch (v.status) {
      VisitStatus.cancelled => ActivityKind.cancelled,
      VisitStatus.missed => ActivityKind.missed,
      VisitStatus.completed when home => ActivityKind.homeVisitDone,
      _ => null,
    };
    if (kind == null) continue;
    items.add(
      ActivityItem(
        id: 'vs_${v.id}',
        at: v.updatedAt,
        kind: kind,
        title: switch (kind) {
          ActivityKind.cancelled => "$who's appointment was cancelled",
          ActivityKind.missed => '$who missed their appointment',
          _ => 'Home visit with $who finished',
        },
        patient: p,
      ),
    );
  }

  // Money in and out.
  for (final r
      in ref.watch(recentRevenueEntriesProvider).value ??
          const <RevenueEntry>[]) {
    if (r.isDeleted || !recent(r.createdAt)) continue;
    final amount = DashFormat.rupees(r.amount);
    final expense = r.kind == TransactionKind.expense;
    final payer = r.patientId != null
        ? nameOf(r.patientId)
        : (r.payer?.trim() ?? '');
    items.add(
      ActivityItem(
        id: 'r_${r.id}',
        at: r.createdAt,
        kind: expense ? ActivityKind.expense : ActivityKind.paid,
        title: expense
            ? '$amount expense added'
            : payer.isEmpty
            ? '$amount received'
            : '$amount received from $payer',
        detail: r.description.trim().isEmpty ? null : r.description.trim(),
        actorUid: r.createdByUid,
        patient: byId[r.patientId],
      ),
    );
  }

  final pending =
      ref.watch(pendingPaymentsProvider).value ?? const <PendingPayment>[];
  for (final b in pending) {
    if (b.isPaid || !recent(b.createdAt)) continue;
    items.add(
      ActivityItem(
        id: 'u_${b.id}',
        at: b.createdAt,
        kind: ActivityKind.unpaid,
        title:
            '${DashFormat.rupees(b.amount)} left unpaid by '
            '${b.patientId != null ? nameOf(b.patientId) : (b.payer ?? 'a patient')}',
        detail: b.description.trim().isEmpty ? null : b.description.trim(),
        actorUid: b.createdByUid,
        patient: byId[b.patientId],
      ),
    );
  }

  // Stock added.
  final meds =
      ref.watch(medicinesStreamProvider).value ?? const <MedicineModel>[];
  final medName = {for (final m in meds) m.id: m.name};
  for (final t
      in ref.watch(stockPurchasesProvider).value ??
          const <StockTransactionModel>[]) {
    if (t.type != StockTransactionType.restock || !recent(t.createdAt)) {
      continue;
    }
    items.add(
      ActivityItem(
        id: 's_${t.id}',
        at: t.createdAt,
        kind: ActivityKind.restocked,
        title: 'Added ${t.quantity} ${medName[t.medicineId] ?? 'items'} to stock',
        desktopTab: DesktopTab.inventory,
      ),
    );
  }

  // Consultation notes saved today.
  for (final ConsultationNote n in ref.watch(todaysScribeNotesProvider)) {
    final at = n.confirmedAt ?? n.createdAt;
    if (!recent(at)) continue;
    items.add(
      ActivityItem(
        id: 'n_${n.id}',
        at: at,
        kind: ActivityKind.noteSaved,
        title: 'Consultation notes saved for ${nameOf(n.patientId)}',
        actorUid: n.authorUid,
        patient: byId[n.patientId],
      ),
    );
  }

  // Team.
  for (final m in members) {
    final joined = m.joinedAt;
    if (joined == null || !recent(joined) || m.isOwner) continue;
    items.add(
      ActivityItem(
        id: 'm_${m.uid}',
        at: joined,
        kind: ActivityKind.memberJoined,
        title:
            '${m.name.trim().isEmpty ? 'Someone' : m.name.trim()} joined the clinic',
        detail: m.roleName.trim().isEmpty ? null : m.roleName.trim(),
      ),
    );
  }

  // Radiology: new studies and signed reports. Empty for clinics without
  // radiology, so no extra check is needed.
  final studies = ref.watch(radStudiesProvider).value ?? const <RadStudy>[];
  final studyById = {for (final s in studies) s.id: s};
  String studyName(RadStudy s) => s.patientName.trim().isNotEmpty
      ? s.patientName.trim()
      : nameOf(s.patientId);
  for (final s in studies) {
    if (!recent(s.receivedAt)) continue;
    items.add(
      ActivityItem(
        id: 'rs_${s.id}',
        at: s.receivedAt,
        kind: ActivityKind.radStudy,
        title: 'New ${s.modality.short} study for ${studyName(s)}',
        detail: s.description.trim().isEmpty ? null : s.description.trim(),
        desktopTab: DesktopTab.worklist,
      ),
    );
  }
  for (final r in ref.watch(radReportsProvider).value ?? const <RadReport>[]) {
    final signed = r.signedAt;
    if (signed == null || !recent(signed)) continue;
    final s = studyById[r.studyId];
    items.add(
      ActivityItem(
        id: 'rr_${r.id}',
        at: signed,
        kind: ActivityKind.radSigned,
        title:
            'Report signed for ${s != null ? studyName(s) : nameOf(r.patientId)}',
        detail: r.title.trim().isEmpty ? null : r.title.trim(),
        desktopTab: DesktopTab.reports,
      ),
    );
  }

  // WhatsApp: failed reminders and patients' replies (clinics with
  // reminders only).
  if (ref.watch(whatsAppRemindersAvailableProvider)) {
    for (final l
        in ref.watch(failedRemindersProvider).value ??
            const <WhatsAppNotificationLog>[]) {
      if (!recent(l.updatedAt)) continue;
      final who = l.recipientName.trim().isNotEmpty
          ? l.recipientName.trim()
          : nameOf(l.patientId);
      items.add(
        ActivityItem(
          id: 'wf_${l.id}',
          at: l.updatedAt,
          kind: ActivityKind.reminderFailed,
          title: "WhatsApp reminder to $who didn't send",
          detail: l.failureReason?.trim().isEmpty ?? true
              ? null
              : l.failureReason!.trim(),
          patient: byId[l.patientId],
        ),
      );
    }
    for (final r
        in ref.watch(whatsAppRepliesProvider).value ??
            const <WhatsAppReply>[]) {
      if (!recent(r.receivedAt)) continue;
      final who = byId[r.patientId] != null
          ? nameOf(r.patientId)
          : (r.name.trim().isNotEmpty ? r.name.trim() : r.phone);
      final kind = switch (r.kind) {
        'stop' => ActivityKind.optedOut,
        'start' => ActivityKind.optedIn,
        _ => ActivityKind.replied,
      };
      items.add(
        ActivityItem(
          id: 'wr_${r.id}',
          at: r.receivedAt,
          kind: kind,
          title: switch (kind) {
            ActivityKind.optedOut => '$who turned off WhatsApp reminders',
            ActivityKind.optedIn => '$who turned WhatsApp reminders back on',
            _ => '$who replied on WhatsApp',
          },
          detail: kind == ActivityKind.replied && r.text.trim().isNotEmpty
              ? '"${r.text.trim()}"'
              : null,
          actorUid: patientActor,
          patient: byId[r.patientId],
        ),
      );
    }
  }

  items.sort((a, b) => b.at.compareTo(a.at));

  // Needs attention.
  final attention = <AttentionItem>[];
  final low =
      ref.watch(lowStockMedicinesProvider).value ?? const <MedicineModel>[];
  if (low.isNotEmpty) {
    attention.add(
      AttentionItem(
        kind: AttentionKind.lowStock,
        title: '${DashFormat.plural(low.length, 'medicine')} running low',
        detail: DashFormat.names([for (final m in low) m.name], max: 3),
      ),
    );
  }
  final expiring =
      ref.watch(expiringMedicinesProvider).value ?? const <MedicineModel>[];
  if (expiring.isNotEmpty) {
    attention.add(
      AttentionItem(
        kind: AttentionKind.expiring,
        title:
            '${DashFormat.plural(expiring.length, 'medicine')} expiring soon',
        detail: DashFormat.names([for (final m in expiring) m.name], max: 3),
      ),
    );
  }
  final unpaid = [for (final b in pending) if (!b.isPaid) b];
  if (unpaid.isNotEmpty) {
    final total = unpaid.fold<double>(0, (s, b) => s + b.amount);
    attention.add(
      AttentionItem(
        kind: AttentionKind.unpaid,
        title: '${DashFormat.rupees(total)} unpaid',
        detail: DashFormat.plural(unpaid.length, 'bill'),
      ),
    );
  }
  final invites = [
    for (final i
        in ref.watch(clinicInvitesProvider).value ?? const <ClinicInvite>[])
      if (i.status == 'pending') i,
  ];
  if (invites.isNotEmpty) {
    attention.add(
      AttentionItem(
        kind: AttentionKind.invites,
        title:
            '${DashFormat.plural(invites.length, 'invite')} not accepted yet',
        detail: DashFormat.names([
          for (final i in invites)
            i.name.trim().isEmpty ? i.phone : i.name.trim(),
        ], max: 3),
      ),
    );
  }
  const open = {
    RadStudyStatus.newStudy,
    RadStudyStatus.reading,
    RadStudyStatus.draft,
    RadStudyStatus.preliminary,
  };
  final overdue = [
    for (final s in studies)
      if (open.contains(s.status) && s.dueAt != null && s.dueAt!.isBefore(now))
        s,
  ];
  if (overdue.isNotEmpty) {
    attention.add(
      AttentionItem(
        kind: AttentionKind.overdueStudies,
        title: '${DashFormat.plural(overdue.length, 'study', 'studies')} overdue',
        detail: DashFormat.names([for (final s in overdue) studyName(s)], max: 3),
      ),
    );
  }

  // Birthdays today. Patients saved with only an age get a made-up birthday
  // on the day they were added, so skip those.
  final birthdays = [
    for (final p in patients)
      if (p.dateOfBirth.month == now.month &&
          p.dateOfBirth.day == now.day &&
          p.dateOfBirth.year < now.year &&
          !(p.createdAt.month == p.dateOfBirth.month &&
              p.createdAt.day == p.dateOfBirth.day))
        p,
  ];

  return ActivityFeed(
    items: items.length > activityMax ? items.sublist(0, activityMax) : items,
    attention: attention,
    birthdays: birthdays,
    names: names,
    me: me,
    lastPatient: lastPatient,
    lastPatientAt: lastPatientAt,
  );
});

/// True when someone else (a team member or a patient) did something since
/// Notifications was opened.
final activityUnreadProvider = Provider<bool>((ref) {
  final seen = ref.watch(activitySeenProvider);
  if (seen == null) return false;
  final feed = ref.watch(activityFeedProvider);
  return feed.items.any(
    (i) => i.at.isAfter(seen) && i.actorUid.isNotEmpty && i.actorUid != feed.me,
  );
});

/// "X-ray", "Scan", "PDF", "Photo" or "File", from the name and type.
String _fileWord(PatientFile f) {
  final name = f.name.toLowerCase();
  final type = f.contentType.toLowerCase();
  const xray = ['xray', 'x-ray', 'x ray', 'opg', 'rvg', 'iopa', 'cbct'];
  if (xray.any(name.contains)) return 'X-ray';
  if (type.contains('dicom') || name.endsWith('.dcm')) return 'Scan';
  if (type == 'application/pdf') return 'PDF';
  if (type.startsWith('image/')) return 'Photo';
  return 'File';
}
```

Notes for this task:
- If `currentUserProvider` gives something without `.uid`, use `ref.watch(authStateProvider).value?.uid ?? ''` instead.
- If `pendingPaymentsProvider` is not in `revenue_view_providers.dart`, find it with a search and fix that import.
- If `clinicInvitesProvider` is not a list of `ClinicInvite`, skip the invites block and note it.
- If `DesktopTab.worklist` or `DesktopTab.reports` doesn't exist, search `mobile_more.dart`'s `mobileDestinationScreen` for the radiology worklist / reports tabs and use those names.

---

## Task 6: the Notifications screen

Replace the whole content of `lib/features/mobile/mobile_notifications.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_feed.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_seen.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A bell, for Notifications. CruIcons has none yet; same stroke style
/// (24-unit viewBox, round caps).
const mobileBellIcon = CruIconData(
  'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0',
);

/// Opens Notifications over Home, the way Instagram's heart opens
/// Activity.
void openMobileNotifications(BuildContext context) => pushMobile(
  context,
  const MobileHostPage(backLabel: 'Home', child: MobileNotificationsScreen()),
);

/// CruDoc's storage on this phone, only when it's past 90% of its limit.
final _storageFullProvider = FutureProvider.autoDispose<LocalStorageReport?>((
  ref,
) async {
  final r = await LocalStorageManager.instance.report();
  if (r.limitBytes <= 0 || r.totalBytes < r.limitBytes * 0.9) return null;
  return r;
});

/// The small blue "new" dot (rows and the home bell).
class MobileUnreadDot extends StatelessWidget {
  const MobileUnreadDot({super.key, this.size = 8});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: MobileBlue.neon,
      shape: BoxShape.circle,
    ),
  );
}

/// What happened lately, Instagram-style: the last patient, what needs
/// attention, birthdays, then activity by day.
class MobileNotificationsScreen extends ConsumerStatefulWidget {
  const MobileNotificationsScreen({super.key});

  @override
  ConsumerState<MobileNotificationsScreen> createState() =>
      _MobileNotificationsScreenState();
}

class _MobileNotificationsScreenState
    extends ConsumerState<MobileNotificationsScreen> {
  /// When the page was last opened before now: rows newer than it get
  /// the dot.
  DateTime? _seenBefore;

  @override
  void initState() {
    super.initState();
    _seenBefore = ref.read(activitySeenProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(activitySeenProvider.notifier).markSeen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(activityFeedProvider);
    final now = ref.watch(dashboardNowProvider);
    final storage = ref.watch(_storageFullProvider).value;
    final last = feed.lastPatient;
    final groups = _groups(feed.items, now);
    final empty =
        feed.items.isEmpty &&
        feed.attention.isEmpty &&
        feed.birthdays.isEmpty &&
        storage == null &&
        last == null;

    return ListView(
      padding: EdgeInsets.only(
        bottom: MobileMetrics.navBottom(context) + CruSpace.s24,
      ),
      children: [
        const MobileHeader(pushed: true, title: 'Notifications'),
        if (empty)
          const MobileEmpty(
            icon: mobileBellIcon,
            title: 'Nothing new',
            body:
                'New patients, files, payments, bookings and replies '
                'show up here.',
          ),
        if (last != null)
          MobileRowGroup(
            title: 'Pick up where you left off',
            children: [
              MobileRow(
                leading: MobileAvatar(name: last.fullName, size: 38),
                title: last.fullName,
                subtitle: feed.lastPatientAt == null
                    ? null
                    : 'Last seen ${_ago(feed.lastPatientAt!, now)}',
                chevron: true,
                onTap: () => openMobilePatient(context, last),
              ),
            ],
          ),
        if (feed.attention.isNotEmpty || storage != null)
          MobileRowGroup(
            title: 'Needs attention',
            children: [
              for (final a in feed.attention)
                MobileRow(
                  leading: MobileIconTile(
                    icon: _attentionIcon(a.kind),
                    tone: MobileTone.amber,
                  ),
                  title: a.title,
                  subtitle: a.detail,
                  chevron: a.kind != AttentionKind.invites,
                  onTap: a.kind == AttentionKind.invites
                      ? null
                      : () => _openAttention(a),
                ),
              if (storage != null)
                MobileRow(
                  leading: const MobileIconTile(
                    icon: CruIcons.download,
                    tone: MobileTone.amber,
                  ),
                  title: 'Phone storage almost full',
                  subtitle:
                      'CruDoc is using ${_size(storage.totalBytes)} of its '
                      '${_size(storage.limitBytes)} limit',
                  chevron: true,
                  onTap: () => openMobileSettings(
                    context,
                    ref,
                    SettingsSection.storage,
                    backLabel: 'Notifications',
                  ),
                ),
            ],
          ),
        if (feed.birthdays.isNotEmpty)
          MobileRowGroup(
            title: 'Birthdays today',
            children: [
              for (final p in feed.birthdays)
                MobileRow(
                  leading: MobileAvatar(name: p.fullName, size: 38),
                  title: p.fullName,
                  subtitle: 'Turns ${now.year - p.dateOfBirth.year} today',
                  trailing: MobileChip(
                    label: 'Send wishes',
                    selected: true,
                    onTap: () => _wish(p),
                  ),
                  onTap: () => openMobilePatient(context, p),
                ),
            ],
          ),
        for (final g in groups)
          MobileRowGroup(
            title: g.$1,
            children: [for (final i in g.$2) _row(feed, i, now)],
          ),
      ],
    );
  }

  Widget _row(ActivityFeed feed, ActivityItem i, DateTime now) {
    final (icon, tone) = _look(i.kind);
    final actor = feed.actorName(i);
    final unread = _seenBefore != null && i.at.isAfter(_seenBefore!);
    final p = i.patient;
    final tab = i.desktopTab;
    return MobileRow(
      leading: MobileIconTile(icon: icon, tone: tone),
      title: i.title,
      subtitle: [?i.detail, ?actor, _ago(i.at, now)].join(' · '),
      trailing: unread ? const MobileUnreadDot() : null,
      onTap: p != null
          ? () => openMobilePatient(context, p)
          : tab != null
          ? () => openMobileDestination(
              context,
              tab,
              backLabel: 'Notifications',
            )
          : null,
    );
  }

  void _wish(Patient p) {
    final first = p.firstName.trim().isEmpty ? p.fullName : p.firstName.trim();
    PatientActions.whatsApp(
      context,
      p,
      message:
          'Happy birthday, $first! Wishing you good health and a '
          'wonderful year ahead.',
    );
  }

  void _openAttention(AttentionItem a) {
    switch (a.kind) {
      case AttentionKind.lowStock:
      case AttentionKind.expiring:
        openMobileDestination(
          context,
          DesktopTab.inventory,
          backLabel: 'Notifications',
        );
      case AttentionKind.overdueStudies:
        openMobileDestination(
          context,
          DesktopTab.worklist,
          backLabel: 'Notifications',
        );
      case AttentionKind.unpaid:
        Navigator.of(context).pop();
        openMobileRevenue(ref);
      case AttentionKind.invites:
        break;
    }
  }

  /// Today, Yesterday, This week, Earlier — only the ones with rows.
  static List<(String, List<ActivityItem>)> _groups(
    List<ActivityItem> items,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final week = today.subtract(const Duration(days: 6));
    final out = <String, List<ActivityItem>>{
      'Today': [],
      'Yesterday': [],
      'This week': [],
      'Earlier': [],
    };
    for (final i in items) {
      final key = !i.at.isBefore(today)
          ? 'Today'
          : !i.at.isBefore(yesterday)
          ? 'Yesterday'
          : !i.at.isBefore(week)
          ? 'This week'
          : 'Earlier';
      out[key]!.add(i);
    }
    return [
      for (final e in out.entries)
        if (e.value.isNotEmpty) (e.key, e.value),
    ];
  }

  /// "Just now", "5m ago", "3h ago", "2d ago", then "12 Oct".
  static String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DashFormat.shortDate(t);
  }

  /// "920 MB", "1.5 GB".
  static String _size(int bytes) {
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    return bytes >= gb
        ? '${(bytes / gb).toStringAsFixed(1)} GB'
        : '${(bytes / mb).round()} MB';
  }

  static CruIconData _attentionIcon(AttentionKind k) => switch (k) {
    AttentionKind.lowStock => CruIcons.box,
    AttentionKind.expiring => CruIcons.warning,
    AttentionKind.unpaid => CruIcons.rupee,
    AttentionKind.invites => CruIcons.userPlus,
    AttentionKind.overdueStudies => CruIcons.clock,
  };

  static (CruIconData, MobileTone) _look(ActivityKind k) => switch (k) {
    ActivityKind.patientAdded => (CruIcons.userPlus, MobileTone.blue),
    ActivityKind.fileAdded => (CruIcons.fileText, MobileTone.violet),
    ActivityKind.consultDone => (CruIcons.check, MobileTone.green),
    ActivityKind.booked => (CruIcons.calendar, MobileTone.indigo),
    ActivityKind.cancelled => (CruIcons.close, MobileTone.slate),
    ActivityKind.missed => (CruIcons.warning, MobileTone.amber),
    ActivityKind.homeVisitDone => (CruIcons.home, MobileTone.green),
    ActivityKind.paid => (CruIcons.rupee, MobileTone.green),
    ActivityKind.expense => (CruIcons.wallet, MobileTone.slate),
    ActivityKind.unpaid => (CruIcons.rupee, MobileTone.amber),
    ActivityKind.restocked => (CruIcons.box, MobileTone.sky),
    ActivityKind.noteSaved => (CruIcons.mic, MobileTone.violet),
    ActivityKind.memberJoined => (CruIcons.user, MobileTone.blue),
    ActivityKind.radStudy => (CruIcons.scan, MobileTone.indigo),
    ActivityKind.radSigned => (CruIcons.pen, MobileTone.green),
    ActivityKind.reminderFailed => (CruIcons.warning, MobileTone.amber),
    ActivityKind.replied => (CruIcons.whatsapp, MobileTone.green),
    ActivityKind.optedOut => (CruIcons.whatsapp, MobileTone.slate),
    ActivityKind.optedIn => (CruIcons.whatsapp, MobileTone.teal),
  };
}
```

Notes for this task:
- `openMobileRevenue` lives in `mobile_kit.dart`; `openMobilePatient`, `openMobileDestination` and `openMobileSettings` in `mobile_more.dart`; `DesktopTab` in `dashboard_actions.dart`; `SettingsSection` in `desktop_settings_screen.dart`.
- If `MobileBlue.neon` isn't a `const` colour, drop the `const` in front of `BoxDecoration`.
- If two `MobileRowGroup`s touch with no gap between them on screen, put `const SizedBox(height: CruSpace.s8)` between them. Don't restyle anything else.

---

## Task 7: server — save patients' WhatsApp replies (DO NOT DEPLOY)

Today the WhatsApp webhook auto-replies to patients but doesn't keep what they wrote, so the app can't show replies. Save each reply in a new collection `whatsapp_replies` that only that clinic can read.

### 7a. `functions/src/whatsapp/logs.ts`

Replace the whole function `lastClinicFor` (near line 272) with:

```ts
export async function lastClinicFor(
  phone: string,
): Promise<{
  clinicName?: string;
  doctorId?: string;
  patientId?: string | null;
  recipientName?: string;
  visitId?: string;
} | null> {
  const snap = await getDb()
    .collection(LOGS_COLLECTION)
    .where("recipientPhone", "==", phone)
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();

  if (snap.empty) return null;
  const doc = snap.docs[0];
  const data = doc.data();
  return {
    clinicName: data.clinicName,
    doctorId: data.doctorId,
    patientId: data.patientId ?? null,
    recipientName: data.recipientName,
    visitId: doc.id,
  };
}
```

### 7b. `functions/src/whatsapp/webhook.ts`

1. Under the line `const AUTOREPLY_COLLECTION = "whatsapp_autoreplies";` add:

```ts

/** What patients wrote back, readable by their clinic (Notifications). */
const REPLIES_COLLECTION = "whatsapp_replies";
```

2. Add this function right above `async function handleInbound(`:

```ts
/** Keeps what a patient wrote, so their clinic sees it in Notifications. */
async function recordReply(
  m: Record<string, any>,
  from: string,
  text: string,
  kind: "text" | "stop" | "start",
): Promise<void> {
  try {
    const clinic = await lastClinicFor(from);
    if (!clinic?.doctorId) return;
    const id = String(m.id || "") || `${from}_${Date.now()}`;
    await getDb().collection(REPLIES_COLLECTION).doc(id).set({
      doctorId: clinic.doctorId,
      patientId: clinic.patientId ?? null,
      visitId: clinic.visitId ?? null,
      name: clinic.recipientName ?? "",
      phone: from,
      kind,
      text: text.slice(0, 500),
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    console.error("[WhatsApp] could not record reply", err);
  }
}
```

3. Inside `handleInbound`, right after the line `const intent = classifyReply(text);` add:

```ts
    await recordReply(
      m,
      from,
      text,
      intent === "stop" ? "stop" : intent === "start" ? "start" : "text",
    );
```

If `admin` isn't imported in `webhook.ts`, use the same import the file already has for Firestore timestamps. If `classifyReply` returns names other than `"stop"` / `"start"`, use the matching names from `optouts.ts`.

### 7c. `firestore.rules`

Right after the closing `}` of the `match /whatsapp_notification_logs/{logId} { ... }` block (it contains a nested `match /events/{eventId}`), add:

```
    // What patients wrote back to the reminder number. Only the server
    // writes; the clinic reads them in Notifications.
    match /whatsapp_replies/{replyId} {
      allow get, list: if clinicAllows(resource.data.doctorId, 'messaging');
      allow write: if false;
    }
```

### 7d. `firestore.indexes.json`

Add these two objects to the `"indexes"` array (keep the JSON valid: commas between objects):

```json
{
  "collectionGroup": "whatsapp_notification_logs",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "doctorId", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "updatedAt", "order": "DESCENDING" }
  ]
},
{
  "collectionGroup": "whatsapp_replies",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "doctorId", "order": "ASCENDING" },
    { "fieldPath": "receivedAt", "order": "DESCENDING" }
  ]
}
```

---

## Task 8: dot on the home bell

File: `lib/features/mobile/mobile_home.dart`, class `_HomeHeader` (near line 750).

1. Add this import with the others at the top:

```dart
import 'package:doctor_management_app/features/mobile/activity/activity_feed.dart';
```

2. Find:

```dart
          MobileCircleButton(
            icon: mobileBellIcon,
            semanticLabel: 'Notifications',
            onPressed: () => openMobileNotifications(context),
          ),
```

Replace with:

```dart
          Consumer(
            builder: (context, ref, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                MobileCircleButton(
                  icon: mobileBellIcon,
                  semanticLabel: 'Notifications',
                  onPressed: () => openMobileNotifications(context),
                ),
                if (ref.watch(activityUnreadProvider))
                  const Positioned(
                    top: 9,
                    right: 9,
                    child: IgnorePointer(child: MobileUnreadDot(size: 9)),
                  ),
              ],
            ),
          ),
```

---

## Checks (run once, at the end)

1. `flutter analyze lib/features/mobile lib/features/messaging lib/features/files/data/files_providers.dart` → no new errors or warnings. Fix any errors in the files you made or changed.
2. In `functions/`: `npm run build` and `npm run lint` → no errors in `webhook.ts` or `logs.ts`.
3. Check `firestore.indexes.json` is still valid JSON (for example `node -e "JSON.parse(require('fs').readFileSync('firestore.indexes.json','utf8'))"`).
4. Do not run the app, a build, or any deploy.

## Report back

- Which tasks are done.
- Every place you changed the given code to make it compile, and why.
- Anything you skipped.
- The output of each Check.
- A reminder that Task 7 (functions, rules, indexes) still needs deploying.
