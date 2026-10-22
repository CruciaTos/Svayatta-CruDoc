import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/feature_usage_service.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';

/// The tour's version. Bumping it shows the tour again to everyone (for a
/// big redesign); records at an older version count as not seen.
const int kTutorialVersion = 1;

/// Accounts set up before this date used the app before the tour existed,
/// so it doesn't open on its own for them (they can still start it from
/// Settings). Keep it at the day the tour ships.
final DateTime kTutorialReleaseCutoff = DateTime.utc(2026, 10, 22);

enum TutorialOutcome { completed, skipped }

/// What is saved when a tour ends.
@immutable
class TutorialRecord {
  const TutorialRecord({
    required this.outcome,
    required this.lastStep,
    this.version = kTutorialVersion,
  });

  final TutorialOutcome outcome;

  /// The step it ended on, numbered as in the full list for the platform
  /// (the welcome card is 1), so numbers stay comparable across roles.
  final int lastStep;
  final int version;
}

/// Where tour records are kept on the server. Swapped out in tests.
abstract interface class TutorialRemote {
  /// [key] is the record's name under `tutorial` (see
  /// [TutorialRepository.recordKey]).
  Future<void> save(String uid, String key, TutorialRecord r);
}

/// `users/{uid}.tutorial.<key>`, merged into the profile the same way
/// onboarding writes it, so nothing else on the profile changes. A replay
/// that finishes adds `completedAt` and keeps an earlier `skippedAt`.
class FirestoreTutorialRemote implements TutorialRemote {
  const FirestoreTutorialRemote();

  @override
  Future<void> save(String uid, String key, TutorialRecord r) =>
      FirebaseFirestore.instance.collection('users').doc(uid).set({
        'tutorial': {
          key: {
            'version': r.version,
            r.outcome == TutorialOutcome.completed
                    ? 'completedAt'
                    : 'skippedAt':
                FieldValue.serverTimestamp(),
            'lastStep': r.lastStep,
          },
        },
      }, SetOptions(merge: true));
}

/// Reads and writes whether someone has seen the tour: the profile in
/// Firestore, mirrored to shared_preferences so the tour never flashes
/// while the profile loads and works offline. Either saying "seen" wins.
/// Demo sessions keep it in memory only, per session.
class TutorialRepository {
  TutorialRepository({
    TutorialRemote remote = const FirestoreTutorialRemote(),
    String? Function()? currentUid,
    DateTime? Function()? accountCreatedAt,
    bool Function()? isDemo,
    int Function()? demoSession,
    void Function(String event)? log,
  }) : _remote = remote,
       _uid = currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _createdAt =
           accountCreatedAt ??
           (() => FirebaseAuth.instance.currentUser?.metadata.creationTime),
       _isDemo = isDemo ?? (() => DemoSessionService.isDemoMode),
       _demoSession =
           demoSession ??
           (() => DemoSessionService.sessionRevisionNotifier.value),
       _log = log ?? _logUsage;

  final TutorialRemote _remote;
  final String? Function() _uid;
  final DateTime? Function() _createdAt;
  final bool Function() _isDemo;
  final int Function() _demoSession;
  final void Function(String event) _log;

  /// `session:platform` keys of demo tours seen in this run of the app.
  final Set<String> _demoSeen = {};

  static void _logUsage(String event) =>
      unawaited(FeatureUsageService.log(event).catchError((_) {}));

  /// The record's name under `tutorial`: `desktop` and `mobile` for the
  /// app tours, `voiceDesktop` and `voiceMobile` for the voice ones.
  static String recordKey(
    TutorialPlatform platform, [
    TutorialTour tour = TutorialTour.app,
  ]) => switch (tour) {
    TutorialTour.app => platform.name,
    TutorialTour.voice =>
      'voice${platform.name[0].toUpperCase()}${platform.name.substring(1)}',
  };

  static String prefsKey(
    String uid,
    TutorialPlatform platform, [
    TutorialTour tour = TutorialTour.app,
    int version = kTutorialVersion,
  ]) => 'crudoc.tutorial.$uid.${recordKey(platform, tour)}.v$version';

