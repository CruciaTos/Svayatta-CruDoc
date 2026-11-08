import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:doctor_management_app/features/files/data/wifi_offers.dart';
import 'package:doctor_management_app/features/files/lan/lan_mdns_service.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';

/// iOS suspends the server and the Bonjour advert in the background. When the
/// app is back in front, bring them up again and look for waiting files.
class LanLifecycle with WidgetsBindingObserver {
  LanLifecycle._();
  static final LanLifecycle instance = LanLifecycle._();
  bool _on = false;

  void start() {
    if (_on || !(Platform.isIOS || Platform.isMacOS)) return;
    _on = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_on) return;
    WidgetsBinding.instance.removeObserver(this);
    _on = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    () async {
      final port = await LanServer.instance.start(); // no-op if running
      await LanMdnsService.instance.stopBroadcast();
      await LanMdnsService.instance.startBroadcast(port: port);
      await WifiOffers.instance.checkNow();
    }();
  }
}

