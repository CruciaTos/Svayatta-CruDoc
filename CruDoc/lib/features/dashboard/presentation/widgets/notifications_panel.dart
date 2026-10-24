import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_feed.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_seen.dart';
import 'package:doctor_management_app/features/mobile/activity/visit_badge.dart';
import 'package:doctor_management_app/features/mobile/mobile_notifications.dart'
    show mobileBellIcon;
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/settings/presentation/desktop_settings_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The dashboard's bell: opens Notifications, with a dot when someone
/// else (a team member or a patient) did something since it was last
/// opened.
class NotificationsBellButton extends ConsumerWidget {
  const NotificationsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(activityUnreadProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CruSquareButton(
          icon: mobileBellIcon,
          secondary: true,
          semanticLabel: unread
              ? 'Notifications, something new'
              : 'Notifications',
          tooltip: 'Notifications',
          onPressed: () => showNotificationsPanel(context),
        ),
        if (unread)
          const Positioned(
            top: CruSpace.s8,
            right: CruSpace.s8,
            child: IgnorePointer(child: _NewDot()),
          ),
      ],
    );
  }
}

/// Wide enough that each row reads on one line.
const double _panelWidth = 520;

/// Notifications on the desktop: the phone's feed (where you left off,
/// what needs attention, birthdays, then activity by day) in a panel that
/// slides in from the right over the page. It keeps the page's Day or
/// Evening look.
Future<void> showNotificationsPanel(BuildContext context) {
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notifications',
    barrierColor: theme.extension<CruColors>()?.scrim ?? Colors.transparent,
    transitionDuration: CruMotion.of(context),
    pageBuilder: (context, _, _) =>
        Theme(data: theme, child: const _NotificationsPanel()),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: CruMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NotificationsPanel extends ConsumerStatefulWidget {
  const _NotificationsPanel();

  @override
  ConsumerState<_NotificationsPanel> createState() =>
      _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<_NotificationsPanel> {
  /// When the panel was last opened before now: rows newer than it get
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

  /// Closes the panel and opens [tab] in the shell.
  void _go(int tab) {
    final navigate = ref.read(shellNavigatorProvider);
    Navigator.of(context).pop();
    navigate?.call(tab);
  }

  void _openPatient(Patient p) => DashboardActions.openPatient(context, p);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final feed = ref.watch(activityFeedProvider);
    final now = ref.watch(dashboardNowProvider);
    final storage = ref.watch(storageNearlyFullProvider).value;
    final last = feed.lastPatient;
    final groups = activityGroups(feed.items, now);
    final empty =
        feed.items.isEmpty &&
        feed.attention.isEmpty &&
        feed.birthdays.isEmpty &&
        storage == null &&
        last == null;

    final sections = <Widget>[
      if (last != null)
        _Section(
          title: 'Pick up where you left off',
          rows: [
            _Row(
              leading: CruMonogram(name: last.fullName, size: CruSize.iconTile),
              title: last.fullName,
              meta: feed.lastPatientAt == null
                  ? null
                  : activityAgo(feed.lastPatientAt!, now),
              onTap: () => _openPatient(last),
            ),
          ],
        ),
      if (feed.attention.isNotEmpty || storage != null)
        _Section(
          title: 'Needs attention',
          rows: [
            for (final a in feed.attention)
              _Row(
                leading: CruIconTile(
                  icon: _attentionIcon(a.kind),
                  tone: CruTileTone.amber,
                ),
                title: a.title,
                subtitle: a.detail,
                onTap: switch (a.kind) {
                  AttentionKind.lowStock ||
                  AttentionKind.expiring => () => _go(DesktopTab.inventory),
                  AttentionKind.overdueStudies => () => _go(
                    DesktopTab.worklist,
                  ),
                  AttentionKind.unpaid => () => _go(DesktopTab.revenue),
                  AttentionKind.invites => null,
                },
              ),
            if (storage != null)
              _Row(
                leading: const CruIconTile(
                  icon: CruIcons.download,
                  tone: CruTileTone.amber,
                ),
                title: 'Storage almost full',
                subtitle:
                    'CruDoc is using ${storageSize(storage.totalBytes)} of its '
                    '${storageSize(storage.limitBytes)} limit on this computer',
                onTap: () {
                  ref.read(settingsSectionProvider.notifier).state =
                      SettingsSection.storage;
                  _go(DesktopTab.settings);
                },
              ),
          ],
        ),
      if (feed.birthdays.isNotEmpty)
        _Section(
          title: 'Birthdays today',
          rows: [
            for (final p in feed.birthdays)
              _Row(
                leading: CruMonogram(name: p.fullName, size: CruSize.iconTile),
                title: p.fullName,
                subtitle: 'Turns ${now.year - p.dateOfBirth.year} today',
                trailing: CruCapsuleButton(
                  label: 'Send wishes',
                  semanticLabel: 'Send birthday wishes to ${p.fullName}',
                  onPressed: () => _wish(p),
                ),
                onTap: () => _openPatient(p),
              ),
          ],
        ),
      for (final g in groups)
        _Section(
          title: g.$1,
          rows: [for (final i in g.$2) _activityRow(feed, i, now)],
        ),
    ];

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: SizedBox(
          width: math.min(
            _panelWidth,
            MediaQuery.sizeOf(context).width - CruSpace.s32,
          ),
          height: double.infinity,
          child: Material(
            type: MaterialType.transparency,
            child: CruCard(
              padding: EdgeInsets.zero,
              semanticLabel: 'Notifications',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s24,
                      CruSpace.s20,
                      CruSpace.s16,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              'Notifications',
                              style: CruType.title2.tint(c.label),
                            ),
                          ),
                        ),
                        CruIconButton(
                          icon: CruIcons.close,
                          semanticLabel: 'Close notifications',
                          size: CruSize.squareButton,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: empty
                        ? const _Empty()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                              CruSpace.s12,
                              0,
                              CruSpace.s12,
                              CruSpace.s24,
                            ),
                            children: sections,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityRow(ActivityFeed feed, ActivityItem i, DateTime now) {
    final (icon, tone) = _look(i.kind);
    final actor = feed.actorName(i);
    final unread = _seenBefore != null && i.at.isAfter(_seenBefore!);
    final p = i.patient;
    final tab = i.desktopTab;
    return _Row(
      leading: i.showsPatient
          ? VisitBadged(
              avatar: CruMonogram(name: p!.fullName, size: CruSize.iconTile),
              avatarSize: CruSize.iconTile,
              homeVisit: i.homeVisit,
            )
          : CruIconTile(icon: icon, tone: tone),
      title: i.title,
      subtitle: [?i.detail, ?actor].isEmpty
          ? null
          : [?i.detail, ?actor].join(' · '),
      meta: activityAgo(i.at, now),
      unread: unread,
      onTap: p != null
          ? () => _openPatient(p)
          : tab != null
          ? () => _go(tab)
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

  static CruIconData _attentionIcon(AttentionKind k) => switch (k) {
    AttentionKind.lowStock => CruIcons.box,
    AttentionKind.expiring => CruIcons.warning,
    AttentionKind.unpaid => CruIcons.rupee,
    AttentionKind.invites => CruIcons.userPlus,
    AttentionKind.overdueStudies => CruIcons.clock,
  };

  /// Icon and tile tint per kind: green is done, amber is waiting or
  /// needs a look, teal is stock and files; the rest stay neutral.
  static (CruIconData, CruTileTone) _look(ActivityKind k) => switch (k) {
    ActivityKind.patientAdded => (CruIcons.userPlus, CruTileTone.neutral),
    ActivityKind.fileAdded => (CruIcons.fileText, CruTileTone.teal),
    ActivityKind.consultDone => (CruIcons.check, CruTileTone.green),
    ActivityKind.booked => (CruIcons.calendar, CruTileTone.neutral),
    ActivityKind.cancelled => (CruIcons.close, CruTileTone.neutral),
    ActivityKind.missed => (CruIcons.warning, CruTileTone.amber),
    ActivityKind.homeVisitDone => (CruIcons.home, CruTileTone.green),
    ActivityKind.paid => (CruIcons.rupee, CruTileTone.green),
    ActivityKind.expense => (CruIcons.wallet, CruTileTone.neutral),
    ActivityKind.unpaid => (CruIcons.rupee, CruTileTone.amber),
    ActivityKind.restocked => (CruIcons.box, CruTileTone.teal),
    ActivityKind.noteSaved => (CruIcons.mic, CruTileTone.neutral),
    ActivityKind.memberJoined => (CruIcons.user, CruTileTone.neutral),
    ActivityKind.radStudy => (CruIcons.scan, CruTileTone.neutral),
    ActivityKind.radSigned => (CruIcons.pen, CruTileTone.green),
    ActivityKind.reminderFailed => (CruIcons.warning, CruTileTone.amber),
    ActivityKind.replied => (CruIcons.whatsapp, CruTileTone.neutral),
    ActivityKind.optedOut => (CruIcons.whatsapp, CruTileTone.neutral),
    ActivityKind.optedIn => (CruIcons.whatsapp, CruTileTone.neutral),
  };
}

/// A titled group of rows, spaced out rather than ruled.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s12,
              0,
              CruSpace.s12,
              CruSpace.s4,
            ),
            child: Text(title, style: CruType.groupLabel.tint(c.label3)),
          ),
          ...rows,
        ],
      ),
    );
  }
}

