import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Doctor';
    final email = user?.email ?? '—';
    final phone = user?.phoneNumber ?? '—';

    // Determine provider for the "Joined" label
    final providerIds =
        user?.providerData.map((info) => info.providerId).toList() ?? [];
    String authMethod = 'Email';
    if (providerIds.contains('google.com')) {
      authMethod = 'Google';
    } else if (providerIds.contains('phone')) {
      authMethod = 'Phone';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with back button
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: AppColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 48), // balance the back arrow
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Profile picture
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.slateBlue, width: 3),
                  color: AppColors.cardSurfaceAlt,
                ),
                child: user?.photoURL != null
                    ? ClipOval(
                        child: Image.network(
                          user!.photoURL!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.person,
                              color: AppColors.silver,
                              size: 60),
                        ),
                      )
                    : const Icon(Icons.person,
                        color: AppColors.silver, size: 60),
              ),
              const SizedBox(height: 16),
              Text(
                displayName,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Signed in via $authMethod',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 32),
              // Profile info cards
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (email != '—')
                      _ProfileCard(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: email,
                      ),
                    if (email != '—') const SizedBox(height: 12),
                    if (phone != '—')
                      _ProfileCard(
                        icon: Icons.phone_outlined,
                        title: 'Phone',
                        subtitle: phone,
                      ),
                    if (phone != '—') const SizedBox(height: 12),
                    _ProfileCard(
                      icon: Icons.shield_outlined,
                      title: 'Auth Provider',
                      subtitle: authMethod,
                    ),
                    const SizedBox(height: 28),
                    // Log Out button — functional
                    OutlinedButton.icon(
                      onPressed: () async {
                        final authService = AuthService();
                        await authService.signOut();
                        if (!context.mounted) return;
                        context.go('/auth');
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Log Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
}

class _ProfileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ProfileCard(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.silver, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}