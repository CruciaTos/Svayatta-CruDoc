import 'dart:ui';   // for ImageFilter
import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_records.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue.dart';
import 'package:doctor_management_app/features/summary/presentation/summary.dart';
import 'package:doctor_management_app/features/bottom_nav/bottom_nav_bar.dart';
import 'package:doctor_management_app/features/invoice/presentation/invoice_create_screen.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointments.dart';


class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  final List<Widget> _screens = const [
    HomeDashboardScreen(),
    PatientRecords(),
    InvoiceCreateScreen(),
    RevenueScreen(),
    EventsScreen(),
      // Placeholder for the fifth screen
  ];

  // Height of the nav bar (including margins/padding) – we'll use this to pad the content
  static const double navBarHeight = 78.0;   // adjust to match your bar

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ---- Background gradient + animated lines + PageView ----
          ShellBackground(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              children: _screens
                  .map((screen) => Padding(
                        padding: EdgeInsets.only(
                            bottom: navBarHeight),   // make room for the overlay
                        child: screen,
                      ))
                  .toList(),
            ),
          ),
          // ---- Floating navigation bar ----
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: BottomNavBar(
              selectedIndex: _currentIndex,
              onTap: _onNavTap,
            ),
          ),
        ],
      ),
    );
  }
}