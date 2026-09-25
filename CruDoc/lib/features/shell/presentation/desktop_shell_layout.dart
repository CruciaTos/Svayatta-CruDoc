import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Sidebar + content on the neutral canvas. Pure layout: `DesktopShell`
/// feeds it live screens, the golden tests feed it the dashboard with
/// fake providers.
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
    return ColoredBox(
      color: context.cru.canvas,
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
