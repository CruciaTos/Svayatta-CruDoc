import 'dart:math' as math;

import 'package:doctor_management_app/core/theme/app_colors.dart';
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

  int _currentPage = 1;
  bool _obscurePassword = true;

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
  }

  @override
  void dispose() {
    _pageController.dispose();
    _backgroundController.dispose();
    _contentController.dispose();
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isWide = constraints.maxWidth > 720;
                    final authPages = [
                      _IntroPanel(
                        progress: _backgroundController.value,
                        onLogin: () => _goToPage(1),
                        onSignup: () => _goToPage(2),
                      ),
                      _AuthFormPanel(
                        progress: _backgroundController.value,
                        mode: _AuthMode.login,
                        obscurePassword: _obscurePassword,
                        onBack: () => _goToPage(0),
                        onObscureToggle: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onPrimary: _enterApp,
                        onSecondary: () => _goToPage(2),
                      ),
                      _AuthFormPanel(
                        progress: _backgroundController.value,
                        mode: _AuthMode.signup,
                        obscurePassword: _obscurePassword,
                        onBack: () => _goToPage(1),
                        onObscureToggle: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onPrimary: _enterApp,
                        onSecondary: () => _goToPage(1),
                      ),
                    ];

                    if (!isWide) {
                      return PageView(
                        controller: _pageController,
                        onPageChanged: _handlePageChanged,
                        children: authPages,
                      );
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 980 : 430,
                          maxHeight: 860,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide ? 28 : 18,
                            vertical: 18,
                          ),
                          child: _WideAuthPreview(
                            controller: _pageController,
                            backgroundProgress: _backgroundController.value,
                            obscurePassword: _obscurePassword,
                            onObscureToggle: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            onPageChanged: _handlePageChanged,
                            onSwitchPage: _goToPage,
                            onEnterApp: _enterApp,
                          ),
                        ),
                      ),
                    );
                  },
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

class _WideAuthPreview extends StatelessWidget {
  const _WideAuthPreview({
    required this.controller,
    required this.backgroundProgress,
    required this.obscurePassword,
    required this.onObscureToggle,
    required this.onPageChanged,
    required this.onSwitchPage,
    required this.onEnterApp,
  });

  final PageController controller;
  final double backgroundProgress;
  final bool obscurePassword;
  final VoidCallback onObscureToggle;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onSwitchPage;
  final VoidCallback onEnterApp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PhoneFrame(
            child: _IntroPanel(
              progress: backgroundProgress,
              onLogin: () => onSwitchPage(1),
              onSignup: () => onSwitchPage(2),
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: _PhoneFrame(
            child: PageView(
              controller: controller,
              onPageChanged: onPageChanged,
              children: [
                _IntroPanel(
                  progress: backgroundProgress,
                  onLogin: () => onSwitchPage(1),
                  onSignup: () => onSwitchPage(2),
                ),
                _AuthFormPanel(
                  progress: backgroundProgress,
                  mode: _AuthMode.login,
                  obscurePassword: obscurePassword,
                  onBack: () => onSwitchPage(0),
                  onObscureToggle: onObscureToggle,
                  onPrimary: onEnterApp,
                  onSecondary: () => onSwitchPage(2),
                ),
                _AuthFormPanel(
                  progress: backgroundProgress,
                  mode: _AuthMode.signup,
                  obscurePassword: obscurePassword,
                  onBack: () => onSwitchPage(1),
                  onObscureToggle: onObscureToggle,
                  onPrimary: onEnterApp,
                  onSecondary: () => onSwitchPage(1),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: _PhoneFrame(
            child: _AuthFormPanel(
              progress: backgroundProgress,
              mode: _AuthMode.signup,
              obscurePassword: obscurePassword,
              onBack: () => onSwitchPage(1),
              onObscureToggle: onObscureToggle,
              onPrimary: onEnterApp,
              onSecondary: () => onSwitchPage(1),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.49,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(24), child: child),
      ),
    );
  }
}

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

enum _AuthMode { login, signup }

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({
    required this.progress,
    required this.mode,
    required this.obscurePassword,
    required this.onBack,
    required this.onObscureToggle,
    required this.onPrimary,
    required this.onSecondary,
  });

  final double progress;
  final _AuthMode mode;
  final bool obscurePassword;
  final VoidCallback onBack;
  final VoidCallback onObscureToggle;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  bool get _isLogin => mode == _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPanel(
      progress: progress,
      whiteWaveHeight: 0.47,
      child: Stack(
        children: [
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
          Positioned(
            left: 24,
            right: 24,
            top: 92,
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
            child: Padding(
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
                  onObscureToggle: onObscureToggle,
                  onPrimary: onPrimary,
                  onSecondary: onSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    super.key,
    required this.mode,
    required this.obscurePassword,
    required this.onObscureToggle,
    required this.onPrimary,
    required this.onSecondary,
  });

  final _AuthMode mode;
  final bool obscurePassword;
  final VoidCallback onObscureToggle;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  bool get _isLogin => mode == _AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isLogin) ...[
          const _AuthTextField(icon: Icons.person_rounded, hintText: 'Name'),
          const SizedBox(height: 10),
        ],
        _AuthTextField(
          icon: Icons.email_rounded,
          hintText: 'Email',
          initialValue: _isLogin ? 'doctor@crudoc.com' : null,
          trailing: _isLogin
              ? const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF66A8FF),
                  size: 18,
                )
              : null,
        ),
        const SizedBox(height: 10),
        _AuthTextField(
          icon: Icons.lock_rounded,
          hintText: 'Password',
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0A7BFF),
                padding: EdgeInsets.zero,
                minimumSize: const Size(10, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 18),
        _AuthButton(
          label: _isLogin ? 'Log in' : 'Sign up',
          filled: true,
          onPressed: onPrimary,
        ),
        const SizedBox(height: 10),
        const _DividerLabel(),
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

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.icon,
    required this.hintText,
    this.initialValue,
    this.obscureText = false,
    this.trailing,
  });

  final IconData icon;
  final String hintText;
  final String? initialValue;
  final bool obscureText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
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
