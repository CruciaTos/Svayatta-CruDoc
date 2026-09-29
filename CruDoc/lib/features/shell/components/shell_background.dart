import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/features/shell/components/animated_background.dart';

/// The shell's page background.
///
/// Keep it centralized here so every page that sits under the shell uses the
/// same neutral canvas color instead of a one-off gradient or custom fill.
class ShellBackground extends StatelessWidget {
  final Widget child;
  const ShellBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<CruColors>() ?? CruColors.day;

    return Container(
      decoration: BoxDecoration(color: c.canvas),
      child: AnimatedBackground(child: child),
    );
  }
}
