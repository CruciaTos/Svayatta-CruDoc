import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';

/// Widget that checks authentication and redirects accordingly.
class SuperAdminAuthGuard extends ConsumerWidget {
  final Widget child;

  const SuperAdminAuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(superAdminAuthProvider);

    if (!authState.isAuthenticated && !authState.isLoading) {
      return const SuperAdminLoginScreen();
    }

    if (authState.isTwoFARequired && !authState.isTwoFAVerified) {
      return const SuperAdminLoginScreen(show2FA: true);
    }

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return child;
  }
}

/// Widget that requires the user to be an authenticated Super Admin.
class RequireSuperAdmin extends ConsumerWidget {
  final Widget child;

  const RequireSuperAdmin({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SuperAdminAuthGuard(child: child);
  }
}

/// Error boundary widget for Super Admin screens.
class SuperAdminErrorBoundary extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Widget child;

  const SuperAdminErrorBoundary({
    super.key,
    this.errorMessage,
    this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return child;
  }
}