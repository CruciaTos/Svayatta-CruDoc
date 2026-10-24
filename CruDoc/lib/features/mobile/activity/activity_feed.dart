import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/local_storage_manager.dart';
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
    this.homeVisit = false,
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

  /// A home visit rather than an appointment at the clinic.
  final bool homeVisit;

  /// An appointment or home visit of one patient (booked, cancelled,
  /// missed, seen): its row shows that patient's monogram, not an icon.
  bool get showsPatient =>
      patient != null &&
      const {
        ActivityKind.booked,
        ActivityKind.cancelled,
        ActivityKind.missed,
        ActivityKind.consultDone,
        ActivityKind.homeVisitDone,
      }.contains(kind);
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

  final patients = ref.watch(patientsStreamProvider).value ?? const <Patient>[];
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
          homeVisit: home,
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
        homeVisit: home,
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
        title:
            'Added ${t.quantity} ${medName[t.medicineId] ?? 'items'} to stock',
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
  final unpaid = [
    for (final b in pending)
      if (!b.isPaid) b,
  ];
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
        title:
            '${DashFormat.plural(overdue.length, 'study', 'studies')} overdue',
        detail: DashFormat.names([
          for (final s in overdue) studyName(s),
        ], max: 3),
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

/// CruDoc's storage on this device, only when it's past 90% of its limit.
final storageNearlyFullProvider =
    FutureProvider.autoDispose<LocalStorageReport?>((ref) async {
      final r = await LocalStorageManager.instance.report();
      if (r.limitBytes <= 0 || r.totalBytes < r.limitBytes * 0.9) return null;
      return r;
    });

/// Today, Yesterday, This week, Earlier — only the ones with rows.
List<(String, List<ActivityItem>)> activityGroups(
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
String activityAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DashFormat.shortDate(t);
}

/// "920 MB", "1.5 GB".
String storageSize(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  return bytes >= gb
      ? '${(bytes / gb).toStringAsFixed(1)} GB'
      : '${(bytes / mb).round()} MB';
}
