import 'dart:ui'; // required for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

// Vivid blue used for both container tint and active background
const Color chartBarLight = Color.fromARGB(255, 30, 120, 255);

/// Tab index of the Inventory screen — used to attach the low-stock badge
/// to the right icon.
const int _inventoryTabIndex = 2;

class BottomNavBar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
  ];

  static const _activeIcons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStockCount =
        ref.watch(lowStockMedicinesProvider).maybeWhen(
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
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            // Container background uses vivid blue with low opacity
            color: Color.fromARGB(255, 220, 250, 255),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: chartBarLight.withValues(alpha: 0.3), // vivid blue border
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_icons.length, (index) {
              final isActive = index == selectedIndex;
              final badgeCount =
                  index == _inventoryTabIndex ? inventoryBadgeCount : 0;
              return GestureDetector(
                onTap: () => onTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    // Active background = solid vivid blue
                    color: isActive ? chartBarLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isActive ? _activeIcons[index] : _icons[index],
                        size: 22,
                        // White on active, silver when inactive
                        color: isActive ? Colors.white : AppColors.silver,
                      ),
                      if (badgeCount > 0)
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
          ),
        ),
      ),
    );
  }
}
