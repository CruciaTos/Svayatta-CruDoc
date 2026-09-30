import 'package:flutter/material.dart';

import 'package:crudoc_shared/widgets/cru/cru.dart';

/// Sidebar + content on the neutral canvas. Pure layout: `DesktopShell`
/// feeds it live screens, the golden tests feed it the dashboard with
/// fake providers.
/// The desktop shell background is intentionally flat and uniform.
class CruAmbientBackground extends StatelessWidget {
  const CruAmbientBackground({
    super.key,
    required this.child,
    this.isEvening = false,
    this.dayBackgroundColor = const Color(0xFFEEF1F6),
  });

  final Widget child;
  final bool isEvening;
  final Color dayBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final color = isEvening ? context.cru.canvas : dayBackgroundColor;
    return ColoredBox(color: color, child: child);
  }
}

class DesktopShellLayout extends StatelessWidget {
  const DesktopShellLayout({
    super.key,
    required this.sidebar,
    required this.content,
    this.overlay,
    this.dayBackgroundColor = const Color(0xFFEEF1F6),
  });

  final Widget sidebar;
  final Widget content;
  final Color dayBackgroundColor;

  /// Floating layer above everything (e.g. the chat button on screens
  /// that don't have the dashboard's search).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruAmbientBackground(
      isEvening: c.isEvening,
      dayBackgroundColor: dayBackgroundColor,
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
