import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Starts Firestore afresh between two people signing in on the same
/// Windows PC.
///
/// Without it Firestore froze for good when a second account signed in, and
/// its cache kept the previous person's results: a doctor limited to their
/// assigned patients could be answered from the front desk's cached list
/// (see integration_test/account_switch_credentials_test.dart). So after
/// every sign-out the client is shut down and its cache deleted, and every
/// sign-in waits for that to finish.
class FirestoreAccountReset {
  FirestoreAccountReset._();

  static Future<void> _last = Future<void>.value();

  /// Starts a reset after the last one, once [after] (what still uses
  /// Firestore) has finished. Does nothing off Windows.
  static Future<void> start({Future<void>? after}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return _last;
    }
    return _last = _last.then((_) async {
      try {
        await after?.timeout(const Duration(seconds: 15));
      } catch (error) {
        debugPrint('Shutting down Firestore without waiting: $error');
      }
      await _reset();
    });
  }

  /// Completes once every reset started so far has finished. Await this
  /// before signing anyone in.
  static Future<void> get done => _last;

  /// Never throws, so one failure can't block later sign-ins.
  static Future<void> _reset() async {
    final firestore = FirebaseFirestore.instance;
    final started = DateTime.now();
    // The signed-out person's screens are still closing and dropping their
    // listeners.
    await Future<void>.delayed(_settle);
    try {
      await firestore.terminate().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('Could not shut down Firestore after sign-out: $error');
      return;
    }
    // Starting a new client straight after the old one shut down left it
    // offline on Windows (it never reconnected, and the next sign-in then
    // read as "user does not exist" and crashed). A short pause avoids it.
    await Future<void>.delayed(_settle);
    var cleared = false;
    try {
      await firestore.clearPersistence().timeout(const Duration(seconds: 10));
      cleared = true;
    } catch (error) {
      debugPrint('Could not clear the Firestore cache after sign-out: $error');
    }
    await Future<void>.delayed(_settle);
    final online = await _reachable(firestore);
    debugPrint(
      'Firestore reset after sign-out in '
      '${DateTime.now().difference(started).inMilliseconds}ms '
      '(cache ${cleared ? 'cleared' : 'NOT cleared'}, '
      'server ${online ? 'reachable' : 'NOT reachable'})',
    );
  }

  static const _settle = Duration(seconds: 2);

  /// Whether a server read gets an answer (a refusal counts) within
  /// [limit]. Gives up so a clinic that really is offline can still sign in.
  static Future<bool> _reachable(
    FirebaseFirestore firestore, {
    Duration limit = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(limit);
    while (DateTime.now().isBefore(end)) {
      try {
        await firestore
            .collection('users')
            .doc('_reachability_probe')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        return true;
      } on FirebaseException catch (e) {
        if (e.code != 'unavailable') return true;
      } on TimeoutException {
        // Still connecting.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}
