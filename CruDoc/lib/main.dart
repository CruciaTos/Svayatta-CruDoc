import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/services/firestore_sync_service.dart';
import 'core/services/initial_firestore_migration_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  await InitialFirestoreMigrationService.instance.runIfNeeded();
  await FirestoreSyncService.instance.start();

  runApp(const ProviderScope(child: MoodyDashboardApp()));
}

class MoodyDashboardApp extends StatelessWidget {
  const MoodyDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Moody Blues Dashboard',
      theme: ThemeData.dark(useMaterial3: true),
      routerConfig: appRouter,
    );
  }
}
