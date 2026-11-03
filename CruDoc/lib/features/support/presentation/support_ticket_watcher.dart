import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/push_notifications.dart';

/// A bug report or feedback this doctor sent, as far as the watcher cares.
@immutable
class WatchedTicket {
  const WatchedTicket({
    required this.id,
    required this.status,
    this.category = 'bug',
    this.resolution = '',
  });

  final String id;
  final String status;
  final String category;
  final String resolution;

  bool get isResolved => status == 'resolved';

  /// Same wording as the push (functions/src/support_tickets.ts).
  ({String title, String body}) get news => (
    title: category == 'feedback'
        ? 'Your feedback was looked at'
        : 'Your issue is resolved',
    body: resolution.trim().isEmpty
        ? 'Thanks for letting us know.'
        : resolution.trim(),
  );
}

/// The resolved tickets to tell the doctor about now. Adds every resolved
/// ticket to [announced] whether or not it is shown, so each is news once.
///
/// [fresh]: nothing was ever announced on this device, so tickets already
/// resolved are history, not news. [phone]: the push covers a phone, so it
/// only shows tickets it saw resolved while open ([seenOpen] holds the ids
/// it saw unresolved earlier this session); a desktop has no push and shows
/// any resolved ticket it hasn't announced yet.
List<WatchedTicket> ticketsToAnnounce(
  List<WatchedTicket> tickets, {
  required Set<String> announced,
  required Set<String> seenOpen,
  required bool fresh,
  required bool phone,
}) {
  final out = <WatchedTicket>[];
  for (final t in tickets) {
    if (!t.isResolved) {
      seenOpen.add(t.id);
      continue;
    }
    if (!announced.add(t.id)) continue;
    if (fresh) continue;
    if (phone && !seenOpen.contains(t.id)) continue;
    out.add(t);
  }
  return out;
}

/// Shows a notification when the Super Admin resolves a bug report or
/// feedback this doctor sent. Phones also get a push from the server
/// (onSupportTicketResolved) when the app is closed.
class SupportTicketWatcher extends ConsumerStatefulWidget {
  const SupportTicketWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SupportTicketWatcher> createState() =>
      _SupportTicketWatcherState();
}

class _SupportTicketWatcherState extends ConsumerState<SupportTicketWatcher>
    with WidgetsBindingObserver {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  final Set<String> _announced = {};
  final Set<String> _seenOpen = {};
  bool _fresh = false;
  bool _foreground = true;

  static bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // There is no tickets screen to open: tapping just brings the app up.
    PushNotifications.instance.setRoute('support_ticket', _noRoute);
    ref.listenManual(
      authStateProvider,
      (_, next) => _watch(next.value?.uid),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotifications.instance.clearRoute('support_ticket', _noRoute);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  static void _noRoute(Map<String, dynamic> data) {}

  String _key(String uid) => 'support.resolvedAnnounced.$uid';

  Future<void> _watch(String? uid) async {
    if (uid == _uid) return;
    await _sub?.cancel();
    _sub = null;
    _uid = uid;
    _announced.clear();
    _seenOpen.clear();
    if (uid == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key(uid));
      _fresh = saved == null;
      _announced.addAll(saved ?? const []);
    } catch (_) {
      _fresh = true;
    }
    if (_uid != uid || !mounted) return;

    _sub = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('doctorId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) => _onTickets(uid, snap),
          onError: (Object e) =>
              debugPrint('[SupportTicketWatcher] listen failed: $e'),
        );
  }

  Future<void> _onTickets(
    String uid,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_uid != uid) return;
    final tickets = [
      for (final d in snap.docs)
        WatchedTicket(
          id: d.id,
          status: d.data()['status'] as String? ?? '',
          category: d.data()['category'] as String? ?? 'bug',
          resolution: d.data()['resolution'] as String? ?? '',
        ),
    ];
    final news = ticketsToAnnounce(
      tickets,
      announced: _announced,
      seenOpen: _seenOpen,
      fresh: _fresh,
      phone: _phone,
    );
    // A first answer from the offline cache may not hold every ticket yet.
    if (!snap.metadata.isFromCache) _fresh = false;
    for (final t in news) {
      if (_phone && !_foreground) continue;
      await PushNotifications.instance.show(
        id: 'support:${t.id}'.hashCode & 0x7fffffff,
        title: t.news.title,
        body: t.news.body,
        data: {'type': 'support_ticket', 'ticketId': t.id},
      );
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _announced.toList();
      await prefs.setStringList(
        _key(uid),
        list.length > 200 ? list.sublist(list.length - 200) : list,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
