import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shows the account deletion confirmation dialog.
/// Returns true if the account was deleted and the user signed out.
Future<bool> showDeleteAccountDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DeleteAccountDialog(),
  );
  return result ?? false;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _needsPassword = false;
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canConfirm => _confirmController.text.trim() == 'DELETE';

  Future<void> _onDelete() async {
    if (!_canConfirm || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('You are not signed in.');
      }

      final providers = user.providerData.map((p) => p.providerId).toSet();
      final isApple = providers.contains('apple.com');
      final isGoogle = providers.contains('google.com');
      final isPassword = providers.contains('password');

      // Apple requires fresh sign-in and token revocation on deletion
      if (isApple) {
        await AuthService().signInWithApple();
        final code = AuthService.lastAppleAuthorizationCode;
        if (code != null && code.isNotEmpty) {
          try {
            await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code);
          } catch (_) {}
        }
      }

      Future<void> executeDelete() async {
        await CallableClient().call('deleteAccount', <String, dynamic>{});
      }

      try {
        await executeDelete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          await _reauthenticate(
            user,
            isGoogle: isGoogle,
            isApple: isApple,
            isPassword: isPassword,
          );
          await executeDelete();
        } else {
          rethrow;
        }
      } on CallableException catch (e) {
        if (e.code == 'requires-recent-login' ||
            e.message.toLowerCase().contains('requires-recent-login')) {
          await _reauthenticate(
            user,
            isGoogle: isGoogle,
            isApple: isApple,
            isPassword: isPassword,
          );
          await executeDelete();
        } else {
          rethrow;
        }
      }

      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _reauthenticate(
    User user, {
    required bool isGoogle,
    required bool isApple,
    required bool isPassword,
  }) async {
    if (isGoogle) {
      await AuthService().signInWithGoogle();
    } else if (isApple) {
      await AuthService().signInWithApple();
      final code = AuthService.lastAppleAuthorizationCode;
      if (code != null && code.isNotEmpty) {
        try {
          await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(code);
        } catch (_) {}
      }
    } else if (isPassword) {
      if (_passwordController.text.trim().isEmpty) {
        setState(() {
          _needsPassword = true;
          _busy = false;
          _error = 'Please enter your password below to confirm deletion.';
        });
        throw Exception('Password required to confirm.');
      }
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordController.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CruSize.dialog),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delete your account?', style: CruType.title2.tint(c.label)),
              const SizedBox(height: CruSpace.s12),
              Text(
                'This permanently deletes your CruDoc login. If you own a '
                'clinic, it also deletes the clinic\'s patients, visits, files '
                'and invoices. This cannot be undone.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                controller: _confirmController,
                label: 'Type DELETE to confirm',
                hint: 'DELETE',
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_needsPassword) ...[
                const SizedBox(height: CruSpace.s12),
                CruTextField(
                  controller: _passwordController,
                  label: 'Account password',
                  hint: 'Enter your password',
                  obscureText: true,
                  enabled: !_busy,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: CruSpace.s12),
                Text(_error!, style: CruType.caption.tint(c.redText)),
              ],
              const SizedBox(height: CruSpace.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: 'Cancel',
                    kind: CruButtonKind.secondary,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  if (_busy)
                    SizedBox.square(
                      dimension: CruSpace.s20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.accent,
                      ),
                    )
                  else
                    CruPressable(
                      onTap: _canConfirm ? _onDelete : null,
                      builder: (context, hovered) => AnimatedContainer(
                        duration: CruMotion.of(context, CruMotion.fast),
                        height: 40,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s16,
                        ),
                        decoration: ShapeDecoration(
                          color: _canConfirm
                              ? (hovered
                                    ? c.redTint.withValues(alpha: 0.8)
                                    : c.redTint)
                              : c.inset,
                          shape: cruShape(CruRadius.control),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Delete account',
                          style: CruType.text.copyWith(
                            color: _canConfirm ? c.redText : c.label3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
