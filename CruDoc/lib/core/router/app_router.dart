import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/shell.dart';
import '../../features/super_admin/screens/auth/login_screen.dart';
import '../../features/super_admin/screens/main_shell.dart';
import '../../features/super_admin/middleware/auth_middleware.dart';

final GoRouter appRouter = _createAppRouter();

GoRouter _createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final path = state.matchedLocation;
      final isAuthRoute = path == '/' || path == '/auth';
      final isAdminRoute = path.startsWith('/admin');
      final isAdminLoginRoute = path == '/admin/login';

      // Unauthenticated users trying to access protected routes
      if (!isLoggedIn && !isAuthRoute && !isAdminLoginRoute) {
        // If trying to access /admin, redirect to admin login
        if (isAdminRoute) {
          return '/admin/login';
        }
        return '/auth';
      }

      // Logged-in users on auth pages → go to dashboard
      if (isLoggedIn && isAuthRoute) {
        return '/dashboard';
      }

      // --- CRITICAL SECURITY GUARD ---
      // Logged-in users trying to access /admin (not the login page):
      // Verify they actually have the superAdmin role in Firestore.
      if (isLoggedIn && isAdminRoute && !isAdminLoginRoute) {
        try {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();

          if (!doc.exists || doc.data() == null) {
            // No super admin profile → not an admin, block access.
            return '/dashboard';
          }

          final role = doc.data()!['role'] as String?;
          if (role != 'superAdmin') {
            // User exists but is not a superAdmin → block access.
            return '/dashboard';
          }

          final isActive = doc.data()!['isActive'] as bool? ?? false;
          if (!isActive) {
            // Admin account is disabled → block access.
            return '/dashboard';
          }
        } catch (_) {
          // On any error, deny access to admin panel.
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const Shell()),
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
