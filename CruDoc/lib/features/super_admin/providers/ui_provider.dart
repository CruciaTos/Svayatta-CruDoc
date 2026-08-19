import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Available tabs in the Super Admin sidebar.
enum SuperAdminTab {
  dashboard,
  doctors,
  features,
  analytics,
  apiKeys,
  support,
  auditLogs,
  settings;

  String get label {
    switch (this) {
      case SuperAdminTab.dashboard:
        return 'Dashboard';
      case SuperAdminTab.doctors:
        return 'Doctors';
      case SuperAdminTab.features:
        return 'Features';
      case SuperAdminTab.analytics:
        return 'Analytics';
      case SuperAdminTab.apiKeys:
        return 'API Keys & Usage';
      case SuperAdminTab.support:
        return 'Support';
      case SuperAdminTab.auditLogs:
        return 'Audit Logs';
      case SuperAdminTab.settings:
        return 'Settings';
    }
  }
}

/// UI state for the Super Admin panel.
class SuperAdminUIState {
  final SuperAdminTab selectedTab;
  final bool isSidebarOpen;
  final bool isMobileView;

  const SuperAdminUIState({
    this.selectedTab = SuperAdminTab.dashboard,
    this.isSidebarOpen = true,
    this.isMobileView = false,
  });

  SuperAdminUIState copyWith({
    SuperAdminTab? selectedTab,
    bool? isSidebarOpen,
    bool? isMobileView,
  }) {
    return SuperAdminUIState(
      selectedTab: selectedTab ?? this.selectedTab,
      isSidebarOpen: isSidebarOpen ?? this.isSidebarOpen,
      isMobileView: isMobileView ?? this.isMobileView,
    );
  }
}

/// Provider for Super Admin UI state.
class SuperAdminUINotifier extends Notifier<SuperAdminUIState> {
  @override
  SuperAdminUIState build() {
    return const SuperAdminUIState();
  }

  void selectTab(SuperAdminTab tab) {
    state = state.copyWith(selectedTab: tab);
  }

  void toggleSidebar() {
    state = state.copyWith(isSidebarOpen: !state.isSidebarOpen);
  }

  void setMobileView(bool isMobile) {
    state = state.copyWith(isMobileView: isMobile, isSidebarOpen: !isMobile);
  }
}

final superAdminUIProvider =
    NotifierProvider<SuperAdminUINotifier, SuperAdminUIState>(
  SuperAdminUINotifier.new,
);