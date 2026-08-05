import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/ui_provider.dart';
import 'dashboard/dashboard_screen.dart';
import 'dashboard/doctors_screen.dart';
import 'dashboard/audit_logs_screen.dart';
import 'dashboard/support_screen.dart';
import 'dashboard/features_screen.dart';

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
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: Icon(
                        _tabIcon(tab),
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                      title: Text(
                        tab.label,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : null,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onTap: () {
                        ref.read(superAdminUIProvider.notifier).selectTab(tab);
                        if (isMobile) {
                          ref
                              .read(superAdminUIProvider.notifier)
                              .toggleSidebar();
                        }
                      },
                    ),
                  ),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.currentAdmin?.name ?? 'Admin',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
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
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
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
            Icon(
              Icons.admin_panel_settings,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              'CruDoc Admin',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
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
        return const SuperAdminDoctorsScreen();
      case SuperAdminTab.subscriptions:
        return const _ComingSoonTab(
          icon: Icons.subscriptions_outlined,
          title: 'Subscription Management',
          description:
              'Manage doctor subscription plans, upgrades, downgrades, and trial extensions.',
        );
      case SuperAdminTab.features:
        return const SuperAdminFeaturesScreen();
      case SuperAdminTab.analytics:
        return const _ComingSoonTab(
          icon: Icons.analytics_outlined,
          title: 'Analytics',
          description: 'View platform-wide analytics, charts, and export data.',
        );
      case SuperAdminTab.support:
        return const SuperAdminSupportScreen();
      case SuperAdminTab.auditLogs:
        return const SuperAdminAuditLogsScreen();
      case SuperAdminTab.settings:
        return const _ComingSoonTab(
          icon: Icons.settings_outlined,
          title: 'Settings',
          description:
              'Configure platform settings, profile, 2FA, and system configuration.',
        );
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

/// "Coming Soon" placeholder tab for screens not yet built.
class _ComingSoonTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ComingSoonTab({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction, size: 18, color: Colors.amber[800]),
                  const SizedBox(width: 8),
                  Text(
                    'Coming Soon',
                    style: TextStyle(
                      color: Colors.amber[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
