import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard.dart';
import 'package:doctor_management_app/features/patient_records/presentation/patient_records.dart';
import 'package:doctor_management_app/features/work/presentation/events.dart';
import 'package:doctor_management_app/features/revenue/presentation/revenue.dart';
import 'package:doctor_management_app/features/summary/presentation/summary.dart';
import 'package:doctor_management_app/features/bottom_nav/bottom_nav_bar.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeDashboardScreen(),       // 0 – grid
    PatientRecords(),            // 1 – check
    EventsScreen(),              // 2 – description
    RevenueScreen(),             // 3 – calendar
    SummaryScreen(),             // 4 – person (new)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}