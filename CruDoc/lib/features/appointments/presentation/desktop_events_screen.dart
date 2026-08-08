import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/appointments/presentation/visitation_screen.dart';

/// Desktop version of the Appointments & Events tab.
///
/// For now this just reuses the exact same mobile [EventsScreen] and
/// centers it in a max-width column so it doesn't stretch edge-to-edge on
/// a wide window. Nothing about the mobile screen changes.
///
/// Intentionally a placeholder — replace with a real desktop layout
/// (e.g. a calendar grid) whenever you're ready.
class DesktopEventsScreen extends StatelessWidget {
  const DesktopEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: EventsScreen(),
      ),
    );
  }
}