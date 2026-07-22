import 'dart:math' as math;

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/features/auth/presentation/phone_auth_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _backgroundController;
  late final AnimationController _contentController;

  final AuthService _authService = AuthService();

  int _currentPage = 1; // start on login page
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Controllers for form fields
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  // Demo credentials
  static const _demoEmail = 'doctor@crudoc.com';
  static const _demoPassword = 'demo1234';

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

    // Pre-fill demo email on login page
    _emailController.text = _demoEmail;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _backgroundController.dispose();
    _contentController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  void _enterApp() => context.go('/dashboard');

  // ---------- Email / Password Login ----------

  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password');
      return;
    }

    // Demo credentials bypass — no Firebase needed
    if (email == _demoEmail && password == _demoPassword) {
      _enterApp();
      return;
    }

    // Real Firebase email/password auth
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      _enterApp();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showError(e.message ?? 'Login failed');
    } catch (e) {
      if (!mounted) return;
      _showError('Login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- Email / Password Signup ----------

  Future<void> _handleEmailSignup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Set display name if provided
      if (name.isNotEmpty) {
        await credential.user?.updateDisplayName(name);
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
      await _authService.signInWithGoogle();
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

    if (result != null && mounted) {
      _enterApp();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
}

// ==================== INTRO PANEL ====================

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

// ==================== AUTH MODE ====================

enum _AuthMode { login, signup }

// ==================== AUTH FORM PANEL ====================

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({
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
          // Back button
          Positioned(
            top: 18,
            left: 14,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                minimumSize: const Size(34, 34),
              ),
            ),
          ),
          // Title
          Positioned(
            left: 24,
            right: 24,
            top: 56,
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
          // Form at bottom
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

// ==================== AUTH FORM (email/password + social) ====================

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
  final VoidCallback onSecondary;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onPhoneSignIn;

  bool get _isLogin => mode == _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name field (signup only)
        if (!_isLogin) ...[
          _AuthTextField(
            icon: Icons.person_rounded,
            hintText: 'Name',
            controller: nameController,
          ),
          const SizedBox(height: 8),
        ],
        // Email field
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
        // Password field
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

        // Primary action button (Log in / Sign up)
        _PrimaryButton(
          label: _isLogin ? 'Log in' : 'Sign up',
          isLoading: isLoading,
          onPressed: onPrimary,
        ),
        const SizedBox(height: 10),
        const _DividerLabel(),
        const SizedBox(height: 10),

        // Social sign-in buttons
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

        // Switch between login / signup
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

// ==================== REUSABLE WIDGETS ====================

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
          backgroundColor:
              outlined ? Colors.transparent : Colors.white,
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
                color: outlined
                    ? const Color(0xFF9A9A9A)
                    : const Color(0xFF4A4A4A),
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

// ==================== ANIMATED PANEL ====================

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

// ==================== PAGE DOTS ====================

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

// ==================== PAINTERS ====================

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
      ..shader =
          RadialGradient(
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
