import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';

/// Provider for the [GmailAuthService] singleton.
final gmailAuthServiceProvider = Provider<GmailAuthService>((ref) {
  return GmailAuthService();
});

/// Async notifier managing the doctor's Gmail connection status and email.
class GmailConnectionNotifier extends AsyncNotifier<String?> {
  @override
  FutureOr<String?> build() async {
    try {
      final authService = ref.watch(gmailAuthServiceProvider);
      final isRestored = await authService.restoreSession();
      if (isRestored) {
        return authService.connectedEmail;
      }
      return null;
    } catch (e, st) {
      debugPrint('GmailConnectionNotifier.build silent restore error: $e\n$st');
      return null; // Always fail-safe to "Not Connected" on initial load
    }
  }

  /// Triggers the interactive OAuth sign-in flow.
  Future<void> connect() async {
    state = const AsyncValue.loading();
    try {
      final authService = ref.read(gmailAuthServiceProvider);
      final email = await authService.signIn();
      state = AsyncValue.data(email);
    } on GmailAuthCancelledException {
      // User explicitly closed/cancelled the Google dialog — return to un-connected cleanly
      state = const AsyncValue.data(null);
    } catch (e, st) {
      debugPrint('GmailConnectionNotifier.connect error: $e\n$st');
      state = AsyncValue.error(e, st);
    }
  }

  /// Disconnects the Gmail account and revokes tokens.
  Future<void> disconnect() async {
    state = const AsyncValue.loading();
    try {
      final authService = ref.read(gmailAuthServiceProvider);
      await authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      debugPrint('GmailConnectionNotifier.disconnect error: $e\n$st');
      state = const AsyncValue.data(null);
    }
  }
}

/// Provider for the Gmail connection state (returns the connected email or null).
final gmailConnectionProvider =
    AsyncNotifierProvider<GmailConnectionNotifier, String?>(
  GmailConnectionNotifier.new,
);
