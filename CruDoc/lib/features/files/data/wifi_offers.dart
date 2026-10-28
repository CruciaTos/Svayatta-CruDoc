import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_offer_model.dart';
import 'file_offers_repository.dart';
import '../lan/lan_server.dart';

/// Wi-Fi offers travel only over clinic Wi-Fi, whenever both devices are on
/// it, so a send never waits for the colleague.
///
/// - As sender: every Wi-Fi offer still waiting is served by this device's
///   Wi-Fi server, also after a restart.
/// - As recipient: every Wi-Fi offer downloads by itself as soon as the
///   sender answers on this Wi-Fi (checked every 30 s and when the network
///   changes). They only ever come from colleagues in your own clinic.
/// - On Android, while files wait either way, a quiet notification keeps
///   the app running in the background, so phones send and receive without
///   CruDoc open.
class _WaitingNotice {
  static const _id = 4711;
  static const _channel = 'crudoc_wifi_waiting';
  static bool _on = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  static Future<void> show(int incoming, int outgoing) async {
    if (!Platform.isAndroid) return;
    final parts = [
      if (incoming > 0) '$incoming to receive',
      if (outgoing > 0) '$outgoing to send',
    ];
    try {
      await _android?.startForegroundService(
        id: _id,
        title: 'Files waiting for clinic Wi-Fi',
        body: parts.join(' · '),
        notificationDetails: const AndroidNotificationDetails(
          _channel,
          'Files waiting for Wi-Fi',
          channelDescription:
              'Keeps CruDoc ready to send and receive files on clinic Wi-Fi.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
        ),
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _on = true;
    } catch (e) {
      debugPrint('[WifiOffers] waiting notice: $e');
    }
  }

  static Future<void> hide() async {
    if (!Platform.isAndroid || !_on) return;
    _on = false;
    try {
      await _android?.stopForegroundService();
    } catch (e) {
      debugPrint('[WifiOffers] waiting notice: $e');
    }
  }
}

/// Runs Wi-Fi offers (see the library comment above [_WaitingNotice]).
class WifiOffers {
  WifiOffers._();
  static final WifiOffers instance = WifiOffers._();

  static const _every = Duration(seconds: 30);
  static const _waitingKey = 'crudoc.files.wifiWaiting';

  StreamSubscription<List<FileOffer>>? _sentSub;
  StreamSubscription<List<FileOffer>>? _incomingSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _timer;
  List<FileOffer> _incoming = const [];
  final Set<String> _served = {};
  bool _trying = false;
  void Function(String offerId)? _onReceived;

  void start({
    required String clinicId,
    required String uid,
    void Function(String offerId)? onReceived,
  }) {
    stop();
    _onReceived = onReceived;
    final repo = FileOffersRepository.instance;
    _sentSub = repo
        .watchSentOffers(clinicId: clinicId, myUid: uid)
        .listen(
          _serve,
          onError: (Object e) => debugPrint('[WifiOffers] sent: $e'),
        );
    _incomingSub = repo
        .watchIncomingOffers(clinicId: clinicId, myUid: uid)
        .listen((list) {
          _incoming = list;
          _updateNotice();
          unawaited(_tryWaiting());
        }, onError: (Object e) => debugPrint('[WifiOffers] incoming: $e'));
    _timer = Timer.periodic(_every, (_) => unawaited(_tryWaiting()));
    _netSub = Connectivity().onConnectivityChanged.listen(
      (_) => Future.delayed(const Duration(seconds: 2), _tryWaiting),
    );
  }

  void stop() {
    _sentSub?.cancel();
    _incomingSub?.cancel();
    _netSub?.cancel();
    _timer?.cancel();
    _sentSub = _incomingSub = null;
    _netSub = null;
    _timer = null;
    _incoming = const [];
    unawaited(_WaitingNotice.hide());
    for (final id in _served) {
      LanServer.instance.unregisterOpenOffer(id);
    }
    _served.clear();
  }

  /// Keeps this device's waiting Wi-Fi offers downloadable.
  void _serve(List<FileOffer> sent) {
    final open = {
      for (final o in sent)
        if (o.via == FileOfferVia.lan && o.status == FileOfferStatus.sent)
          o.id: o,
    };
    for (final id in _served.difference(open.keys.toSet())) {
      LanServer.instance.unregisterOpenOffer(id);
    }
    for (final o in open.values) {
      LanServer.instance.registerOpenOffer(o);
    }
    _served
      ..clear()
      ..addAll(open.keys);
    _updateNotice();
  }

  int get _waitingIn => _incoming
      .where(
        (o) => o.via == FileOfferVia.lan && o.status == FileOfferStatus.sent,
      )
      .length;

  void _updateNotice() {
    final inCount = _waitingIn;
    final outCount = _served.length;
    if (inCount + outCount == 0) {
      unawaited(_WaitingNotice.hide());
    } else {
      unawaited(_WaitingNotice.show(inCount, outCount));
    }
  }

  /// [offer] was accepted while its sender isn't on this Wi-Fi: it
  /// downloads once they are.
  Future<void> wait(FileOffer offer) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = {...prefs.getStringList(_waitingKey) ?? const <String>[]};
    if (ids.add(offer.id)) await prefs.setStringList(_waitingKey, [...ids]);
  }

  Future<void> _tryWaiting() async {
    if (_trying || _incoming.isEmpty) return;
    _trying = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final waiting = {...prefs.getStringList(_waitingKey) ?? const <String>[]};
      final due = [
        for (final o in _incoming)
          if (o.via == FileOfferVia.lan && o.status == FileOfferStatus.sent) o,
      ];
      final unreachable = <String>{};
      for (final o in due) {
        // One failed handshake per sender is enough for this round.
        if (unreachable.contains(o.from)) continue;
        try {
          await FileOffersRepository.instance.acceptOffer(o);
          waiting.remove(o.id);
          _onReceived?.call(o.id);
        } on SenderNotOnWifiException {
          unreachable.add(o.from);
        } catch (e) {
          debugPrint('[WifiOffers] receive ${o.id}: $e');
        }
      }
      // Forget offers no longer waiting (received, declined, cancelled).
      final live = {for (final o in _incoming) o.id};
      waiting.removeWhere((id) => !live.contains(id));
      await prefs.setStringList(_waitingKey, [...waiting]);
    } finally {
      _trying = false;
    }
  }
}
