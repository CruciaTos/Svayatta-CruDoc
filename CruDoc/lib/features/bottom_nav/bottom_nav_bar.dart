import 'dart:ui'; // required for ImageFilter
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _icons = [
    Icons.grid_view_rounded,
    Icons.check_circle_outline_rounded,
    Icons.description_outlined,
    Icons.calendar_today_outlined,
    Icons.person_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.charcoalGray.withOpacity(0.75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.divider.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_icons.length, (index) {
              final isActive = index == selectedIndex;
              return GestureDetector(
                onTap: () => onTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.beige : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _icons[index],
                    size: 22,
                    color:
                        isActive ? AppColors.midnightBlue : AppColors.silver,
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