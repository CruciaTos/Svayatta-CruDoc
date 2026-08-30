import 'package:shared_preferences/shared_preferences.dart';

/// Thin `shared_preferences` wrapper for desktop-only layout state.
/// Keeps the sidebar's expanded/collapsed choice across app restarts so
/// desktop users don't have to re-collapse it every session.
class DesktopShellPreferences {
  DesktopShellPreferences();

  static const String _kSidebarExpandedKey = 'crudoc.desktop_shell.sidebar_expanded';

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
}
