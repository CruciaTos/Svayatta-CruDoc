import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: _initialRoute(),
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/dashboard', builder: (context, state) => const Shell()),
  ],
);

/// If the user is already signed in, go straight to dashboard.
String _initialRoute() {
  return FirebaseAuth.instance.currentUser != null ? '/dashboard' : '/auth';
}
