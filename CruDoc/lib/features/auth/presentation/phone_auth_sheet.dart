import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';

/// A bottom-sheet that handles Phone Number → OTP verification.
///
/// Returns a [UserCredential] via `Navigator.pop` on success, or null if
/// the user dismisses the sheet.
class PhoneAuthSheet extends StatefulWidget {
  const PhoneAuthSheet({super.key, required this.authService});

  final AuthService authService;

  @override
  State<PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<PhoneAuthSheet> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  String _countryCode = '+91';
  String? _verificationId;
  int? _resendToken;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _errorText;

  // Resend cooldown
  int _resendCountdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendCountdown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCountdown--);
      return _resendCountdown > 0;
    });
  }

  Future<void> _sendOTP({bool resend = false}) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 7) {
      setState(() => _errorText = 'Enter a valid phone number');
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
          // Android auto-retrieval — sign in automatically
          try {
            final userCredential = await FirebaseAuth.instance
                .signInWithCredential(credential);
            if (!mounted) return;
            Navigator.of(context).pop(userCredential);
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _errorText = 'Auto-verification failed: $e';
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _errorText = e.message ?? 'Failed to send OTP';
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Failed to send OTP: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorText = 'Enter the 6-digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final userCredential = await widget.authService.verifyOTP(
        verificationId: _verificationId!,
        smsCode: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(userCredential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message ?? 'Invalid OTP';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Verification failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF087DFF), Color(0xFF075BCE)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  _otpSent ? 'Enter OTP' : 'Phone Sign-In',
                  style: const TextStyle(
                    fontFamily: AppColors.headingFontFamily,
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _otpSent
                      ? 'We sent a code to $_countryCode ${_phoneController.text.trim()}'
                      : 'Enter your phone number to receive a one-time code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                if (!_otpSent) ...[
                  // Phone number input
                  Row(
                    children: [
                      // Country code
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _countryCode,
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Phone field
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Phone number',
                            hintStyle: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // OTP input
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      hintText: '• • • • • •',
                      hintStyle: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 24,
                        letterSpacing: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Resend button
                  GestureDetector(
                    onTap: _resendCountdown > 0 ? null : () => _sendOTP(resend: true),
                    child: Text(
                      _resendCountdown > 0
                          ? 'Resend in ${_resendCountdown}s'
                          : 'Resend OTP',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: _resendCountdown > 0
                            ? Colors.white.withOpacity(0.4)
                            : Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                // Error text
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: Colors.redAccent.shade100,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Primary button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : _otpSent
                            ? _verifyOTP
                            : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white.withOpacity(0.5),
                      foregroundColor: const Color(0xFF087DFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Color(0xFF087DFF),
                            ),
                          )
                        : Text(
                            _otpSent ? 'Verify OTP' : 'Send OTP',
                            style: const TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                if (_otpSent) ...[
                  const SizedBox(height: 12),
                  // Change number
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _otpSent = false;
                        _verificationId = null;
                        _otpController.clear();
                        _errorText = null;
                      });
                    },
                    child: Text(
                      'Change phone number',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
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
}) {
  return showModalBottomSheet<UserCredential>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => PhoneAuthSheet(authService: authService),
  );
}
