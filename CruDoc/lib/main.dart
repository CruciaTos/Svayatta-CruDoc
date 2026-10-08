import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_options.dart';
import 'core/clinic/clinic_access.dart';
import 'core/clinic/clinic_models.dart';
import 'core/clinic/clinic_session.dart';
import 'core/models/doctor_specialty.dart';
import 'core/providers/specialty_provider.dart';
import 'features/dental/dental_features.dart';
import 'core/router/app_router.dart';
import 'core/services/encryption_key_manager.dart';
import 'core/services/device_session_service.dart';
import 'core/services/firestore_sync_service.dart';
import 'core/services/initial_firestore_migration_service.dart';
import 'core/services/local_database_service.dart';
import 'core/services/maps_key.dart';
import 'core/pdf/services/generated_document_sync.dart';
import 'core/services/storage_sync_queue.dart';
import 'features/dental/records/dental_photo_cloud_sync.dart';
import 'features/inventory/data/services/inventory_receipt_sync.dart';
import 'features/radiology/data/radiology_cloud_sync.dart';
import 'features/scribe/data/services/scribe_audio_sync.dart';
import 'core/theme/cru_theme.dart';
import 'features/settings/data/appearance_provider.dart';
import 'features/voice/presentation/voice_overlay.dart';
import 'features/files/data/files_cloud_sync.dart';
import 'features/files/data/files_repository.dart';

const bool _useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: false,
);

/// 10.0.2.2 is the host machine as seen from the Android emulator. Pass
/// `--dart-define=EMULATOR_HOST=<pc-lan-ip>` for a physical phone, or
/// `localhost` for Windows / web.
const String _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    // Android starts the default app natively from google-services.json; if
    // its options differ from ours, keep the native one rather than crash.
    if (e.code != 'duplicate-app') rethrow;
  }

  if (_useFirebaseEmulators) {
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);

    FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).useFunctionsEmulator(_emulatorHost, 5001);

    // Without this, debug uploads go to the real bucket even while the
    // emulators are running.
    await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);
  }

  // The default retry window is about ten minutes, far too long for a clinic
  // that is offline: give up quickly and let StorageSyncQueue retry later.
  FirebaseStorage.instance.setMaxUploadRetryTime(const Duration(seconds: 30));
  FirebaseStorage.instance.setMaxOperationRetryTime(
    const Duration(seconds: 30),
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
    _wireDoctorScopedStartup();
  } else {
    _wireWebEncryptionKeyLoading();
  }
  MapsKey.loadOnSignIn();
  // Each feature that keeps a cloud path on its own record says how, before
  // the queue can finish an upload it left waiting.
  RadiologyCloudSync.register();
  ScribeAudioSync.register();
  GeneratedDocumentSync.register();
  InventoryReceiptSync.register();
  DentalPhotoCloudSync.register();
  FilesRepository.register();
  StorageSyncQueue.instance.start();

  runApp(const ProviderScope(child: MoodyDashboardApp()));
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void _showForcedLogoutSnackBar(String reason) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final messenger = rootScaffoldMessengerKey.currentState;

    if (messenger != null && messenger.mounted) {
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } catch (e) {
        debugPrint('Could not show forced logout snackbar: $e');
      }
    }
  });
}

/// On Web (and Windows) there's no background sync to start — repositories
/// read/write Firestore directly or sync on write — but they still call
/// FieldCipher.encrypt/decrypt, so the clinic's key still needs to be loaded
/// as soon as someone signs in, and cleared on sign-out.
void _wireWebEncryptionKeyLoading() {
  _followClinic(
    platform: 'Web',
    open: (user, access) =>
        EncryptionKeyManager.instance.loadForDoctor(access.clinicId),
    close: () async {
      // Started on first use here (see FilesCloudSync).
      FilesCloudSync.instance.stop();
      if (!kIsWeb) await LocalDatabaseService.instance.close();
      EncryptionKeyManager.instance.clear();
    },
  );
}

/// Starts (and re-starts) the local-first data layer strictly in response
/// to actual sign-in state, rather than unconditionally at cold start.
///
/// This matters for two reasons:
/// 1. At a cold start, nobody may be signed in yet (Google/Phone-OTP
///    happens *inside* the app) — running migration/sync before that would
///    either be denied by Firestore rules or, if rules were ever loosened,
///    pull every doctor's data onto the device. See
///    InitialFirestoreMigrationService for the bug this used to cause.
/// 2. It's also what catches a *different* doctor signing in on a device
///    that already has another doctor's data cached — before touching
///    anything else, it wipes the stale cache so the two doctors' data
///    can never mix locally.
void _wireDoctorScopedStartup() {
  _followClinic(
    platform: 'Mobile',
    // Order matters: the key must be loaded before migration/sync try to
    // decrypt anything, and the local cache must be confirmed to belong to
    // this clinic and person before anything is written into it.
    open: (user, access) async {
      await EncryptionKeyManager.instance.loadForDoctor(access.clinicId);
      await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(
        LocalDatabaseService.scopeFor(access.clinicId, user.uid),
      );
      await InitialFirestoreMigrationService.instance.runIfNeeded();
      await FirestoreSyncService.instance.start();
      FilesCloudSync.instance.ensureStarted();
    },
    close: () async {
      FilesCloudSync.instance.stop();
      await FirestoreSyncService.instance.stop();
      await LocalDatabaseService.instance.close();
      EncryptionKeyManager.instance.clear();
    },
  );
}

