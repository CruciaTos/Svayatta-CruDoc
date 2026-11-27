import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../data/abdm_api.dart';
import '../domain/abha_consent.dart';
import '../domain/abha_input.dart';
import '../domain/abha_profile.dart';

/// Result returned when the user completes an ABHA verify or create flow.
class AbhaResult {
  const AbhaResult({
    required this.flowId,
    required this.profile,
    this.existingPatientId,
    this.unmaskedMobile,
  });

  final String flowId;
  final AbhaProfile profile;
  final String? existingPatientId;
  final String? unmaskedMobile;
}

/// Opens the ABHA verification / creation dialog.
Future<AbhaResult?> showAbhaFlowDialog(
  BuildContext context, {
  Patient? patient,
}) {
  return showDialog<AbhaResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AbhaFlowDialog(patient: patient),
  );
}

enum _AbhaTab { hasAbha, createAbha }

enum _FlowStep {
  input,
  pickMethod,
  pickProfile,
  otp,
  commMobileOtp,
  chooseAddress,
  result,
}

class _AbhaFlowDialog extends StatefulWidget {
  const _AbhaFlowDialog({this.patient});

  final Patient? patient;

  @override
  State<_AbhaFlowDialog> createState() => _AbhaFlowDialogState();
}

class _AbhaFlowDialogState extends State<_AbhaFlowDialog> {
  _AbhaTab _tab = _AbhaTab.hasAbha;
  _FlowStep _step = _FlowStep.input;

  final _identifierCtrl = TextEditingController();
  final _aadhaarCtrl = TextEditingController();
  final _commMobileCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _consentAgreed = false;
  bool _busy = false;
  String? _notice;

  // Flow state
  String _flowId = '';
  String _otpKind = '';
  String _otpChannel = '';
  String _otpIdentifier = '';
  String? _selectedIndex;
  String? _unmaskedMobile;

  // Has-ABHA choices
  List<String> _allowedMethods = const ['mobile', 'aadhaar'];
  String _chosenMethod = 'mobile';
  List<AbhaSearchAccount> _searchAccounts = const [];
  AbhaSearchAccount? _pickedAccount;
  bool _noMobileAbhaFound = false;

  // OTP timer
  Timer? _timer;
  int _secondsLeft = 0;
  int _resendsLeft = 2;

  // Address step
  List<String> _suggestedAddresses = const [];
  bool _addressAlreadyExists = false;

