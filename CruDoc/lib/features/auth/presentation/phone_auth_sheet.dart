import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The grab handle at the top of the sheet.
const double _kHandleWidth = 36;
const double _kHandleHeight = 4;

/// A bottom-sheet that handles Phone Number → OTP verification.
///
/// Returns a [UserCredential] via `Navigator.pop` on success, or null if
/// the user dismisses the sheet.
///
/// With [linkToCurrentUser], the number is added to the account that is
/// already signed in (email or Google) instead of signing in with it.
class PhoneAuthSheet extends StatefulWidget {
  const PhoneAuthSheet({
    super.key,
    required this.authService,
    this.linkToCurrentUser = false,
  });

  final AuthService authService;
  final bool linkToCurrentUser;

  @override
  State<PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<PhoneAuthSheet> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  final String _countryCode = '+91';
  String? _verificationId;
  int? _resendToken;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _errorText;

  /// A code is being checked, by the Verify button or Android reading the
  /// SMS on its own. Only one may run, so the code isn't used twice.
  bool _verifying = false;

  // Resend cooldown. One timer at a time, so changing the number and
  // sending again doesn't leave an old countdown running alongside.
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCountdown--);
      if (_resendCountdown <= 0) timer.cancel();
    });
  }

  Future<void> _sendOTP({bool resend = false}) async {
    if (_isLoading) return;
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _errorText = 'Enter your 10-digit mobile number.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await widget.authService.sendOTP(
        phoneNumber: '$_countryCode$phone',
        forceResendingToken: resend ? _resendToken : null,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _otpSent = true;
            _isLoading = false;
          });
          _startResendTimer();
        },
        onAutoVerified: (credential) async {
          // Android auto-retrieval — sign in automatically, unless the
          // person already tapped Verify.
          if (!mounted || _verifying) return;
          setState(() {
            _verifying = true;
            _isLoading = true;
            _errorText = null;
          });
          try {
            final userCredential = widget.linkToCurrentUser
                ? await widget.authService.linkPhoneCredential(credential)
                : await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;
            Navigator.of(context).pop(userCredential);
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;
            setState(() {
              _errorText = widget.linkToCurrentUser
                  ? phoneLinkErrorMessage(e)
                  : 'Auto-verification failed: ${e.message}';
              _isLoading = false;
              _verifying = false;
            });
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _errorText = 'Auto-verification failed: $e';
              _isLoading = false;
              _verifying = false;
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _errorText = e.message ?? "Couldn't send the code. Try again.";
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't send the code. Check the connection and try again.";
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    if (_isLoading || _verifying) return;
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorText = 'Enter the 6-digit code.');
      return;
    }

    setState(() {
      _verifying = true;
      _isLoading = true;
      _errorText = null;
    });

    try {
      final userCredential = widget.linkToCurrentUser
          ? await widget.authService.linkPhone(
              verificationId: _verificationId!,
              smsCode: code,
            )
          : await widget.authService.verifyOTP(
              verificationId: _verificationId!,
              smsCode: code,
            );
      if (!mounted) return;
      Navigator.of(context).pop(userCredential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = widget.linkToCurrentUser
            ? phoneLinkErrorMessage(e)
            : e.message ?? "That code didn't work. Check it and try again.";
        _isLoading = false;
        _verifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = "Couldn't check the code. Try again.";
        _isLoading = false;
        _verifying = false;
      });
    }
  }

  void _changeNumber() => setState(() {
    _resendTimer?.cancel();
    _resendCountdown = 0;
    _otpSent = false;
    _verificationId = null;
    _otpController.clear();
    _errorText = null;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final number = '$_countryCode ${_phoneController.text.trim()}';
    final title = _otpSent
        ? 'Enter the code'
        : widget.linkToCurrentUser
        ? 'Confirm your number'
        : 'Sign in with your phone';
    final lead = _otpSent
        ? 'We sent a 6-digit code to $number.'
        : widget.linkToCurrentUser
        ? 'Clinics that invite this number can then find you.'
        : "We'll text you a one-time code.";
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              CruSpace.s12,
              CruSpace.s20,
              CruSpace.s20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: _kHandleWidth,
                    height: _kHandleHeight,
                    decoration: ShapeDecoration(
                      color: c.separator,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s20),
                Semantics(
                  header: true,
                  child: Text(title, style: CruType.title.tint(c.label)),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(lead, style: CruType.text.tabular.tint(c.label2)),
                const SizedBox(height: CruSpace.s20),
                if (!_otpSent)
                  CruTextField(
                    key: const ValueKey('phone'),
                    label: 'Phone number',
                    controller: _phoneController,
                    prefix: _countryCode,
                    keyboardType: TextInputType.phone,
                    tabular: true,
                    autofocus: true,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational,
                    ],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isLoading ? null : _sendOTP(),
                  )
                else ...[
                  CruTextField(
                    key: const ValueKey('code'),
                    label: 'Code',
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    tabular: true,
                    autofocus: true,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isLoading ? null : _verifyOTP(),
                  ),
                  const SizedBox(height: CruSpace.s8),
                  Row(
                    children: [
                      if (_resendCountdown > 0)
                        Text(
                          'Resend in ${_resendCountdown}s',
                          style: CruType.text.tabular.tint(c.label3),
                        )
                      else
                        CruLink(
                          label: 'Resend code',
                          onPressed: _isLoading
                              ? null
                              : () => _sendOTP(resend: true),
                        ),
                      const Spacer(),
                      CruLink(
                        label: 'Change number',
                        onPressed: _changeNumber,
                      ),
                    ],
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: CruSpace.s12),
                  Text(_errorText!, style: CruType.text.tint(c.label)),
                ],
                const SizedBox(height: CruSpace.s20),
                CruButton(
                  label: _isLoading
                      ? (_otpSent ? 'Checking…' : 'Sending…')
                      : (_otpSent ? 'Verify' : 'Send code'),
                  large: true,
                  expand: true,
                  onPressed: _isLoading
                      ? null
                      : _otpSent
                      ? _verifyOTP
                      : _sendOTP,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper to show the phone auth sheet. Returns a [UserCredential] on success.
Future<UserCredential?> showPhoneAuthSheet(
  BuildContext context, {
  required AuthService authService,
  bool linkToCurrentUser = false,
}) {
  return showModalBottomSheet<UserCredential>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PhoneAuthSheet(
      authService: authService,
      linkToCurrentUser: linkToCurrentUser,
    ),
  );
}
