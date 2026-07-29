import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/shell.dart';
// ADD THESE IMPORTS:
import '../../features/super_admin/screens/auth/login_screen.dart';
import '../../features/super_admin/screens/main_shell.dart';
import '../../features/super_admin/middleware/auth_middleware.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: _initialRoute(),
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/dashboard', builder: (context, state) => const Shell()),
    // ADD SUPER ADMIN ROUTES:
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

/// If the user is already signed in, go straight to dashboard.
String _initialRoute() {
  return FirebaseAuth.instance.currentUser != null ? '/dashboard' : '/auth';
}