  // Result
  AbhaProfile? _profile;
  String? _existingPatientId;

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    if (p != null) {
      if (p.abhaNumber.trim().isNotEmpty) {
        _identifierCtrl.text = p.abhaNumber.trim();
      } else if (p.abhaAddress.trim().isNotEmpty) {
        _identifierCtrl.text = p.abhaAddress.trim();
      } else if (p.phone.trim().isNotEmpty) {
        _identifierCtrl.text = digitsOnly(p.phone);
        _commMobileCtrl.text = digitsOnly(p.phone);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _aadhaarCtrl.clear();
    _identifierCtrl.clear();
    _otpCtrl.clear();
    _identifierCtrl.dispose();
    _aadhaarCtrl.dispose();
    _commMobileCtrl.dispose();
    _otpCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _switchTab(_AbhaTab tab) {
    if (_busy || _tab == tab) return;
    _timer?.cancel();
    setState(() {
      _tab = tab;
      _step = _FlowStep.input;
      _notice = null;
      _noMobileAbhaFound = false;
      _addressAlreadyExists = false;
      _otpCtrl.clear();
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
    } on AbdmException catch (e) {
      if (mounted) {
        setState(() {
      if (_step == _FlowStep.chooseAddress &&
          e.message.toLowerCase().contains('already exists')) {
        _notice = 'ABHA address already exists.';
        _addressAlreadyExists = true;
      } else {
        _notice = e.message;
      }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPrimaryPressed() async {
    switch (_step) {
      case _FlowStep.input:
        if (_tab == _AbhaTab.hasAbha) {
          await _handleHasAbhaInput();
        } else {
          await _handleCreateSendOtp();
        }
        break;
      case _FlowStep.pickMethod:
        await _sendOtpForMethod();
        break;
      case _FlowStep.pickProfile:
        if (_pickedAccount != null) {
          await _selectMobileAccount(_pickedAccount!);
        }
        break;
      case _FlowStep.otp:
        await _handleVerifyOtp();
        break;
      case _FlowStep.commMobileOtp:
        await _handleVerifyCommMobileOtp();
        break;
      case _FlowStep.chooseAddress:
        await _handleSetAddress();
        break;
      case _FlowStep.result:
        if (_profile != null) {
          Navigator.of(context).pop(
            AbhaResult(
              flowId: _flowId,
              profile: _profile!,
              existingPatientId: _existingPatientId,
              unmaskedMobile: _unmaskedMobile,
            ),
          );
        }
        break;
    }
  }

  Future<void> _handleHasAbhaInput() async {
    final raw = _identifierCtrl.text.trim();
    final type = detectAbhaInput(raw);
    if (type == AbhaInputType.invalid) {
      final d = digitsOnly(raw);
      setState(() {
        _notice = d.isNotEmpty && d.length < 10
            ? 'Please enter a valid mobile number.'
            : 'Enter a 14-digit ABHA number, 12-digit Aadhaar, 10-digit mobile, or ABHA address.';
      });
      return;
    }

    await _runBusy(() async {
      switch (type) {
        case AbhaInputType.abhaNumber:
          _otpKind = 'abhaNumber';
          _otpIdentifier = digitsOnly(raw);
          _allowedMethods = const ['mobile', 'aadhaar'];
          _chosenMethod = 'mobile';
          setState(() => _step = _FlowStep.pickMethod);
          break;
        case AbhaInputType.aadhaar:
          final digits = digitsOnly(raw);
          _otpKind = 'aadhaar';
          _otpChannel = 'aadhaar';
          _otpIdentifier = digits;
          final res = await AbdmApi.instance.sendOtp(
            kind: 'aadhaar',
            channel: 'aadhaar',
            identifier: digits,
          );
          _flowId = res.flowId;
          _resendsLeft = res.resendsLeft;
          _otpCtrl.clear();
          _startCountdown();
          setState(() => _step = _FlowStep.otp);
          break;
        case AbhaInputType.mobile:
          final digits = digitsOnly(raw);
          _unmaskedMobile = digits;
          final res = await AbdmApi.instance.searchMobile(digits);
          if (res.accounts.isEmpty) {
            setState(() => _noMobileAbhaFound = true);
          } else {
            _flowId = res.flowId ?? '';
            _searchAccounts = res.accounts;
            _pickedAccount = null;
            setState(() {
              _noMobileAbhaFound = false;
              _step = _FlowStep.pickProfile;
            });
          }
          break;
        case AbhaInputType.abhaAddress:
          final res = await AbdmApi.instance.searchAddress(raw);
          _flowId = res.flowId;
          _otpKind = 'address';
          _otpIdentifier = raw;
          _allowedMethods = res.methods.isEmpty
              ? const ['mobile', 'aadhaar']
              : res.methods;
          _chosenMethod = _allowedMethods.first;
          setState(() => _step = _FlowStep.pickMethod);
          break;
        case AbhaInputType.invalid:
          break;
      }
    });
  }

  Future<void> _sendOtpForMethod() async {
    await _runBusy(() async {
      _otpChannel = _chosenMethod;
      final res = await AbdmApi.instance.sendOtp(
        kind: _otpKind,
        channel: _chosenMethod,
        identifier: _otpIdentifier,
        flowId: _otpKind == 'address' && _flowId.isNotEmpty ? _flowId : null,
      );
      _flowId = res.flowId;
      _resendsLeft = res.resendsLeft;
      _otpCtrl.clear();
      _startCountdown();
      setState(() => _step = _FlowStep.otp);
    });
  }

  Future<void> _selectMobileAccount(AbhaSearchAccount account) async {
    await _runBusy(() async {
      _otpKind = 'index';
      _otpChannel = 'mobile';
      _selectedIndex = account.index;
      _otpIdentifier = _unmaskedMobile ?? '';
      final res = await AbdmApi.instance.sendOtp(
        kind: 'index',
        channel: 'mobile',
        identifier: _otpIdentifier,
        index: account.index,
        flowId: _flowId,
      );
      _flowId = res.flowId;
      _resendsLeft = res.resendsLeft;
      _otpCtrl.clear();
      _startCountdown();
      setState(() => _step = _FlowStep.otp);
    });
  }

  Future<void> _handleCreateSendOtp() async {
    final aadhaar = digitsOnly(_aadhaarCtrl.text);
    final mobile = digitsOnly(_commMobileCtrl.text);
    if (!isValidAadhaar(aadhaar)) {
      setState(() => _notice = 'Aadhaar Number is not valid');
      return;
    }
    if (!isValidMobile(mobile)) {
      setState(() => _notice = 'Please enter a valid mobile number.');
      return;
    }
    if (!_consentAgreed) {
      setState(() => _notice = 'Please agree to the consent terms first.');
      return;
    }

    await _runBusy(() async {
      _otpKind = 'create';
      _otpChannel = 'aadhaar';
      _otpIdentifier = aadhaar;
      _unmaskedMobile = mobile;
      final res = await AbdmApi.instance.sendOtp(
        kind: 'create',
        channel: 'aadhaar',
        identifier: aadhaar,
        consent: true,
      );
      _flowId = res.flowId;
      _resendsLeft = res.resendsLeft;
      _otpCtrl.clear();
      _startCountdown();
      setState(() => _step = _FlowStep.otp);
    });
  }

  Future<void> _handleResendOtp() async {
    if (_secondsLeft > 0 || _resendsLeft <= 0 || _busy) return;
    await _runBusy(() async {
      final res = await AbdmApi.instance.sendOtp(
        kind: _otpKind,
        channel: _otpChannel,
        identifier: _otpIdentifier,
        index: _selectedIndex,
        flowId: _flowId.isNotEmpty ? _flowId : null,
      );
      _flowId = res.flowId;
      _resendsLeft = res.resendsLeft;
      _startCountdown();
    });
  }

  Future<void> _handleVerifyOtp() async {
    final otp = digitsOnly(_otpCtrl.text);
    if (!isValidOtp(otp)) {
      setState(() => _notice = 'Enter the 6-digit OTP.');
      return;
    }

    await _runBusy(() async {
      final res = await AbdmApi.instance.verifyOtp(
        flowId: _flowId,
        otp: otp,
        mobile: _tab == _AbhaTab.createAbha ? _unmaskedMobile : null,
      );
      _profile = res.profile;
      _existingPatientId = res.existingPatientId;

      if (_tab == _AbhaTab.createAbha && res.needsMobileOtp) {
        _otpKind = 'commMobile';
        _otpChannel = 'mobile';
        _otpIdentifier = _unmaskedMobile ?? '';
        _otpCtrl.clear();
        setState(() {
          _secondsLeft = 0;
          _resendsLeft = 2;
          _step = _FlowStep.commMobileOtp;
        });
        try {
          final mobRes = await AbdmApi.instance.sendOtp(
            kind: 'commMobile',
            channel: 'mobile',
            identifier: _otpIdentifier,
            flowId: _flowId,
          );
          if (mounted) {
            _resendsLeft = mobRes.resendsLeft;
            _startCountdown();
          }
        } on AbdmException catch (e) {
          if (mounted) setState(() => _notice = e.message);
        }
        return;
      }

      if (_tab == _AbhaTab.createAbha &&
          (res.isNew || res.profile.abhaAddress.isEmpty)) {
        await _loadSuggestionsAndGoToAddress();
        return;
      }

      setState(() => _step = _FlowStep.result);
    });
  }

  Future<void> _handleVerifyCommMobileOtp() async {
    final otp = digitsOnly(_otpCtrl.text);
    if (!isValidOtp(otp)) {
      setState(() => _notice = 'Enter the 6-digit OTP.');
      return;
    }

    await _runBusy(() async {
      final res = await AbdmApi.instance.verifyOtp(
        flowId: _flowId,
        otp: otp,
      );
      _profile = res.profile;
      _existingPatientId = res.existingPatientId;
      await _loadSuggestionsAndGoToAddress();
    });
  }

  Future<void> _loadSuggestionsAndGoToAddress() async {
    setState(() {
      _addressAlreadyExists = false;
      _step = _FlowStep.chooseAddress;
    });
    try {
      final suggestions = await AbdmApi.instance.suggestAddress(_flowId);
      if (!mounted) return;
      _suggestedAddresses = suggestions;
      if (suggestions.isNotEmpty && _addressCtrl.text.isEmpty) {
        _addressCtrl.text = suggestions.first.split('@').first;
      }
      setState(() {});
    } on AbdmException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _handleSetAddress() async {
    final addr = _addressCtrl.text.trim();
    final rules = AbhaAddressRules.evaluate(addr);
    if (!rules.isValid) {
      setState(() => _notice = 'Please enter a valid ABHA address.');
      return;
    }
    await _runBusy(() async {
      final chosen = await AbdmApi.instance.setAddress(
        flowId: _flowId,
        abhaAddress: addr,
      );
      final cur = _profile;
      if (cur != null) {
        _profile = AbhaProfile(
          abhaNumber: cur.abhaNumber,
          abhaAddress: chosen,
          name: cur.name,
          gender: cur.gender,
          dateOfBirth: cur.dateOfBirth,
          mobile: cur.mobile,
          kycVerified: cur.kycVerified,
        );
      }
      setState(() => _step = _FlowStep.result);
    });
  }

  Future<void> _viewCard() async {
    await _runBusy(() async {
      final card = await AbdmApi.instance.card(_flowId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _AbhaCardDialog(
          card: card,
          abhaNumber: _profile?.abhaNumber ?? 'abha',
        ),
      );
    });
  }

  String get _submitLabel => switch (_step) {
    _FlowStep.input => _tab == _AbhaTab.hasAbha ? 'Continue' : 'Send OTP',
    _FlowStep.pickMethod => 'Send OTP',
    _FlowStep.pickProfile => 'Send OTP',
    _FlowStep.otp => 'Verify OTP',
    _FlowStep.commMobileOtp => 'Verify mobile',
    _FlowStep.chooseAddress => 'Save address',
    _FlowStep.result => 'Use ABHA',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruFormDialog(
      title: 'ABHA',
      submitLabel: _submitLabel,
      busy: _busy,
      notice: _notice,
      onSubmit: _onPrimaryPressed,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == _FlowStep.input) ...[
            CruSegmentedControl<_AbhaTab>(
              expand: true,
              selected: _tab,
              onChanged: _switchTab,
              segments: const [
                CruSegment(_AbhaTab.hasAbha, 'Has ABHA'),
                CruSegment(_AbhaTab.createAbha, 'Create ABHA'),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
          ],
          if (_step == _FlowStep.input && _tab == _AbhaTab.hasAbha)
            _buildHasAbhaInput(c),
          if (_step == _FlowStep.input && _tab == _AbhaTab.createAbha)
            _buildCreateInput(c),
          if (_step == _FlowStep.pickMethod) _buildPickMethod(c),
          if (_step == _FlowStep.pickProfile) _buildPickProfile(c),
          if (_step == _FlowStep.otp || _step == _FlowStep.commMobileOtp)
            _buildOtpStep(c),
          if (_step == _FlowStep.chooseAddress) _buildChooseAddress(c),
          if (_step == _FlowStep.result) _buildResultStep(c),
        ],
      ),
    );
  }

  Widget _buildHasAbhaInput(CruColors c) {
    final raw = _identifierCtrl.text;
    final maskAsAadhaar =
        !RegExp(r'[a-zA-Z@]').hasMatch(raw) && digitsOnly(raw).length == 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruTextField(
          label: 'ABHA number, Aadhaar, mobile or ABHA address',
          controller: _identifierCtrl,
          hint: '14-digit ABHA, 12-digit Aadhaar, 10-digit mobile, or name@abdm',
          obscureText: maskAsAadhaar,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: null,
          onChanged: (_) {
            setState(() {
              _noMobileAbhaFound = false;
              _notice = null;
            });
          },
          validator: (v) {
            final s = (v ?? '').trim();
            if (s.isEmpty) return null;
            final d = digitsOnly(s);
            if (!RegExp(r'[a-zA-Z@]').hasMatch(s) &&
                d.isNotEmpty &&
                d.length != 10 &&
                d.length != 12 &&
                d.length != 14) {
              return d.length < 10
                  ? 'Please enter a valid mobile number.'
                  : 'Enter 10, 12, or 14 digits.';
            }
            return null;
          },
        ),
        if (_noMobileAbhaFound) ...[
          const SizedBox(height: CruSpace.s12),
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No ABHA found for this mobile number.',
                    style: CruType.text.copyWith(color: c.label),
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                CruButton(
                  label: 'Create ABHA',
                  kind: CruButtonKind.secondary,
                  onPressed: () {
                    _commMobileCtrl.text = digitsOnly(_identifierCtrl.text);
                    _switchTab(_AbhaTab.createAbha);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCreateInput(CruColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruTextField(
          label: 'Aadhaar number',
          controller: _aadhaarCtrl,
          hint: '12-digit Aadhaar number',
          obscureText: true,
          tabular: true,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: null,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final d = digitsOnly(v ?? '');
            if (d.isEmpty) return null;
            return d.length == 12 ? null : 'Aadhaar Number is not valid';
          },
        ),
        const SizedBox(height: CruSpace.s12),
        CruTextField(
          label: 'Mobile number',
          controller: _commMobileCtrl,
          hint: '10-digit mobile number',
          tabular: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final d = digitsOnly(v ?? '');
            if (d.isEmpty) return null;
            return d.length == 10 ? null : 'Please enter a valid mobile number.';
          },
        ),
        const SizedBox(height: CruSpace.s12),
        Container(
          constraints: const BoxConstraints(maxHeight: 140),
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(
            color: c.inset,
            shape: cruShape(CruRadius.control),
          ),
          child: SingleChildScrollView(
            child: Text(
              abhaConsentText,
              style: CruType.caption.copyWith(color: c.label2),
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s8),
        CruPressable(
          onTap: () => setState(() => _consentAgreed = !_consentAgreed),
          builder: (context, hovered) => Row(
            children: [
              Checkbox(
                value: _consentAgreed,
                onChanged: (v) => setState(() => _consentAgreed = v ?? false),
              ),
              Expanded(
                child: Text(
                  'I agree',
                  style: CruType.text.copyWith(color: c.label),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPickMethod(CruColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify using',
          style: CruType.subhead.copyWith(color: c.label2),
        ),
        const SizedBox(height: CruSpace.s8),
        CruSegmentedControl<String>(
          expand: true,
          selected: _chosenMethod,
          onChanged: (m) => setState(() => _chosenMethod = m),
          segments: [
            for (final m in _allowedMethods)
              CruSegment(m, m == 'mobile' ? 'Mobile OTP' : 'Aadhaar OTP'),
          ],
        ),
      ],
    );
  }

  Widget _buildPickProfile(CruColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select ABHA profile',
          style: CruType.subhead.copyWith(color: c.label2),
        ),
        const SizedBox(height: CruSpace.s8),
        for (final acct in _searchAccounts) ...[
          CruPressable(
            onTap: _busy ? null : () => setState(() => _pickedAccount = acct),
            builder: (context, hovered) {
              final selected = _pickedAccount?.index == acct.index;
              return Container(
                padding: const EdgeInsets.all(CruSpace.s12),
                decoration: ShapeDecoration(
                  color: selected
                      ? c.accentWash
                      : (hovered ? cruHoverShade(c.inset, c) : c.inset),
                  shape: cruShape(
                    CruRadius.control,
                    side: selected
                        ? BorderSide(color: c.accent, width: 1.5)
                        : BorderSide.none,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            acct.name,
                            style: CruType.row.copyWith(color: c.label),
                          ),
                          const SizedBox(height: CruSpace.s2),
                          Text(
                            '${acct.abhaNumberMasked} · ${acct.gender}',
                            style: CruType.caption.copyWith(
                              color: c.label2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    CruIcon(
                      selected ? CruIcons.check : CruIcons.chevronRight,
                      color: selected ? c.accentText : c.label3,
                      size: 18,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: CruSpace.s8),
        ],
      ],
    );
  }

  Widget _buildOtpStep(CruColors c) {
    final isComm = _step == _FlowStep.commMobileOtp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruTextField(
          label: isComm ? 'Mobile verification OTP' : 'Enter 6-digit OTP',
          controller: _otpCtrl,
          hint: '6 digits',
          tabular: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (v) {
            final d = digitsOnly(v ?? '');
            if (d.isEmpty) return null;
            return d.length == 6 ? null : 'OTP must be 6 digits.';
          },
        ),
        const SizedBox(height: CruSpace.s12),
        Row(
          children: [
            Expanded(
              child: Text(
                _resendsLeft > 0
                    ? 'Resends left: $_resendsLeft'
                    : 'Maximum OTP resend attempts reached. Please try again after 30 mins',
                style: CruType.caption.copyWith(
                  color: _resendsLeft > 0 ? c.label2 : c.redText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: _secondsLeft > 0 ? 'Resend (${_secondsLeft}s)' : 'Resend',
              kind: CruButtonKind.inset,
              onPressed: (_secondsLeft == 0 && _resendsLeft > 0 && !_busy)
                  ? _handleResendOtp
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChooseAddress(CruColors c) {
    final rules = AbhaAddressRules.evaluate(_addressCtrl.text);
    final hasInput = _addressCtrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_suggestedAddresses.isNotEmpty) ...[
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final s in _suggestedAddresses)
                CruPressable(
                  onTap: () => setState(() {
                    _addressCtrl.text = s.split('@').first;
                    _addressAlreadyExists = false;
                    _notice = null;
                  }),
                  builder: (context, hovered) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s12,
                      vertical: CruSpace.s6,
                    ),
                    decoration: ShapeDecoration(
                      color: hovered ? cruHoverShade(c.inset, c) : c.inset,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      s,
                      style: CruType.caption.copyWith(color: c.label),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
        ],
        CruTextField(
          label: 'ABHA address',
          controller: _addressCtrl,
          hint: '8–18 characters',
          onChanged: (_) => setState(() {
            _addressAlreadyExists = false;
            _notice = null;
          }),
        ),
        const SizedBox(height: CruSpace.s8),
        _RuleRow(
          label: '8 to 18 characters',
          ok: rules.lengthOk,
          active: hasInput,
        ),
        _RuleRow(
          label: 'Letters and digits only (one . and one _ allowed)',
          ok: rules.charsOk && rules.specialCountOk,
          active: hasInput,
        ),
        _RuleRow(
          label: 'Cannot start or end with . or _',
          ok: rules.edgesOk,
          active: hasInput,
        ),
        if (_addressAlreadyExists) ...[
          const SizedBox(height: CruSpace.s12),
          Row(
            children: [
              CruButton(
                label: 'Use existing',
                kind: CruButtonKind.secondary,
                onPressed: () => setState(() => _step = _FlowStep.result),
              ),
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: 'Create new',
                kind: CruButtonKind.inset,
                onPressed: () => setState(() {
                  _addressCtrl.clear();
                  _addressAlreadyExists = false;
                  _notice = null;
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildResultStep(CruColors c) {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: CruType.title.copyWith(color: c.label)),
          const SizedBox(height: CruSpace.s6),
          Text(
            'ABHA Number: ${p.abhaNumber}',
            style: CruType.text.copyWith(
              color: c.label,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (p.abhaAddress.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s4),
            Text(
              'ABHA Address: ${p.abhaAddress}',
              style: CruType.text.copyWith(color: c.label2),
            ),
          ],
          const SizedBox(height: CruSpace.s12),
          CruButton(
            label: 'View card',
            kind: CruButtonKind.secondary,
            onPressed: _busy ? null : _viewCard,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.label,
    required this.ok,
    required this.active,
  });

  final String label;
  final bool ok;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final color = !active ? c.label3 : (ok ? c.greenText : c.redText);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
      child: Row(
        children: [
          CruIcon(ok ? CruIcons.check : CruIcons.close, size: 14, color: color),
          const SizedBox(width: CruSpace.s6),
          Expanded(
            child: Text(label, style: CruType.caption.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _AbhaCardDialog extends StatelessWidget {
  const _AbhaCardDialog({required this.card, required this.abhaNumber});

  final AbhaCardData card;
  final String abhaNumber;

  Uint8List get _bytes => base64Decode(card.base64);

  Future<void> _save(BuildContext context) async {
    try {
      final ext = card.contentType.contains('pdf') ? 'pdf' : 'png';
      final name = 'ABHA_${abhaNumber.replaceAll(RegExp(r'\D'), '')}.$ext';
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save ABHA Card',
        fileName: name,
        bytes: _bytes,
      );
      if (path != null &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(path).writeAsBytes(_bytes);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't save the ABHA card.")),
        );
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    File? tempFile;
    try {
      final ext = card.contentType.contains('pdf') ? 'pdf' : 'png';
      final dir = await getTemporaryDirectory();
      tempFile = File(
        '${dir.path}/ABHA_${abhaNumber.replaceAll(RegExp(r'\D'), '')}.$ext',
      );
      await tempFile.writeAsBytes(_bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(tempFile.path, mimeType: card.contentType)]),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't share the ABHA card.")),
        );
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isImage = !card.contentType.contains('pdf');
    return Dialog(
      backgroundColor: c.surface,
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ABHA Card', style: CruType.title.copyWith(color: c.label)),
              const SizedBox(height: CruSpace.s12),
              if (isImage)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: Image.memory(_bytes, fit: BoxFit.contain),
                )
              else
                Text(
                  'PDF card ready to save or share.',
                  style: CruType.text.copyWith(color: c.label2),
                ),
              const SizedBox(height: CruSpace.s16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: 'Share',
                    kind: CruButtonKind.secondary,
                    onPressed: () => _share(context),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruButton(
                    label: 'Save',
                    kind: CruButtonKind.primary,
                    onPressed: () => _save(context),
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
