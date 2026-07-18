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
  String _doctorName = '';        // TODO: fetch from user session
  String _specialty = '';        // TODO: fetch from user session

  // ---- Revenue card state (lifted up) ----
  bool _isMonthly = true;
  int _selectedBarIndex = 0;     // will be updated when data is available

  // Replace these empty lists with data fetched from your repository
  List<BarData> _weeklyBars = [];
  List<BarData> _monthlyBars = [];

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
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onProfileTap,
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doctorName.isNotEmpty ? doctorName : '---',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                specialty.isNotEmpty ? specialty : '---',
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
          child: const Icon(Icons.notifications_none,
              color: AppColors.silver, size: 24),
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
    // Handle empty data gracefully
    final bool isEmpty = bars.isEmpty;
    final int safeSelectedIndex =
        isEmpty ? -1 : selectedBarIndex.clamp(0, bars.length - 1);

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
                'Revenue',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  _buildToggleChip('Week', !isMonthly),
                  const SizedBox(width: 6),
                  _buildToggleChip('Month', isMonthly),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
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
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Bar chart (handles empty state)
          SizedBox(
            height: 130,
            child: isEmpty
                ? const Center(
                    child: Text(
                      'No data',
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
                      final isSelected = index == safeSelectedIndex;

                      final barColor = isSelected
                          ? AppColors.chartBarLight
                          : AppColors.chartBarDim;

                      final labelStyle = TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: isSelected
                            ? AppColors.chartBarLight
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal,
                      );

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onBarSelected(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  height: 96 * bar.heightFactor,
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(bar.label, style: labelStyle),
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

  Widget _buildToggleChip(String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (label == 'Month' && !isMonthly) {
          onToggle(true);
        } else if (label == 'Week' && isMonthly) {
          onToggle(false);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppColors.slateBlue : AppColors.cardSurfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
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