import 'package:flutter/material.dart';

/// Flat shell background placeholder kept only to preserve the existing API.
/// The shell no longer uses an animated gradient or grid decoration.
class AnimatedBackground extends StatelessWidget {
  final Widget child;
  const AnimatedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
