import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/files/data/file_offer_model.dart';

/// Queues file offers made offline for eventual sync to Firestore (Tasks M3, M4).
class OfflineOfferQueue {
  OfflineOfferQueue._();
  static final OfflineOfferQueue instance = OfflineOfferQueue._();

  static const String _queueKey = 'crudoc.lan.offline_offers_queue';
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  String _activeClinicId = '';

  void start({required String clinicId}) {
    _activeClinicId = clinicId;
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(flushQueue(_activeClinicId));
      }
    });
    unawaited(flushQueue(_activeClinicId));
  }

  /// Adds an offer to the offline queue when no internet connection is available.
  Future<void> enqueue(FileOffer offer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadQueue(prefs);
      list.add(offer.toJson());
      await prefs.setString(_queueKey, jsonEncode(list));
      debugPrint('[OfflineOfferQueue] Queued offer ${offer.id} for sync');
    } catch (e) {
      debugPrint('[OfflineOfferQueue] Enqueue error: $e');
    }
  }

  /// Flushes all queued offers to Firestore when connectivity is restored.
  Future<void> flushQueue(String clinicId) async {
    if (clinicId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadQueue(prefs);
      if (list.isEmpty) return;

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final collection = firestore.collection('clinics').doc(clinicId).collection('file_offers');

      for (final item in list) {
        final id = item['id'] as String? ?? '';
        if (id.isEmpty) continue;
        // Back to Firestore types (Timestamps, so the TTL on expireAt works).
        final offer = FileOffer.fromFirestore(
          id: id,
          clinicId: clinicId,
          data: item,
        );
        batch.set(
          collection.doc(id),
          offer.toFirestore(),
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      await prefs.remove(_queueKey);
      debugPrint('[OfflineOfferQueue] Successfully flushed ${list.length} offline offers');
    } catch (e) {
      debugPrint('[OfflineOfferQueue] Flush error (will retry): $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadQueue(SharedPreferences prefs) async {
    final str = prefs.getString(_queueKey);
    if (str == null || str.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(str);
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  void stop() {
    _connSub?.cancel();
    _connSub = null;
  }
}
