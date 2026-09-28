import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Sidebar + content on the neutral canvas. Pure layout: `DesktopShell`
/// feeds it live screens, the golden tests feed it the dashboard with
/// fake providers.
/// Ambient glowing gradient background inspired by modern dashboard design,
/// featuring a soft medical-blue wash across the right side and bottom.
class CruAmbientBackground extends StatelessWidget {
  const CruAmbientBackground({
    super.key,
    required this.child,
    this.isEvening = false,
  });

  final Widget child;
  final bool isEvening;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (isEvening) {
      return ColoredBox(
        color: c.canvas,
        child: child,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF4F7FE),
        gradient: LinearGradient(
          begin: Alignment(-1.0, -1.0),
          end: Alignment(1.0, 1.0),
          stops: [0.0, 0.50, 1.0],
          colors: [
            Color(0xFFF4F7FE), // Top-left base color
            Color(0xFFEAF4FD), // Smooth transition in the middle (50%)
            Color(0xFFDFEFFD), // Light airy sky blue at bottom-right
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Upper-right airy sky blue ambient glow with natural spread
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.15),
                    radius: 1.65,
                    colors: [
                      const Color(0xFFD0EBFE).withValues(alpha: 0.22),
                      const Color(0xFFE3F3FE).withValues(alpha: 0.12),
                      const Color(0xFFF1F9FF).withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 0.78, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Gentle lower-right ambient glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.65, 1.05),
                    radius: 1.45,
                    colors: [
                      const Color(0xFFD8EEFE).withValues(alpha: 0.14),
                      const Color(0xFFEDF7FE).withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.50, 1.0],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class DesktopShellLayout extends StatelessWidget {
  const DesktopShellLayout({
    super.key,
    required this.sidebar,
    required this.content,
    this.overlay,
  });

  final Widget sidebar;
  final Widget content;

  /// Floating layer above everything (e.g. the chat button on screens
  /// that don't have the dashboard's search).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruAmbientBackground(
      isEvening: c.isEvening,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sidebar,
              Expanded(child: content),
            ],
          ),
          ?overlay,
        ],
      ),
    );
  }
}
