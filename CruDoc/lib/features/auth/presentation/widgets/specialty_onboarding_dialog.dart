import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

/// Full-screen modal dialog shown once after a Google / Phone sign-in when
/// the doctor's Firestore profile has no specialty set.
///
/// Returns the selected [DoctorSpecialty] or `null` if dismissed.
Future<DoctorSpecialty?> showSpecialtyOnboardingDialog(BuildContext context) {
  return showGeneralDialog<DoctorSpecialty>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xDD0F172A),
    transitionDuration: const Duration(milliseconds: 420),
    transitionBuilder: (context, a1, a2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: a1, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: a1,
            curve: Curves.easeOutBack,
          ).drive(Tween(begin: 0.92, end: 1.0)),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _SpecialtyOnboardingContent();
    },
  );
}

class _SpecialtyOnboardingContent extends ConsumerStatefulWidget {
  const _SpecialtyOnboardingContent();

  @override
  ConsumerState<_SpecialtyOnboardingContent> createState() =>
      _SpecialtyOnboardingContentState();
}

class _SpecialtyOnboardingContentState
    extends ConsumerState<_SpecialtyOnboardingContent> {
  DoctorSpecialtyType? _selectedType;
  bool _isSaving = false;

  Future<void> _handleConfirm() async {
    if (_selectedType == null || _isSaving) return;

    final spec = DoctorSpecialty.all.firstWhere(
      (s) => s.type == _selectedType,
      orElse: () => DoctorSpecialty.defaultSpecialty,
    );

    setState(() => _isSaving = true);

    try {
      await saveDoctorSpecialty(spec);
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(spec);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;
    final gridCrossAxisCount = isWide ? 4 : 2;
    final cardSize = isWide ? 130.0 : 110.0;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: isWide ? 620 : size.width * 0.92,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00ACC1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.local_hospital_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Welcome to CruDoc',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: AppColors.headingFontFamily,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Select your medical specialty to personalize your clinical workspace.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Specialty Grid ──
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCrossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: cardSize / (cardSize + 16),
                    ),
                    itemCount: DoctorSpecialty.all.length,
                    itemBuilder: (context, index) {
                      final spec = DoctorSpecialty.all[index];
                      final isSelected = _selectedType == spec.type;

                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedType = spec.type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? spec.accentColor.withValues(alpha: 0.10)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? spec.accentColor
                                  : const Color(0xFFE2E8F0),
                              width: isSelected ? 2.2 : 1.2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          spec.accentColor.withValues(alpha: 0.18),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? spec.accentColor
                                      : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  spec.icon,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                spec.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected
                                      ? spec.accentColor
                                      : const Color(0xFF334155),
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontFamily: AppColors.bodyFontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Footer ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        (_selectedType != null && !_isSaving)
                            ? _handleConfirm
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedType != null
                          ? DoctorSpecialty.all
                              .firstWhere((s) => s.type == _selectedType)
                              .accentColor
                          : const Color(0xFF94A3B8),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFE2E8F0),
                      disabledForegroundColor:
                          const Color(0xFF94A3B8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _selectedType != null
                                ? 'Continue as ${DoctorSpecialty.all.firstWhere((s) => s.type == _selectedType).label}'
                                : 'Select your specialty',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: AppColors.bodyFontFamily,
                            ),
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
