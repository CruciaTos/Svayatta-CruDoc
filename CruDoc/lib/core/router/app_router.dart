import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/shell/presentation/shell.dart';
import '../../features/super_admin/screens/auth/login_screen.dart';
import '../../features/super_admin/screens/main_shell.dart';
import '../../features/super_admin/middleware/auth_middleware.dart';

late final GoRouter appRouter = _createAppRouter();

GoRouter _createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final isAuthRoute =
          state.matchedLocation == '/' || state.matchedLocation == '/auth';

      if (!isLoggedIn && !isAuthRoute) {
        return '/auth';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/dashboard';
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
