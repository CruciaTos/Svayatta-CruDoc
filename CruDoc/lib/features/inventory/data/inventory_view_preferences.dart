import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';

/// `shared_preferences` storage for the Inventory list/grid choice
/// (device-local, like the other desktop preferences).
class InventoryViewPreferences {
  static const String _key = 'crudoc.inventory.viewMode';

  Future<InventoryViewMode> getViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    return InventoryViewMode.fromName(prefs.getString(_key));
  }

  Future<void> setViewMode(InventoryViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
