import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/dashboard/widgets/todays_visits_card.dart';
import 'package:doctor_management_app/features/dashboard/widgets/quick_actions_row.dart';
import 'package:doctor_management_app/features/dashboard/widgets/recent_activity_card.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart'; // adjust import path

class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(),            // now tappable avatar
              const SizedBox(height: 24),
              const _RevenueSnapshotCard(),
              const SizedBox(height: 16),
              const _StatsGrid(),
              const SizedBox(height: 20),
              const QuickActionsRow(),
              const SizedBox(height: 20),
              const TodaysVisitsCard(),
              const SizedBox(height: 16),
              const RecentActivityCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- TOP BAR ----------
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // TAPPABLE PROFILE AVATAR
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.slateBlue, width: 1.5),
            ),
            child: ClipOval(
              child: Container(
                color: AppColors.cardSurfaceAlt,
                child: const Icon(Icons.person, color: AppColors.silver, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dr. Rutuja Nilgunkar',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Physiotherapist',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.notifications_none, color: AppColors.silver, size: 24),
      ],
    );
  }
}

// ---------- REVENUE SNAPSHOT CARD ----------
class _RevenueSnapshotCard extends StatelessWidget {
  const _RevenueSnapshotCard();

  static const Map<String, double> _months = {
    'Feb': 0.35, 'Mar': 0.55, 'Apr': 0.42,
    'May': 0.9,  'Jun': 0.62, 'Jul': 0.48,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Revenue',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: AppColors.silver, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('₹42,300',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w700, height: 1.0)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('This month, so far',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _months.entries.map((entry) {
                final isPeak = entry.value == 0.9;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 96 * entry.value,
                          decoration: BoxDecoration(
                            color: isPeak ? AppColors.chartBarLight : AppColors.chartBarDim,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(entry.key, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- STATS GRID ----------
class _StatsGrid extends StatelessWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          child: Column(
            children: [
              _StatCard(label: 'Active Patients', value: '38', delta: '+3 this month', deltaPositive: true),
              SizedBox(height: 14),
              _StatCard(label: 'Pending Invoices', value: '5', delta: '₹8,200 due', deltaPositive: false),
            ],
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              _StatCard(label: "This Week's Visits", value: '17', delta: '3 today', deltaPositive: true),
              SizedBox(height: 14),
              _StatCard(label: 'Packages Ending', value: '2', delta: 'renew soon', deltaPositive: false),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final bool deltaPositive;

  const _StatCard({required this.label, required this.value, required this.delta, required this.deltaPositive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  delta,
                  style: TextStyle(
                    color: deltaPositive ? AppColors.positiveGreen : Colors.redAccent.withOpacity(0.8),
                    fontSize: 11.5, fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}