import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue.dart';

/// Desktop version of the Revenue & Financials tab.
///
/// For now this just reuses the exact same mobile [RevenueScreen] and
/// centers it in a max-width column so it doesn't stretch edge-to-edge on
/// a wide window. Nothing about the mobile screen changes.
///
/// Intentionally a placeholder — replace with a real desktop layout
/// (e.g. charts side-by-side with the breakdown table) whenever you're
/// ready.
class DesktopRevenueScreen extends StatelessWidget {
  const DesktopRevenueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: RevenueScreen(),
      ),
    );
  }
}