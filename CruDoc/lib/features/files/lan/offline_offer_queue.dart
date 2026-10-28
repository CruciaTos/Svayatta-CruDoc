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
  Future<void> enqueue(FileOffer offer) => enqueueAll([offer]);

  /// Adds [offers] in one write. Wi-Fi sends queue their offers until the
  /// server has them: Firestore keeps a pending write in memory only
  /// (persistence is off), so a restart would otherwise lose it.
  Future<void> enqueueAll(List<FileOffer> offers) => _serial(() async {
    if (offers.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadQueue(prefs);
      list.addAll([for (final o in offers) o.toJson()]);
      await prefs.setString(_queueKey, jsonEncode(list));
      debugPrint(
        '[OfflineOfferQueue] Queued ${offers.length} offer(s) for sync',
      );
    } catch (e) {
      debugPrint('[OfflineOfferQueue] Enqueue error: $e');
    }
  });

  /// Drops [ids] from the queue: the server has them.
  Future<void> remove(Iterable<String> ids) => _serial(() async {
    final drop = ids.toSet();
    if (drop.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadQueue(prefs);
      list.removeWhere((item) => drop.contains(item['id']));
      if (list.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setString(_queueKey, jsonEncode(list));
      }
    } catch (e) {
      debugPrint('[OfflineOfferQueue] Remove error: $e');
    }
  });

  bool _flushing = false;

  /// Flushes all queued offers to Firestore when connectivity is restored.
  /// One write per offer: an offer that already reached the server (or was
  /// answered since) is refused by the rules, which means it is done, and
  /// must not hold back the others.
  Future<void> flushQueue(String clinicId) async {
    if (clinicId.isEmpty || _flushing) return;
    _flushing = true;
    final done = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadQueue(prefs);
      if (list.isEmpty) return;

      final collection = FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('file_offers');

      for (final item in list) {
        final id = item['id'] as String? ?? '';
        if (id.isEmpty) continue;
        // Back to Firestore types (Timestamps, so the TTL on expireAt works).
        final offer = FileOffer.fromFirestore(
          id: id,
          clinicId: clinicId,
          data: item,
        );
        try {
          await collection.doc(id).set(offer.toFirestore());
          done.add(id);
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          done.add(id);
        }
      }
      debugPrint('[OfflineOfferQueue] Flushed ${done.length} offline offers');
    } catch (e) {
      debugPrint('[OfflineOfferQueue] Flush error (will retry): $e');
    } finally {
      await remove(done);
      _flushing = false;
    }
  }

  Future<void> _lock = Future.value();

  /// Runs [task] after the queue's other reads and writes, so two of them
  /// never overwrite each other's list.
  Future<void> _serial(Future<void> Function() task) {
    final next = _lock.then((_) => task());
    _lock = next.catchError((_) {});
    return next;
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
