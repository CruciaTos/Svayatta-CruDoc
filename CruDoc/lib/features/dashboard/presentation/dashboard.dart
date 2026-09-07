import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart' as vmodel;
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/dashboard/data/models/activity_item.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/recent_activity_provider.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_calendar_sheet.dart';
import 'package:doctor_management_app/features/dental/presentation/widgets/dental_quick_actions_row.dart';
import 'package:doctor_management_app/features/shell/components/specialty_switcher_dialog.dart';
import 'package:doctor_management_app/features/dashboard/presentation/web_dashboard_view.dart';

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


// ---------- Home Dashboard Screen (Stateful for local UI state) ----------
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
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
    _navigateToTabOrExplain(
      tabIndex: 2,
      unavailableTitle: 'Inventory',
      unavailableMessage:
          'Low-stock and expiring medicines are listed in the Inventory section.',
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
    if (kIsWeb && MediaQuery.of(context).size.width > 768) {
      return WebDashboardView(onNavigateToTab: widget.onNavigateToTab);
    }


    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: StreamBuilder<List<String>>(
          stream: DoctorFeatureGuard.watchEnabledModules(),
          builder: (context, modulesSnapshot) {
            final enabledModules = modulesSnapshot.data ?? DoctorFeatureGuard.defaultModules;
            final isRevenueEnabled = DoctorFeatureGuard.isEnabled(enabledModules, 'revenue');
            final isInventoryEnabled = DoctorFeatureGuard.isEnabled(enabledModules, 'inventory');
            final isPatientsEnabled = DoctorFeatureGuard.isEnabled(enabledModules, 'patients');
            final isAppointmentsEnabled = DoctorFeatureGuard.isEnabled(enabledModules, 'appointments');

            void showLockedNotice(String featureLabel) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🔒 $featureLabel is disabled by Administrator.',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.cardSurface,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            }

            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: DoctorProfileHelper.watchDoctorProfile(),
                    builder: (context, profileSnapshot) {
                      final profileData = profileSnapshot.data;
                      final currentUser = FirebaseAuth.instance.currentUser;
                      final doctorName = DoctorProfileHelper.formatDoctorName(
                          currentUser, profileData);
                      final specialty =
                          DoctorProfileHelper.formatSpecialty(profileData);

                      return _TopBar(
                        doctorName: doctorName,
                        specialty: specialty,
                        onProfileTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  if (isInventoryEnabled) ...[
                    LowStockBanner(
                      onTap: () => _navigateToTabOrExplain(
                        tabIndex: 2,
                        unavailableTitle: 'Inventory',
                        unavailableMessage:
                            'Low-stock and expiring medicines are listed in the Inventory section.',
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (!isRevenueEnabled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lock_rounded, color: Colors.amber.shade300, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Revenue & Financials',
                                style: TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Feature Locked by Super Admin',
                                style: TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  color: AppColors.textPrimary.withValues(alpha: 0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
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
                              _selectedBarIndex = -1; // reset selection to current day / month
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

                  StreamBuilder<Map<String, dynamic>?>(
                    stream: DoctorProfileHelper.watchDoctorProfile(),
                    builder: (context, profileSnapshot) {
                      final rawSpecialty = DoctorProfileHelper.formatSpecialty(profileSnapshot.data);
                      final isDentist = rawSpecialty.toLowerCase().contains('dent');
                      if (!isDentist) return const SizedBox.shrink();

                      return const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: DentalQuickActionsRow(),
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                  QuickActionsRow(
                    onNewVisit: isAppointmentsEnabled
                        ? () => _navigateToTabOrExplain(
                              tabIndex: 4,
                              unavailableTitle: 'Visits',
                              unavailableMessage:
                                  'Visit scheduling lives in the Events section. Open Events and use the plus button to add a home visitation or clinic appointment.',
                            )
                        : () => showLockedNotice('Appointments & Visits'),
                    onAddInventoryItem: isInventoryEnabled
                        ? _openAddMedicine
                        : () => showLockedNotice('Inventory Management'),
                    onAddPatient: isPatientsEnabled
                        ? _openAddPatient
                        : () => showLockedNotice('Patient Records'),
                    onAppointments: isAppointmentsEnabled
                        ? () => AppointmentCalendarSheet.show(context)
                        : () => showLockedNotice('Appointments & Calendar'),
                  ),
                  const SizedBox(height: 12),
                  if (isAppointmentsEnabled)
                    TodaysVisitsCard(
                      onViewAll: () => _navigateToTabOrExplain(
                        tabIndex: 4,
                        unavailableTitle: "Today's Visits",
                        unavailableMessage:
                            'Visitations and appointments live in the Events section.',
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded, color: Colors.amber.shade300, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Today's Visits module is disabled",
                              style: TextStyle(
                                fontFamily: AppColors.bodyFontFamily,
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  const RecentActivityCard(),
                ],
              ),
            );
          },
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
              const SizedBox(height: 4),
              Builder(builder: (context) {
                final specMeta = DoctorSpecialty.fromString(specialty);
                return Tooltip(
                  message: 'Tap to switch specialty',
                  waitDuration: const Duration(milliseconds: 300),
                  child: InkWell(
                    onTap: () => showSpecialtySwitcherDialog(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: specMeta.accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: specMeta.accentColor.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(specMeta.icon,
                              size: 13, color: specMeta.accentColor),
                          const SizedBox(width: 5),
                          Text(
                            specialty.isNotEmpty ? specialty : '---',
                            style: TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: specMeta.accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 13,
                            color: specMeta.accentColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
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
                      color: AppColors.slateBlue.withValues(alpha: 0.7),
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
                      color: AppColors.textPrimary.withValues(alpha: 0.35),
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
                                            color: AppColors.chartBarLight.withValues(alpha: 0.6),
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
              : Colors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.slateBlue
                : AppColors.slateBlue.withValues(alpha: 0.20),
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

// =============================================================================
// INLINED DASHBOARD WIDGETS
// =============================================================================

class TodaysVisitsCard extends ConsumerWidget {
  const TodaysVisitsCard({super.key, this.onViewAll});

  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: visitsAsync.when(
        loading: () => _CardShell(
          count: null,
          onViewAll: onViewAll,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.slateBlue,
                ),
              ),
            ),
          ),
        ),
        error: (error, stack) => _CardShell(
          count: null,
          onViewAll: onViewAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Could not load today\'s visits.',
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
        data: (visits) {
          final resolved = visits.where((vw) => vw.patient != null).toList();

          return _CardShell(
            count: resolved.length,
            onViewAll: onViewAll,
            child: resolved.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No visits scheduled for today.',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < resolved.length; i++) ...[
                        _VisitRow(
                          visitWithPatient: resolved[i],
                          onTap: () =>
                              showSessionDetailsSheet(context, resolved[i]),
                        ),
                        if (i != resolved.length - 1)
                          const Divider(
                            height: 24,
                            color: Color(0xFFDDE6F0),
                          ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final int? count;
  final VoidCallback? onViewAll;
  final Widget child;

  const _CardShell({
    required this.count,
    required this.onViewAll,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Visits",
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.chartBarLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  count == null ? '—' : '$count scheduled',
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _VisitRow extends StatelessWidget {
  final VisitWithPatient visitWithPatient;
  final VoidCallback onTap;

  const _VisitRow({required this.visitWithPatient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visit = visitWithPatient.visit;
    final patient = visitWithPatient.patient!;
    final isHome = visit.visitType == vmodel.VisitType.home;
    final timeLabel = DateFormat('h:mm a').format(visit.scheduledStart);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.cardSurfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isHome ? Icons.home_outlined : Icons.local_hospital_outlined,
                color: AppColors.beige,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isHome ? 'Home visitation' : 'Clinic appointment',
                    style: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              timeLabel,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.silver,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({
    super.key,
    this.onNewVisit,
    this.onAddInventoryItem,
    this.onAddPatient,
    this.onLogExpense,
    this.onAppointments,
  });

  final VoidCallback? onNewVisit;
  final VoidCallback? onAddInventoryItem;
  final VoidCallback? onAddPatient;
  final VoidCallback? onLogExpense;
  final VoidCallback? onAppointments;

  static const List<_QuickAction> _actions = [
    _QuickAction(icon: Icons.calendar_today_outlined, label: 'New Visit'),
    _QuickAction(icon: Icons.inventory_2_outlined, label: 'Inventory'),
    _QuickAction(icon: Icons.person_add, label: 'Patient'),
    _QuickAction(icon: Icons.event, label: 'Appointments'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _actions
              .map(
                (action) => SizedBox(
                  width: itemWidth.clamp(74.0, 120.0),
                  height: 80,
                  child: _QuickActionButton(
                    action: action,
                    onTap: _tapHandlerFor(action.label),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  VoidCallback? _tapHandlerFor(String label) {
    switch (label) {
      case 'New Visit':
        return onNewVisit;
      case 'Inventory':
        return onAddInventoryItem;
      case 'Patient':
        return onAddPatient;
      case 'Appointments':
      case 'Logs':
        return onAppointments ?? onLogExpense;
    }
    return null;
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  const _QuickAction({required this.icon, required this.label});
}

class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback? onTap;

  const _QuickActionButton({required this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.chartBarLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(action.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentActivityCard extends ConsumerStatefulWidget {
  const RecentActivityCard({super.key});

  @override
  ConsumerState<RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends ConsumerState<RecentActivityCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(recentActivityProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.chartBarLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: AppColors.chartBarLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              activityAsync.whenOrNull(
                data: (items) {
                  if (items.isNotEmpty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.chartBarLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length} updates',
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: AppColors.chartBarLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ) ??
                  const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 8),
          activityAsync.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.chartBarLight,
                  ),
                ),
              ),
            ),
            error: (error, stack) => const SizedBox(
              height: 70,
              child: Center(
                child: Text(
                  'Could not load recent activity.',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      'No recent activity yet.',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 175,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: false,
                  radius: const Radius.circular(4),
                  thickness: 3.5,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 14,
                      thickness: 0.7,
                      color: Color(0xFFE8EEF5),
                    ),
                    itemBuilder: (context, index) {
                      return _ActivityRow(item: items[index]);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ActivityItem item;
  const _ActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Icon(
              item.icon,
              color: AppColors.slateBlue,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.relativeTime,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class LowStockBanner extends ConsumerWidget {
  const LowStockBanner({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicinesAsync = ref.watch(medicinesStreamProvider);
    final items = medicinesAsync.value ?? [];

    final lowStockCount = items.where((item) => item.isLowStock).length;
    final now = DateTime.now();
    final expiredCount = items
        .where((item) => item.expiryDate != null && item.expiryDate!.isBefore(now))
        .length;
    final expSoonCount = items
        .where((item) =>
            item.isExpiringSoon &&
            !(item.expiryDate != null && item.expiryDate!.isBefore(now)))
        .length;

    if (lowStockCount == 0 && expiredCount == 0 && expSoonCount == 0) {
      return const SizedBox.shrink();
    }

    final alerts = <String>[];
    if (lowStockCount > 0) alerts.add('$lowStockCount low stock');
    if (expiredCount > 0) alerts.add('$expiredCount expired');
    if (expSoonCount > 0) alerts.add('$expSoonCount expiring soon');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Inventory Notice: ${alerts.join(", ")}',
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: Color(0xFF92400E),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFD97706),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

