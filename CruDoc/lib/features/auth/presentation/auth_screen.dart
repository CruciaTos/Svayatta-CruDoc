import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/services/device_session_service.dart';
import 'package:doctor_management_app/features/auth/presentation/phone_auth_sheet.dart';
import 'package:doctor_management_app/features/auth/presentation/widgets/specialty_onboarding_dialog.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with TickerProviderStateMixin {
  // Mobile Controllers
  late final PageController _pageController;
  late final AnimationController _backgroundController;
  late final AnimationController _contentController;

  // Web Scroll Controller (initialized eagerly to prevent LateInitializationError)
  final ScrollController _webScrollController = ScrollController();

  final AuthService _authService = AuthService();

  int _currentPage = 1; // Start on login page for mobile
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Form Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPage);
    
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )..forward();

    _loadRememberedCredentials();

    // Clean empty text controllers by default
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final savedEmail = await _secureStorage.read(key: 'remembered_email');
      final rememberFlag = await _secureStorage.read(key: 'remember_me');
      if (mounted) {
        setState(() {
          if (rememberFlag == 'true' && savedEmail != null && savedEmail.trim().isNotEmpty) {
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
    _pageController.dispose();
    _backgroundController.dispose();
    _contentController.dispose();
    _webScrollController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _fillDemoCredentials() {
    final spec = ref.read(authSpecialtyProvider);
    setState(() {
      _emailController.text = spec.demoEmail;
      _passwordController.text = spec.demoPassword;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(spec.icon, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            Text('${spec.label} demo credentials pre-filled! Click Log in.'),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// 1-Click fast login into the Trial Demo account for developers.
  /// Activates an instant local demo session (rate-limit immune) and syncs with Firebase in background.
  Future<void> _handleTrialDemoLogin() async {
    final spec = ref.read(authSpecialtyProvider);
    _emailController.text = spec.demoEmail;
    _passwordController.text = spec.demoPassword;

    // 1. Activate trial demo session immediately (bypasses Firebase network rate-limits)
    DemoSessionService.startDemoSession(spec);

    // 2. Background attempt to authenticate with Firebase if available
    unawaited(() async {
      try {
        UserCredential userCred;
        try {
          userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: spec.demoEmail,
            password: spec.demoPassword,
          );
        } catch (_) {
          userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: spec.demoEmail,
            password: spec.demoPassword,
          );
        }

        final user = userCred.user;
        if (user != null) {
          final docRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);
          await docRef.set({
            'uid': user.uid,
            'email': spec.demoEmail,
            'displayName': 'Dr. Demo Doctor',
            'doctorName': 'Dr. Demo Doctor',
            'specialty': spec.label,
            'specialization': spec.label,
            'status': 'Active',
            'role': 'doctor',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Trial demo background auth note: $e');
      }
    }());

    if (_rememberMe) {
      unawaited(_secureStorage.write(
          key: 'remembered_email', value: spec.demoEmail));
      unawaited(_secureStorage.write(key: 'remember_me', value: 'true'));
    }

    if (!mounted) return;
    _enterApp();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _syncUserProfile(User user, {String? name}) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();

      String derivedName = name?.trim() ?? '';
      if (derivedName.isEmpty && user.displayName != null && user.displayName!.trim().isNotEmpty) {
        derivedName = user.displayName!.trim();
      }
      if (derivedName.isEmpty && user.email != null && user.email!.isNotEmpty) {
        final emailPart = user.email!.split('@').first;
        final parts = emailPart.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty);
        if (parts.isNotEmpty) {
          derivedName = parts.map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase()).join(' ');
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
          'displayName': derivedName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (derivedName.isNotEmpty) {
        final existingName = snap.data()?['displayName'] as String?;
        if (existingName == null || existingName.isEmpty) {
          await ref.update({'displayName': derivedName});
        }
      }
    } catch (e) {
      debugPrint('Sync user profile warning: $e');
    }
  }

  /// Sanitizes user credentials to prevent script injection / XSS / SQLi patterns
  String _sanitizeAuthInput(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Strip HTML & script tags
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // Strip non-printable control chars
        .replaceAll(RegExp(r"['\x22;\\]"), '') // Strip injection delimiters
        .trim();
  }

  OverlayEntry? _toastOverlayEntry;

  void _showAuthToast(String message, {bool isError = true}) {
    if (!mounted) return;

    // Dismiss previous active toast if any
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;

    final overlayState = Overlay.of(context);
    _toastOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 28,
          left: 20,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(_toastOverlayEntry!);

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (_toastOverlayEntry != null && _toastOverlayEntry!.mounted) {
        _toastOverlayEntry?.remove();
        _toastOverlayEntry = null;
      }
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
                if (data['status'] == 'Disabled' || data['status'] == 'Inactive') {
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
      _showUserDoesNotExistDialog(
        title: 'User Does Not Exist',
        message:
            'User does not exist in database. Please contact Super Admin to create your account.',
      );
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

    // Email format validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
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
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user != null) {
        await _syncUserProfile(credential.user!, name: name);
        await DeviceSessionService.instance.registerNewSession(credential.user!.uid);
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
        if (mounted) await _maybeOnboardSpecialty(user);
      }
      if (!mounted) return;
      _enterApp();
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

    final result = await showPhoneAuthSheet(
      context,
      authService: _authService,
    );

    if (result != null) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await DeviceSessionService.instance.registerNewSession(currentUser.uid);
        if (mounted) await _maybeOnboardSpecialty(currentUser);
      }
      if (mounted) {
        _enterApp();
      }
    }
  }

  /// Shows the specialty onboarding dialog if the user has no specialty set.
  Future<void> _maybeOnboardSpecialty(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final hasSpecialty = data != null &&
          ((data['specialty'] as String?)?.trim().isNotEmpty == true ||
           (data['specialization'] as String?)?.trim().isNotEmpty == true);
      if (!hasSpecialty && mounted) {
        await showSpecialtyOnboardingDialog(context);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktopLayout = screenWidth > 800 && (
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux
    );

    if (isDesktopLayout) {
      return _buildWebAuthView(context);
    }

    return _buildMobileAuthView(context);
  }

  // ==================== MOBILE AUTH VIEW (UNCHANGED) ====================

  Widget _buildMobileAuthView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF087DFF),
      body: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _AuthBackgroundPainter(
                    progress: _backgroundController.value,
                  ),
                ),
              ),
              SafeArea(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _handlePageChanged,
                  children: [
                    // Page 0: Intro
                    _IntroPanel(
                      progress: _backgroundController.value,
                      onLogin: () => _goToPage(1),
                      onSignup: () => _goToPage(2),
                    ),
                    // Page 1: Login
                    _AuthFormPanel(
                      progress: _backgroundController.value,
                      mode: _AuthMode.login,
                      obscurePassword: _obscurePassword,
                      isLoading: _isLoading,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      nameController: _nameController,
                      onBack: () => _goToPage(0),
                      onObscureToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onPrimary: _handleEmailLogin,
                      onTrialDemoLogin: _handleTrialDemoLogin,
                      onSecondary: () => _goToPage(2),
                      onGoogleSignIn: _handleGoogleSignIn,
                      onPhoneSignIn: _handlePhoneSignIn,
                    ),
                    // Page 2: Signup
                    _AuthFormPanel(
                      progress: _backgroundController.value,
                      mode: _AuthMode.signup,
                      obscurePassword: _obscurePassword,
                      isLoading: _isLoading,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      nameController: _nameController,
                      onBack: () => _goToPage(1),
                      onObscureToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onPrimary: _handleEmailSignup,
                      onSecondary: () => _goToPage(1),
                      onGoogleSignIn: _handleGoogleSignIn,
                      onPhoneSignIn: _handlePhoneSignIn,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: _PageDots(
                  count: 3,
                  activeIndex: _currentPage,
                  onDotTap: _goToPage,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handlePageChanged(int index) {
    setState(() => _currentPage = index);
    _contentController
      ..reset()
      ..forward();
  }

  // ==================== WEB AUTH VIEW — CLEAN MEDICAL SPLIT DESIGN ====================

  Widget _buildWebAuthView(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final selectedSpecialty = ref.watch(authSpecialtyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, _) {
          return Column(
            children: [
              // Full Height Split Body
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left — Sober Medical Illustration Panel
                    Expanded(
                      flex: 55,
                      child: _WebIllustrationPanel(
                        progress: _backgroundController.value,
                        selectedSpecialty: selectedSpecialty,
                        onSpecialtySelected: (spec) {
                          ref.read(authSpecialtyProvider.notifier).select(spec);
                        },
                      ),
                    ),

                    // Right — Sleek & Clean Login Form Panel
                    Container(
                      width: math.min(screenSize.width * 0.42, 500),
                      color: Colors.white,
                      child: Center(
                        child: SingleChildScrollView(
                          controller: _webScrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 56,
                            vertical: 48,
                          ),
                          child: _WebAuthPortalCard(
                            obscurePassword: _obscurePassword,
                            isLoading: _isLoading,
                            rememberMe: _rememberMe,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            selectedSpecialty: selectedSpecialty,
                            onObscureToggle: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            onRememberMeToggle: () => setState(
                                () => _rememberMe = !_rememberMe),
                            onPrimarySubmit: _handleEmailLogin,
                            onTrialDemoLogin: _handleTrialDemoLogin,
                            onDemoFill: _fillDemoCredentials,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Minimal Footer
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 48),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFF1F5F9)),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      ' CruDoc Clinical Management System. All Rights Reserved.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {},
                      child: const Text(
                        'Terms & Conditions',
                        style: TextStyle(
                          color: Color(0xFF00ACC1),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    InkWell(
                      onTap: () {},
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: Color(0xFF00ACC1),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==================== WEB NAVBAR HEADER ====================



// ==================== WEB ILLUSTRATION PANEL ====================

class _WebIllustrationPanel extends StatelessWidget {
  const _WebIllustrationPanel({
    required this.progress,
    required this.selectedSpecialty,
    required this.onSpecialtySelected,
  });

  final double progress;
  final DoctorSpecialty selectedSpecialty;
  final ValueChanged<DoctorSpecialty> onSpecialtySelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selectedSpecialty.gradientColors,
        ),
      ),
      child: Stack(
        children: [
          // Background decorative circles
          Positioned(
            left: -60,
            top: -60,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: selectedSpecialty.accentColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -40,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: selectedSpecialty.accentColor.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Animated ECG Line Painter
          Positioned.fill(
            child: CustomPaint(
              painter: _WebIllustrationPainter(
                progress: progress,
                accentColor: selectedSpecialty.accentColor,
              ),
            ),
          ),

          // Main Centerpiece Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Soft glass backdrop container for specialty icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  width: 440,
                  height: 330,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(220),
                    boxShadow: [
                      BoxShadow(
                        color: selectedSpecialty.accentColor.withValues(alpha: 0.12),
                        blurRadius: 50,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _DoctorFigure(isFemale: false),
                      _SpecialtyHeroIcon(
                        progress: progress,
                        specialty: selectedSpecialty,
                      ),
                      _DoctorFigure(isFemale: true),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    'CruDoc ${selectedSpecialty.shortLabel} Suite',
                    key: ValueKey(selectedSpecialty.type),
                    style: TextStyle(
                      color: HSLColor.fromColor(selectedSpecialty.accentColor)
                          .withLightness(0.22)
                          .toColor(),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontFamily: AppColors.headingFontFamily,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    selectedSpecialty.tagline,
                    key: ValueKey(selectedSpecialty.tagline),
                    style: TextStyle(
                      color: HSLColor.fromColor(selectedSpecialty.accentColor)
                          .withLightness(0.30)
                          .toColor(),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Specialty Selector Pills (bottom of panel) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: _SpecialtyPillBar(
              selectedSpecialty: selectedSpecialty,
              onSelected: onSpecialtySelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated specialty icon that replaces the static heart.
class _SpecialtyHeroIcon extends StatelessWidget {
  const _SpecialtyHeroIcon({required this.progress, required this.specialty});

  final double progress;
  final DoctorSpecialty specialty;

  @override
  Widget build(BuildContext context) {
    final double scale = 1.0 + math.sin(progress * math.pi * 2) * 0.04;
    return Transform.scale(
      scale: scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: specialty.accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: specialty.accentColor.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            specialty.icon,
            key: ValueKey(specialty.type),
            color: Colors.white,
            size: 52,
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrollable pill bar for selecting a medical specialty.
class _SpecialtyPillBar extends StatelessWidget {
  const _SpecialtyPillBar({
    required this.selectedSpecialty,
    required this.onSelected,
  });

  final DoctorSpecialty selectedSpecialty;
  final ValueChanged<DoctorSpecialty> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: DoctorSpecialty.all.map((spec) {
          final isSelected = spec.type == selectedSpecialty.type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onSelected(spec),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? spec.accentColor
                        : Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? spec.accentColor
                          : Colors.black.withValues(alpha: 0.06),
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: spec.accentColor.withValues(alpha: 0.30),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        spec.icon,
                        size: 15,
                        color: isSelected
                            ? Colors.white
                            : spec.accentColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        spec.shortLabel,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF334155),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppColors.bodyFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DoctorFigure extends StatelessWidget {
  const _DoctorFigure({required this.isFemale});

  final bool isFemale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFD7A97A),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 28,
              decoration: BoxDecoration(
                color: isFemale
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF424242),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(5)),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              width: 18,
              height: 28,
              decoration: BoxDecoration(
                color: isFemale
                    ? const Color(0xFF1A237E)
                    : const Color(0xFF424242),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(5)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// _HeartIcon replaced by _SpecialtyHeroIcon above.



// ==================== WEB ILLUSTRATION PAINTER ====================

class _WebIllustrationPainter extends CustomPainter {
  _WebIllustrationPainter({
    required this.progress,
    this.accentColor = const Color(0xFF00ACC1),
  });

  final double progress;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double wave = math.sin(progress * math.pi * 2);
    final Paint ecgPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.30)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double y0 = size.height * 0.80 + wave * 4;
    final double segW = size.width / 10;
    final Path ecgPath = Path()..moveTo(0, y0);
    ecgPath
      ..lineTo(segW * 2, y0)
      ..lineTo(segW * 2.5, y0 - 18)
      ..lineTo(segW * 3, y0 + 30)
      ..lineTo(segW * 3.5, y0 - 40)
      ..lineTo(segW * 4, y0 + 20)
      ..lineTo(segW * 4.5, y0)
      ..lineTo(segW * 6.5, y0)
      ..lineTo(segW * 7, y0 - 14)
      ..lineTo(segW * 7.5, y0 + 10)
      ..lineTo(size.width, y0);
    canvas.drawPath(ecgPath, ecgPaint);
  }

  @override
  bool shouldRepaint(covariant _WebIllustrationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
}

// ==================== WEB AUTH PORTAL CARD (LOGIN ONLY) ====================

class _WebAuthPortalCard extends StatelessWidget {
  const _WebAuthPortalCard({
    required this.obscurePassword,
    required this.isLoading,
    required this.rememberMe,
    required this.emailController,
    required this.passwordController,
    required this.selectedSpecialty,
    required this.onObscureToggle,
    required this.onRememberMeToggle,
    required this.onPrimarySubmit,
    required this.onTrialDemoLogin,
    required this.onDemoFill,
  });

  final bool obscurePassword;
  final bool isLoading;
  final bool rememberMe;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final DoctorSpecialty selectedSpecialty;
  final VoidCallback onObscureToggle;
  final VoidCallback onRememberMeToggle;
  final VoidCallback onPrimarySubmit;
  final VoidCallback onTrialDemoLogin;
  final VoidCallback onDemoFill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Specialty-Themed Logo Header
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selectedSpecialty.accentColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: selectedSpecialty.accentColor.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  selectedSpecialty.icon,
                  key: ValueKey(selectedSpecialty.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'cru.doc',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.5,
                    fontFamily: AppColors.headingFontFamily,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '${selectedSpecialty.shortLabel} Clinical Suite',
                    key: ValueKey(selectedSpecialty.shortLabel),
                    style: TextStyle(
                      color: selectedSpecialty.accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 36),

        // Welcome Doctor Title (specialty-adaptive)
        const Text(
          'Welcome Back Doctor !',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontFamily: AppColors.headingFontFamily,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            selectedSpecialty.tagline,
            key: ValueKey(selectedSpecialty.tagline),
            style: TextStyle(
              color: selectedSpecialty.accentColor.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Email Field
        _WebTextField(
          controller: emailController,
          hintText: 'Enter your email address',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 16),

        // Password Field
        _WebTextField(
          controller: passwordController,
          hintText: 'Enter your password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          trailing: IconButton(
            onPressed: onObscureToggle,
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color(0xFF94A3B8),
              size: 18,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Remember Me & Need Help
        Row(
          children: [
            GestureDetector(
              onTap: onRememberMeToggle,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      rememberMe
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: rememberMe
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember Me',
                      style: TextStyle(
                        color: rememberMe
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: onDemoFill,
              child: const Text(
                'Need Help?',
                style: TextStyle(
                  color: Color(0xFF00ACC1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Login Button — accent color matches selected specialty
        SizedBox(
          height: 52,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            child: ElevatedButton(
              onPressed: isLoading ? null : onPrimarySubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedSpecialty.accentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    selectedSpecialty.accentColor.withValues(alpha: 0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Login as ${selectedSpecialty.label}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        fontFamily: AppColors.bodyFontFamily,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 1-Click Trial Demo Mode Button
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onTrialDemoLogin,
            icon: const Icon(Icons.bolt_rounded,
                color: Color(0xFF059669), size: 20),
            label: const Text(
              'Launch Trial Demo Mode (Dev Account)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
                fontFamily: AppColors.bodyFontFamily,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  const Color(0xFF059669).withValues(alpha: 0.06),
              side: const BorderSide(color: Color(0xFF059669), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== WEB TEXT FIELD ====================

class _WebTextField extends StatelessWidget {
  const _WebTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: const Color(0xFF00ACC1),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF00ACC1), size: 18),
        suffixIcon: trailing,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0xFF00ACC1),
            width: 1.8,
          ),
        ),
      ),
    );
  }
}



// ==================== ORIGINAL MOBILE INTRO PANEL ====================

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({
    required this.progress,
    required this.onLogin,
    required this.onSignup,
  });

  final double progress;
  final VoidCallback onLogin;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPanel(
      progress: progress,
      whiteWaveHeight: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'cru.doc',
              style: TextStyle(
                color: Colors.white,
                fontFamily: AppColors.headingFontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 820),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doctor\nmanagement',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Manage patients, visits, inventory, and revenue from one smooth workspace.',
                    style: TextStyle(
                      color: Color(0xC7FFFFFF),
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _AuthButton(label: 'Log in', filled: false, onPressed: onLogin),
            const SizedBox(height: 10),
            _AuthButton(label: 'Sign up', filled: true, onPressed: onSignup),
          ],
        ),
      ),
    );
  }
}

// ==================== AUTH MODE ENUM ====================

enum _AuthMode { login, signup }

// ==================== ORIGINAL MOBILE FORM PANEL ====================

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({
    super.key,
    required this.progress,
    required this.mode,
    required this.obscurePassword,
    required this.isLoading,
    required this.emailController,
    required this.passwordController,
    required this.nameController,
    required this.onBack,
    required this.onObscureToggle,
    required this.onPrimary,
    this.onTrialDemoLogin,
    required this.onSecondary,
    required this.onGoogleSignIn,
    required this.onPhoneSignIn,
  });

  final double progress;
  final _AuthMode mode;
  final bool obscurePassword;
  final bool isLoading;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController nameController;
  final VoidCallback onBack;
  final VoidCallback onObscureToggle;
  final VoidCallback onPrimary;
  final VoidCallback? onTrialDemoLogin;
  final VoidCallback onSecondary;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onPhoneSignIn;

  bool get _isLogin => mode == _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPanel(
      progress: progress,
      whiteWaveHeight: 0.32,
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 14,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 20,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(mode),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 620),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(-18 * (1 - value), 0),
                    child: child,
                  ),
                );
              },
              child: Text(
                _isLogin ? 'Welcome\nBack' : 'Create\nAccount',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: AppColors.headingFontFamily,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _AuthForm(
                  key: ValueKey(mode),
                  mode: mode,
                  obscurePassword: obscurePassword,
                  isLoading: isLoading,
                  emailController: emailController,
                  passwordController: passwordController,
                  nameController: nameController,
                  onObscureToggle: onObscureToggle,
                  onPrimary: onPrimary,
                  onTrialDemoLogin: onTrialDemoLogin,
                  onSecondary: onSecondary,
                  onGoogleSignIn: onGoogleSignIn,
                  onPhoneSignIn: onPhoneSignIn,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ORIGINAL MOBILE AUTH FORM ====================

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    super.key,
    required this.mode,
    required this.obscurePassword,
    required this.isLoading,
    required this.emailController,
    required this.passwordController,
    required this.nameController,
    required this.onObscureToggle,
    required this.onPrimary,
    this.onTrialDemoLogin,
    required this.onSecondary,
    required this.onGoogleSignIn,
    required this.onPhoneSignIn,
  });

  final _AuthMode mode;
  final bool obscurePassword;
  final bool isLoading;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController nameController;
  final VoidCallback onObscureToggle;
  final VoidCallback onPrimary;
  final VoidCallback? onTrialDemoLogin;
  final VoidCallback onSecondary;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onPhoneSignIn;

  bool get _isLogin => mode == _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isLogin) ...[
          _AuthTextField(
            icon: Icons.person_rounded,
            hintText: 'Name',
            controller: nameController,
          ),
          const SizedBox(height: 8),
        ],
        _AuthTextField(
          icon: Icons.email_rounded,
          hintText: 'Email',
          controller: emailController,
          trailing: _isLogin
              ? const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF66A8FF),
                  size: 18,
                )
              : null,
        ),
        const SizedBox(height: 8),
        _AuthTextField(
          icon: Icons.lock_rounded,
          hintText: 'Password',
          controller: passwordController,
          obscureText: obscurePassword,
          trailing: IconButton(
            onPressed: onObscureToggle,
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: const Color(0xFFB6B6B6),
              size: 17,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ),
        if (_isLogin) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Demo: demo1234',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: const Color(0xFF0A7BFF).withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else
          const SizedBox(height: 10),
        const SizedBox(height: 4),
        _PrimaryButton(
          label: _isLogin ? 'Log in' : 'Sign up',
          isLoading: isLoading,
          onPressed: onPrimary,
        ),
        if (_isLogin && onTrialDemoLogin != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onTrialDemoLogin,
              icon: const Icon(Icons.bolt_rounded,
                  color: Color(0xFF059669), size: 18),
              label: const Text(
                'Launch Trial Demo Mode',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF059669),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF059669).withValues(alpha: 0.08),
                side: const BorderSide(color: Color(0xFF059669), width: 1.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        const _DividerLabel(),
        const SizedBox(height: 10),
        _SocialButton(
          icon: Icons.g_mobiledata_rounded,
          label: 'Continue with Google',
          onPressed: onGoogleSignIn,
        ),
        const SizedBox(height: 6),
        _SocialButton(
          icon: Icons.phone_rounded,
          label: 'Sign in with Phone',
          outlined: true,
          onPressed: onPhoneSignIn,
        ),
        const SizedBox(height: 10),
        _AuthButton(
          label: _isLogin ? 'Sign up' : 'Log in',
          filled: false,
          darkText: true,
          onPressed: onSecondary,
        ),
      ],
    );
  }
}

// ==================== ORIGINAL REUSABLE WIDGETS ====================

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.icon,
    required this.hintText,
    this.controller,
    this.obscureText = false,
    this.trailing,
  });

  final IconData icon;
  final String hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      cursorColor: const Color(0xFF0A7BFF),
      style: const TextStyle(
        color: Color(0xFF4A4A4A),
        fontFamily: AppColors.bodyFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFFB7B7B7),
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFFC0C0C0), size: 15),
        prefixIconConstraints: const BoxConstraints(minWidth: 28),
        suffixIcon: trailing,
        suffixIconConstraints: const BoxConstraints(minWidth: 30),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE1E1E1), width: 1.3),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF8FC4FF), width: 1.6),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 4,
          shadowColor: const Color(0xFF0A7BFF).withValues(alpha: 0.22),
          backgroundColor: const Color(0xFF0A7BFF),
          disabledBackgroundColor:
              const Color(0xFF0A7BFF).withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final bool outlined;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 38,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: outlined ? Colors.transparent : Colors.white,
          foregroundColor:
              outlined ? const Color(0xFF9A9A9A) : const Color(0xFF4A4A4A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: outlined
                  ? const Color(0xFFDADADA).withValues(alpha: 0.9)
                  : const Color(0xFFE8E8E8),
              width: 1.2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color:
                    outlined ? const Color(0xFF9A9A9A) : const Color(0xFF4A4A4A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.filled,
    required this.onPressed,
    this.darkText = false,
  });

  final String label;
  final bool filled;
  final bool darkText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color foreground = filled
        ? Colors.white
        : darkText
            ? const Color(0xFF9A9A9A)
            : const Color(0xFF0A7BFF);

    return SizedBox(
      width: double.infinity,
      height: 36,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: filled ? 4 : 0,
          shadowColor: const Color(0xFF0A7BFF).withValues(alpha: 0.22),
          backgroundColor: filled ? const Color(0xFF0A7BFF) : Colors.white,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(
              color: filled
                  ? Colors.transparent
                  : const Color(0xFFDADADA).withValues(alpha: 0.9),
              width: 1.4,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFE7E7E7), height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'or',
            style: TextStyle(
              color: Color(0xFFB7B7B7),
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFE7E7E7), height: 1)),
      ],
    );
  }
}

// ==================== ORIGINAL ANIMATED PANEL ====================

class _AnimatedPanel extends StatelessWidget {
  const _AnimatedPanel({
    required this.progress,
    required this.whiteWaveHeight,
    required this.child,
  });

  final double progress;
  final double whiteWaveHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF087DFF), Color(0xFF075BCE)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WaterPanelPainter(
                progress: progress,
                whiteWaveHeight: whiteWaveHeight,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ==================== ORIGINAL PAGE DOTS ====================

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.activeIndex,
    required this.onDotTap,
  });

  final int count;
  final int activeIndex;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final bool active = activeIndex == index;
        return GestureDetector(
          onTap: () => onDotTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: active ? 0.9 : 0.42),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      }),
    );
  }
}

// ==================== ORIGINAL PAINTERS ====================

class _WaterPanelPainter extends CustomPainter {
  _WaterPanelPainter({required this.progress, required this.whiteWaveHeight});

  final double progress;
  final double whiteWaveHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint darkBlue = Paint()..color = const Color(0xFF065BCD);
    final Paint lightBlue = Paint()..color = const Color(0xFF1086FF);
    final Paint bubblePaint = Paint()..color = const Color(0xFF2292FF);

    final double wave = math.sin(progress * math.pi * 2);

    final Path topBlob = Path()
      ..moveTo(size.width * -0.05, size.height * 0.29)
      ..cubicTo(
        size.width * 0.18,
        size.height * (0.22 + wave * 0.03),
        size.width * 0.30,
        size.height * 0.46,
        size.width * 0.55,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.83,
        size.height * (0.19 - wave * 0.025),
        size.width * 1.04,
        size.height * 0.28,
        size.width * 1.08,
        size.height * 0.10,
      )
      ..lineTo(size.width * 1.08, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(topBlob, lightBlue);

    final Path middleBlob = Path()
      ..moveTo(size.width * -0.08, size.height * 0.51)
      ..cubicTo(
        size.width * 0.18,
        size.height * (0.43 - wave * 0.025),
        size.width * 0.35,
        size.height * 0.62,
        size.width * 0.57,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.77,
        size.height * (0.49 + wave * 0.02),
        size.width * 0.70,
        size.height * 0.35,
        size.width * 1.05,
        size.height * 0.46,
      )
      ..lineTo(size.width * 1.05, size.height)
      ..lineTo(size.width * -0.08, size.height)
      ..close();
    canvas.drawPath(middleBlob, darkBlue);

    if (whiteWaveHeight > 0) {
      final double top = size.height * whiteWaveHeight;
      final Path whiteWave = Path()
        ..moveTo(0, top)
        ..cubicTo(
          size.width * 0.22,
          top - 24 - wave * 8,
          size.width * 0.40,
          top + 20,
          size.width * 0.58,
          top + 2 + wave * 8,
        )
        ..cubicTo(
          size.width * 0.77,
          top - 17,
          size.width * 0.91,
          top + 10 + wave * 8,
          size.width,
          top - 8,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(whiteWave, Paint()..color = Colors.white);
    }

    final bubbles = <_Bubble>[
      _Bubble(0.84, 0.07, 0.09, 0.00),
      _Bubble(0.77, 0.21, 0.035, 0.34),
      _Bubble(0.15, 0.45, 0.028, 0.56),
      _Bubble(0.61, 0.39, 0.085, 0.13),
      _Bubble(0.89, 0.38, 0.03, 0.72),
      _Bubble(0.32, 0.05, 0.03, 0.44),
      _Bubble(0.72, 0.13, 0.027, 0.88),
    ];

    for (final bubble in bubbles) {
      final double float = math.sin((progress + bubble.phase) * math.pi * 2);
      final Offset center = Offset(
        size.width * bubble.x + float * 5,
        size.height * bubble.y - float * 6,
      );
      canvas.drawCircle(center, size.width * bubble.radius, bubblePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaterPanelPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.whiteWaveHeight != whiteWaveHeight;
  }
}

class _AuthBackgroundPainter extends CustomPainter {
  _AuthBackgroundPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.00),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.18, size.height * 0.16),
          radius: size.width * 0.5,
        ),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final Paint bubblePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10);
    for (int i = 0; i < 18; i++) {
      final double phase = i / 18;
      final double x = (math.sin(i * 1.7) * 0.5 + 0.5) * size.width;
      final double y = ((phase + progress * 0.12) % 1) * size.height;
      final double radius = 4 + (i % 5) * 2.6;
      canvas.drawCircle(Offset(x, y), radius, bubblePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _Bubble {
  const _Bubble(this.x, this.y, this.radius, this.phase);

  final double x;
  final double y;
  final double radius;
  final double phase;
}
