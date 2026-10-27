import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity.dart';
import 'lan_device_model.dart';
import 'lan_ip_helper.dart';

/// Manages registration, discovery and presence of trusted devices in Firestore (Tasks K2, K3).
class DeviceRegistryService {
  DeviceRegistryService._();
  static final DeviceRegistryService instance = DeviceRegistryService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String _activeClinicId = '';
  int _activePort = 0;
  List<LanDevice> _cachedDevices = [];

  List<LanDevice> get cachedDevices => List.unmodifiable(_cachedDevices);

  /// Initializes registration and starts watching connectivity changes to refresh presence.
  Future<void> start({
    required String clinicId,
    required String myUid,
    required int port,
  }) async {
    _activeClinicId = clinicId;
    _activePort = port;

    await DeviceIdentity.instance.initialize();
    await _loadCachedDevices(clinicId);

    await ensureRegistered(clinicId: clinicId, myUid: myUid);
    await updatePresence(clinicId: clinicId, port: port);

    // Watch connectivity changes
    await _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) async {
      if (_activeClinicId.isNotEmpty && _activePort > 0) {
        await updatePresence(clinicId: _activeClinicId, port: _activePort);
      }
    });
  }

  /// Ensures this device has an up-to-date doc in `clinics/{clinicId}/devices/{deviceId}`.
  Future<void> ensureRegistered({
    required String clinicId,
    required String myUid,
  }) async {
    if (clinicId.isEmpty || myUid.isEmpty) return;

    final id = DeviceIdentity.instance;
    final docRef = _firestore
        .collection('clinics')
        .doc(clinicId)
        .collection('devices')
        .doc(id.deviceId);

    try {
      final snap = await docRef.get();
      if (!snap.exists) {
        final ips = await LanIpHelper.getLocalIpv4Addresses();
        await docRef.set({
          'uid': myUid,
          'name': id.deviceName,
          'platform': id.platform,
          'certPem': id.certPem,
          'certSha256': id.certSha256,
          'lan': {
            'ips': ips,
            'port': _activePort,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'lastSeenAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.update({
          'name': id.deviceName,
          'lastSeenAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[DeviceRegistry] Failed to ensure registered: $e');
    }
  }

  /// Publishes local IP addresses and listening port to Firestore.
  Future<void> updatePresence({
    required String clinicId,
    required int port,
  }) async {
    if (clinicId.isEmpty) return;

    _activePort = port;
    final ips = await LanIpHelper.getLocalIpv4Addresses();
    final deviceId = DeviceIdentity.instance.deviceId;

    try {
      await _firestore
          .collection('clinics')
          .doc(clinicId)
          .collection('devices')
          .doc(deviceId)
          .update({
        'lan': {
          'ips': ips,
          'port': port,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[DeviceRegistry] Update presence error (will retry): $e');
    }
  }

  /// Real-time stream of all registered devices in the clinic.
  Stream<List<LanDevice>> watchDevices(String clinicId) {
    if (clinicId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('clinics')
        .doc(clinicId)
        .collection('devices')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => LanDevice.fromFirestore(
                id: d.id,
                clinicId: clinicId,
                data: d.data(),
              ))
          .toList();

      _cachedDevices = list;
      _saveCachedDevices(clinicId, list);
      return list;
    });
  }

  /// Removes a registered device doc.
  Future<void> removeDevice({
    required String clinicId,
    required String deviceId,
  }) async {
    if (clinicId.isEmpty || deviceId.isEmpty) return;
    await _firestore
        .collection('clinics')
        .doc(clinicId)
        .collection('devices')
        .doc(deviceId)
        .delete();
  }

  /// Finds a colleague device by their UID with reachable subnet IPs.
  Future<LanDevice?> findColleagueDevice({
    required String clinicId,
    required String colleagueUid,
  }) async {
    // 1. Look in cached or active devices
    final devices = _cachedDevices.where((d) => d.uid == colleagueUid).toList();
    if (devices.isEmpty) return null;

    final myIps = await LanIpHelper.getLocalIpv4Addresses();

    // Prefer device sharing same subnet
    for (final dev in devices) {
      final matching = LanIpHelper.matchingSubnetIps(myIps: myIps, peerIps: dev.ips);
      if (matching.isNotEmpty && dev.port > 0) {
        return dev;
      }
    }

    // Fallback: any device of colleague with an endpoint
    return devices.where((d) => d.hasLanEndpoint).firstOrNull;
  }

  // ────────────── Offline Cache (Phase 5, Task M2) ──────────────

  static const _cachePrefix = 'crudoc.lan.cached_devices.';

  Future<void> _saveCachedDevices(String clinicId, List<LanDevice> devices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = devices.map((d) => {
        'id': d.id,
        'uid': d.uid,
        'name': d.name,
        'platform': d.platform,
        'certPem': d.certPem,
        'certSha256': d.certSha256,
        'ips': d.ips,
        'port': d.port,
        'savedAt': DateTime.now().toIso8601String(),
      }).toList();

      await prefs.setString('$_cachePrefix$clinicId', jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _loadCachedDevices(String clinicId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('$_cachePrefix$clinicId');
      if (str == null || str.isEmpty) return;

      final List<dynamic> decoded = jsonDecode(str);
      final list = <LanDevice>[];
      final now = DateTime.now();

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final savedAt = DateTime.tryParse(item['savedAt'] as String? ?? '');
        // Cache expires after 7 days (7-day rule, Task M2)
        if (savedAt == null || now.difference(savedAt).inDays > 7) continue;

        list.add(LanDevice(
          id: item['id'] as String? ?? '',
          clinicId: clinicId,
          uid: item['uid'] as String? ?? '',
          name: item['name'] as String? ?? '',
          platform: item['platform'] as String? ?? '',
          certPem: item['certPem'] as String? ?? '',
          certSha256: item['certSha256'] as String? ?? '',
          ips: List<String>.from(item['ips'] as List? ?? []),
          port: (item['port'] as num? ?? 0).toInt(),
        ));
      }
      if (list.isNotEmpty) {
        _cachedDevices = list;
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
