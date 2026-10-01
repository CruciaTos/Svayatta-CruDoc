import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/mobile/mobile_shell.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell.dart';

/// Width (logical pixels) above which [DesktopShell] is shown instead of
/// the phone [MobileShell]. Tweak this single number to change where the
/// layout switches over.
const double kDesktopBreakpoint = 900;

/// Picks between the phone [MobileShell] and [DesktopShell] based on the
/// available width.
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return const DesktopShell();
        }
        return const MobileShell();
      },
    );
  }
}
