import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/dashboard/widgets/todays_visits_card.dart';
import 'package:doctor_management_app/features/dashboard/widgets/quick_actions_row.dart';
import 'package:doctor_management_app/features/dashboard/widgets/recent_activity_card.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';

// ---------- Data Models ----------
class BarData {
  final String label;
  final double heightFactor; // 0.0 to 1.0
  final int? revenueAmount;  // optional for tooltip / amount display

  const BarData({
    required this.label,
    required this.heightFactor,
    this.revenueAmount,
  });
}

class StatItem {
  final String label;
  final String value;
  final String delta;
  final bool deltaPositive;

  const StatItem({
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaPositive,
  });
}

// ---------- Home Dashboard Screen (Stateful for local UI state) ----------
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  // ---- Doctor info (replace with real data from provider/bloc) ----
  final String _doctorName = '';        // TODO: fetch from user session
  final String _specialty = '';        // TODO: fetch from user session

  // ---- Revenue card state (lifted up) ----
  bool _isMonthly = true;
  int _selectedBarIndex = 0;     // will be updated when data is available

  // Replace these empty lists with data fetched from your repository
  final List<BarData> _weeklyBars = [];
  final List<BarData> _monthlyBars = [];

  // Derived values
  String get _currentAmount {
    final bars = _isMonthly ? _monthlyBars : _weeklyBars;
    if (bars.isEmpty || _selectedBarIndex >= bars.length) return '₹0';
    final bar = bars[_selectedBarIndex];
    return bar.revenueAmount != null ? '₹${bar.revenueAmount}' : '₹0';
  }

  String get _currentSubtitle {
    final bars = _isMonthly ? _monthlyBars : _weeklyBars;
    if (bars.isEmpty || _selectedBarIndex >= bars.length) return '';
    return bars[_selectedBarIndex].label;
  }

  List<BarData> get _currentBars => _isMonthly ? _monthlyBars : _weeklyBars;

  @override
  Widget build(BuildContext context) {
    // ---- Stats (replace with real data) ----
    final List<StatItem> stats = [
      // TODO: populate with actual values
      // const StatItem(label: 'Active Patients', value: '38', delta: '+3 this month', deltaPositive: true),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(
                doctorName: _doctorName,
                specialty: _specialty,
                onProfileTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
              const SizedBox(height: 24),
              _RevenueSnapshotCard(
                isMonthly: _isMonthly,
                bars: _currentBars,
                selectedBarIndex: _selectedBarIndex,
                amount: _currentAmount,
                subtitle: _currentSubtitle,
                onToggle: (monthly) {
                  setState(() {
                    _isMonthly = monthly;
                    _selectedBarIndex = 0; // reset selection on toggle
                  });
                },
                onBarSelected: (index) {
                  setState(() {
                    _selectedBarIndex = index;
                  });
                },
              ),
              const SizedBox(height: 16),
              _StatsGrid(stats: stats),
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

// ---------- TOP BAR (parameterised) ----------
class _TopBar extends StatelessWidget {
  final String doctorName;
  final String specialty;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationTap;

  const _TopBar({
    required this.doctorName,
    required this.specialty,
    this.onProfileTap,
  }) : onNotificationTap = null;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF3A85FF), Color(0xFF6BC9FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.person, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good afternoon',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                doctorName.isNotEmpty ? doctorName : 'Dr. ---',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                specialty.isNotEmpty ? specialty : 'Your dashboard overview',
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onNotificationTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(Icons.notifications_none,
                color: AppColors.slateBlue, size: 22),
          ),
        ),
      ],
    );
  }
}

// ---------- REVENUE SNAPSHOT CARD (no internal dummy data) ----------
class _RevenueSnapshotCard extends StatelessWidget {
  final bool isMonthly;
  final List<BarData> bars;
  final int selectedBarIndex;
  final String amount;
  final String subtitle;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onBarSelected;

  const _RevenueSnapshotCard({
    required this.isMonthly,
    required this.bars,
    required this.selectedBarIndex,
    required this.amount,
    required this.subtitle,
    required this.onToggle,
    required this.onBarSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = bars.isEmpty;
    final int safeSelectedIndex =
        isEmpty ? -1 : selectedBarIndex.clamp(0, bars.length - 1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Revenue',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      amount,
                      style: const TextStyle(
                        fontFamily: AppColors.headingFontFamily,
                        color: AppColors.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.isNotEmpty ? subtitle : 'No period selected',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _StatusPill(label: 'Week', active: !isMonthly, onTap: () {
                    if (isMonthly) onToggle(false);
                  }),
                  const SizedBox(width: 8),
                  _StatusPill(label: 'Month', active: isMonthly, onTap: () {
                    if (!isMonthly) onToggle(true);
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 130,
            decoration: BoxDecoration(
              color: AppColors.cardSurfaceAlt,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: isEmpty
                ? const Center(
                    child: Text(
                      'No data yet',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(bars.length, (index) {
                      final bar = bars[index];
                      final bool isSelected = index == safeSelectedIndex;
                      final barColor = isSelected
                          ? AppColors.chartBarLight
                          : AppColors.chartBarDim;
                      final labelColor = isSelected
                          ? AppColors.chartBarLight
                          : AppColors.textSecondary;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onBarSelected(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  height: (bars[index].heightFactor * 96).clamp(24.0, 96.0),
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  bar.label,
                                  style: TextStyle(
                                    fontFamily: AppColors.bodyFontFamily,
                                    color: labelColor,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _StatusPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.chartBarLight : AppColors.cardSurfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: active ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ---------- STATS GRID (parameterised) ----------
class _StatsGrid extends StatelessWidget {
  final List<StatItem> stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const SizedBox.shrink();
    }

    // Arrange into pairs for two columns
    final int half = (stats.length / 2).ceil();
    final leftStats = stats.sublist(0, half);
    final rightStats = stats.sublist(half);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              for (final stat in leftStats) ...[
                _StatCard(stat: stat),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              for (final stat in rightStats) ...[
                _StatCard(stat: stat),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final StatItem stat;

  const _StatCard({required this.stat});

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
            stat.label,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stat.value,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  stat.delta,
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: stat.deltaPositive
                        ? AppColors.positiveGreen
                        : Colors.redAccent.withValues(alpha: 0.8),
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