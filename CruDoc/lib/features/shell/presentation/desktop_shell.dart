import 'package:flutter/material.dart';

/// The desktop layout shell – a persistent sidebar + main content area.
/// Replace the placeholder body with your actual navigation and pages.
class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 240,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                const SizedBox(height: 48),
                Text(
                  'CruDoc',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                // Add your navigation items here
                ListTile(
                  leading: const Icon(Icons.dashboard),
                  title: const Text('Dashboard'),
                  onTap: () {},
                ),
                ListTile(
                  leading: const Icon(Icons.people),
                  title: const Text('Patients'),
                  onTap: () {},
                ),
                // ... more items
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Main content
          Expanded(
            child: Navigator(
              // Use a nested Navigator if you need internal routing
              onGenerateRoute: (settings) {
                // Replace with your actual page generation
                return MaterialPageRoute(
                  builder: (_) => const Center(
                    child: Text('Desktop Content Area'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}