import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

// Vivid blue brand color used for accents and active states
const Color chartBarLight = Color.fromARGB(255, 30, 120, 255);

/// Tab index of the Inventory screen — used to attach the low-stock badge
const int _inventoryTabIndex = 2;

/// Item model for the bottom navigation bar
class _NavItemData {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItemData({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class BottomNavBar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<String>? enabledModules;
  final VoidCallback? onChatbotTap;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.enabledModules,
    this.onChatbotTap,
  });

  @override
  ConsumerState<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends ConsumerState<BottomNavBar>
    with SingleTickerProviderStateMixin {
  bool _isMenuOpen = false;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotationAnimation;

  static const List<_NavItemData> _navItems = [
    _NavItemData(
      label: 'Home',
      icon: Icons.grid_view_rounded,
      activeIcon: Icons.grid_view_rounded,
    ),
    _NavItemData(
      label: 'Patients',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
    ),
    _NavItemData(
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
    ),
    _NavItemData(
      label: 'Revenue',
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments_rounded,
    ),
    _NavItemData(
      label: 'Visits',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
    ),
    _NavItemData(
      label: 'Campaigns',
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign_rounded,
    ),
    _NavItemData(
      label: 'Queue',
      icon: Icons.format_list_numbered_rounded,
      activeIcon: Icons.format_list_numbered_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 280),
    );

    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInOutCubic,
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
        _animController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = ref.watch(lowStockMedicinesProvider).maybeWhen(
          data: (data) => data.length,
          orElse: () => 0,
        );
    final expiringCount = ref.watch(expiringMedicinesProvider).maybeWhen(
          data: (data) => data.length,
          orElse: () => 0,
        );
    final inventoryBadgeCount = lowStockCount + expiringCount;

    final screenWidth = MediaQuery.of(context).size.width;

    // Geometric constants for perfect proportions
    const double collapsedSize = 56.0; // Perfect circle diameter (56x56)
    const double expandedHeight = 62.0; // Balanced vertical height for icon + label
    final double maxExpandedWidth = (screenWidth - 28.0).clamp(330.0, 480.0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final t = _expandAnimation.value.clamp(0.0, 1.0);
          final currentWidth = collapsedSize + ((maxExpandedWidth - collapsedSize) * t);
          final currentHeight = collapsedSize + ((expandedHeight - collapsedSize) * t);
          final currentRadius = currentHeight / 2.0; // Continuous tangent capsule curvature

          return Container(
            width: currentWidth,
            height: currentHeight,
            decoration: BoxDecoration(
              color: _animController.value < 0.2
                  ? chartBarLight
                  : const Color.fromARGB(255, 232, 248, 255).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(currentRadius),
              border: Border.all(
                color: _animController.value < 0.2
                    ? Colors.white.withValues(alpha: 0.45)
                    : chartBarLight.withValues(alpha: 0.32),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isMenuOpen
                      ? Colors.black.withValues(alpha: 0.08)
                      : chartBarLight.withValues(alpha: 0.35)),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                if (_isMenuOpen)
                  BoxShadow(
                    color: chartBarLight.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(currentRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: _animController.value < 0.2
                    // =========================================================
                    // 1. COLLAPSED VIEW: MATHEMATICALLY PERFECT CIRCULAR BUTTON
                    // =========================================================
                    ? InkWell(
                        onTap: _toggleMenu,
                        borderRadius: BorderRadius.circular(currentRadius),
                        child: Center(
                          child: RotationTransition(
                            turns: _rotationAnimation,
                            child: const Icon(
                              Icons.apps_rounded,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    // =========================================================
                    // 2. EXPANDED VIEW: BALANCED HORIZONTAL CAPSULE DOCK
                    // =========================================================
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Close Button (Symmetric 42x42 circle)
                            InkWell(
                              onTap: _toggleMenu,
                              borderRadius: BorderRadius.circular(21),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: chartBarLight.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: RotationTransition(
                                    turns: _rotationAnimation,
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                      color: chartBarLight,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1.2,
                              height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: AppColors.divider,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),

                            // Scrollable Row of Navigation Items
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Nav Items
                                    ...List.generate(_navItems.length, (index) {
                                      final item = _navItems[index];
                                      final isActive = index == widget.selectedIndex;
                                      final badgeCount = index == _inventoryTabIndex
                                          ? inventoryBadgeCount
                                          : 0;
                                      final moduleKey =
                                          DoctorFeatureGuard.getModuleKeyForTab(index);
                                      final isEnabled = widget.enabledModules == null ||
                                          index == 0 ||
                                          index == 5 ||
                                          DoctorFeatureGuard.isEnabled(
                                              widget.enabledModules!, moduleKey);

                                      // Stagger delay per item
                                      final staggerInterval = Interval(
                                        (index * 0.08).clamp(0.0, 0.6),
                                        ((index * 0.08) + 0.4).clamp(0.0, 1.0),
                                        curve: Curves.easeOutBack,
                                      );
                                      final itemAnim = staggerInterval.transform(
                                        _animController.value.clamp(0.0, 1.0),
                                      );

                                      return Transform.scale(
                                        scale: 0.75 + (0.25 * itemAnim),
                                        child: Opacity(
                                          opacity: itemAnim.clamp(0.0, 1.0),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            child: InkWell(
                                              onTap: () {
                                                widget.onTap(index);
                                                _closeMenu();
                                              },
                                              borderRadius: BorderRadius.circular(15),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                height: 48,
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 11,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isActive
                                                      ? chartBarLight
                                                      : Colors.white,
                                                  borderRadius: BorderRadius.circular(15),
                                                  border: Border.all(
                                                    color: isActive
                                                        ? chartBarLight
                                                        : AppColors.divider,
                                                    width: 1,
                                                  ),
                                                  boxShadow: isActive
                                                      ? [
                                                          BoxShadow(
                                                            color: chartBarLight.withValues(alpha: 0.32),
                                                            blurRadius: 6,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ]
                                                      : [
                                                          BoxShadow(
                                                            color: Colors.black.withValues(alpha: 0.02),
                                                            blurRadius: 4,
                                                            offset: const Offset(0, 1),
                                                          ),
                                                        ],
                                                ),
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Stack(
                                                      clipBehavior: Clip.none,
                                                      children: [
                                                        Icon(
                                                          isActive
                                                              ? item.activeIcon
                                                              : item.icon,
                                                          size: 20,
                                                          color: isActive
                                                              ? Colors.white
                                                              : (isEnabled
                                                                  ? AppColors.slateBlue
                                                                  : AppColors.slateBlue.withValues(alpha: 0.4)),
                                                        ),
                                                        if (!isEnabled)
                                                          Positioned(
                                                            right: -4,
                                                            top: -4,
                                                            child: Container(
                                                              padding: const EdgeInsets.all(1.5),
                                                              decoration: const BoxDecoration(
                                                                color: Colors.amber,
                                                                shape: BoxShape.circle,
                                                              ),
                                                              child: const Icon(
                                                                Icons.lock_rounded,
                                                                size: 7.5,
                                                                color: Colors.black87,
                                                              ),
                                                            ),
                                                          )
                                                        else if (badgeCount > 0)
                                                          Positioned(
                                                            right: -5,
                                                            top: -5,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 4,
                                                                vertical: 1.5,
                                                              ),
                                                              constraints: const BoxConstraints(
                                                                minWidth: 14,
                                                                minHeight: 14,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFEF4444),
                                                                borderRadius: BorderRadius.circular(7),
                                                              ),
                                                              child: Text(
                                                                badgeCount > 9
                                                                    ? '9+'
                                                                    : '$badgeCount',
                                                                textAlign: TextAlign.center,
                                                                style: const TextStyle(
                                                                  fontFamily: AppColors.bodyFontFamily,
                                                                  color: Colors.white,
                                                                  fontSize: 7.5,
                                                                  fontWeight: FontWeight.w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      item.label,
                                                      style: TextStyle(
                                                        fontFamily: AppColors.bodyFontFamily,
                                                        fontSize: 10,
                                                        fontWeight: isActive
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: isActive
                                                            ? Colors.white
                                                            : AppColors.charcoalGray,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),

                                    // AI Assistant Button (Aligned with other items)
                                    if (widget.onChatbotTap != null) ...[
                                      Container(
                                        width: 1.2,
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.divider,
                                          borderRadius: BorderRadius.circular(1),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 3),
                                        child: InkWell(
                                          onTap: () {
                                            _closeMenu();
                                            widget.onChatbotTap!();
                                          },
                                          borderRadius: BorderRadius.circular(15),
                                          child: Container(
                                            height: 48,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF1E78FF)
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.smart_toy_rounded,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'AI Bot',
                                                  style: TextStyle(
                                                    fontFamily: AppColors.bodyFontFamily,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                  ],
                                ),
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
    );
  }
}
