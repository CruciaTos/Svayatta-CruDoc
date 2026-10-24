import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Tokens from one Google sign-in in the browser.
class DesktopGoogleTokens {
  const DesktopGoogleTokens({
    required this.accessToken,
    required this.expiresIn,
    this.idToken,
    this.refreshToken,
  });

  final String accessToken;
  final String? idToken;

  /// Only when asked for offline access.
  final String? refreshToken;

  /// Seconds until [accessToken] expires.
  final int expiresIn;
}

/// Why a browser sign-in didn't finish.
class DesktopGoogleOAuthException implements Exception {
  const DesktopGoogleOAuthException(this.message, {this.cancelled = false});

  /// Plain words for the person signing in.
  final String message;

  /// They closed the page, said no, or took too long.
  final bool cancelled;

  @override
  String toString() => message;
}

/// Google sign-in where the google_sign_in plugin has no implementation
/// (Windows and Linux): opens Google's page in the browser and catches the
/// answer on a one-time local address (OAuth 2.0 with PKCE, RFC 8252).
///
/// Uses a Google Cloud "Desktop app" OAuth client in the Firebase project,
/// passed at build time:
/// `--dart-define-from-file=google_desktop_oauth.json` with
/// `GOOGLE_DESKTOP_CLIENT_ID` and `GOOGLE_DESKTOP_CLIENT_SECRET`. Google
/// doesn't treat a desktop client's secret as confidential, but the file is
/// kept out of git anyway.
abstract final class DesktopGoogleOAuth {
  static const clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );

  static const _authHost = 'accounts.google.com';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// This platform signs in through the browser.
  static bool get usesBrowser =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// The build carries the desktop client.
  static bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Signs in through the browser and returns Google's tokens.
  ///
  /// [offline] also asks for a refresh token (Gmail keeps sending while the
  /// app is closed); [forceConsent] shows the consent screen again, which
  /// Google needs before it hands out a new refresh token.
  static Future<DesktopGoogleTokens> authorize({
    required List<String> scopes,
    bool offline = false,
    bool forceConsent = false,
    http.Client? client,
  }) async {
    if (!configured) {
      throw const DesktopGoogleOAuthException(
        "Google sign-in isn't set up on this computer yet.",
      );
    }
    HttpServer? server;
    try {
      final verifier = _codeVerifier();
      final state = _codeVerifier();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://127.0.0.1:${server.port}';

      final authUri = Uri.https(_authHost, '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'code_challenge': _codeChallenge(verifier),
        'code_challenge_method': 'S256',
        'state': state,
        if (offline) 'access_type': 'offline',
        if (forceConsent) 'prompt': 'consent' else 'prompt': 'select_account',
      });
      if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
        throw const DesktopGoogleOAuthException(
          "Couldn't open the browser for Google sign-in.",
        );
      }

      // Skip stray requests (a browser asking for /favicon.ico) until the
      // one carrying Google's answer arrives.
      final request = await server
          .firstWhere(
            (r) =>
                r.uri.queryParameters.containsKey('code') ||
                r.uri.queryParameters.containsKey('error'),
          )
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => throw const DesktopGoogleOAuthException(
              'Google sign-in timed out. Please try again.',
              cancelled: true,
            ),
          );
      final params = request.uri.queryParameters;
      final code = params['code'];
      final ok = code != null && params['state'] == state;
      request.response
        ..headers.contentType = ContentType.html
        ..write(_page(ok));
      await request.response.close();
      if (!ok) {
        throw const DesktopGoogleOAuthException(
          'Google sign-in was cancelled.',
          cancelled: true,
        );
      }

      final body = await _token(client, {
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      });
      return DesktopGoogleTokens(
        accessToken: body['access_token'] as String,
        idToken: body['id_token'] as String?,
        refreshToken: body['refresh_token'] as String?,
        expiresIn: body['expires_in'] as int? ?? 3600,
      );
    } finally {
      await server?.close(force: true);
    }
  }

  /// A new access token from a refresh token.
  static Future<DesktopGoogleTokens> refresh(
    String refreshToken, {
    http.Client? client,
  }) async {
    final body = await _token(client, {
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    });
    return DesktopGoogleTokens(
      accessToken: body['access_token'] as String,
      idToken: body['id_token'] as String?,
      refreshToken: refreshToken,
      expiresIn: body['expires_in'] as int? ?? 3600,
    );
  }

  static Future<Map<String, dynamic>> _token(
    http.Client? client,
    Map<String, String> fields,
  ) async {
    final c = client ?? http.Client();
    try {
      final response = await c.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'client_id': clientId, 'client_secret': clientSecret, ...fields},
      );
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          body is! Map<String, dynamic> ||
          body['access_token'] is! String) {
        debugPrint('[google-desktop] token ${response.statusCode}: ${response.body}');
        throw const DesktopGoogleOAuthException(
          "Google didn't accept the sign-in. Please try again.",
        );
      }
      return body;
    } finally {
      if (client == null) c.close();
    }
  }

  static String _codeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  /// What the browser tab shows once Google sends it back.
  static String _page(bool ok) {
    final title = ok ? 'Signed in to CruDoc' : 'Sign-in cancelled';
    final line = ok
        ? 'You can close this tab and go back to CruDoc.'
        : 'Nothing was changed. You can close this tab and try again in CruDoc.';
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<title>$title</title></head>'
        '<body style="font-family:system-ui,sans-serif;text-align:center;'
        'padding-top:72px;color:#1d1d1f">'
        '<h2 style="font-weight:600">$title</h2><p>$line</p></body></html>';
  }
}
