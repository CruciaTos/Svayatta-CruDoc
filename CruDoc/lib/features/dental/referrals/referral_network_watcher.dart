import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/push_notifications.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_share_flows.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';

/// What to tell a doctor about [share] now that it is in its current
/// status, or null when there is nothing to say. [incoming]: they are the
/// doctor it was sent to.
({String title, String body})? referralNews(
  ReferralShare share, {
  required bool incoming,
}) {
  if (incoming) {
    final from = drName(share.senderName);
    return switch (share.status) {
      ReferralStatus.sent => (
        title:
            '${share.urgency == ReferralUrgency.urgent ? 'Urgent: ' : ''}'
            'New referral from $from',
        body: share.reason.isEmpty ? 'Open Referrals to see it.' : share.reason,
      ),
      ReferralStatus.withdrawn => (
        title: '$from withdrew a referral',
        body: 'The patient\'s details are no longer shared.',
      ),
      _ => null,
    };
  }
  final to = drName(share.recipientName);
  final what = switch (share.status) {
    ReferralStatus.acknowledged => 'accepted your referral',
    ReferralStatus.seen => 'has seen your patient',
    ReferralStatus.completed => 'completed your referral',
    ReferralStatus.declined => 'declined your referral',
    _ => null,
  };
  if (what == null) return null;
  return (
    title: '$to $what',
    body: share.reply.isNotEmpty ? share.reply : share.reason,
  );
}

/// Keeps an eye on referrals sent to and from this doctor in CruDoc while
/// the app runs: shows a notification for each new one and each answer,
/// keeps this device registered for pushes, copies the other doctor's
/// progress into the local referral (so the rest of the clinic sees it),
/// and opens Referrals when a notification is tapped.
class ReferralNetworkWatcher extends ConsumerStatefulWidget {
  const ReferralNetworkWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReferralNetworkWatcher> createState() =>
      _ReferralNetworkWatcherState();
}

class _ReferralNetworkWatcherState extends ConsumerState<ReferralNetworkWatcher>
    with WidgetsBindingObserver {
  /// "shareId:status" already announced on this device, for [_uid].
  final Set<String> _announced = {};
  String? _uid;
  Future<void>? _loading;

  /// Nothing was announced on this device before: the referrals already
  /// there when each stream first arrives are not news.
  bool _freshDevice = false;
  final Set<bool> _streamsSeen = {};
  bool _foreground = true;

  /// On a phone a closed or backgrounded app gets the push instead.
  static bool get _phone => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotifications.instance.onOpen = _openReferrals;
    // Closed with the widget.
    ref.listenManual(authStateProvider, (_, next) {
      final uid = next.value?.uid;
      if (uid != null) PushNotifications.instance.register(uid);
    }, fireImmediately: true);
    ref.listenManual(
      incomingSharesProvider,
      (_, next) => _onShares(next.value, true),
      fireImmediately: true,
    );
    ref.listenManual(
      outgoingSharesProvider,
      (_, next) => _onShares(next.value, false),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (PushNotifications.instance.onOpen == _openReferrals) {
      PushNotifications.instance.onOpen = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void _openReferrals() {
    if (!mounted) return;
    final shell = ref.read(shellNavigatorProvider);
    if (shell != null && shell(DesktopTab.dentalReferrals)) return;
    openMobileDestination(context, DesktopTab.dentalReferrals);
  }

  String _key(String uid) => 'referrals.announced.$uid';

  /// Loads what was announced for [uid], once, whichever stream asks first.
  Future<void> _load(String uid) {
    if (_uid != uid) {
      _uid = uid;
      _announced.clear();
      _streamsSeen.clear();
      _loading = () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final saved = prefs.getStringList(_key(uid));
          _freshDevice = saved == null;
          _announced.addAll(saved ?? const []);
        } catch (_) {
          _freshDevice = true;
        }
      }();
    }
    return _loading!;
  }

  Future<void> _save(String uid, Set<String> announced) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = announced.toList();
      await prefs.setStringList(
        _key(uid),
        list.length > 500 ? list.sublist(list.length - 500) : list,
      );
    } catch (_) {}
  }

  Future<void> _onShares(List<ReferralShare>? shares, bool incoming) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (shares == null || uid == null) return;
    await _copyIntoLocal(shares);

    await _load(uid);
    if (_uid != uid) return;
    final baseline = _freshDevice && !_streamsSeen.contains(incoming);
    _streamsSeen.add(incoming);
    for (final s in shares) {
      final key = '${s.id}:${s.status.name}';
      if (!_announced.add(key)) continue;
      final news = referralNews(s, incoming: incoming);
      if (baseline || news == null || (_phone && !_foreground)) continue;
      await PushNotifications.instance.show(
        id: key.hashCode & 0x7fffffff,
        title: news.title,
        body: news.body,
      );
    }
    await _save(uid, _announced);
  }

  /// Copies the other doctor's progress into the local referral it belongs
  /// to, so the rest of the clinic, who can't read the share, sees it too.
  Future<void> _copyIntoLocal(List<ReferralShare> shares) async {
    final records =
        ref.read(clinicRecordsProvider(RecKind.referral)).value ??
        const <DentalRecord>[];
    for (final s in shares) {
      final record = records.where((r) => r.str('shareId') == s.id).firstOrNull;
      if (record == null) continue;
      final history = [for (final h in s.history) h.toJson()];
      if (record.str('status') == s.status.name &&
          record.str('reply') == s.reply &&
          (record.data['history'] as List?)?.length == history.length) {
        continue;
      }
      await saveDentalRecord(
        ref,
        record.copyWith(
          data: {
            ...record.data,
            'status': s.status.name,
            'reply': s.reply,
            'history': history,
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
