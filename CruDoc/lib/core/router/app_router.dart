import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/responsive_shell.dart';
import '../../features/super_admin/screens/auth/login_screen.dart';
import '../../features/super_admin/screens/main_shell.dart';
import '../../features/super_admin/middleware/auth_middleware.dart';

final GoRouter appRouter = _createAppRouter();

class _FirebaseAuthListenable extends ChangeNotifier {
  _FirebaseAuthListenable() {
    _subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
    DemoSessionService.sessionStateNotifier.addListener(notifyListeners);
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    DemoSessionService.sessionStateNotifier.removeListener(notifyListeners);
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
      final isAdminRoute = path.startsWith('/admin');
      final isAdminLoginRoute = path == '/admin/login';

      // 1. Unauthenticated users trying to access protected routes
      if (!isLoggedIn && !isAuthRoute && !isAdminLoginRoute) {
        if (isAdminRoute) {
          return '/admin/login';
        }
        return '/auth';
      }

      // If user is logged in via Demo Session (instant dev bypass)
      if (isDemo) {
        if (isAdminRoute) return '/dashboard';
        if (isAuthRoute) return '/dashboard';
        return null;
      }

      // If user is logged in via Firebase Auth, check their role to enforce strict role-based route separation
      if (isLoggedIn && user != null) {
        String? role;
        bool isActiveAdmin = true;

        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 2));

          if (doc.exists && doc.data() != null) {
            role = doc.data()!['role'] as String?;
            isActiveAdmin = doc.data()!['isActive'] as bool? ?? true;
          }
        } catch (_) {}

        final isSuperAdmin = role == 'superAdmin';

        // 2. SUPER ADMIN ROLE BOUNDARY
        if (isSuperAdmin) {
          // Inactive admin -> send to admin login
          if (!isActiveAdmin && !isAdminLoginRoute) {
            return '/admin/login';
          }
          // Super Admin trying to access doctor routes or auth pages -> redirect to /admin
          if (!isAdminRoute) {
            return '/admin';
          }
          return null; // Allow access to /admin
        }

        // 3. DOCTOR / REGULAR USER ROLE BOUNDARY
        // Non-admin trying to access /admin routes -> redirect to /dashboard
        if (isAdminRoute) {
          return '/dashboard';
        }

        // Logged-in doctor on auth pages -> redirect to /dashboard
        if (isAuthRoute) {
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const ResponsiveShell()),
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const SuperAdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const SuperAdminAuthGuard(
          child: SuperAdminShell(),
        ),
      ),
    ],
  );
}