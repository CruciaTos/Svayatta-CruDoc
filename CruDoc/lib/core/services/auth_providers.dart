import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

/// Singleton [AuthService] instance.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Reactive stream of the currently signed-in Firebase user (or null).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Convenience provider for the current [User] snapshot (nullable).
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});
