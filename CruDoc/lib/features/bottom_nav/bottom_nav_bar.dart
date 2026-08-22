import 'dart:ui'; // required for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

// Vivid blue used for both container tint and active background
const Color chartBarLight = Color.fromARGB(255, 30, 120, 255);

/// Tab index of the Inventory screen — used to attach the low-stock badge
/// to the right icon.
const int _inventoryTabIndex = 2;

class BottomNavBar extends ConsumerWidget {
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

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
    Icons.campaign_outlined,
  ];

  static const _activeIcons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
    Icons.campaign_rounded,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStockCount = ref.watch(lowStockMedicinesProvider).maybeWhen(
          data: (data) => data.length,
          orElse: () => 0,
        );
    final expiringCount = ref.watch(expiringMedicinesProvider).maybeWhen(
          data: (data) => data.length,
          orElse: () => 0,
        );
    final inventoryBadgeCount = lowStockCount + expiringCount;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            // Container background uses vivid blue with low opacity
            color: const Color.fromARGB(255, 220, 250, 255),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: chartBarLight.withValues(alpha: 0.3), // vivid blue border
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ...List.generate(_icons.length, (index) {
                final isActive = index == selectedIndex;
                final badgeCount =
                    index == _inventoryTabIndex ? inventoryBadgeCount : 0;
                final moduleKey = DoctorFeatureGuard.getModuleKeyForTab(index);
                final isEnabled = enabledModules == null ||
                    index == 0 ||
                    index == 5 ||
                    DoctorFeatureGuard.isEnabled(enabledModules!, moduleKey);

                return GestureDetector(
                  onTap: () => onTap(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      // Active background = solid vivid blue
                      color: isActive ? chartBarLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          isActive ? _activeIcons[index] : _icons[index],
                          size: 21,
                          // White on active, silver when inactive (or slightly dimmed if locked)
                          color: isActive
                              ? Colors.white
                              : (isEnabled
                                  ? AppColors.silver
                                  : AppColors.silver.withValues(alpha: 0.5)),
                        ),
                        if (!isEnabled)
                          Positioned(
                            right: -5,
                            top: -5,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                size: 9,
                                color: Colors.black87,
                              ),
                            ),
                          )
                        else if (badgeCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                badgeCount > 9 ? '9+' : '$badgeCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // AI Chatbot button directly beside the Events button
              if (onChatbotTap != null)
                GestureDetector(
                  onTap: onChatbotTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF1E78FF).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.smart_toy_rounded,
                      size: 21,
                      color: Colors.white,
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
