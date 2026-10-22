import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/tutorial/data/tutorial_repository.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';

import 'tutorial_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('profile record', () {
    test('a record at the current version counts as seen', () {
      final profile = {
        'tutorial': {
          'desktop': {'version': kTutorialVersion, 'skippedAt': null},
        },
      };
      expect(
        TutorialRepository.profileHasRecord(profile, TutorialPlatform.desktop),
        isTrue,
      );
      // Each platform has its own record.
      expect(
        TutorialRepository.profileHasRecord(profile, TutorialPlatform.mobile),
        isFalse,
      );
    });

    test('a record from before a version bump does not', () {
      final profile = {
        'tutorial': {
          'desktop': {'version': kTutorialVersion - 1, 'completedAt': 1},
        },
      };
      expect(
        TutorialRepository.profileHasRecord(profile, TutorialPlatform.desktop),
        isFalse,
      );
    });
  });

  group('existing users', () {
    final cutoff = DateTime.utc(2026, 10, 22);

    test('onboarding finished before the release', () {
      expect(
        TutorialRepository.isExistingUser(
          profile: {
            'onboarding': {
              'completedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
            },
          },
          cutoff: cutoff,
        ),
        isTrue,
      );
    });

    test('onboarding just finished (server time pending) is new', () {
      expect(
        TutorialRepository.isExistingUser(
          profile: {
            'onboarding': {'completedAt': null},
          },
          // Even on an old account: they onboarded now.
          accountCreatedAt: DateTime.utc(2025, 1, 1),
          cutoff: cutoff,
        ),
        isFalse,
      );
    });

    test('no onboarding (clinic member): the account age decides', () {
      expect(
        TutorialRepository.isExistingUser(
          profile: {'memberKind': 'staff'},
          accountCreatedAt: DateTime.utc(2025, 6, 1),
          cutoff: cutoff,
        ),
        isTrue,
      );
      expect(
        TutorialRepository.isExistingUser(
          profile: {'memberKind': 'staff'},
          accountCreatedAt: DateTime.utc(2026, 11, 2),
          cutoff: cutoff,
        ),
        isFalse,
      );
    });
  });

  group('record', () {
    test(
      'skipping saves skippedAt and the step, and mirrors locally',
      () async {
        final remote = FakeTutorialRemote();
        final repo = fakeRepository(remote: remote);

        await repo.record(
          TutorialPlatform.desktop,
          TutorialOutcome.skipped,
          lastStep: 3,
        );

        expect(remote.saves, hasLength(1));
        final save = remote.saves.single;
        expect(save.uid, 'u1');
        expect(save.key, 'desktop');
        expect(save.r.outcome, TutorialOutcome.skipped);
        expect(save.r.lastStep, 3);
        expect(save.r.version, kTutorialVersion);
        expect(await repo.seenLocally(TutorialPlatform.desktop), isTrue);
        expect(await repo.seenLocally(TutorialPlatform.mobile), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool(
            TutorialRepository.prefsKey('u1', TutorialPlatform.desktop),
          ),
          isTrue,
        );
      },
    );

    test('a skipped replay writes nothing; a finished one completes', () async {
      final remote = FakeTutorialRemote();
      final repo = fakeRepository(remote: remote);

      await repo.record(
        TutorialPlatform.mobile,
        TutorialOutcome.skipped,
        lastStep: 2,
        replay: true,
      );
      expect(remote.saves, isEmpty);

      await repo.record(
        TutorialPlatform.mobile,
        TutorialOutcome.completed,
        lastStep: 7,
        replay: true,
      );
      expect(remote.saves.single.r.outcome, TutorialOutcome.completed);
    });

    test('demo sessions keep it in memory, per session', () async {
      final remote = FakeTutorialRemote();
      var session = 1;
      final repo = TutorialRepository(
        remote: remote,
        currentUid: () => null,
        isDemo: () => true,
        demoSession: () => session,
        log: (_) {},
      );

      expect(await repo.hasSeen(TutorialPlatform.desktop), isFalse);
      await repo.record(
        TutorialPlatform.desktop,
        TutorialOutcome.completed,
        lastStep: 8,
      );
      expect(remote.saves, isEmpty);
      expect(await repo.hasSeen(TutorialPlatform.desktop), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      // A fresh demo session shows it again.
      session = 2;
      expect(await repo.hasSeen(TutorialPlatform.desktop), isFalse);
    });

    test('the voice tour has its own record', () async {
      final remote = FakeTutorialRemote();
      final repo = fakeRepository(
        remote: remote,
        // Even an older account: the voice tour goes by its own record.
        createdAt: DateTime.utc(2025, 1, 1),
      );
      expect(
        TutorialRepository.recordKey(
          TutorialPlatform.mobile,
          TutorialTour.voice,
        ),
        'voiceMobile',
      );
      expect(
        await repo.hasSeen(TutorialPlatform.desktop, tour: TutorialTour.voice),
        isFalse,
      );
      await repo.record(
        TutorialPlatform.desktop,
        TutorialOutcome.completed,
        lastStep: 5,
        tour: TutorialTour.voice,
      );
      expect(remote.saves.single.key, 'voiceDesktop');
      expect(
        await repo.hasSeen(TutorialPlatform.desktop, tour: TutorialTour.voice),
        isTrue,
      );
      // The app tour's own mirror is untouched.
      expect(await repo.seenLocally(TutorialPlatform.desktop), isFalse);
    });

    test('an existing account is treated as seen', () async {
      final repo = fakeRepository(
        remote: FakeTutorialRemote(),
        createdAt: DateTime.utc(2025, 1, 1),
      );
      expect(
        await repo.hasSeen(TutorialPlatform.desktop, profile: const {}),
        isTrue,
      );
    });
  });
}
