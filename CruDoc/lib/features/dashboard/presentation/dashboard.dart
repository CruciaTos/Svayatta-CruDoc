import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/dashboard/widgets/todays_visits_card.dart';
import 'package:doctor_management_app/features/dashboard/widgets/quick_actions_row.dart';
import 'package:doctor_management_app/features/dashboard/widgets/recent_activity_card.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_list_screen.dart';
import 'package:doctor_management_app/features/dashboard/widgets/low_stock_banner.dart';

// ---------- Data Models ----------
class BarData {
  final String label;
  final double heightFactor; // 0.0 to 1.0
  final int? revenueAmount; // optional for tooltip / amount display

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
  const HomeDashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  // ---- Doctor info from Firebase Auth ----
  String get _doctorName =>
      FirebaseAuth.instance.currentUser?.displayName ?? '';
  String get _specialty => ''; // TODO: fetch from Firestore user profile

  // ---- Revenue card state (lifted up) ----
  final RevenueRepository _revenueRepository = RevenueRepository();
  bool _isMonthly = true;
  int _selectedBarIndex = -1; // use current month/day if not yet selected
  bool _hideRevenue = true; // eye-toggle to mask the revenue section (hidden by default)

  /// Builds bars for the current week view with fixed Mon‑Sun labels.
  /// Each bar shows the revenue of the **most recent occurrence** of that weekday.
  List<BarData> _buildWeeklyBars(List<RevenueEntry> entries) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final currentWeekday = today.weekday; // 1 = Monday, 7 = Sunday

    // Only consider income entries for the chart
    final incomeEntries = entries
        .where((e) => e.kind == TransactionKind.income)
        .toList();

    final dailyAmounts = List.generate(7, (index) {
      final weekday = index + 1; // 1 = Mon ... 7 = Sun

      // Find the most recent date with this weekday <= today
      DateTime targetDate;
      if (weekday == currentWeekday) {
        targetDate = todayMidnight; // today
      } else if (weekday < currentWeekday) {
        // earlier this week
        final diff = currentWeekday - weekday;
        targetDate = todayMidnight.subtract(Duration(days: diff));
      } else {
        // weekday > currentWeekday → from last week
        final diff = currentWeekday + (7 - weekday);
        targetDate = todayMidnight.subtract(Duration(days: diff));
      }

      final amount = incomeEntries
          .where((entry) => _isSameDate(entry.date, targetDate))
          .fold<double>(0, (sum, entry) => sum + entry.amount);
      return MapEntry(targetDate, amount);
    });

    final maxAmount = dailyAmounts.fold<double>(
        0, (maxValue, entry) => entry.value > maxValue ? entry.value : maxValue);

    return dailyAmounts.map((entry) {
      final amount = entry.value;
      return BarData(
        label: _shortWeekday(entry.key.weekday),
        heightFactor: maxAmount > 0 ? (amount / maxAmount) : 0.12,
        revenueAmount: amount.toInt(),
      );
    }).toList();
  }

  List<BarData> _buildMonthlyBars(List<RevenueEntry> entries) {
    final today = DateTime.now();
    // Only income entries for the chart
    final incomeEntries = entries
        .where((e) => e.kind == TransactionKind.income)
        .toList();

    final months = List.generate(6, (index) {
      final monthDate = DateTime(today.year, today.month - 5 + index, 1);
      final amount = incomeEntries.fold<double>(0, (sum, entry) {
        if (entry.date.year == monthDate.year && entry.date.month == monthDate.month) {
          return sum + entry.amount;
        }
        return sum;
      });
      return MapEntry(monthDate, amount);
    });

    final maxAmount = months.fold<double>(0, (maxValue, entry) {
      return entry.value > maxValue ? entry.value : maxValue;
    });

    return months.map((entry) {
      final amount = entry.value;
      return BarData(
        label: _shortMonth(entry.key.month),
        heightFactor: maxAmount > 0 ? (amount / maxAmount) : 0.12,
        revenueAmount: amount.toInt(),
      );
    }).toList();
  }

  String _shortMonth(int month) {
    const labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return labels[month - 1];
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _shortWeekday(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  int _defaultSelectedBarIndex(List<BarData> bars) {
    if (bars.isEmpty) return 0;
    if (_isMonthly) {
      return bars.length - 1;
    }
    // In weekly mode, today's bar is always at index (today.weekday - 1)
    return DateTime.now().weekday - 1;
  }

  void _openAddPatient() {
    showAddPatientSheet(context);
  }

  void _openAddMedicine() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InventoryListScreen(autoOpenAddForm: true),
      ),
    );
  }

  void _showSectionInfo({required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: AppColors.sectionHeading.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Okay'),
          ),
        ],
      ),
    );
  }

  void _navigateToTabOrExplain({
    required int tabIndex,
    required String unavailableTitle,
    required String unavailableMessage,
  }) {
    final navigate = widget.onNavigateToTab;
    if (navigate != null) {
      navigate(tabIndex);
      return;
    }

    _showSectionInfo(title: unavailableTitle, message: unavailableMessage);
  }

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
              const SizedBox(height: 16),
              LowStockBanner(
                onTap: () => _navigateToTabOrExplain(
                  tabIndex: 2,
                  unavailableTitle: 'Inventory',
                  unavailableMessage:
                      'Low-stock and expiring medicines are listed in the Inventory section.',
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<RevenueEntry>>(
                stream: _revenueRepository.watchRevenueEntries(),
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? const <RevenueEntry>[];
                  final bars = _isMonthly
                      ? _buildMonthlyBars(entries)
                      : _buildWeeklyBars(entries);
                  final currentIndex = bars.isEmpty
                      ? -1
                      : (_selectedBarIndex >= 0
                          ? _selectedBarIndex.clamp(0, bars.length - 1)
                          : _defaultSelectedBarIndex(bars));
                  final amount = currentIndex < 0
                      ? '₹0'
                      : '₹${bars[currentIndex].revenueAmount ?? 0}';
                  final subtitle = currentIndex < 0
                      ? ''
                      : bars[currentIndex].label;

                  return _RevenueSnapshotCard(
                    isMonthly: _isMonthly,
                    bars: bars,
                    selectedBarIndex: currentIndex < 0 ? 0 : currentIndex,
                    amount: amount,
                    subtitle: subtitle,
                    hideRevenue: _hideRevenue,
                    onHideToggle: () {
                      setState(() => _hideRevenue = !_hideRevenue);
                    },
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
                  );
                },
              ),
              const SizedBox(height: 16),
              _StatsGrid(stats: stats),
              const SizedBox(height: 20),
              QuickActionsRow(
                onNewVisit: () => _navigateToTabOrExplain(
                  tabIndex: 4,
                  unavailableTitle: 'Visits',
                  unavailableMessage:
                      'Visit scheduling lives in the Events section. Open Events and use the plus button to add a home visitation or clinic appointment.',
                ),
                onAddInventoryItem: _openAddMedicine,
                onAddPatient: _openAddPatient,
                onLogExpense: () => _showSectionInfo(
                  title: 'Log',
                  message:
                      'Expense logging is not available yet. This section will help you record clinic expenses and compare them with revenue once implemented.',
                ),
              ),
              const SizedBox(height: 20),
              TodaysVisitsCard(
                onViewAll: () => _navigateToTabOrExplain(
                  tabIndex: 4,
                  unavailableTitle: "Today's Visits",
                  unavailableMessage:
                      'Visitations and appointments live in the Events section.',
                ),
              ),
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
                child: const Icon(
                  Icons.person,
                  color: AppColors.silver,
                  size: 26,
                ),
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
          child: const Icon(
            Icons.notifications_none,
            color: AppColors.silver,
            size: 24,
          ),
        ),
      ],
    );
  }
}

