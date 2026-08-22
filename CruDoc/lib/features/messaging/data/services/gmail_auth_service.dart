import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';

/// Service managing OAuth 2.0 user consent and credentials for the Gmail API.
///
/// Features:
/// - Minimum required scope: `https://www.googleapis.com/auth/gmail.send`
/// - Native Google Sign-In for Android/iOS/Web
/// - OAuth 2.0 PKCE loopback redirect for Desktop (Windows/macOS)
/// - Multi-tenant isolation: credentials stored in [FlutterSecureStorage] by doctor UID
/// - Concurrency-safe silent token refresh with mutex lock
class GmailAuthService {
  GmailAuthService({
    FlutterSecureStorage? secureStorage,
    GoogleSignIn? googleSignIn,
    http.Client? httpClient,
  })  : _secureStorage = secureStorage ??
            (kIsWeb
                ? const FlutterSecureStorage()
                : const FlutterSecureStorage(
                    aOptions: AndroidOptions(encryptedSharedPreferences: true),
                  )),
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const [
                'https://www.googleapis.com/auth/gmail.send',
              ],
            ),
        _httpClient = httpClient;

  final FlutterSecureStorage _secureStorage;
  final GoogleSignIn _googleSignIn;
  final http.Client? _httpClient;

  static const String _gmailScope = 'https://www.googleapis.com/auth/gmail.send';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';

  static const String _desktopClientId = String.fromEnvironment(
    'GMAIL_OAUTH_CLIENT_ID',
    defaultValue: '',
  );

  // In-memory token cache
  String? _cachedAccessToken;
  DateTime? _accessTokenExpiresAt;
  String? _connectedEmail;
  Completer<String>? _refreshCompleter;

  /// Current authenticated doctor's ID for multi-tenant isolation.
  String get _currentDoctorId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
  }

  String _refreshTokenKey(String doctorId) => 'gmail_refresh_token_$doctorId';
  String _connectedEmailKey(String doctorId) => 'gmail_connected_email_$doctorId';

  /// Whether a connected Gmail account is available for sending emails.
  bool get isConnected => _connectedEmail != null && _connectedEmail!.isNotEmpty;

  /// Alias for isConnected.
  bool get isSignedIn => isConnected;

  /// The email address of the connected Gmail account.
  String? get connectedEmail => _connectedEmail;

  /// Restores session silently from secure storage on app startup.
  Future<bool> restoreSession() async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      _clearMemoryState();
      return false;
    }

    try {
      final storedEmail = await _secureStorage.read(key: _connectedEmailKey(doctorId));
      if (storedEmail == null || storedEmail.isEmpty) {
        _clearMemoryState();
        return false;
      }

      // Check desktop refresh token
      if (_isDesktop) {
        final storedRefreshToken = await _secureStorage.read(key: _refreshTokenKey(doctorId));
        if (storedRefreshToken != null && storedRefreshToken.isNotEmpty) {
          try {
            await _refreshDesktopAccessToken(storedRefreshToken);
            _connectedEmail = storedEmail;
            return true;
          } catch (_) {
            await signOut();
            return false;
          }
        }
      } else {
        // Mobile / Web
        try {
          final account = await _googleSignIn.signInSilently();
          if (account != null) {
            _connectedEmail = account.email;
            await _secureStorage.write(
              key: _connectedEmailKey(doctorId),
              value: account.email,
            );
            return true;
          }
        } catch (_) {}
      }

      _clearMemoryState();
      return false;
    } catch (_) {
      _clearMemoryState();
      return false;
    }
  }

  /// Initiates the OAuth sign-in flow.
  Future<String> signIn() async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw const GmailAuthRevokedException('User must be signed in to connect Gmail.');
    }

    if (_isDesktop) {
      return _signInDesktop(doctorId);
    } else {
      return _signInMobileOrWeb(doctorId);
    }
  }

  /// Disconnects the Gmail account, revokes OAuth tokens, and clears local credentials.
  Future<void> signOut() async {
    final doctorId = _currentDoctorId;
    final client = _httpClient ?? http.Client();

    try {
      if (_isDesktop) {
        final token = await _secureStorage.read(key: _refreshTokenKey(doctorId)) ??
            _cachedAccessToken;
        if (token != null && token.isNotEmpty) {
          try {
            await client.post(
              Uri.parse(_revokeEndpoint),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: {'token': token},
            );
          } catch (_) {}
        }
      } else {
        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          try {
            await _googleSignIn.signOut();
          } catch (_) {}
        }
      }
    } finally {
      if (_httpClient == null) {
        client.close();
      }
      await _secureStorage.delete(key: _refreshTokenKey(doctorId));
      await _secureStorage.delete(key: _connectedEmailKey(doctorId));
      _clearMemoryState();
    }
  }

  /// Returns valid `Authorization: Bearer <token>` HTTP headers.
  Future<Map<String, String>> getAuthHeaders() async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw const GmailAuthRevokedException('No signed-in doctor found.');
    }

    if (_isDesktop) {
      final token = await _getValidDesktopAccessToken(doctorId);
      return {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
    } else {
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();

      if (account == null) {
        throw const GmailAuthRevokedException('Gmail session not found. Please connect your account.');
      }

      final auth = await account.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw const GmailAuthRevokedException('Failed to retrieve Gmail access token.');
      }

      return {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Mobile / Web Flow (Native Google Sign-In)
  // ---------------------------------------------------------------------------

  Future<String> _signInMobileOrWeb(String doctorId) async {
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();

      if (account != null) {
        final hasScope = await _googleSignIn.canAccessScopes(
          const [_gmailScope],
        );
        if (!hasScope) {
          final granted = await _googleSignIn.requestScopes(
            const [_gmailScope],
          );
          if (!granted) {
            throw const GmailAuthCancelledException();
          }
        }
        account = _googleSignIn.currentUser;
      } else {
        account = await _googleSignIn.signIn();
      }

      if (account == null) {
        throw const GmailAuthCancelledException();
      }

      _connectedEmail = account.email;
      await _secureStorage.write(
        key: _connectedEmailKey(doctorId),
        value: account.email,
      );

      return account.email;
    } on PlatformException catch (pe) {
      if (pe.code == 'sign_in_canceled') {
        throw const GmailAuthCancelledException();
      }
      if (pe.message?.contains('ApiException: 10') == true || pe.details?.toString().contains('10') == true) {
        throw const GmailSendException(
          'Google Sign-In requires registering your debug SHA-1 in Firebase Console:\n90:97:84:95:7F:7A:25:9D:08:44:5F:F9:37:DA:5C:04:4C:D4:CA:14',
        );
      }
      throw GmailSendException('Google Sign-In failed (${pe.code}): ${pe.message ?? ''}');
    } catch (e) {
      if (e is GmailException) rethrow;
      throw GmailSendException('Failed to connect Gmail account: ${e.toString()}');
    }
  }

  // ---------------------------------------------------------------------------
  // Desktop Flow (PKCE + Loopback Redirect RFC 8252)
  // ---------------------------------------------------------------------------

  Future<String> _signInDesktop(String doctorId) async {
    if (_desktopClientId.isEmpty) {
      throw const GmailSendException(
        'Desktop OAuth client ID not configured. Pass --dart-define=GMAIL_OAUTH_CLIENT_ID=... at build time.',
      );
    }

    HttpServer? server;
    try {
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://localhost:$port';

      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _desktopClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'email $_gmailScope',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
      });

      final launched = await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw const GmailNetworkException('Could not launch browser for Google sign-in.');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw const GmailAuthCancelledException('Sign-in timed out. Please try again.'),
      );

      final queryParams = request.uri.queryParameters;
      final code = queryParams['code'];
      final error = queryParams['error'];

      request.response.headers.contentType = ContentType.html;
      if (code != null) {
        request.response.write('''
          <!DOCTYPE html>
          <html>
            <head><title>CruDoc Gmail Connected</title></head>
            <body style="font-family: sans-serif; text-align: center; padding-top: 50px;">
              <h2 style="color: #16A34A;">Gmail Connected Successfully!</h2>
              <p>You can close this tab and return to CruDoc.</p>
            </body>
          </html>
        ''');
      } else {
        request.response.write('''
          <!DOCTYPE html>
          <html>
            <head><title>Connection Cancelled</title></head>
            <body style="font-family: sans-serif; text-align: center; padding-top: 50px;">
              <h2 style="color: #DC2626;">Gmail Connection Cancelled</h2>
              <p>You can close this tab and return to CruDoc.</p>
            </body>
          </html>
        ''');
      }
      await request.response.close();

      if (error != null || code == null) {
        throw const GmailAuthCancelledException();
      }

      return await _exchangeCodeForTokens(
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
        doctorId: doctorId,
      );
    } finally {
      await server?.close(force: true);
    }
  }

  Future<String> _exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    required String doctorId,
  }) async {
    final client = _httpClient ?? http.Client();
    try {
      final response = await client.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _desktopClientId,
          'code': code,
          'code_verifier': codeVerifier,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) {
        throw const GmailAuthRevokedException('Failed to exchange authorization code for tokens.');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String?;
      final refreshToken = body['refresh_token'] as String?;
      final expiresIn = body['expires_in'] as int? ?? 3600;
      final idToken = body['id_token'] as String?;

      if (accessToken == null) {
        throw const GmailAuthRevokedException('No access token returned by Google OAuth.');
      }

      String? email = _extractEmailFromIdToken(idToken);
      email ??= await _fetchEmailFromUserInfo(accessToken, client);

      _cachedAccessToken = accessToken;
      _accessTokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
      _connectedEmail = email;

      if (refreshToken != null) {
        await _secureStorage.write(
          key: _refreshTokenKey(doctorId),
          value: refreshToken,
        );
      }
      if (email != null) {
        await _secureStorage.write(
          key: _connectedEmailKey(doctorId),
          value: email,
        );
      }

      return email ?? 'connected';
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<String> _getValidDesktopAccessToken(String doctorId) async {
    if (_cachedAccessToken != null &&
        _accessTokenExpiresAt != null &&
        DateTime.now().isBefore(_accessTokenExpiresAt!)) {
      return _cachedAccessToken!;
    }

    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<String>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey(doctorId));
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const GmailAuthRevokedException('No refresh token available. Please reconnect Gmail.');
      }

      final newToken = await _refreshDesktopAccessToken(refreshToken);
      completer.complete(newToken);
      return newToken;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<String> _refreshDesktopAccessToken(String refreshToken) async {
    final client = _httpClient ?? http.Client();
    try {
      final response = await client.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _desktopClientId,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode != 200) {
        throw const GmailAuthRevokedException('Google refresh token has expired or was revoked.');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String?;
      final expiresIn = body['expires_in'] as int? ?? 3600;

      if (accessToken == null) {
        throw const GmailAuthRevokedException('Invalid token refresh response.');
      }

      _cachedAccessToken = accessToken;
      _accessTokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
      return accessToken;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  String? _extractEmailFromIdToken(String? idToken) {
    if (idToken == null || !idToken.contains('.')) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      var normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchEmailFromUserInfo(String accessToken, http.Client client) async {
    try {
      final res = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        return map['email'] as String?;
      }
    } catch (_) {}
    return null;
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  void _clearMemoryState() {
    _cachedAccessToken = null;
    _accessTokenExpiresAt = null;
    _connectedEmail = null;
  }

  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(64, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
