import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/shell/components/animated_background.dart';

/// The gradient + animated grid-line background used by [Shell].
///
/// Extracted into its own widget so any other screen that needs to visually
/// match the Shell (e.g. a detail page pushed on top of it) can wrap its
/// content in this instead of copy-pasting the gradient/AnimatedBackground
/// pair. Change the look here and every screen using it updates together —
/// nothing to keep in sync by hand.
class ShellBackground extends StatelessWidget {
  final Widget child;
  const ShellBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromARGB(255, 186, 226, 255),
            Color.fromARGB(255, 184, 221, 255),
          ],
        ),
      ),
      child: AnimatedBackground(child: child),
    );
  }
}