  /// Whether [profile] holds a record for [platform] at the current
  /// version. A record is only written when a tour ends, so its version
  /// is enough (its timestamp reads null until the server sets it).
  static bool profileHasRecord(
    Map<String, dynamic>? profile,
    TutorialPlatform platform, [
    TutorialTour tour = TutorialTour.app,
  ]) {
    final tutorial = profile?['tutorial'];
    if (tutorial is! Map) return false;
    final record = tutorial[recordKey(platform, tour)];
    if (record is! Map) return false;
    final version = record['version'];
    return version is num && version >= kTutorialVersion;
  }

  /// Someone who used CruDoc before the tour shipped: onboarding finished
  /// before [cutoff], or (no onboarding: clinic members, older accounts)
  /// the account itself is older.
  static bool isExistingUser({
    Map<String, dynamic>? profile,
    DateTime? accountCreatedAt,
    DateTime? cutoff,
  }) {
    final before = cutoff ?? kTutorialReleaseCutoff;
    final onboarding = profile?['onboarding'];
    if (onboarding is Map) {
      final completed = _date(onboarding['completedAt']);
      // Just finished: the server time isn't back yet.
      return completed != null && completed.isBefore(before);
    }
    final created = accountCreatedAt ?? _date(profile?['createdAt']);
    return created != null && created.isBefore(before);
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp t => t.toDate(),
    DateTime d => d,
    _ => null,
  };

  /// The local mirror only: true means "seen", no need to wait for the
  /// profile. Never true in a demo before the tour has run in it.
  Future<bool> seenLocally(
    TutorialPlatform platform, [
    TutorialTour tour = TutorialTour.app,
  ]) async {
    if (_isDemo()) return _demoSeen.contains(_demoKey(platform, tour));
    final uid = _uid();
    if (uid == null) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefsKey(uid, platform, tour)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether the tour should stay closed on its own: seen at this version
  /// (here or in [profile]), or, for the app tour, someone who used the app
  /// before it. The voice tour only follows a finished app tour, so it
  /// goes by its own record alone.
  Future<bool> hasSeen(
    TutorialPlatform platform, {
    Map<String, dynamic>? profile,
    TutorialTour tour = TutorialTour.app,
  }) async {
    if (_isDemo()) return _demoSeen.contains(_demoKey(platform, tour));
    if (await seenLocally(platform, tour)) return true;
    if (profileHasRecord(profile, platform, tour)) return true;
    if (tour == TutorialTour.voice) return false;
    return isExistingUser(profile: profile, accountCreatedAt: _createdAt());
  }

  /// Saves how a tour ended. A replay that is skipped changes nothing
  /// (its `skippedAt` stays as it was); one that finishes sets
  /// `completedAt`.
  Future<void> record(
    TutorialPlatform platform,
    TutorialOutcome outcome, {
    required int lastStep,
    bool replay = false,
    TutorialTour tour = TutorialTour.app,
  }) async {
    if (replay && outcome == TutorialOutcome.skipped) return;
    if (_isDemo()) {
      _demoSeen.add(_demoKey(platform, tour));
      return;
    }
    final uid = _uid();
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey(uid, platform, tour), true);
    } catch (_) {}
    try {
      await _remote.save(
        uid,
        recordKey(platform, tour),
        TutorialRecord(outcome: outcome, lastStep: lastStep),
      );
    } catch (e) {
      // Offline: Firestore queues the write; the local mirror already
      // keeps the tour closed.
      debugPrint('Could not save the tour record: $e');
    }
  }

  /// Usage events (tutorial_started, tutorial_completed,
  /// tutorial_skipped_step_N; voice_tutorial_… for the voice tour),
  /// counted per user like feature opens.
  /// Demo sessions log nothing (FeatureUsageService skips them).
  void logEvent(String event) => _log(event);

  String _demoKey(TutorialPlatform platform, TutorialTour tour) =>
      '${_demoSession()}:${recordKey(platform, tour)}';
}

final tutorialRepositoryProvider = Provider<TutorialRepository>(
  (ref) => TutorialRepository(),
);
