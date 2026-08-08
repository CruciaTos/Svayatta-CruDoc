import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_list_screen.dart';

/// Desktop version of the Inventory tab.
///
/// For now this just reuses the exact same mobile [InventoryListScreen] and
/// centers it in a max-width column so it doesn't stretch edge-to-edge on
/// a wide window. Nothing about the mobile screen changes.
///
/// Intentionally a placeholder — replace with a real desktop layout
/// (e.g. a sortable table) whenever you're ready.
class DesktopInventoryListScreen extends StatelessWidget {
  const DesktopInventoryListScreen({super.key, this.autoOpenAddForm = false});

  final bool autoOpenAddForm;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: InventoryListScreen(autoOpenAddForm: autoOpenAddForm),
      ),
    );
  }
}