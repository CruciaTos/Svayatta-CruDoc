import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard.dart';

/// Desktop version of the Dashboard tab.
///
/// For now this just reuses the exact same mobile [HomeDashboardScreen]
/// and centers it in a max-width column so it doesn't stretch edge-to-edge
/// on a wide window. Nothing about the mobile screen changes.
///
/// Intentionally a placeholder — swap the body for a real desktop layout
/// (multi-column stats, side-by-side cards, etc.) whenever you're ready.
class DesktopDashboardScreen extends StatelessWidget {
  const DesktopDashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: HomeDashboardScreen(onNavigateToTab: onNavigateToTab),
      ),
    );
  }
}