/// Signs people in and out of their clinic's data. On sign-in it loads
/// which clinic they work in ([ClinicSession]); every time that answer
/// changes it closes the old clinic's data and [open]s the new one. Joining
/// a clinic re-opens; being removed from one (the answer falls back to
/// their own uid) clears that clinic off this device and signs them out.
/// Changes are handled one at a time, in order.
void _followClinic({
  required String platform,
  required Future<void> Function(User user, ClinicAccess access) open,
  required Future<void> Function() close,
}) {
  String? openedUid;
  String? openedClinicId;
  var queue = Future<void>.value();

  Future<void> onAccess(ClinicAccess? access) async {
    final user = FirebaseAuth.instance.currentUser;
    if (access == null || user == null) {
      if (openedUid != null) await close();
      openedUid = null;
      openedClinicId = null;
      return;
    }
    if (access.uid != user.uid) return;
    if (openedUid == user.uid && openedClinicId == access.clinicId) return;

    final wasInClinic = openedUid == user.uid ? openedClinicId : null;
    if (openedUid != null) await close();
    openedUid = null;
    openedClinicId = null;

    if (wasInClinic != null &&
        wasInClinic != user.uid &&
        access.clinicId == user.uid) {
      await _forgetClinicOnDevice(wasInClinic, user.uid);
      await FirebaseAuth.instance.signOut();
      _showForcedLogoutSnackBar('You no longer have access to this clinic.');
      return;
    }

    // Removed while signed out, or moved to another clinic: drop the old
    // clinic's copy from this device.
    final previous = ClinicSession.instance.previousClinicId;
    if (previous != null) await _forgetClinicOnDevice(previous, user.uid);

    await open(user, access);
    openedUid = user.uid;
    openedClinicId = access.clinicId;
    await _copyMemberProfile(user);
  }

  ClinicSession.instance.stream.listen((access) {
    queue = queue.then((_) async {
      try {
        await onAccess(access);
      } catch (error, stackTrace) {
        debugPrint('$platform clinic startup failed: $error');
        debugPrint(stackTrace.toString());
      }
    });
  });

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    try {
      if (user == null) {
        DeviceSessionService.instance.stopSessionMonitoring();
        await DeviceSessionService.instance.clearSessionToken();
        ClinicSession.instance.clear();
        return;
      }

      DeviceSessionService.instance.startSessionMonitoring(
        user.uid,
        onForcedLogout: (reason) {
          debugPrint('$platform forced logout: $reason');
          _showForcedLogoutSnackBar(reason);
        },
      );

      await ClinicSession.instance.load(user.uid);
    } catch (error, stackTrace) {
      debugPrint('$platform startup auth bootstrap failed: $error');
      debugPrint(stackTrace.toString());
    }
  });
}

/// Clears what this device kept for a clinic the person no longer works
/// in: its cache file and its cached data key. Never touches anyone's own
/// (owner) data.
Future<void> _forgetClinicOnDevice(String clinicId, String uid) async {
  if (clinicId == uid) return;
  try {
    if (!kIsWeb) {
      await LocalDatabaseService.instance.deleteDatabaseForScope(
        LocalDatabaseService.scopeFor(clinicId, uid),
      );
    }
    await EncryptionKeyManager.instance.forgetCachedKey(clinicId);
  } catch (error) {
    debugPrint('Could not clear clinic $clinicId from this device: $error');
  }
}

/// A doctor who joined a clinic, or whose specialty an admin changed, gets
/// the clinic's choice copied to their own profile (the app keeps an
/// encrypted copy there too, so the server doesn't write it). Dental
/// features are copied once only; after that the dentist changes them in
/// Settings.
Future<void> _copyMemberProfile(User user) async {
  final member = ClinicSession.instance.member;
  if (member == null || member.kind != MemberKind.doctor) return;
  try {
    final profile =
        (await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get())
            .data() ??
        const <String, dynamic>{};
    if (member.specialty.isNotEmpty &&
        member.specialty != profile['specialty']) {
      await saveDoctorSpecialty(
        DoctorSpecialty.fromString(member.specialty),
        user: user,
      );
    }
    final dental = DentalFeature.parse(member.dentalFeatures);
    if (dental != null &&
        dental.isNotEmpty &&
        profile['dentalFeatures'] == null) {
      await saveDentalFeatures(dental);
    }
  } catch (error) {
    debugPrint('Could not copy the clinic profile: $error');
  }
}

class MoodyDashboardApp extends ConsumerWidget {
  const MoodyDashboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(resolvedAppearanceProvider);
    final textSize = ref.watch(textSizePreferenceProvider);
    final isEvening = appearance == CruAppearance.evening;

    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Moody Blues Dashboard',
      // Starts in Calm Clinical Night (Evening) theme by default, fully toggleable across the app
      theme: CruTheme.day(),
      darkTheme: CruTheme.evening(),
      themeMode: isEvening ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(systemScale * textSize.scale),
          ),
          child: VoiceOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
