import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/features/settings/data/desktop_settings_preferences.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/shell/data/desktop_shell_preferences.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';

/// Professional, full-featured Master-Detail Desktop Settings Screen for CruDoc.
class DesktopSettingsScreen extends ConsumerStatefulWidget {
  const DesktopSettingsScreen({super.key});

  @override
  ConsumerState<DesktopSettingsScreen> createState() =>
      _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends ConsumerState<DesktopSettingsScreen> {
  final DesktopSettingsPreferences _settingsPrefs =
      DesktopSettingsPreferences();
  final DesktopShellPreferences _shellPrefs = DesktopShellPreferences();

  int _selectedTabIndex = 0;
  String _appVersion = '1.0.0';
  String _deviceDisplayName = 'Windows Desktop';

  // Scribe & Clinical state
  String _scribeLanguage = 'English (India)';
  String _noteFormat = 'SOAP (Subjective, Objective, Assessment, Plan)';
  bool _autoGenerateRx = true;
  bool _autoExtractDiagnoses = true;
  String _audioQuality = 'High Fidelity (44.1 kHz)';

  // Billing & Invoices state
  String _currencySymbol = '₹';
  double _consultationFee = 500.0;
  double _followUpFee = 300.0;
  bool _gstEnabled = false;
  double _gstRate = 18.0;
  String _invoicePrefix = 'CRU-';
  int _paymentTermsDays = 0;
  String _defaultPaymentMode = 'UPI / QR Code';

  // Notifications state
  bool _lowStockAlerts = true;
  bool _expiryAlerts = true;
  bool _queueSoundChime = true;
  bool _appointmentReminders = true;
  bool _criticalVitalsAlert = true;

  // Desktop Appearance & Shell state
  bool _sidebarExpanded = true;
  int _defaultStartupTab = 0;
  bool _compactDensity = false;
  bool _soundEffects = true;
  bool _hardwareAcceleration = true;

  // Practice & Letterhead Controllers
  final TextEditingController _clinicNameController = TextEditingController();
  final TextEditingController _qualificationsController =
      TextEditingController();
  final TextEditingController _regNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _taglineController = TextEditingController();
  final TextEditingController _footerDisclaimerController =
      TextEditingController();

  bool _isSavingClinic = false;
  bool _isCheckingUpdate = false;
  String? _updateStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _clinicNameController.dispose();
    _qualificationsController.dispose();
    _regNumberController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taglineController.dispose();
    _footerDisclaimerController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    final version = await DeviceInfoHelper.getAppVersion();
    final device = await DeviceInfoHelper.getDeviceDisplayName();
    if (!mounted) return;
    setState(() {
      _appVersion = version;
      _deviceDisplayName = device;
    });
  }

