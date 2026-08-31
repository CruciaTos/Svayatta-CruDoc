import 'package:shared_preferences/shared_preferences.dart';

/// Thin `shared_preferences` wrapper for desktop-only layout state.
/// Keeps the sidebar's expanded/collapsed choice across app restarts so
/// desktop users don't have to re-collapse it every session.
class DesktopShellPreferences {
  DesktopShellPreferences();

  static const String _kSidebarExpandedKey = 'crudoc.desktop_shell.sidebar_expanded';
  static const String _kLastTabIndexKey = 'crudoc.desktop_shell.last_tab_index';

  /// Whether the sidebar should render expanded. Defaults to `true`
  /// (matches the shell's original hardcoded default) when nothing has
  /// been saved yet.
  Future<bool> getSidebarExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSidebarExpandedKey) ?? true;
  }

  Future<void> setSidebarExpanded(bool isExpanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSidebarExpandedKey, isExpanded);
  }

  /// Last tab the desktop user had open, so relaunching the app (or coming
  /// back from another tab of a multi-window setup) restores where they
  /// left off instead of always dropping back to the dashboard. Defaults
  /// to `0` (Dashboard) when nothing has been saved yet.
  Future<int> getLastTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLastTabIndexKey) ?? 0;
  }

  Future<void> setLastTabIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastTabIndexKey, index);
  }
}
