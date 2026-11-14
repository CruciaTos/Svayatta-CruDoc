import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/services/desktop_google_oauth.dart';
import 'package:doctor_management_app/features/messaging/data/providers/reminder_settings_providers.dart';

/// The clinic's Gmail for automatic reminder emails, and the log of what went
/// out. The server sends (functions/src/reminders/); this file only connects
/// the account, shows its state and lists recent attempts.
///
/// Separate from [GmailAuthService], which keeps tokens on one device for
/// campaigns sent from the app. These emails are sent by the server while
/// every device is off, so Google's one-time code goes to the server, which
/// keeps the refresh token sealed.

const String _gmailSendScope = 'https://www.googleapis.com/auth/gmail.send';

/// The Web application OAuth client the server exchanges codes with (same id
/// as the GMAIL_OAUTH_CLIENT_ID secret; the client id is not a secret).
/// Pass `--dart-define=GMAIL_OAUTH_CLIENT_ID=...` when building.
const String kGmailOAuthClientId = String.fromEnvironment(
  'GMAIL_OAUTH_CLIENT_ID',
);

class ClinicGmailException implements Exception {
  const ClinicGmailException(this.message, {this.cancelled = false});

  /// Plain words for the clinic owner.
  final String message;

  /// They backed out; nothing to report.
  final bool cancelled;

  @override
  String toString() => message;
}

/// `clinics/{uid}/messaging_status/gmail`, written by the server.
class ClinicGmailStatus {
  const ClinicGmailStatus({required this.state, this.address});

  /// connected | reauth_required | disconnected
  final String state;
  final String? address;

  bool get connected => state == 'connected';
  bool get needsReconnect => state == 'reauth_required';
}

final clinicGmailStatusProvider = StreamProvider.autoDispose<ClinicGmailStatus>(
  (ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const ClinicGmailStatus(state: 'disconnected'));
    }
    return FirebaseFirestore.instance
        .collection('clinics')
        .doc(uid)
        .collection('messaging_status')
        .doc('gmail')
        .snapshots()
        .map((s) {
          final d = s.data();
          return ClinicGmailStatus(
            state: d?['state'] as String? ?? 'disconnected',
            address: d?['address'] as String?,
          );
        });
  },
);

/// One automatic reminder or recall attempt, from `reminder_log`. Holds a
/// patient id and no contact details; the screen looks the name up locally.
class ReminderLogEntry {
  const ReminderLogEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.at,
    this.patientId,
    this.channel,
    this.reason,
    this.errorCode,
  });

  final String id;
  final ReminderKind kind;

  /// queued | sent | failed | skipped | pending
  final String status;
  final DateTime at;
  final String? patientId;
  final ReminderChannel? channel;
  final String? reason;
  final String? errorCode;
}

/// The last 50 attempts, newest first.
final reminderLogProvider = StreamProvider.autoDispose<List<ReminderLogEntry>>((
  ref,
) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('clinics')
      .doc(uid)
      .collection('reminder_log')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snap) => [
          for (final d in snap.docs)
            ReminderLogEntry(
              id: d.id,
              kind: d.data()['kind'] == 'recall'
                  ? ReminderKind.recall
                  : ReminderKind.reminder,
              status: d.data()['status'] as String? ?? 'pending',
              at:
                  (d.data()['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              patientId: d.data()['patientId'] as String?,
              channel: switch (d.data()['channel']) {
                'whatsapp' => ReminderChannel.whatsapp,
                'email' => ReminderChannel.email,
                _ => null,
              },
              reason: d.data()['reason'] as String?,
              errorCode: d.data()['errorCode'] as String?,
            ),
        ],
      );
});

/// Connects and disconnects the clinic's Gmail through the server.
class ClinicGmailLink {
  ClinicGmailLink({CallableClient? functions})
    : _functions = functions ?? CallableClient();

  final CallableClient _functions;

  /// Whether this build knows the OAuth client to sign in with.
  static bool get configured => kGmailOAuthClientId.isNotEmpty;

  /// Signs in with Google (offline access, gmail.send only), hands the
  /// one-time code to `connectClinicGmail` and returns the connected address.
  Future<String> connect() async {
    if (kIsWeb) {
      throw const ClinicGmailException(
        'Connect Gmail from the Android, iOS or Windows app.',
      );
    }
    if (!configured) {
      throw const ClinicGmailException(
        "Connecting Gmail isn't set up in this build yet.",
      );
    }
    final ({String code, String redirectUri}) grant;
    try {
      grant = DesktopGoogleOAuth.usesBrowser
          ? await _codeFromBrowser()
          : await _codeFromDevice();
    } on DesktopGoogleOAuthException catch (e) {
      throw ClinicGmailException(e.message, cancelled: e.cancelled);
    }

    try {
      final res = await _functions.call('connectClinicGmail', {
        'authCode': grant.code,
        'redirectUri': grant.redirectUri,
      });
      final address = (res as Map)['address'] as String?;
      if (address == null || address.isEmpty) {
        throw const ClinicGmailException("Couldn't read the Gmail address.");
      }
      return address;
    } on CallableException catch (e) {
      throw ClinicGmailException(
        e.message.isEmpty ? "Couldn't connect Gmail. Try again." : e.message,
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await _functions.call('disconnectClinicGmail', {});
    } on CallableException catch (e) {
      throw ClinicGmailException(
        e.message.isEmpty ? "Couldn't disconnect Gmail. Try again." : e.message,
      );
    }
  }

  Future<({String code, String redirectUri})> _codeFromBrowser() =>
      DesktopGoogleOAuth.authorizeForServer(
        clientId: kGmailOAuthClientId,
        scopes: const ['openid', 'email', _gmailSendScope],
      );

  /// Android, iOS and macOS: the native sheet gives a server auth code. It is
  /// only issued on a fresh sign-in, so a first answer without one is retried
  /// after signing out.
  Future<({String code, String redirectUri})> _codeFromDevice() async {
    final google = GoogleSignIn(
      scopes: const ['email', _gmailSendScope],
      serverClientId: kGmailOAuthClientId,
      forceCodeForRefreshToken: true,
    );
    try {
      var account = await google.signIn();
      if (account != null && account.serverAuthCode == null) {
        await google.signOut();
        account = await google.signIn();
      }
      if (account == null) {
        throw const ClinicGmailException(
          'Google sign-in was cancelled.',
          cancelled: true,
        );
      }
      final code = account.serverAuthCode;
      if (code == null || code.isEmpty) {
        throw const ClinicGmailException(
          "Google didn't allow sending email. Try again.",
        );
      }
      return (code: code, redirectUri: '');
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled') {
        throw const ClinicGmailException(
          'Google sign-in was cancelled.',
          cancelled: true,
        );
      }
      throw ClinicGmailException('Google sign-in failed (${e.code}).');
    }
  }
}

final clinicGmailLinkProvider = Provider<ClinicGmailLink>(
  (ref) => ClinicGmailLink(),
);
