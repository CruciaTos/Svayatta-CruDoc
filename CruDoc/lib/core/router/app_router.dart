import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/responsive_shell.dart';

final GoRouter appRouter = _createAppRouter();

class _FirebaseAuthListenable extends ChangeNotifier {
  _FirebaseAuthListenable() {
    _subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
    DemoSessionService.sessionStateNotifier.addListener(notifyListeners);
    DemoSessionService.sessionRevisionNotifier.addListener(notifyListeners);
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    DemoSessionService.sessionStateNotifier.removeListener(notifyListeners);
    DemoSessionService.sessionRevisionNotifier.removeListener(notifyListeners);
    super.dispose();
  }
}

final _firebaseAuthListenable = _FirebaseAuthListenable();

GoRouter _createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _firebaseAuthListenable,
    redirect: (context, state) async {
      final user = FirebaseAuth.instance.currentUser;
      final isDemo = DemoSessionService.isDemoMode;
      final isLoggedIn = user != null || isDemo;
      final path = state.matchedLocation;
      final isAuthRoute = path == '/' || path == '/auth';

      // Super Admin is a separate web app on its own subdomain
      // (CrudocSuper-admin, next to this repo); the clinic app has no admin
      // routes.

      // 1. Unauthenticated users trying to access protected clinic routes
      if (!isLoggedIn && !isAuthRoute) {
        return '/auth';
      }

      // 2. Authenticated users landing on landing/auth routes
      if (isLoggedIn && isAuthRoute) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const ResponsiveShell(),
      ),
    ],
  );
}
