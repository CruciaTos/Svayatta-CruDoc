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
