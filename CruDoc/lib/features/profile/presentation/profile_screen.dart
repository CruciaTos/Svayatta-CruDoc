import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/profile/presentation/widgets/gmail_integration_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
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

    return StreamBuilder<Map<String, dynamic>?>(
      stream: DoctorProfileHelper.watchDoctorProfile(user),
      builder: (context, snapshot) {
        final profileData = snapshot.data;
        final doctorName =
            DoctorProfileHelper.formatDoctorName(user, profileData);
        final specialty = DoctorProfileHelper.formatSpecialty(profileData);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ShellBackground(
            child: SafeArea(
              child: Column(
                children: [
                  // ---- Top Header Navigation Bar ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.textPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                        const Text(
                          'Doctor Profile',
                          style: TextStyle(
                            fontFamily: AppColors.headingFontFamily,
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        InkWell(
                          onTap: () => _showEditProfileSheet(
                              context, doctorName, specialty),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E78FF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF1E78FF)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.edit_rounded,
                                  color: Color(0xFF1E78FF),
                                  size: 15,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E78FF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---- Main Content List ----
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        // ---- Hero Profile Card ----
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 24, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0C000000),
                                blurRadius: 14,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Avatar Ring
                              Container(
                                width: 96,
                                height: 96,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1E78FF),
                                      Color(0xFF00C6FF)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1E78FF)
                                          .withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: user?.photoURL != null
                                      ? ClipOval(
                                          child: Image.network(
                                            user!.photoURL!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, _) =>
                                                const Icon(
                                              Icons.medical_services_rounded,
                                              color: Color(0xFF1E78FF),
                                              size: 44,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_rounded,
                                          color: Color(0xFF1E78FF),
                                          size: 52,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Doctor Name
                              Text(
                                doctorName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppColors.headingFontFamily,
                                  color: Color(0xFF0F172A),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Specialty Pill Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E78FF)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF1E78FF)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_hospital_rounded,
                                      size: 14,
                                      color: Color(0xFF1E78FF),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      specialty,
                                      style: const TextStyle(
                                        color: Color(0xFF1E78FF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Verified Badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 15,
                                    color: Color(0xFF16A34A),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Verified Medical Practitioner',
                                    style: TextStyle(
                                      color: Color(0xFF16A34A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ---- Quick Action: Edit Profile Button ----
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showEditProfileSheet(
                                context, doctorName, specialty),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF1E78FF),
                                    Color(0xFF1D4ED8)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x331E78FF),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.edit_note_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Edit Profile Name & Specialty',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ---- Information Cards Section ----
                        const Text(
                          'Account Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (email != '—') ...[
                          _ProfileCard(
                            icon: Icons.email_outlined,
                            iconColor: const Color(0xFF1E78FF),
                            iconBg: const Color(0xFF1E78FF)
                                .withValues(alpha: 0.1),
                            title: 'Email Address',
                            subtitle: email,
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (phone != '—') ...[
                          _ProfileCard(
                            icon: Icons.phone_outlined,
                            iconColor: const Color(0xFF0D9488),
                            iconBg: const Color(0xFF0D9488)
                                .withValues(alpha: 0.1),
                            title: 'Phone Number',
                            subtitle: phone,
                          ),
                          const SizedBox(height: 10),
                        ],
                        _ProfileCard(
                          icon: Icons.local_hospital_outlined,
                          iconColor: const Color(0xFF8B5CF6),
                          iconBg:
                              const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                          title: 'Specialty / Qualification',
                          subtitle: specialty,
                        ),
                        const SizedBox(height: 10),
                        _ProfileCard(
                          icon: Icons.shield_outlined,
                          iconColor: const Color(0xFFF59E0B),
                          iconBg:
                              const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          title: 'Authentication Provider',
                          subtitle: '$authMethod Account',
                        ),
                        if (!kIsWeb) ...[
                          const SizedBox(height: 20),
                          // ---- Gmail Integration Section ----
                          const Text(
                            'Integrations & Notifications',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const GmailIntegrationCard(),
                        ],
                        const SizedBox(height: 28),

                        // ---- Log Out Button ----
                        OutlinedButton.icon(
                          onPressed: () async {
                            final authService = AuthService();
                            await authService.signOut();
                            if (!context.mounted) return;
                            context.go('/auth');
                          },
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Log Out Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            backgroundColor: const Color(0xFFFEF2F2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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
      },
    );
  }

  void _showEditProfileSheet(
      BuildContext context, String currentName, String currentSpecialty) {
    final nameController = TextEditingController(text: currentName);
    final specialtyController = TextEditingController(text: currentSpecialty);
    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Doctor Profile',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Doctor Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Dr. Vinit Parab',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Specialty / Qualification',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: specialtyController,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. General Physician, MD Cardiology',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setSheetState(() => isSaving = true);
                          try {
                            await DoctorProfileHelper.updateProfile(
                              doctorName: nameController.text,
                              specialty: specialtyController.text,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } finally {
                            if (ctx.mounted) {
                              setSheetState(() => isSaving = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(isSaving ? 'Saving...' : 'Save Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E78FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
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
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;

  const _ProfileCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}