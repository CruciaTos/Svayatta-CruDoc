import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_records.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue.dart';
import 'package:doctor_management_app/features/bottom_nav/bottom_nav_bar.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_list_screen.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/appointments/presentation/visitation_screen.dart';
import 'package:doctor_management_app/features/chatbot/presentation/chatbot_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  late final List<Widget> _screens;

  // Height of the nav bar (including margins/padding) – we'll use this to pad the content
  static const double navBarHeight = 78.0; // adjust to match your bar

  static const List<IconData> _screenIcons = [
    Icons.grid_view_rounded,
    Icons.groups_rounded,
    Icons.inventory_2_outlined,
    Icons.payments_outlined,
    Icons.calendar_today_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeDashboardScreen(onNavigateToTab: _onNavTap),
      const PatientRecords(),
      const InventoryListScreen(),
      const RevenueScreen(),
      const EventsScreen(),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index < 0 || index >= _screens.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: DoctorFeatureGuard.watchEnabledModules(),
      builder: (context, snapshot) {
        final enabledModules = snapshot.data ?? DoctorFeatureGuard.defaultModules;

        return InventoryAlertListener(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // ---- Background gradient + animated lines + PageView ----
                ShellBackground(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentIndex = index),
                    itemCount: _screens.length,
                    itemBuilder: (context, index) {
                      final moduleKey = DoctorFeatureGuard.getModuleKeyForTab(index);
                      final isTabEnabled = index == 0 || DoctorFeatureGuard.isEnabled(enabledModules, moduleKey);

                      Widget content;
                      if (!isTabEnabled) {
                        content = MobileFeatureDisabledView(
                          featureTitle: DoctorFeatureGuard.getTabTitle(index),
                          icon: _screenIcons[index],
                          onBackToDashboard: () => _onNavTap(0),
                        );
                      } else {
                        content = _screens[index];
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: kIsWeb ? 0 : navBarHeight,
                        ),
                        child: content,
                      );
                    },
                  ),
                ),
                // ---- Floating navigation bar (Mobile Only) ----
                if (!kIsWeb)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 12,
                    child: BottomNavBar(
                      selectedIndex: _currentIndex,
                      onTap: _onNavTap,
                      enabledModules: enabledModules,
                    ),
                  ),
                // ---- Floating Chat FAB (Mobile Only) ----
                if (!kIsWeb)
                  Positioned(
                    right: 16,
                    bottom: 90, // above the nav bar
                    child: GestureDetector(
                      onTap: () => ChatbotScreen.show(context),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E78FF).withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.smart_toy_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