/// One notification: tile or monogram, what happened and who on one line
/// each, and when on the right (with a dot if it's new), or an action.
/// The whole row opens what it's about.
class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.unread = false,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;

  /// "5m ago", on the right.
  final String? meta;
  final bool unread;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: [title, ?subtitle, ?meta, if (unread) 'new'].join(', '),
      builder: (context, hovered) => DecoratedBox(
        decoration: ShapeDecoration(
          color: hovered && onTap != null ? c.hoverFill : Colors.transparent,
          shape: cruShape(CruRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: CruSpace.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CruType.callout.tabular.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        subtitle!,
                        style: CruType.subhead.tabular.tint(c.label2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (meta != null) ...[
                const SizedBox(width: CruSpace.s16),
                Text(meta!, style: CruType.caption.tabular.tint(c.label3)),
              ],
              if (unread) ...[
                const SizedBox(width: CruSpace.s8),
                const _NewDot(),
              ],
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s16),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Nothing new".
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CruSpace.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(mobileBellIcon, size: 28, color: c.label3),
            const SizedBox(height: CruSpace.s12),
            Text('Nothing new', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(
              'New patients, files, payments, bookings and replies show '
              'up here.',
              textAlign: TextAlign.center,
              style: CruType.subhead.tint(c.label2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small "new" dot: something happened since Notifications was last
/// opened.
class _NewDot extends StatelessWidget {
  const _NewDot();

  @override
  Widget build(BuildContext context) => Container(
    width: CruSpace.s8,
    height: CruSpace.s8,
    decoration: BoxDecoration(
      color: context.cru.accent,
      shape: BoxShape.circle,
    ),
  );
}
