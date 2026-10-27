import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'device_identity.dart';

/// Manages mDNS / DNS-SD advertising and discovery for offline Wi-Fi peer finding (Task M1).
class LanMdnsService {
  LanMdnsService._();
  static final LanMdnsService instance = LanMdnsService._();

  static const String serviceType = '_crudoc._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  bool _isBroadcasting = false;
  bool _isDiscovering = false;

  bool get isBroadcasting => _isBroadcasting;
  bool get isDiscovering => _isDiscovering;

  /// Advertises this device on the local network via mDNS.
  /// The advert carries only `v=1`, the random `deviceId` and the port (no clinic/PHI).
  Future<void> startBroadcast({required int port}) async {
    if (_isBroadcasting || port <= 0) return;

    try {
      final deviceId = DeviceIdentity.instance.deviceId;
      final service = BonsoirService(
        name: 'CruDoc-$deviceId',
        type: serviceType,
        port: port,
        attributes: {
          'v': '1',
          'deviceId': deviceId,
        },
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();
      _isBroadcasting = true;
      debugPrint('[LanMdns] Started broadcasting $serviceType on port $port');
    } catch (e) {
      debugPrint('[LanMdns] Broadcast error: $e');
    }
  }

  /// Stops mDNS advertisement.
  Future<void> stopBroadcast() async {
    if (!_isBroadcasting) return;
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    _isBroadcasting = false;
  }

  /// Starts browsing for `_crudoc._tcp` peers on the local network.
  /// Runs only while Files or Send sheet is open to preserve battery.
  Future<void> startDiscovery({
    required void Function(String deviceId, String host, int port) onPeerDiscovered,
  }) async {
    if (_isDiscovering) return;

    try {
      _discovery = BonsoirDiscovery(type: serviceType);
      await _discovery!.initialize();

      _discoverySub = _discovery!.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            event.service.resolve(_discovery!.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent():
            final service = event.service;
            final deviceId = service.attributes['deviceId'] ?? '';
            final host = service.hostAddresses.firstOrNull ?? '';
            final port = service.port;

            if (deviceId.isNotEmpty && host.isNotEmpty && port > 0) {
              onPeerDiscovered(deviceId, host, port);
            }
          default:
            break;
        }
      });

      await _discovery!.start();
      _isDiscovering = true;
      debugPrint('[LanMdns] Started discovery for $serviceType');
    } catch (e) {
      debugPrint('[LanMdns] Discovery start error: $e');
    }
  }

  /// Stops discovery when Files or Send sheet is closed.
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    try {
      await _discoverySub?.cancel();
      _discoverySub = null;
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
    _isDiscovering = false;
    debugPrint('[LanMdns] Stopped discovery');
  }
}