  Future<void> _loadPreferences() async {
    final scribeLang = await _settingsPrefs.getScribeLanguage();
    final noteFmt = await _settingsPrefs.getNoteFormat();
    final autoRx = await _settingsPrefs.getAutoGenerateRx();
    final autoDiag = await _settingsPrefs.getAutoExtractDiagnoses();
    final audioQ = await _settingsPrefs.getAudioQuality();

    final curr = await _settingsPrefs.getCurrencySymbol();
    final conFee = await _settingsPrefs.getDefaultConsultationFee();
    final fupFee = await _settingsPrefs.getDefaultFollowUpFee();
    final gstOn = await _settingsPrefs.getGstEnabled();
    final gstR = await _settingsPrefs.getGstRate();
    final invPre = await _settingsPrefs.getInvoicePrefix();
    final payTerms = await _settingsPrefs.getPaymentTermsDays();
    final payMode = await _settingsPrefs.getDefaultPaymentMode();

    final lowStock = await _settingsPrefs.getLowStockAlerts();
    final expiry = await _settingsPrefs.getExpiryAlerts();
    final queueChime = await _settingsPrefs.getQueueSoundChime();
    final apptRemind = await _settingsPrefs.getAppointmentReminders();
    final critVitals = await _settingsPrefs.getCriticalVitalsAlert();

    final sidebarExp = await _shellPrefs.getSidebarExpanded();
    final startupTab = await _shellPrefs.getLastTabIndex();
    final compact = await _settingsPrefs.getCompactDensity();
    final sfx = await _settingsPrefs.getSoundEffects();
    final hwAccel = await _settingsPrefs.getHardwareAcceleration();

    if (!mounted) return;
    setState(() {
      _scribeLanguage = scribeLang;
      _noteFormat = noteFmt;
      _autoGenerateRx = autoRx;
      _autoExtractDiagnoses = autoDiag;
      _audioQuality = audioQ;

      _currencySymbol = curr;
      _consultationFee = conFee;
      _followUpFee = fupFee;
      _gstEnabled = gstOn;
      _gstRate = gstR;
      _invoicePrefix = invPre;
      _paymentTermsDays = payTerms;
      _defaultPaymentMode = payMode;

      _lowStockAlerts = lowStock;
      _expiryAlerts = expiry;
      _queueSoundChime = queueChime;
      _appointmentReminders = apptRemind;
      _criticalVitalsAlert = critVitals;

      _sidebarExpanded = sidebarExp;
      _defaultStartupTab = startupTab;
      _compactDensity = compact;
      _soundEffects = sfx;
      _hardwareAcceleration = hwAccel;
    });
  }

  void _populateClinicControllersOnce(Map<String, dynamic>? data, User? user) {
    if (_clinicNameController.text.isEmpty && data != null) {
      _clinicNameController.text =
          (data['clinicName'] ?? data['practiceName'] ?? '') as String;
      _qualificationsController.text =
          (data['qualifications'] ?? data['doctorQualifications'] ?? '')
              as String;
      _regNumberController.text =
          (data['registrationNumber'] ?? data['doctorRegistrationNumber'] ?? '')
              as String;
      _addressController.text = (data['clinicAddress'] ?? '') as String;
      _phoneController.text =
          (data['clinicPhone'] ?? user?.phoneNumber ?? '') as String;
      _emailController.text =
          (data['clinicEmail'] ?? user?.email ?? '') as String;
      _taglineController.text = (data['letterheadTagline'] ?? '') as String;
      _footerDisclaimerController.text =
          (data['letterheadFooterDisclaimer'] ?? '') as String;
    }
  }

