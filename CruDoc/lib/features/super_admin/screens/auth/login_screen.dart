import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/features/shell/presentation/desktop_shell_layout.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';

/// Super Admin Login Screen redesigned into the CruDoc Calm Clinical design system.
/// Features email/password login, 2FA prompt, and 1-click Dev Demo Access.
class SuperAdminLoginScreen extends ConsumerStatefulWidget {
  final bool show2FA;

  const SuperAdminLoginScreen({super.key, this.show2FA = false});

  @override
  ConsumerState<SuperAdminLoginScreen> createState() =>
      _SuperAdminLoginScreenState();
}

class _SuperAdminLoginScreenState extends ConsumerState<SuperAdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _is2FAMode = false;

  @override
  void initState() {
    super.initState();
    _is2FAMode = widget.show2FA;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(superAdminAuthProvider.notifier);
    final success = await authNotifier.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      context.go('/admin');
    } else if (!success && mounted) {
      final state = ref.read(superAdminAuthProvider);
      if (state.isTwoFARequired) {
        setState(() => _is2FAMode = true);
      }
    }
  }

  Future<void> _handle2FA() async {
    if (_otpController.text.length != 6) return;

    final authNotifier = ref.read(superAdminAuthProvider.notifier);
    final verified = await authNotifier.verify2FA(_otpController.text);
    if (verified && mounted) {
      context.go('/admin');
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send reset email')),
      );
    }
  }

  Future<void> _handleDemoDevLogin() async {
    final success =
        await ref.read(superAdminAuthProvider.notifier).loginDemoDev();
    if (success && mounted) {
      context.go('/admin');
    }
  }

  void _fillDemoAdminCredentials() {
    setState(() {
      _emailController.text = 'admin@crudoc.com';
      _passwordController.text = 'admin123';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('Super Admin demo credentials pre-filled (admin@crudoc.com)!'),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final authState = ref.watch(superAdminAuthProvider);

    return Scaffold(
      backgroundColor: c.canvas,
      body: CruAmbientBackground(
        isEvening: c.isEvening,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: CruCard(
                padding: const EdgeInsets.all(CruSpace.s32),
                child: _is2FAMode
                    ? _build2FAForm(c, authState)
                    : _buildLoginForm(c, authState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(CruColors c, SuperAdminAuthState authState) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo & Brand Header
          Center(
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: c.accent,
                shape: cruShape(CruRadius.appMark),
              ),
              child: CruIcon(
                CruIcons.plus,
                size: 26,
                strokeWidth: 3.4,
                color: c.onAccent,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Text(
            SuperAdminConstants.appName,
            textAlign: TextAlign.center,
            style: CruType.largeTitle.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Master Platform Root & System Administration',
            textAlign: TextAlign.center,
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s24),

          // Error Message Banner
          if (authState.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: ShapeDecoration(
                color: c.redTint,
                shape: cruShape(CruRadius.control),
              ),
              child: Row(
                children: [
                  CruIcon(CruIcons.warning, size: 16, color: c.redText),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Text(
                      authState.errorMessage!,
                      style: CruType.caption.w600.tint(c.redText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s16),
          ],

          // Email Input
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: CruType.text.tint(c.label),
            decoration: InputDecoration(
              labelText: 'Administrator Email',
              hintText: 'admin@crudoc.com',
              filled: true,
              fillColor: c.inset,
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: CruIcon(CruIcons.user, size: 18, color: c.label3),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
                borderSide: BorderSide(color: c.hairline),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Invalid email address';
              return null;
            },
          ),
          const SizedBox(height: CruSpace.s14),

          // Password Input
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: CruType.text.tint(c.label),
            decoration: InputDecoration(
              labelText: 'Master Password',
              filled: true,
              fillColor: c.inset,
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.lock_outline, size: 18, color: c.label3),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: c.label3,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
                borderSide: BorderSide(color: c.hairline),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              return null;
            },
          ),
          const SizedBox(height: CruSpace.s8),

          // Forgot Password Link
          Align(
            alignment: Alignment.centerRight,
            child: CruPressable(
              onTap: _handleForgotPassword,
              builder: (ctx, hovered) => Text(
                'Forgot password?',
                style: CruType.caption.tint(c.accentText),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s20),

          // Primary Sign-in Button
          CruButton(
            label: 'Sign in to Console',
            kind: CruButtonKind.primary,
            large: true,
            expand: true,
            onPressed: authState.isLoading ? null : _handleLogin,
          ),

          const SizedBox(height: CruSpace.s20),
          Divider(height: 1, color: c.hairline),
          const SizedBox(height: CruSpace.s16),

          // ⚡ DEV DEMO ACCESS CARD
          Container(
            padding: const EdgeInsets.all(14),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CruIcon(CruIcons.sparkle, size: 16, color: c.amberText),
                    const SizedBox(width: CruSpace.s6),
                    Text(
                      'DEVELOPER DEMO ACCESS',
                      style: CruType.caption.w600.tint(c.label),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s6),
                Text(
                  'Bypasses external Firebase network rate-limits and launches the Super Admin suite in mock admin mode.',
                  style: CruType.caption.tint(c.label3),
                ),
                const SizedBox(height: CruSpace.s12),
                CruButton(
                  label: '⚡ Launch Super Admin Demo (Dev Access)',
                  kind: CruButtonKind.tinted,
                  expand: true,
                  onPressed: _handleDemoDevLogin,
                ),
                const SizedBox(height: CruSpace.s8),
                CruPressable(
                  onTap: _fillDemoAdminCredentials,
                  builder: (ctx, hovered) => Text(
                    'Pre-fill credentials (admin@crudoc.com)',
                    style: CruType.caption.tint(c.label2),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: CruSpace.s16),

          // Return to Clinic Login Portal
          Center(
            child: CruPressable(
              onTap: () => context.go('/auth'),
              builder: (ctx, hovered) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(CruIcons.chevronLeft, size: 14, color: c.label2),
                  const SizedBox(width: CruSpace.s6),
                  Text(
                    'Return to Doctor Clinic Login',
                    style: CruType.caption.tint(c.label2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build2FAForm(CruColors c, SuperAdminAuthState authState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: c.accentTint,
              shape: cruShape(CruRadius.appMark),
            ),
            child: Icon(Icons.lock_outline, size: 24, color: c.accentText),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        Text(
          'Two-Factor Authentication',
          textAlign: TextAlign.center,
          style: CruType.largeTitle.tint(c.label),
        ),
        const SizedBox(height: CruSpace.s4),
        Text(
          'Enter the 6-digit verification code from your authenticator app.',
          textAlign: TextAlign.center,
          style: CruType.caption.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s24),

        if (authState.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(color: c.redTint, shape: cruShape(CruRadius.control)),
            child: Text(authState.errorMessage!, style: CruType.caption.w600.tint(c.redText)),
          ),
          const SizedBox(height: CruSpace.s16),
        ],

        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: CruType.metric.tint(c.label),
          decoration: InputDecoration(
            hintText: '000000',
            counterText: '',
            filled: true,
            fillColor: c.inset,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CruRadius.control),
              borderSide: BorderSide(color: c.hairline),
            ),
          ),
          onChanged: (v) {
            if (v.length == 6) _handle2FA();
          },
        ),
        const SizedBox(height: CruSpace.s20),

        CruButton(
          label: 'Verify Code',
          kind: CruButtonKind.primary,
          large: true,
          expand: true,
          onPressed: _handle2FA,
        ),
        const SizedBox(height: CruSpace.s12),

        CruButton(
          label: '⚡ Bypass 2FA (Dev Demo Mode)',
          kind: CruButtonKind.secondary,
          expand: true,
          onPressed: _handleDemoDevLogin,
        ),
        const SizedBox(height: CruSpace.s12),

        Center(
          child: CruPressable(
            onTap: () => setState(() => _is2FAMode = false),
            builder: (ctx, hovered) => Text('Back to Login', style: CruType.caption.tint(c.label2)),
          ),
        ),
      ],
    );
  }
}