import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/ui_provider.dart';
import 'dashboard/dashboard_screen.dart';

/// Main Super Admin shell with sidebar navigation and content area.
class SuperAdminShell extends ConsumerStatefulWidget {
  const SuperAdminShell({super.key});

  @override
  ConsumerState<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends ConsumerState<SuperAdminShell> {
  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(superAdminUIProvider);
    final authState = ref.watch(superAdminAuthProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          if (uiState.isSidebarOpen)
            _buildSidebar(context, uiState, authState, isMobile),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, uiState, authState, isMobile),
                // Content
                Expanded(child: _buildContent(uiState.selectedTab)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    SuperAdminUIState uiState,
    SuperAdminAuthState authState,
    bool isMobile,
  ) {
    return Container(
      width: isMobile ? 240 : 260,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Logo section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  color: Theme.of(context).primaryColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'CruDoc Admin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        ref.read(superAdminUIProvider.notifier).toggleSidebar(),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: SuperAdminTab.values.map((tab) {
                final isSelected = uiState.selectedTab == tab;
                return ListTile(
                  leading: Icon(_tabIcon(tab)),
                  title: Text(tab.label),
                  selected: isSelected,
                  selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () {
                    ref.read(superAdminUIProvider.notifier).selectTab(tab);
                    if (isMobile) {
                      ref.read(superAdminUIProvider.notifier).toggleSidebar();
                    }
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // Admin profile section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    (authState.currentAdmin?.name.isNotEmpty == true
                            ? authState.currentAdmin!.name[0]
                            : 'A')
                        .toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.currentAdmin?.name ?? 'Admin',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        authState.currentAdmin?.email ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed: () => _showLogoutDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    SuperAdminUIState uiState,
    SuperAdminAuthState authState,
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          if (!uiState.isSidebarOpen || isMobile)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () =>
                  ref.read(superAdminUIProvider.notifier).toggleSidebar(),
            ),
          if (!uiState.isSidebarOpen) ...[
            const SizedBox(width: 8),
            Icon(Icons.admin_panel_settings,
                color: Theme.of(context).primaryColor, size: 28),
            const SizedBox(width: 8),
            Text('CruDoc Admin',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold)),
          ],
          const Spacer(),
          Icon(Icons.notifications_outlined, color: Colors.grey[600]),
          const SizedBox(width: 16),
          Icon(Icons.search, color: Colors.grey[600]),
        ],
      ),
    );
  }

  Widget _buildContent(SuperAdminTab tab) {
    switch (tab) {
      case SuperAdminTab.dashboard:
        return const SuperAdminDashboardScreen();
      case SuperAdminTab.doctors:
        return const Center(child: Text('Doctors Management'));
      case SuperAdminTab.subscriptions:
        return const Center(child: Text('Subscriptions'));
      case SuperAdminTab.features:
        return const Center(child: Text('Features'));
      case SuperAdminTab.analytics:
        return const Center(child: Text('Analytics'));
      case SuperAdminTab.support:
        return const Center(child: Text('Support Tickets'));
      case SuperAdminTab.auditLogs:
        return const Center(child: Text('Audit Logs'));
      case SuperAdminTab.settings:
        return const Center(child: Text('Settings'));
    }
  }

  IconData _tabIcon(SuperAdminTab tab) {
    switch (tab) {
      case SuperAdminTab.dashboard:
        return Icons.dashboard_outlined;
      case SuperAdminTab.doctors:
        return Icons.people_outline;
      case SuperAdminTab.subscriptions:
        return Icons.subscriptions_outlined;
      case SuperAdminTab.features:
        return Icons.toggle_on_outlined;
      case SuperAdminTab.analytics:
        return Icons.analytics_outlined;
      case SuperAdminTab.support:
        return Icons.support_agent_outlined;
      case SuperAdminTab.auditLogs:
        return Icons.history_outlined;
      case SuperAdminTab.settings:
        return Icons.settings_outlined;
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(superAdminAuthProvider.notifier).logout();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}