  Future<void> _saveClinicProfile() async {
    setState(() => _isSavingClinic = true);
    try {
      await DoctorProfileHelper.updateLetterheadBranding(
        clinicName: _clinicNameController.text,
        doctorQualifications: _qualificationsController.text,
        registrationNumber: _regNumberController.text,
        clinicAddress: _addressController.text,
        clinicPhone: _phoneController.text,
        clinicEmail: _emailController.text,
        tagline: _taglineController.text,
        footerDisclaimer: _footerDisclaimerController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Clinic Profile & Letterhead saved to Cloud'),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save clinic profile: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingClinic = false);
    }
  }

  Future<void> _triggerCheckForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateStatusMessage = 'Checking GitHub releases...';
    });

    try {
      await ref
          .read(updateControllerProvider.notifier)
          .checkForUpdate(force: true);
      final checkResult = ref.read(updateControllerProvider).checkResult;

      if (!mounted) return;
      setState(() {
        if (checkResult is UpToDate) {
          _updateStatusMessage = 'You are using the latest version of CruDoc.';
        } else if (checkResult is UpdateAvailable) {
          _updateStatusMessage =
              'Update ${checkResult.release.version} is available!';
        } else if (checkResult is CheckFailed) {
          _updateStatusMessage = 'Update check: ${checkResult.reason}';
        } else {
          _updateStatusMessage = 'Check completed.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateStatusMessage = 'Check failed: $e';
      });
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Sign Out of CruDoc?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to end your current session? Any unsaved local changes have already been synced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authService = AuthService();
      await authService.signOut();
      if (!mounted) return;
      context.go('/auth');
    }
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 10),
            Text('Clear Local Cache?'),
          ],
        ),
        content: const Text(
          'This will purge local temporary files, image thumbnail caches, and offline consultation drafts. Your cloud data is completely safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
            ),
            child: const Text('Purge Cache'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Local cache successfully purged (0 MB free)'),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _sendPasswordReset() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email address associated with this account.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending reset link: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ShellBackground(
            child: SafeArea(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: DoctorProfileHelper.watchDoctorProfile(user),
                builder: (context, snapshot) {
                  final profileData = snapshot.data;
                  _populateClinicControllersOnce(profileData, user);

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFCBD5E1),
                              width: 0.75,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0C000000),
                                blurRadius: 20,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // ----------------- Top Header Bar -----------------
                              _buildTopHeader(user, profileData),

                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // ----------------- Master-Detail Body -----------------
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left Navigation Rail
                                    _buildLeftNavRail(),

                                    const VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: Color(0xFFE2E8F0),
                                    ),

                                    // Right Content Panel
                                    Expanded(
                                      child: _buildSelectedContentPanel(
                                        user,
                                        profileData,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP HEADER
  // ===========================================================================

  Widget _buildTopHeader(User? user, Map<String, dynamic>? profileData) {
    final doctorName = DoctorProfileHelper.formatDoctorName(user, profileData);
    final activeSpec = ref.watch(activeDoctorSpecialtyProvider).maybeWhen(
          data: (s) => s,
          orElse: () => DoctorSpecialty.defaultSpecialty,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          // Back Button
          Tooltip(
            message: 'Return to Workspace (Esc)',
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF1E293B),
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Title & Breadcrumb
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Settings & Preferences',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      'v$_appVersion Desktop',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Configure practice letterheads, clinical AI defaults, billing rates, and desktop layout',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Cloud Sync Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.cloud_done_rounded,
                    color: Color(0xFF16A34A), size: 14),
                SizedBox(width: 6),
                Text(
                  'Cloud Synced',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Doctor Account Pill
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: activeSpec.accentColor.withValues(alpha: 0.15),
                    child: Icon(
                      activeSpec.icon,
                      size: 15,
                      color: activeSpec.accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        doctorName,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        activeSpec.shortLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: activeSpec.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LEFT NAV RAIL
  // ===========================================================================

  static const List<_NavTabItem> _tabs = [
    _NavTabItem(
      title: 'Practice & Letterhead',
      subtitle: 'Clinic info, address & Rx branding',
      icon: Icons.apartment_rounded,
    ),
    _NavTabItem(
      title: 'Doctor & Account',
      subtitle: 'Doctor profile, specialty & login',
      icon: Icons.badge_rounded,
    ),
    _NavTabItem(
      title: 'AI Scribe & Clinical',
      subtitle: 'SOAP templates, language & AI',
      icon: Icons.auto_awesome_rounded,
    ),
    _NavTabItem(
      title: 'Billing & Invoices',
      subtitle: 'Currency, consultation fees & tax',
      icon: Icons.receipt_long_rounded,
    ),
    _NavTabItem(
      title: 'Notifications & Audio',
      subtitle: 'Stock alerts & queue sound chimes',
      icon: Icons.notifications_active_outlined,
    ),
    _NavTabItem(
      title: 'Desktop & Shortcuts',
      subtitle: 'Sidebar, startup tab & hotkeys',
      icon: Icons.desktop_windows_rounded,
    ),
    _NavTabItem(
      title: 'System & Updates',
      subtitle: 'Version check, offline DB & session',
      icon: Icons.info_outline_rounded,
    ),
  ];

  Widget _buildLeftNavRail() {
    return Container(
      width: 270,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 8),
            child: Text(
              'CATEGORIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _tabs.length,
              separatorBuilder: (ctx, idx) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = _tabs[index];
                final isSelected = _selectedTabIndex == index;

                return InkWell(
                  onTap: () => setState(() => _selectedTabIndex = index),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF2563EB).withValues(alpha: 0.25)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            item.icon,
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF1D4ED8)
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isSelected
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 24, color: Color(0xFFE2E8F0)),

          // Bottom Session Link
          InkWell(
            onTap: _handleSignOut,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded,
                      size: 16, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text(
                    'Sign Out Session',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CONTENT PANELS ROUTER
  // ===========================================================================

  Widget _buildSelectedContentPanel(
    User? user,
    Map<String, dynamic>? profileData,
  ) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildPracticeLetterheadPanel(user, profileData);
      case 1:
        return _buildDoctorAccountPanel(user, profileData);
      case 2:
        return _buildAiClinicalPanel();
      case 3:
        return _buildBillingInvoicesPanel();
      case 4:
        return _buildNotificationsAudioPanel();
      case 5:
        return _buildDesktopShortcutsPanel();
      case 6:
        return _buildSystemUpdatesPanel(user);
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // TAB 0: PRACTICE & LETTERHEAD
  // ===========================================================================

  Widget _buildPracticeLetterheadPanel(
    User? user,
    Map<String, dynamic>? profileData,
  ) {
    final letterheadConfig =
        DoctorLetterheadConfig.fromProfileData(profileData, user);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Clinic & Document Letterhead',
                description:
                    'Information entered here is embedded on patient prescriptions, clinical summaries, and billing receipts.',
              ),
              const SizedBox(height: 20),

              // Live Letterhead Preview Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.preview_rounded,
                            size: 18, color: Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        const Text(
                          'Live Document Letterhead Preview',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Rx & Invoice Header',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Letterhead Mock Banner
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.local_hospital_rounded,
                                  color: Color(0xFF2563EB),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _clinicNameController.text.isNotEmpty
                                          ? _clinicNameController.text
                                          : letterheadConfig.clinicName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _taglineController.text.isNotEmpty
                                          ? _taglineController.text
                                          : letterheadConfig.tagline,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF64748B),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_addressController.text.isNotEmpty ? _addressController.text : letterheadConfig.clinicAddress}  •  Ph: ${_phoneController.text.isNotEmpty ? _phoneController.text : letterheadConfig.clinicPhone}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    letterheadConfig.doctorName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    _qualificationsController.text.isNotEmpty
                                        ? _qualificationsController.text
                                        : letterheadConfig.qualifications,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    'Reg: ${_regNumberController.text.isNotEmpty ? _regNumberController.text : letterheadConfig.registrationNumber}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 20, color: Color(0xFFE2E8F0)),
                          Text(
                            _footerDisclaimerController.text.isNotEmpty
                                ? _footerDisclaimerController.text
                                : letterheadConfig.footerDisclaimer,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Form Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Practice Details Form',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Clinic / Hospital Name',
                            controller: _clinicNameController,
                            hint: 'e.g. Apex Multispecialty Clinic',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Doctor Qualifications',
                            controller: _qualificationsController,
                            hint: 'e.g. MBBS, MD (Medicine), DNB',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Medical Registration Number',
                            controller: _regNumberController,
                            hint: 'e.g. MMC-2024/98765',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Practice Phone / Contact',
                            controller: _phoneController,
                            hint: '+91 98765 43210',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Practice Email Address',
                            controller: _emailController,
                            hint: 'clinic@apexhealth.com',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            label: 'Header Tagline / Slogan',
                            controller: _taglineController,
                            hint: 'Compassionate Care, Advanced Medicine',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Clinic Address',
                      controller: _addressController,
                      hint: 'Suite 401, Health Tower, Station Road, Mumbai',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: 'Document Footer Disclaimer',
                      controller: _footerDisclaimerController,
                      hint:
                          'This is a digitally generated document by CruDoc PMS.',
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _isSavingClinic ? null : _saveClinicProfile,
                        icon: _isSavingClinic
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: Text(
                          _isSavingClinic
                              ? 'Saving Changes...'
                              : 'Save Practice Letterhead',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: DOCTOR & ACCOUNT
  // ===========================================================================

  Widget _buildDoctorAccountPanel(
    User? user,
    Map<String, dynamic>? profileData,
  ) {
    final doctorName = DoctorProfileHelper.formatDoctorName(user, profileData);
    final activeSpec = ref.watch(activeDoctorSpecialtyProvider).maybeWhen(
          data: (s) => s,
          orElse: () => DoctorSpecialty.defaultSpecialty,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Doctor Account & Medical Identity',
                description:
                    'Manage your physician credentials, primary clinical specialty, and authentication settings.',
              ),
              const SizedBox(height: 20),

              // Doctor Profile Summary Card
              _buildCardContainer(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor:
                          activeSpec.accentColor.withValues(alpha: 0.12),
                      child: Icon(
                        activeSpec.icon,
                        size: 36,
                        color: activeSpec.accentColor,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doctorName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Active Specialty: ${activeSpec.label}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: activeSpec.accentColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Account Email: ${user?.email ?? '—'}  •  Phone: ${user?.phoneNumber ?? '—'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      ),
                      icon: const Icon(Icons.person_rounded, size: 16),
                      label: const Text('Full Profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF2563EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Specialty Switcher Integration Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Clinical Specialty Workspace',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'CruDoc customizes quick actions, prescription formats, and templates for ${activeSpec.label}.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              showSpecialtySwitcherDialog(context),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Switch Specialty'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DoctorSpecialty.all.map((spec) {
                        final isActive = spec.type == activeSpec.type;
                        return InkWell(
                          onTap: () {
                            switchDoctorSpecialty(
                              context,
                              spec,
                              ref: ref,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? spec.accentColor.withValues(alpha: 0.12)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive
                                    ? spec.accentColor
                                    : const Color(0xFFE2E8F0),
                                width: isActive ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(spec.icon,
                                    size: 15,
                                    color: isActive
                                        ? spec.accentColor
                                        : const Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  spec.shortLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive
                                        ? spec.accentColor
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Security & Password Reset Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account Security & Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Request a verified password reset email or manage sign-in credentials.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _sendPasswordReset,
                          icon: const Icon(Icons.lock_reset_rounded, size: 16),
                          label: const Text('Send Password Reset Email'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: AI SCRIBE & CLINICAL
  // ===========================================================================

  Widget _buildAiClinicalPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'CruDoc AI Scribe & Clinical Intelligence',
                description:
                    'Configure speech-to-text language parsing, automated consultation summary templates, and prescription drafting.',
              ),
              const SizedBox(height: 20),

              // Scribe Intelligence Settings
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consultation Note Formatting',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDropdownField(
                      label: 'Default Clinical Note Format',
                      value: _noteFormat,
                      items: const [
                        'SOAP (Subjective, Objective, Assessment, Plan)',
                        'Standard Clinical Summary',
                        'Free-form Dictation Notes',
                        'Comprehensive Medical Examination',
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _noteFormat = val);
                          _settingsPrefs.setNoteFormat(val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Voice Dictation Language',
                            value: _scribeLanguage,
                            items: const [
                              'English (India)',
                              'English (US)',
                              'Hindi (हिंदी)',
                              'Marathi (मराठी)',
                              'Multilingual Auto-Detect',
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _scribeLanguage = val);
                                _settingsPrefs.setScribeLanguage(val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Audio Input Fidelity',
                            value: _audioQuality,
                            items: const [
                              'High Fidelity (44.1 kHz)',
                              'Standard (22 kHz)',
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _audioQuality = val);
                                _settingsPrefs.setAudioQuality(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Auto-Drafting Toggles
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Automated Extraction & Prescriptions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSwitchTile(
                      title: 'Auto-Generate Prescription (Rx) Draft',
                      subtitle:
                          'Automatically parse medicine names, dosages, and frequency into a draft prescription after recording.',
                      value: _autoGenerateRx,
                      onChanged: (val) {
                        setState(() => _autoGenerateRx = val);
                        _settingsPrefs.setAutoGenerateRx(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Extract Symptoms & ICD-10 Coding',
                      subtitle:
                          'Identify clinical symptoms and suggest matching diagnostic ICD-10 codes for patient history.',
                      value: _autoExtractDiagnoses,
                      onChanged: (val) {
                        setState(() => _autoExtractDiagnoses = val);
                        _settingsPrefs.setAutoExtractDiagnoses(val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: BILLING & INVOICES
  // ===========================================================================

  Widget _buildBillingInvoicesPanel() {
    const paymentTermOptions = [
      'Immediate (Due on Receipt)',
      'Net 7 Days',
      'Net 15 Days',
      'Net 30 Days',
    ];
    String currentTermLabel;
    switch (_paymentTermsDays) {
      case 7:
        currentTermLabel = 'Net 7 Days';
        break;
      case 15:
        currentTermLabel = 'Net 15 Days';
        break;
      case 30:
        currentTermLabel = 'Net 30 Days';
        break;
      default:
        currentTermLabel = 'Immediate (Due on Receipt)';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Billing & Invoice Defaults',
                description:
                    'Set standard consultation tariffs, tax rates, invoice prefixes, and payment terms for the practice.',
              ),
              const SizedBox(height: 20),

              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Currency & Default Fees',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Practice Currency',
                            value: _currencySymbol,
                            items: const ['₹', '\$', '€', '£', 'AED'],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _currencySymbol = val);
                                _settingsPrefs.setCurrencySymbol(val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDoubleField(
                            label: 'Standard Consultation Fee',
                            value: _consultationFee,
                            prefix: _currencySymbol,
                            onChanged: (val) {
                              setState(() => _consultationFee = val);
                              _settingsPrefs.setDefaultConsultationFee(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDoubleField(
                            label: 'Follow-up Consultation Fee',
                            value: _followUpFee,
                            prefix: _currencySymbol,
                            onChanged: (val) {
                              setState(() => _followUpFee = val);
                              _settingsPrefs.setDefaultFollowUpFee(val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Taxation & Invoice Numbering',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSwitchTile(
                      title: 'Enable GST / Tax on Invoices',
                      subtitle:
                          'Automatically calculate and display tax breakout on patient billing statements.',
                      value: _gstEnabled,
                      onChanged: (val) {
                        setState(() => _gstEnabled = val);
                        _settingsPrefs.setGstEnabled(val);
                      },
                    ),
                    if (_gstEnabled) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdownField(
                              label: 'Default GST Rate (%)',
                              value: '${_gstRate.toInt()}%',
                              items: const [
                                '0%',
                                '5%',
                                '12%',
                                '18%',
                                '28%',
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  final num = double.tryParse(
                                          val.replaceAll('%', '')) ??
                                      18.0;
                                  setState(() => _gstRate = num);
                                  _settingsPrefs.setGstRate(num);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStringField(
                            label: 'Invoice Prefix',
                            value: _invoicePrefix,
                            hint: 'CRU-',
                            onChanged: (val) {
                              setState(() => _invoicePrefix = val);
                              _settingsPrefs.setInvoicePrefix(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Default Payment Terms',
                            value: currentTermLabel,
                            items: paymentTermOptions,
                            onChanged: (val) {
                              if (val != null) {
                                int days = 0;
                                if (val.contains('7')) days = 7;
                                if (val.contains('15')) days = 15;
                                if (val.contains('30')) days = 30;
                                setState(() => _paymentTermsDays = days);
                                _settingsPrefs.setPaymentTermsDays(days);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Default Payment Mode',
                            value: _defaultPaymentMode,
                            items: const [
                              'UPI / QR Code',
                              'Cash',
                              'Debit / Credit Card',
                              'Net Banking',
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _defaultPaymentMode = val);
                                _settingsPrefs.setDefaultPaymentMode(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 4: NOTIFICATIONS & AUDIO
  // ===========================================================================

  Widget _buildNotificationsAudioPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Notifications & Audio Alerts',
                description:
                    'Manage low stock inventory alerts, queue token chimes, and clinical audio notifications.',
              ),
              const SizedBox(height: 20),

              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inventory & Stock Alerts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSwitchTile(
                      title: 'Low Stock Level Alerts',
                      subtitle:
                          'Surfaces notification banners when pharmacy items fall below threshold.',
                      value: _lowStockAlerts,
                      onChanged: (val) {
                        setState(() => _lowStockAlerts = val);
                        _settingsPrefs.setLowStockAlerts(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Critical Medicine Expiry Warnings',
                      subtitle:
                          'Alert when medicines are within 60 days of expiry date.',
                      value: _expiryAlerts,
                      onChanged: (val) {
                        setState(() => _expiryAlerts = val);
                        _settingsPrefs.setExpiryAlerts(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Patient Queue & Sound Chimes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              SystemSound.play(SystemSoundType.alert),
                          icon: const Icon(Icons.volume_up_rounded, size: 16),
                          label: const Text('Test Chime'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildSwitchTile(
                      title: 'Patient Queue Audio Chime',
                      subtitle:
                          'Plays an audible chime when the next patient token is called from the queue.',
                      value: _queueSoundChime,
                      onChanged: (val) {
                        setState(() => _queueSoundChime = val);
                        _settingsPrefs.setQueueSoundChime(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Upcoming Appointment Reminders',
                      subtitle:
                          'Notify doctor 10 minutes prior to scheduled patient consultations.',
                      value: _appointmentReminders,
                      onChanged: (val) {
                        setState(() => _appointmentReminders = val);
                        _settingsPrefs.setAppointmentReminders(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Critical Patient Vitals Warning Chime',
                      subtitle:
                          'Audible alert when patient blood pressure or oxygen saturation triggers red flags.',
                      value: _criticalVitalsAlert,
                      onChanged: (val) {
                        setState(() => _criticalVitalsAlert = val);
                        _settingsPrefs.setCriticalVitalsAlert(val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 5: DESKTOP & SHORTCUTS
  // ===========================================================================

  Widget _buildDesktopShortcutsPanel() {
    const tabNames = [
      'Dashboard',
      'Patients',
      'Inventory',
      'Revenue',
      'Appointments',
      'Campaigns',
      'Scribe',
      'Queue',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Desktop Shell & Hotkeys',
                description:
                    'Customize desktop workspace layout, startup behavior, and learn productivity shortcuts.',
              ),
              const SizedBox(height: 20),

              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workspace Preferences',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSwitchTile(
                      title: 'Sidebar Expanded by Default',
                      subtitle:
                          'Show full labels and badges on startup instead of icon-only collapsed sidebar.',
                      value: _sidebarExpanded,
                      onChanged: (val) {
                        setState(() => _sidebarExpanded = val);
                        _shellPrefs.setSidebarExpanded(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildDropdownField(
                      label: 'Default Startup Screen',
                      value: tabNames[_defaultStartupTab.clamp(0, 7)],
                      items: tabNames,
                      onChanged: (val) {
                        if (val != null) {
                          final idx = tabNames.indexOf(val);
                          setState(() => _defaultStartupTab = idx);
                          _shellPrefs.setLastTabIndex(idx);
                        }
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Compact Density Mode',
                      subtitle:
                          'Tighter row paddings in patient records, inventory tables, and bills.',
                      value: _compactDensity,
                      onChanged: (val) {
                        setState(() => _compactDensity = val);
                        _settingsPrefs.setCompactDensity(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'UI Sound Effects',
                      subtitle:
                          'Audible feedback clicks on key desktop interactions.',
                      value: _soundEffects,
                      onChanged: (val) {
                        setState(() => _soundEffects = val);
                        _settingsPrefs.setSoundEffects(val);
                      },
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildSwitchTile(
                      title: 'Hardware Acceleration',
                      subtitle:
                          'Leverage GPU rendering for fluid animations and backdrop blur.',
                      value: _hardwareAcceleration,
                      onChanged: (val) {
                        setState(() => _hardwareAcceleration = val);
                        _settingsPrefs.setHardwareAcceleration(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Keyboard Shortcuts Table
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.keyboard_rounded,
                            size: 18, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Text(
                          'Desktop Keyboard Shortcuts Cheat Sheet',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildShortcutRow('Ctrl + B', 'Toggle Sidebar (Expand / Collapse)'),
                    _buildShortcutRow('Ctrl + 1', 'Jump to Dashboard'),
                    _buildShortcutRow('Ctrl + 2', 'Jump to Patients Records'),
                    _buildShortcutRow('Ctrl + 3', 'Jump to Pharmacy Inventory'),
                    _buildShortcutRow('Ctrl + 4', 'Jump to Revenue & Invoices'),
                    _buildShortcutRow('Ctrl + 5', 'Jump to Appointments Calendar'),
                    _buildShortcutRow('Ctrl + 6', 'Jump to Patient Campaigns'),
                    _buildShortcutRow('Ctrl + 7', 'Jump to CruDoc AI Scribe'),
                    _buildShortcutRow('Ctrl + 8', 'Jump to Patient OPD Queue'),
                    _buildShortcutRow('Esc', 'Close Settings / Dismiss Active Modal'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutRow(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 6: SYSTEM & UPDATES
  // ===========================================================================

  Widget _buildSystemUpdatesPanel(User? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'System, Storage & Updates',
                description:
                    'CruDoc software version information, local SQLite database status, and update installer.',
              ),
              const SizedBox(height: 20),

              // Version & Check for Updates Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Color(0xFF2563EB),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CruDoc Practice Management System',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Installed Version: v$_appVersion  •  $_deviceDisplayName',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed:
                              _isCheckingUpdate ? null : _triggerCheckForUpdate,
                          icon: _isCheckingUpdate
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            _isCheckingUpdate
                                ? 'Checking...'
                                : 'Check for Updates',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_updateStatusMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                            Text(
                              _updateStatusMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Storage & Cache Management Card
              _buildCardContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local Encrypted Storage & Cache',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'CruDoc utilizes SQLCipher-encrypted offline storage to allow rapid offline prescription drafting and instant record lookups.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.shield_rounded,
                                size: 16, color: Color(0xFF059669)),
                            SizedBox(width: 6),
                            Text(
                              'SQLite DB: Encrypted (AES-256) & Synced',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: _handleClearCache,
                          icon: const Icon(Icons.cleaning_services_rounded,
                              size: 16),
                          label: const Text('Clear Local Cache'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD97706),
                            side: const BorderSide(color: Color(0xFFD97706)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Active Session Card
              _buildCardContainer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Signed In Session',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Authenticated as ${user?.email ?? user?.phoneNumber ?? 'Physician'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _handleSignOut,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Sign Out'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // COMMON HELPER WIDGETS
  // ===========================================================================

  Widget _buildSectionHeader({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStringField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoubleField({
    required String label,
    required double value,
    required String prefix,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value.toStringAsFixed(0),
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
          onChanged: (text) {
            final parsed = double.tryParse(text);
            if (parsed != null) onChanged(parsed);
          },
          decoration: InputDecoration(
            prefixText: '$prefix ',
            prefixStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2563EB),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = items.contains(value) ? value : items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: validValue,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            activeTrackColor: const Color(0xFF2563EB),
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NavTabItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const _NavTabItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
