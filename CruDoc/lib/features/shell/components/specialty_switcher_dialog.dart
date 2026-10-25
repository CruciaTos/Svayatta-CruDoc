import 'package:flutter/material.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';

/// Opens a rich modal dialog to switch between clinical specialties.
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
        child: FadeTransition(opacity: curved, child: child),
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
            color: context.cru.surface,
            borderRadius: BorderRadius.circular(CruRadius.card),
            boxShadow: const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.cru.track, width: 1.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: CruSize.iconTile,
                      height: CruSize.iconTile,
                      decoration: BoxDecoration(
                        color: context.cru.inset,
                        borderRadius: BorderRadius.circular(CruRadius.iconTile),
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: context.cru.label2,
                        size: CruSpace.s20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Switch Clinical Specialty',
                                style: CruType.headline.w700.tint(
                                  context.cru.label,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'DEV / TRIAL MODE',
                                  style: CruType.micro.w700
                                      .tint(context.cru.greenText)
                                      .copyWith(letterSpacing: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Switch specialty features dynamically without logging out.',
                            style: CruType.caption.tint(context.cru.label2),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.cru.label2,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),

              // ── Active Indicator Banner ──
              Container(
                margin: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.cru.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
                child: Row(
                  children: [
                    Icon(activeSpec.icon, size: 18, color: context.cru.label2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Currently Active: ',
                          style: CruType.caption.w500.tint(context.cru.label2),
                          children: [
                            TextSpan(
                              text: activeSpec.label,
                              style: CruType.caption.w600.tint(
                                context.cru.label,
                              ),
                            ),
                            TextSpan(
                              text: ' • ${activeSpec.tagline}',
                              style: CruType.micro.tint(context.cru.label2),
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
                      final isCurrent = activeSpec.type == spec.type;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: context.cru.inset,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  border: Border(
                    top: BorderSide(color: context.cru.track, width: 1.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: context.cru.label3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Switches custom toolsets, tooth charts, case sheets, and specialty workflows instantly.',
                        style: CruType.micro.tint(context.cru.label2),
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
      cursor: isActive ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive
                ? context.cru.accentWash
                : (_isHovered ? context.cru.hoverFill : context.cru.surface),
            borderRadius: BorderRadius.circular(CruRadius.card),
            border: Border.all(
              color: isActive ? context.cru.inkBorder : context.cru.cardBorder,
            ),
            boxShadow: const [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.cru.inset,
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
                child: Icon(spec.icon, color: context.cru.label2, size: 22),
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
                            style: CruType.callout.w600.tint(context.cru.label),
                          ),
                        ),
                        if (widget.isLoading)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.cru.accent,
                            ),
                          )
                        else if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.cru.accentTint,
                              borderRadius: BorderRadius.circular(
                                CruRadius.full,
                              ),
                            ),
                            child: Text(
                              'Active',
                              style: CruType.micro.w600.tint(
                                context.cru.accentText,
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
                      style: CruType.micro.tint(context.cru.label2),
                    ),
                    const SizedBox(height: 8),
                    // Quick Action tags preview
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: spec.quickActions.take(3).map((act) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.cru.track,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            act,
                            style: CruType.micro.w600.tint(context.cru.label2),
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
