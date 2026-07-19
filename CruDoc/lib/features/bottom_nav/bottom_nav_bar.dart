import 'dart:ui'; // required for ImageFilter
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

// Vivid blue used for both container tint and active background
const Color chartBarLight = Color.fromARGB(255, 30, 120, 255);

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
            // Container background uses vivid blue with low opacity
            color:  Color.fromARGB(255, 220, 250, 255),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: chartBarLight.withValues(alpha: 0.3), // vivid blue border
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
                    // Active background = solid vivid blue
                    color: isActive ? chartBarLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _icons[index],
                    size: 22,
                    // White on active, silver when inactive
                    color: isActive ? Colors.white : AppColors.silver,
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