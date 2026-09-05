import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

/// Opens a rich modal dialog to switch between any of the 10 medical specialties.
Future<void> showSpecialtySwitcherDialog(BuildContext context) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Specialty Switcher',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, anim1, anim2) {
      return const SpecialtySwitcherDialog();
    },
    transitionBuilder: (ctx, anim1, anim2, child) {
      final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      );
    },
  );
}

/// The Specialty Switcher Dialog Widget.
class SpecialtySwitcherDialog extends ConsumerStatefulWidget {
  const SpecialtySwitcherDialog({super.key});

  @override
  ConsumerState<SpecialtySwitcherDialog> createState() =>
      _SpecialtySwitcherDialogState();
}

class _SpecialtySwitcherDialogState
    extends ConsumerState<SpecialtySwitcherDialog> {
  bool _isSwitching = false;
  String? _switchingLabel;

  @override
  Widget build(BuildContext context) {
    final activeSpecAsync = ref.watch(activeDoctorSpecialtyProvider);
    final activeSpec = activeSpecAsync.maybeWhen(
      data: (s) => s,
      orElse: () => DoctorSpecialty.defaultSpecialty,
    );

    final isWide = MediaQuery.of(context).size.width > 700;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: isWide ? 680 : MediaQuery.of(context).size.width * 0.92,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D422C), Color(0xFF156B47)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Switch Clinical Specialty',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  fontFamily: AppColors.headingFontFamily,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'DEV / TRIAL MODE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF059669),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Switch specialty features dynamically without logging out.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF64748B)),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),

              // ── Active Indicator Banner ──
              Container(
                margin: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: activeSpec.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeSpec.accentColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(activeSpec.icon,
                        size: 18, color: activeSpec.accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Currently Active: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: activeSpec.label,
                              style: TextStyle(
                                color: activeSpec.accentColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' • ${activeSpec.tagline}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Grid of Specialties ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: DoctorSpecialty.all.map((spec) {
                      final isCurrent = spec.type == activeSpec.type;
                      final isBeingSwitched =
                          _isSwitching && _switchingLabel == spec.label;

                      return SizedBox(
                        width: isWide ? (680 - 40 - 12) / 2 : double.infinity,
                        child: _SpecialtyCardItem(
                          spec: spec,
                          isActive: isCurrent,
                          isLoading: isBeingSwitched,
                          onTap: () async {
                            if (isCurrent || _isSwitching) return;
                            setState(() {
                              _isSwitching = true;
                              _switchingLabel = spec.label;
                            });

                            final nav = Navigator.of(context);
                            await switchDoctorSpecialty(
                              context,
                              spec,
                              ref: ref,
                            );

                            if (mounted) {
                              setState(() {
                                _isSwitching = false;
                                _switchingLabel = null;
                              });
                              nav.pop();
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // ── Footer ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 15, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Switches custom toolsets, tooth charts, case sheets, and specialty workflows instantly.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
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

/// A card representing a single specialty item inside the switcher dialog.
class _SpecialtyCardItem extends StatefulWidget {
  final DoctorSpecialty spec;
  final bool isActive;
  final bool isLoading;
  final VoidCallback onTap;

  const _SpecialtyCardItem({
    required this.spec,
    required this.isActive,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_SpecialtyCardItem> createState() => _SpecialtyCardItemState();
}

class _SpecialtyCardItemState extends State<_SpecialtyCardItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final isActive = widget.isActive;

    return MouseRegion(
      cursor: isActive
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive
                ? spec.accentColor.withValues(alpha: 0.08)
                : (_isHovered
                    ? spec.accentColor.withValues(alpha: 0.04)
                    : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? spec.accentColor
                  : (_isHovered
                      ? spec.accentColor.withValues(alpha: 0.4)
                      : const Color(0xFFE2E8F0)),
              width: isActive ? 2.0 : 1.2,
            ),
            boxShadow: _isHovered && !isActive
                ? [
                    BoxShadow(
                      color: spec.accentColor.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: spec.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  spec.icon,
                  color: spec.accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Specialty Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spec.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? spec.accentColor
                                  : const Color(0xFF0F172A),
                              fontFamily: AppColors.headingFontFamily,
                            ),
                          ),
                        ),
                        if (widget.isLoading)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: spec.accentColor,
                            ),
                          )
                        else if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: spec.accentColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      spec.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Quick Action tags preview
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: spec.quickActions.take(3).map((act) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            act,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
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

/// A compact, rich Specialty Switcher Card that lives in the Desktop Side Navigation.
class SidebarSpecialtyCard extends StatelessWidget {
  final VoidCallback onSwitchTap;

  const SidebarSpecialtyCard({
    required this.onSwitchTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: DoctorProfileHelper.watchDoctorProfile(),
      builder: (context, snapshot) {
        final profileData = snapshot.data;
        final rawSpecialty = DoctorProfileHelper.formatSpecialty(profileData);
        final spec = DoctorSpecialty.fromString(rawSpecialty);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: spec.accentColor.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: spec.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SPECIALTY MODE',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: spec.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'TRIAL',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: spec.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: spec.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      spec.icon,
                      color: spec.accentColor,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.label,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppColors.headingFontFamily,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          spec.shortLabel,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Switch Specialty Action Button
              InkWell(
                onTap: onSwitchTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: spec.accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Switch Specialty',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
