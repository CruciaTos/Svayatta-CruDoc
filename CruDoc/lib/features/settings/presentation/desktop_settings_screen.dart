import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/core/utils/device_info_helper.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';

/// Very basic desktop Settings screen: account summary, edit-profile link,
/// app version, and sign out. Matches the light-blue rounded content-panel
/// style used by the other desktop tabs (see DesktopInventoryScreen).
class DesktopSettingsScreen extends StatelessWidget {
  const DesktopSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Stack(
      children: [
        SizedBox.expand(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color.fromARGB(255, 150, 150, 150),
                    width: 0.25,
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _AccountCard(user: user),
                        const SizedBox(height: 16),
                        const _AppInfoCard(),
                        const SizedBox(height: 16),
                        _SignOutCard(context: context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final User? user;

  const _AccountCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: DoctorProfileHelper.watchDoctorProfile(user),
      builder: (context, snapshot) {
        final profileData = snapshot.data;
        final doctorName =
            DoctorProfileHelper.formatDoctorName(user, profileData);
        final specialty = DoctorProfileHelper.formatSpecialty(profileData);
        final email = user?.email ?? '—';

        return _SettingsCard(
          title: 'ACCOUNT',
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      specialty,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Edit Profile'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'APP',
      child: FutureBuilder<String>(
        future: DeviceInfoHelper.getAppVersion(),
        builder: (context, snapshot) {
          final version = snapshot.data ?? '—';
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CruDoc Desktop',
                style: TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              ),
              Text(
                'v$version',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SignOutCard extends StatelessWidget {
  final BuildContext context;

  const _SignOutCard({required this.context});

  Future<void> _handleSignOut(BuildContext context) async {
    final authService = AuthService();
    await authService.signOut();
    if (!context.mounted) return;
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'SESSION',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _handleSignOut(context),
          icon: const Icon(Icons.logout, size: 18, color: Color(0xFFDC2626)),
          label: const Text('Sign Out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFDC2626)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
