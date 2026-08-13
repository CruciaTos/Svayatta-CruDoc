import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/services/encryption_key_manager.dart';
import 'core/services/device_session_service.dart';
import 'core/services/firestore_sync_service.dart';
import 'core/services/initial_firestore_migration_service.dart';
import 'core/services/local_database_service.dart';
import 'core/theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Windows-only smoke test: attempt a direct Firestore read and log result.
  if (defaultTargetPlatform == TargetPlatform.windows) {
    try {
      final testSnap = await FirebaseFirestore.instance
          .collection('users')
          .limit(1)
          .get();
      debugPrint('Windows Firestore smoke test: ${testSnap.docs.length} documents');
    } catch (e, st) {
      debugPrint('Windows Firestore smoke test failed: $e');
      debugPrint(st.toString());
    }
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
    _wireDoctorScopedStartup();
  } else {
    _wireWebEncryptionKeyLoading();
  }

  runApp(const ProviderScope(child: MoodyDashboardApp()));
}

/// On Web there's no local SQLite cache to migrate or sync — repositories
/// read/write Firestore directly (see e.g. PatientRepository's `kIsWeb`
/// branches) — but those branches still call FieldCipher.encrypt/decrypt,
/// so the per-doctor key still needs to be loaded as soon as someone signs
/// in, and cleared on sign-out.
void _wireWebEncryptionKeyLoading() {
  String? lastHandledUid;
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    try {
      if (user == null) {
        DeviceSessionService.instance.stopSessionMonitoring();
        await DeviceSessionService.instance.clearSessionToken();
        EncryptionKeyManager.instance.clear();
        lastHandledUid = null;
        return;
      }
      DeviceSessionService.instance.startSessionMonitoring(
        user.uid,
        onForcedLogout: (reason) {
          debugPrint('Web forced logout: $reason');
        },
      );
      if (lastHandledUid == user.uid) return;
      lastHandledUid = user.uid;
      await EncryptionKeyManager.instance.loadForDoctor(user.uid);
    } catch (error, stackTrace) {
      debugPrint('Web startup auth bootstrap failed: $error');
      debugPrint(stackTrace.toString());
    }
  });
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
  String? lastHandledUid;

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    try {
      if (user == null) {
        DeviceSessionService.instance.stopSessionMonitoring();
        await DeviceSessionService.instance.clearSessionToken();
        if (lastHandledUid != null) {
          await FirestoreSyncService.instance.stop();
          await LocalDatabaseService.instance.close();
          EncryptionKeyManager.instance.clear();
          lastHandledUid = null;
        }
        return;
      }

      DeviceSessionService.instance.startSessionMonitoring(
        user.uid,
        onForcedLogout: (reason) {
          debugPrint('Mobile forced logout: $reason');
        },
      );

      if (lastHandledUid == user.uid) return; // already set up for this doctor
      lastHandledUid = user.uid;

      // Order matters: the key must be loaded before migration/sync try to
      // decrypt anything, and the local cache must be confirmed to belong to
      // this doctor before anything is written into it.
      await EncryptionKeyManager.instance.loadForDoctor(user.uid);
      await LocalDatabaseService.instance.ensureLocalDataMatchesSignedInDoctor(
        user.uid,
      );
      await InitialFirestoreMigrationService.instance.runIfNeeded();
      await FirestoreSyncService.instance.start();
    } catch (error, stackTrace) {
      debugPrint('Doctor-scoped startup bootstrap failed: $error');
      debugPrint(stackTrace.toString());
    }
  });
}

class MoodyDashboardApp extends StatelessWidget {
  const MoodyDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Moody Blues Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        // Ensure the app uses the project's chosen font and base text styles
        fontFamily: AppColors.bodyFontFamily,
        primaryColor: AppColors.accentBlue,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accentBlue),
        textTheme: TextTheme(
          displayLarge: AppColors.pageHeading,
          headlineSmall: AppColors.sectionHeading,
          bodyLarge: AppColors.bodyLarge,
          bodyMedium: AppColors.bodyMedium,
          bodySmall: AppColors.bodySmall,
        ),
      ),
      routerConfig: appRouter,
    );
  }
}