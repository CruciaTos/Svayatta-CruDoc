import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.midnightBlue,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _TopBar(),
                SizedBox(height: 24),
                _IncomeCard(),
                SizedBox(height: 16),
                _StatsGrid(),
                SizedBox(height: 16),
                _GoPremiumCard(),
              ],
            ),
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
        Container(
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
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saira Goodman',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Property agent',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.cardSurfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
          child: const Icon(Icons.notifications_none_rounded,
              color: AppColors.silver, size: 22),
        ),
      ],
    );
  }
}

// ---------- INCOME CARD ----------
class _IncomeCard extends StatelessWidget {
  const _IncomeCard();

  static const Map<String, double> _months = {
    'Jan': 0.35,
    'Feb': 0.55,
    'Mar': 0.42,
    'Apr': 0.9,
    'May': 0.62,
    'Jun': 0.48,
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
              const Text(
                'Income',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.silver, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '\$1,209',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Average income 6 months',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
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
                            color: isPeak
                                ? AppColors.chartBarLight
                                : AppColors.chartBarDim,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
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
              _StatCard(
                label: 'Occupancy',
                value: '92%',
                delta: '+3% d/d',
                deltaPositive: true,
              ),
              SizedBox(height: 14),
              _StatCard(
                label: 'Overdue Pay',
                value: '12',
                delta: '+2 d/d',
                deltaPositive: false,
              ),
            ],
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              _StatCard(
                label: 'New request',
                value: '13',
                delta: '+6 d/d',
                deltaPositive: true,
              ),
              SizedBox(height: 14),
              _StatCard(
                label: 'Inspections',
                value: '9',
                delta: '+1 d/d',
                deltaPositive: true,
              ),
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaPositive,
  });

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
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  delta,
                  style: TextStyle(
                    color: deltaPositive
                        ? AppColors.positiveGreen
                        : Colors.redAccent.withOpacity(0.8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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

// ---------- GO PREMIUM CARD ----------
class _GoPremiumCard extends StatelessWidget {
  const _GoPremiumCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.slateBlue, AppColors.cardSurfaceAlt],
        ),
        border: Border.all(color: AppColors.divider),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 90,
              color: AppColors.beige.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Go Premium',
                style: TextStyle(
                  color: AppColors.beige,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Power up your workflow\nwith exclusive features.',
                style: TextStyle(
                  color: AppColors.beige.withOpacity(0.85),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}