// ---------- REVENUE SNAPSHOT CARD (with pill indicator for today/week & active month) ----------
class _RevenueSnapshotCard extends StatelessWidget {
  final bool isMonthly;
  final List<BarData> bars;
  final int selectedBarIndex;
  final String amount;
  final String subtitle;
  final bool hideRevenue;
  final VoidCallback onHideToggle;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onBarSelected;

  const _RevenueSnapshotCard({
    required this.isMonthly,
    required this.bars,
    required this.selectedBarIndex,
    required this.amount,
    required this.subtitle,
    required this.hideRevenue,
    required this.onHideToggle,
    required this.onToggle,
    required this.onBarSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = bars.isEmpty;
    final int safeSelectedIndex = isEmpty
        ? -1
        : selectedBarIndex.clamp(0, bars.length - 1);

    // Today's bar index for weekly view, current month index for monthly view
    final int todayIndex = DateTime.now().weekday - 1; // 0 = Monday, 6 = Sunday

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header row: "Revenue" label + eye icon + Week/Month chips ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
                  const SizedBox(width: 6),
                  // Eye toggle button
                  GestureDetector(
                    onTap: onHideToggle,
                    child: Icon(
                      hideRevenue ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 17,
                      color: AppColors.slateBlue.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              // Week / Month chips — only shown when not hidden
              if (!hideRevenue)
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
          // ---- Amount + subtitle (hidden when eye is off) ----
          if (hideRevenue)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    '₹ ••••••',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary.withOpacity(0.35),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            )
          else
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
          // ---- Bar chart — hidden when revenue is masked ----
          if (!hideRevenue) ...[
            const SizedBox(height: 20),
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

                        final bool showPill = isMonthly
                            ? (index == bars.length - 1)
                            : (index == todayIndex);

                        final barColor = isSelected
                            ? AppColors.chartBarLight
                            : AppColors.chartBarDim;

                        final labelStyle = TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: isSelected
                              ? AppColors.chartBarLight
                              : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
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
                                  if (showPill)
                                    Transform.translate(
                                      offset: const Offset(0, 3),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.chartBarLight : null,
                                          border: Border.all(
                                            color: AppColors.chartBarLight.withOpacity(0.6),
                                            width: 1.2,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          bar.label,
                                          style: labelStyle.copyWith(
                                            color: isSelected ? Colors.white : AppColors.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          // Active: slateBlue fill; inactive: white at 70% (matches form fields on gradient bg)
          color: isActive
              ? AppColors.slateBlue
              : Colors.white.withOpacity(0.70),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.slateBlue
                : AppColors.slateBlue.withOpacity(0.20),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: isActive ? Colors.white : AppColors.textSecondary,
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