import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/services/demo_data_seeder.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/device_session_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/auth/presentation/phone_auth_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late final AuthService _authService = AuthService();

  /// One sign-in screen on phone and desktop; "Sign up" switches the form
  /// in place.
  _AuthMode _mobileMode = _AuthMode.login;

  /// First launch: the form opens on Sign up (onboarding comes after the
  /// account exists). Null while the flag loads.
  bool? _getStarted;
  static const _kSeenGetStarted = 'seen_get_started';
  bool _obscurePassword = true;
  bool _isLoading = false;

  /// A sign-in problem, or a confirmation ("reset link sent"), shown in
  /// the card above the button.
  String? _notice;
  bool _noticeIsError = true;
  bool _rememberMe = true;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Form Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
    _secureStorage
        .read(key: _kSeenGetStarted)
        .then((v) => v == 'true', onError: (_) => false)
        .then((seen) {
          if (!seen) {
            _secureStorage
                .write(key: _kSeenGetStarted, value: 'true')
                .catchError((_) {});
          }
          if (mounted) {
            setState(() {
              _getStarted = !seen;
              if (!seen) _mobileMode = _AuthMode.signup;
            });
          }
        });

    // Clean empty text controllers by default
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final savedEmail = await _secureStorage.read(key: 'remembered_email');
      final rememberFlag = await _secureStorage.read(key: 'remember_me');
      if (mounted) {
        setState(() {
          if (rememberFlag == 'true' &&
              savedEmail != null &&
              savedEmail.trim().isNotEmpty) {
            _rememberMe = true;
            _emailController.text = savedEmail.trim();
          } else {
            _rememberMe = false;
            _emailController.clear();
            _passwordController.clear();
          }
        });
      }
    } catch (e) {
      debugPrint('Remember Me read warning: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Any email on the demo domain opens the selected specialty's shared
  /// demo account, whatever password is typed, and fills it with sample
  /// data the first time so every screen has something to show.
  static const _demoEmailDomain = '@crudoc.com';

  Future<void> _enterDemo(String email) async {
    // The address picks the demo (dental@crudoc.com opens the dental one);
    // any other address on the domain keeps the last specialty used.
    final typed = email.trim().toLowerCase();
    final spec = DoctorSpecialty.all.firstWhere(
      (s) => s.demoEmail == typed,
      orElse: () => ref.read(authSpecialtyProvider),
    );
    ref.read(authSpecialtyProvider.notifier).select(spec);
    setState(() => _isLoading = true);
    User? user;
    try {
      try {
        user = (await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: spec.demoEmail,
          password: spec.demoPassword,
        )).user;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
          rethrow;
        }
        user = (await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: spec.demoEmail,
          password: spec.demoPassword,
        )).user;
      }
    } catch (e) {
      // Every screen reads the signed-in account, so without one the app
      // would only show loading states. Say why instead of entering.
      debugPrint('Demo account sign-in failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showUserDoesNotExistDialog(
          title: 'Demo Unavailable',
          message: e is FirebaseAuthException && e.message != null
              ? e.message!
              : 'Could not reach the demo account. Check the connection and try again.',
        );
      }
      return;
    }

    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': spec.demoEmail,
          'specialty': spec.label,
          'specialization': spec.label,
          // `status`/entitlements are owned by Cloud Functions now; a demo
          // account relies on the default-active treatment in the guard.
          'role': 'doctor',
          'isDemoAccount': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Demo profile write failed: $e');
      }
      await DemoDataSeeder.seedIfEmpty();
    }

    DemoSessionService.startDemoSession(spec);
    if (user != null) {
      await DeviceSessionService.instance.registerNewSession(user.uid);
    }
    if (_rememberMe) {
      unawaited(_secureStorage.write(key: 'remembered_email', value: email));
      unawaited(_secureStorage.write(key: 'remember_me', value: 'true'));
    }
    if (mounted) setState(() => _isLoading = false);
    _enterApp();
  }

  Future<void> _syncUserProfile(User user, {String? name}) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();

      String derivedName = name?.trim() ?? '';
      if (derivedName.isEmpty &&
          user.displayName != null &&
          user.displayName!.trim().isNotEmpty) {
        derivedName = user.displayName!.trim();
      }
      if (derivedName.isEmpty && user.email != null && user.email!.isNotEmpty) {
        final emailPart = user.email!.split('@').first;
        final parts = emailPart
            .split(RegExp(r'[._-]'))
            .where((p) => p.isNotEmpty);
        if (parts.isNotEmpty) {
          derivedName = parts
              .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
              .join(' ');
        }
      }
      if (derivedName.isEmpty) derivedName = 'Doctor';

      if (user.displayName == null || user.displayName!.isEmpty) {
        await user.updateDisplayName(derivedName);
      }

      if (!snap.exists) {
        await ref.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'name': derivedName,
          'displayName': derivedName,
          'role': 'doctor',
          'isDeleted': false,
          'accountCreated': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = snap.data() ?? {};
        final updates = <String, dynamic>{};

        if (data['role'] != 'doctor') {
          updates['role'] = 'doctor';
        }
        if (data['isDeleted'] != false) {
          updates['isDeleted'] = false;
        }
        final existingName = (data['displayName'] as String?)?.trim();
        if (existingName == null || existingName.isEmpty) {
          updates['displayName'] = derivedName;
        }
        final existingDocName = (data['name'] as String?)?.trim();
        if (existingDocName == null || existingDocName.isEmpty) {
          updates['name'] = derivedName;
        }
        if (data['accountCreated'] == null) {
          updates['accountCreated'] =
              data['createdAt'] ?? FieldValue.serverTimestamp();
        }
        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          await ref.set(updates, SetOptions(merge: true));
        }
      }

      // Auto-init trial via startDoctorTrial Cloud Function if not already set
      try {
        // Parenthesised: `a ? b?['x'] : c` parses `?[` as another `?`.
        final existingStatus = snap.exists ? (snap.data()?['status']) : null;
        if (existingStatus == null) {
          // CallableClient: the cloud_functions plugin has no Windows build.
          await CallableClient().call('startDoctorTrial', {
            'modules': DoctorFeatureGuard.baseModules,
          });
        }
      } catch (e) {
        debugPrint('Auto trial start notice: $e');
      }
    } catch (e) {
      debugPrint('Sync user profile warning: $e');
    }
  }

  /// Sanitizes user credentials to prevent script injection / XSS / SQLi patterns
  String _sanitizeAuthInput(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Strip HTML & script tags
        .replaceAll(
          RegExp(r'[\x00-\x1F\x7F]'),
          '',
        ) // Strip non-printable control chars
        .replaceAll(RegExp(r"['\x22;\\]"), '') // Strip injection delimiters
        .trim();
  }

  void _showAuthToast(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = isError;
    });
  }

  void _showUserDoesNotExistDialog({
    String title = 'User Does Not Exist',
    required String message,
  }) {
    // Show single sleek Top Toast Banner (No double dialog popup)
    _showAuthToast(message, isError: true);
  }

  void _showError(String message) {
    _showAuthToast(message, isError: true);
  }

  void _enterApp() {
    if (!mounted) return;
    context.go('/dashboard');
  }

  // ---------- Email / Password Login ----------

  Future<void> _handleEmailLogin() async {
    if (_isLoading) return; // Rate-limiting guard against double submission
    final email = _sanitizeAuthInput(_emailController.text);
    final password = _sanitizeAuthInput(_passwordController.text);

    // Check empty fields
    if (email.isEmpty || password.isEmpty) {
      _showUserDoesNotExistDialog(
        title: 'User Does Not Exist',
        message:
            'User does not exist. Please enter valid email and password credentials.',
      );
      return;
    }

    if (email.toLowerCase().endsWith(_demoEmailDomain)) {
      await _enterDemo(email);
      return;
    }

    // Real Firebase Auth login (Strict Super Admin / Firebase Database verification)
    setState(() => _isLoading = true);
    final startTime = DateTime.now();

    try {
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCred.user;
      if (user != null) {
        bool existsInDatabase = false;
        bool isDisabled = false;

        try {
          // 1. Direct UID lookup in Firestore 'users' database collection
          final uidDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (uidDoc.exists && uidDoc.data() != null) {
            existsInDatabase = true;
            final data = uidDoc.data()!;
            if (data['status'] == 'Disabled' || data['status'] == 'Inactive') {
              isDisabled = true;
            }
          } else {
            // 2. Email fallback query in 'users' database collection
            if (user.email != null && user.email!.isNotEmpty) {
              final querySnap = await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isEqualTo: user.email!.toLowerCase().trim())
                  .get();

              if (querySnap.docs.isNotEmpty) {
                existsInDatabase = true;
                final data = querySnap.docs.first.data();
                if (data['status'] == 'Disabled' ||
                    data['status'] == 'Inactive') {
                  isDisabled = true;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Database check warning: $e');
        }

        // Enforce timing floor (500ms) to guard against response-timing side channel attacks
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsed < 500) {
          await Future.delayed(Duration(milliseconds: 500 - elapsed));
        }

        // If user is marked disabled/inactive in database
        if (isDisabled) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            _showUserDoesNotExistDialog(
              title: 'Account Disabled',
              message: 'Your account has been disabled by Super Admin.',
            );
          }
          return;
        }

        // If user does NOT exist in Firestore database
        if (!existsInDatabase) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            _showUserDoesNotExistDialog(
              title: 'User Does Not Exist',
              message:
                  'User does not exist in database. Please contact Super Admin to create your account.',
            );
          }
          return;
        }

        // User exists in database and is active -> allow login!
        if (_rememberMe) {
          await _secureStorage.write(key: 'remembered_email', value: email);
          await _secureStorage.write(key: 'remember_me', value: 'true');
        } else {
          await _secureStorage.delete(key: 'remembered_email');
          await _secureStorage.write(key: 'remember_me', value: 'false');
        }

        await _syncUserProfile(user);
        await DeviceSessionService.instance.registerNewSession(user.uid);
        if (!mounted) return;
        _enterApp();
      } else {
        if (!mounted) return;
        _showUserDoesNotExistDialog(
          title: 'User Does Not Exist',
          message:
              'User does not exist in database. Please contact Super Admin to create your account.',
        );
      }
    } catch (e) {
      debugPrint('Login auth exception: $e');

      // Enforce timing floor (500ms) to guard against response-timing side channel attacks
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }

      if (!mounted) return;

      String errorTitle = 'Authentication Error';
      String errorMessage =
          'Unable to sign in. Please check your credentials or contact Super Admin.';

      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorTitle = 'User Does Not Exist';
            errorMessage =
                'User does not exist in database. Please contact Super Admin to create your account.';
            break;
          case 'wrong-password':
          case 'invalid-credential':
            errorTitle = 'Invalid Credentials';
            errorMessage =
                'Invalid email or password. Please check your credentials and try again.';
            break;
          case 'user-disabled':
            errorTitle = 'Account Disabled';
            errorMessage = 'Your account has been disabled by Super Admin.';
            break;
          case 'too-many-requests':
            errorTitle = 'Too Many Requests';
            errorMessage =
                'Too many failed login attempts. Please wait a few minutes before trying again.';
            break;
          case 'network-request-failed':
            errorTitle = 'Network Error';
            errorMessage =
                'Network connection failed. Please check your internet connection.';
            break;
          default:
            if (e.message != null && e.message!.contains('API key expired')) {
              errorTitle = 'Firebase Configuration Error';
              errorMessage =
                  'Firebase API key has expired. Please renew the API key in Firebase Console.';
            } else {
              errorMessage = e.message ?? errorMessage;
            }
        }
      }

      _showUserDoesNotExistDialog(title: errorTitle, message: errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- Email / Password Signup ----------

  Future<void> _handleEmailSignup() async {
    if (_isLoading) return; // Rate-limiting guard against double submission
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    // Loose shape check (name@domain.tld): allows plus addresses and long
    // endings like .health or .clinic. Firebase does the real check.
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@.]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    // Password strength check
    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      if (credential.user != null) {
        await _syncUserProfile(credential.user!, name: name);
        await DeviceSessionService.instance.registerNewSession(
          credential.user!.uid,
        );
      }
      if (!mounted) return;
      _enterApp();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? 'Signup failed');
    } catch (e) {
      if (!mounted) return;
      _showError('Signup failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- Google Sign-In ----------

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final userCredential = await _authService.signInWithGoogle();
      final user = userCredential.user;
      if (user != null) {
        await DeviceSessionService.instance.registerNewSession(user.uid);
        await _syncUserProfile(user);
      }
      if (!mounted) return;
      _enterApp();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'sign-in-cancelled') return;
      // The browser sign-in on Windows says what went wrong in plain words.
      _showError(
        e.code == 'google-desktop-failed'
            ? (e.message ?? 'Google sign-in failed')
            : 'Google sign-in failed',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('cancelled')) {
        _showError('Google sign-in failed');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- Phone Sign-In ----------

  Future<void> _handlePhoneSignIn() async {
    if (_isLoading) return;

    final result = await showPhoneAuthSheet(context, authService: _authService);

    if (result != null) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await DeviceSessionService.instance.registerNewSession(currentUser.uid);
        await _syncUserProfile(currentUser);
      }
      if (mounted) {
        _enterApp();
      }
    }
  }

  // ---------- Forgot password ----------

  Future<void> _handleForgotPassword() async {
    final email = _sanitizeAuthInput(_emailController.text).toLowerCase();
    if (!email.contains('@')) {
      _showError('Enter your email above, then tap Forgot password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } catch (_) {
      // Same answer either way: never say whether an account exists.
    }
    _showAuthToast(
      'If $email has a CruDoc account, a link to reset the password is on '
      'its way.',
      isError: false,
    );
  }

  /// Phone sign-in needs a phone: web and desktop have none.
  bool get _phoneSignInAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isLogin => _mobileMode == _AuthMode.login;

  void _switchMode() => setState(() {
    _mobileMode = _isLogin ? _AuthMode.signup : _AuthMode.login;
    _notice = null;
  });

  void _submit() => _isLogin ? _handleEmailLogin() : _handleEmailSignup();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Blank while the first-launch flag loads, so the form doesn't open on
    // Sign in and then switch to Create account.
    if (_getStarted == null) return Scaffold(backgroundColor: c.canvas);
    final login = _isLogin;
    final busy = _isLoading;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s16,
              vertical: CruSpace.s32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kAuthMaxWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AppMark(),
                    const SizedBox(height: CruSpace.s32),
                    Semantics(
                      header: true,
                      child: Text(
                        login ? 'Sign in' : 'Create your account',
                        style: CruType.largeTitle.tint(c.label),
                      ),
                    ),
                    const SizedBox(height: CruSpace.s6),
                    Text(
                      login
                          ? 'Welcome back to CruDoc.'
                          : 'Next, set up your practice or join your clinic.',
                      style: CruType.lead.tint(c.label2),
                    ),
                    const SizedBox(height: CruSpace.s24),
                    CruCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!login) ...[
                            CruTextField(
                              label: 'Your name',
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                            ),
                            const SizedBox(height: CruSpace.s16),
                          ],
                          CruTextField(
                            label: 'Email',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: CruSpace.s16),
                          CruTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: [
                              login
                                  ? AutofillHints.password
                                  : AutofillHints.newPassword,
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            trailing: CruLink(
                              label: _obscurePassword ? 'Show' : 'Hide',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          if (login)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: CruSpace.s8,
                                ),
                                child: CruLink(
                                  label: 'Forgot password?',
                                  onPressed: _handleForgotPassword,
                                ),
                              ),
                            ),
                          if (_notice != null) ...[
                            const SizedBox(height: CruSpace.s12),
                            Text(
                              _notice!,
                              style: CruType.text.tint(
                                _noticeIsError ? c.label : c.greenText,
                              ),
                            ),
                          ],
                          const SizedBox(height: CruSpace.s20),
                          CruButton(
                            label: busy
                                ? 'Please wait…'
                                : (login ? 'Sign in' : 'Create account'),
                            large: true,
                            expand: true,
                            onPressed: busy ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CruSpace.s20),
                    const _OrDivider(),
                    const SizedBox(height: CruSpace.s20),
                    CruButton(
                      label: 'Continue with Google',
                      kind: CruButtonKind.secondary,
                      large: true,
                      expand: true,
                      onPressed: busy ? null : _handleGoogleSignIn,
                    ),
                    if (_phoneSignInAvailable) ...[
                      const SizedBox(height: CruSpace.s12),
                      CruButton(
                        label: 'Continue with phone number',
                        icon: CruIcons.phone,
                        kind: CruButtonKind.secondary,
                        large: true,
                        expand: true,
                        onPressed: busy ? null : _handlePhoneSignIn,
                      ),
                    ],
                    const SizedBox(height: CruSpace.s24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: CruSpace.s4,
                      children: [
                        Text(
                          login ? 'New to CruDoc?' : 'Already have an account?',
                          style: CruType.text.tint(c.label2),
                        ),
                        CruLink(
                          label: login ? 'Create an account' : 'Sign in',
                          onPressed: _switchMode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content column width on wide screens.
const double _kAuthMaxWidth = 400;

enum _AuthMode { login, signup }

/// The app mark and wordmark, as in the sidebar.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: 'CruDoc',
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: CruSize.appMark,
            height: CruSize.appMark,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.accent,
              shape: cruShape(CruRadius.appMark),
            ),
            child: CruIcon(
              CruIcons.plus,
              size: 16,
              strokeWidth: 3.4,
              color: c.onAccent,
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          Text('CruDoc', style: CruType.wordmark.tint(c.label)),
        ],
      ),
    );
  }
}

/// A hairline either side of "or".
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        const Expanded(child: CruSeparator()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
          child: Text('or', style: CruType.caption.tint(c.label3)),
        ),
        const Expanded(child: CruSeparator()),
      ],
    );
  }
}
