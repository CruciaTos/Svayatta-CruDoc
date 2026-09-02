// desktop_patient_records_screen.dart
import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
// Removed: import of desktop_patient_details_dialog.dart
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_details_screen.dart'; // <-- Added
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';

const _emptyDesktopPatientViewData = _DesktopPatientViewData(
  totalPatients: '0',
  newThisMonth: '0',
  withDiagnosis: '0',
  packageBalance: '₹0',
  genderBreakdown: <_BreakdownItem>[],
  patients: <Patient>[],
);

final _patientCurrencyFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

final _patientDateFormatter = DateFormat('dd/MM/yyyy');

_DesktopPatientViewData _mapPatientsToViewData(List<Patient> patients) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final newThisMonth = patients
      .where((patient) => !patient.createdAt.isBefore(monthStart))
      .length;
  final withDiagnosis = patients
      .where((patient) => patient.diagnosisDisplay.trim().isNotEmpty)
      .length;
  final packageBalance = patients.fold<double>(
    0,
    (sum, patient) => sum + patient.packageBalance,
  );
  final genderCounts = <String, int>{};

  for (final patient in patients) {
    final label = patient.gender.trim().isEmpty
        ? 'Not specified'
        : patient.gender.trim();
    genderCounts.update(label, (value) => value + 1, ifAbsent: () => 1);
  }

  final colors = <Color>[
    const Color(0xFF2196F3),
    const Color(0xFF673AB7),
    const Color(0xFFFF9800),
    const Color(0xFFE91E63),
    const Color(0xFF00C853),
  ];
  final breakdown = genderCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return _DesktopPatientViewData(
    totalPatients: patients.length.toString(),
    newThisMonth: newThisMonth.toString(),
    withDiagnosis: withDiagnosis.toString(),
    packageBalance: _patientCurrencyFormatter.format(packageBalance),
    genderBreakdown: List.unmodifiable(
      breakdown.asMap().entries.map((entry) {
        final count = entry.value.value;
        final percent = patients.isEmpty
            ? 0
            : ((count / patients.length) * 100).round();
        return _BreakdownItem(
          label: entry.value.key,
          value: '$percent% ($count)',
          count: count,
          color: colors[entry.key % colors.length],
        );
      }),
    ),
    patients: List.unmodifiable(patients),
  );
}

class _DesktopPatientViewData {
  final String totalPatients;
  final String newThisMonth;
  final String withDiagnosis;
  final String packageBalance;
  final List<_BreakdownItem> genderBreakdown;
  final List<Patient> patients;

  const _DesktopPatientViewData({
    required this.totalPatients,
    required this.newThisMonth,
    required this.withDiagnosis,
    required this.packageBalance,
    required this.genderBreakdown,
    required this.patients,
  });
}

class _BreakdownItem {
  final String label;
  final String value;
  final int count;
  final Color color;

  const _BreakdownItem({
    required this.label,
    required this.value,
    required this.count,
    required this.color,
  });
}

/// Desktop version of the Patient Records tab.
///
/// A fully realized, interactive patient management dashboard matching the
/// provided design. Includes a donut chart, stats cards, a searchable toolbar,
/// and a rich data table with status chips.
enum PatientDurationFilter {
  allTime,
  today,
  thisWeek,
  thisMonth,
  thisYear,
}

extension PatientDurationFilterExt on PatientDurationFilter {
  String get label {
    switch (this) {
      case PatientDurationFilter.allTime:
        return 'All Time';
      case PatientDurationFilter.today:
        return 'Today';
      case PatientDurationFilter.thisWeek:
        return 'Weekly';
      case PatientDurationFilter.thisMonth:
        return 'Monthly';
      case PatientDurationFilter.thisYear:
        return 'Yearly';
    }
  }
}

List<Patient> _filterPatientsByDuration(
  List<Patient> patients,
  PatientDurationFilter duration,
) {
  if (duration == PatientDurationFilter.allTime) return patients;
  final now = DateTime.now();
  return patients.where((patient) {
    final created = patient.createdAt;
    switch (duration) {
      case PatientDurationFilter.allTime:
        return true;
      case PatientDurationFilter.today:
        return created.year == now.year &&
            created.month == now.month &&
            created.day == now.day;
      case PatientDurationFilter.thisWeek:
        final startOfWeek = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return !created.isBefore(startOfWeek);
      case PatientDurationFilter.thisMonth:
        return created.year == now.year && created.month == now.month;
      case PatientDurationFilter.thisYear:
        return created.year == now.year;
    }
  }).toList();
}

/// Non‑scrollable outer container – the table scrolls internally.
class DesktopPatientRecordsScreen extends StatefulWidget {
  const DesktopPatientRecordsScreen({super.key});

  @override
  State<DesktopPatientRecordsScreen> createState() =>
      _DesktopPatientRecordsScreenState();
}

class _DesktopPatientRecordsScreenState
    extends State<DesktopPatientRecordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Sort, filter, and duration states
  PatientSortOption _sortOption = PatientSortOption.nameAsc;
  PatientFilterOption _filterOption = PatientFilterOption.all;
  PatientDurationFilter _durationFilter = PatientDurationFilter.allTime;

  // When non-null, shows PatientDetailsBody instead of the dashboard.
  Patient? _selectedPatient;

  // Create a single repository instance for the lifetime of this widget.
  late final PatientRepository _repository = PatientRepository();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddPatientSheet() {
    showAddPatientSheet(context, repository: _repository);
  }

  void _openEditPatientSheet(Patient patient) {
    showEditPatientSheet(context, patient: patient, repository: _repository);
  }

  List<Patient> _applySortAndFilter(List<Patient> patients) {
    List<Patient> result = List.of(patients);

    // Filter
    switch (_filterOption) {
      case PatientFilterOption.all:
        break;
      case PatientFilterOption.male:
        result = result
            .where((p) => p.gender.trim().toLowerCase() == 'male')
            .toList();
        break;
      case PatientFilterOption.female:
        result = result
            .where((p) => p.gender.trim().toLowerCase() == 'female')
            .toList();
        break;
      case PatientFilterOption.notSpecified:
        result = result.where((p) => p.gender.trim().isEmpty).toList();
        break;
      case PatientFilterOption.active:
        result = result.where((p) => _statusForPatient(p) == 'Active').toList();
        break;
      case PatientFilterOption.stable:
        result = result.where((p) => _statusForPatient(p) == 'Stable').toList();
        break;
      case PatientFilterOption.critical:
        result = result
            .where((p) => _statusForPatient(p) == 'Critical')
            .toList();
        break;
    }

    // Sort
    switch (_sortOption) {
      case PatientSortOption.nameAsc:
        result.sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
        break;
      case PatientSortOption.nameDesc:
        result.sort(
          (a, b) =>
              b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()),
        );
        break;
      case PatientSortOption.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case PatientSortOption.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case PatientSortOption.packageHigh:
        result.sort((a, b) => b.packageBalance.compareTo(a.packageBalance));
        break;
      case PatientSortOption.packageLow:
        result.sort((a, b) => a.packageBalance.compareTo(b.packageBalance));
        break;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    // ── Inline patient details view ──────────────────────────────────────
    if (_selectedPatient != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: PatientDetailsBody(
          patient: _selectedPatient!,
          onBack: () => setState(() => _selectedPatient = null),
        ),
      );
    }

    // ── Dashboard / table view ───────────────────────────────────────────
    final patientStream = _repository.watchPatients();
    if (kDebugMode) {
      // Log that the stream was created (helps debug startup issues)
      // ignore: avoid_print
      print('[Patients] patientStream created: $patientStream');
    }

    return StreamBuilder<List<Patient>>(
      stream: patientStream,
      builder: (context, snapshot) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[Patients] snapshot: state=${snapshot.connectionState} hasData=${snapshot.hasData} dataCount=${snapshot.data?.length ?? 0} hasError=${snapshot.hasError} error=${snapshot.error}',
          );
        }

        final isWaiting = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final rawPatients = snapshot.data ?? <Patient>[];
        final durationPatients = _filterPatientsByDuration(
          rawPatients,
          _durationFilter,
        );
        final viewData = durationPatients.isEmpty
            ? _emptyDesktopPatientViewData
            : _mapPatientsToViewData(durationPatients);
        final filteredBySearch = _filterPatients(
          viewData.patients,
          _searchQuery,
        );
        final displayPatients = _applySortAndFilter(filteredBySearch);

        return Stack(
          children: [
            SizedBox.expand(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF), // Light blue background
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color.fromARGB(255, 150, 150, 150),
                        width: 0.25,
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: _PatientDashboardView(
                      viewData: viewData,
                      patients: displayPatients,
                      searchController: _searchController,
                      searchQuery: _searchQuery,
                      durationFilter: _durationFilter,
                      onDurationChanged: (filter) {
                        setState(() => _durationFilter = filter);
                      },
                      onSearchChanged: (value) {
                        setState(() => _searchQuery = value.trim());
                      },
                      onClearSearch: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                      onAddPatient: _openAddPatientSheet,
                      onEditPatient: _openEditPatientSheet,
                      onPatientSelected: (patient) {
                        setState(() => _selectedPatient = patient);
                      },
                      sortOption: _sortOption,
                      filterOption: _filterOption,
                      onSortChanged: (option) {
                        setState(() => _sortOption = option);
                      },
                      onFilterChanged: (option) {
                        setState(() => _filterOption = option);
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (hasError)
              Positioned(
                top: 16,
                right: 16,
                child: _PatientsStatusBanner(
                  icon: Icons.error_outline_rounded,
                  message: 'Failed to load patients',
                  color: Colors.red.shade700,
                  backgroundColor: Colors.red.shade50,
                ),
              )
            else if (isWaiting)
              const Positioned(
                top: 16,
                right: 16,
                child: _PatientsStatusBanner(
                  icon: Icons.sync_rounded,
                  message: 'Syncing patients...',
                  color: Color(0xFF2563EB),
                  backgroundColor: Color(0xFFEFF6FF),
                ),
              ),
          ],
        );
      },
    );
  }
}

List<Patient> _filterPatients(List<Patient> patients, String query) {
  final cleanQuery = query.toLowerCase().trim();
  if (cleanQuery.isEmpty) return patients;

  return patients.where((patient) {
    return patient.fullName.toLowerCase().contains(cleanQuery) ||
        patient.phone.toLowerCase().contains(cleanQuery) ||
        patient.id.toLowerCase().contains(cleanQuery) ||
        patient.gender.toLowerCase().contains(cleanQuery) ||
        patient.diagnosisDisplay.toLowerCase().contains(cleanQuery);
  }).toList();
}

class _PatientsStatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color backgroundColor;

  const _PatientsStatusBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// MAIN DASHBOARD VIEW (non‑scrollable outer, scrollable table inside)
// ==============================================================================

class _PatientDashboardView extends StatelessWidget {
  final _DesktopPatientViewData viewData;
  final List<Patient> patients;
  final TextEditingController searchController;
  final String searchQuery;
  final PatientDurationFilter durationFilter;
  final ValueChanged<PatientDurationFilter> onDurationChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onAddPatient;
  final ValueChanged<Patient> onEditPatient;
  final ValueChanged<Patient> onPatientSelected;

  // Sort and filter
  final PatientSortOption sortOption;
  final PatientFilterOption filterOption;
  final ValueChanged<PatientSortOption> onSortChanged;
  final ValueChanged<PatientFilterOption> onFilterChanged;

  const _PatientDashboardView({
    required this.viewData,
    required this.patients,
    required this.searchController,
    required this.searchQuery,
    required this.durationFilter,
    required this.onDurationChanged,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onAddPatient,
    required this.onEditPatient,
    required this.onPatientSelected,
    required this.sortOption,
    required this.filterOption,
    required this.onSortChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header (fixed) ---
        _HeaderSection(
          durationFilter: durationFilter,
          onDurationChanged: onDurationChanged,
        ),
        const SizedBox(height: 24),

        // --- Remaining area: chart/stats + toolbar + scrollable table ---
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chart & Stats Row (responsive to sidebar expanded/collapsed)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth > 780;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _ChartSection(
                            totalPatients: viewData.patients.length,
                            breakdown: viewData.genderBreakdown,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 7,
                          child: _StatsGridSection(viewData: viewData),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _ChartSection(
                          totalPatients: viewData.patients.length,
                          breakdown: viewData.genderBreakdown,
                        ),
                        const SizedBox(height: 16),
                        _StatsGridSection(viewData: viewData),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              // Toolbar (fixed)
              _ToolbarSection(
                controller: searchController,
                searchQuery: searchQuery,
                onChanged: onSearchChanged,
                onClear: onClearSearch,
                onAddPatient: onAddPatient,
                sortOption: sortOption,
                filterOption: filterOption,
                onSortChanged: onSortChanged,
                onFilterChanged: onFilterChanged,
              ),
              const SizedBox(height: 16),

              // Table takes all remaining vertical space and scrolls
              Expanded(
                child: _PatientTable(
                  patients: patients,
                  onEditPatient: onEditPatient,
                  onPatientSelected: onPatientSelected,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// 1. HEADER SECTION (adjusted for dark glass background)
// ==============================================================================

class _HeaderSection extends StatelessWidget {
  final PatientDurationFilter durationFilter;
  final ValueChanged<PatientDurationFilter> onDurationChanged;

  const _HeaderSection({
    required this.durationFilter,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Patients',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Overview of registered patients (${durationFilter.label.toLowerCase()}).',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
          ],
        ),
        Row(
          children: [
            PopupMenuButton<PatientDurationFilter>(
              tooltip: 'Select duration filter',
              initialValue: durationFilter,
              onSelected: onDurationChanged,
              itemBuilder: (context) => PatientDurationFilter.values
                  .map(
                    (f) => PopupMenuItem<PatientDurationFilter>(
                      value: f,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            f.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: f == durationFilter
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: f == durationFilter
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF1F2937),
                            ),
                          ),
                          if (f == durationFilter)
                            const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Color(0xFF2563EB),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: Color(0xFF4B5563),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      durationFilter.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: Color(0xFF4B5563),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==============================================================================
// 2. CHART SECTION (unchanged, white card)
// ==============================================================================

class _ChartSection extends StatelessWidget {
  final int totalPatients;
  final List<_BreakdownItem> breakdown;

  const _ChartSection({required this.totalPatients, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                'Patient Breakdown',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Distribution from live patient records.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    totalPatients: totalPatients,
                    breakdown: breakdown,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: breakdown.isEmpty
                    ? Text(
                        'No patient records yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      )
                    : Column(
                        children: breakdown
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LegendItem(
                                  label: item.label,
                                  percentage: item.value,
                                  color: item.color,
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final int totalPatients;
  final List<_BreakdownItem> breakdown;

  const _DonutChartPainter({
    required this.totalPatients,
    required this.breakdown,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeWidth = 22.0;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    if (breakdown.isEmpty || totalPatients == 0) {
      final paint = Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -pi / 2, 2 * pi, false, paint);
    } else {
      double start = -pi / 2;
      for (final item in breakdown) {
        final sweep = (item.count / totalPatients) * 2 * pi;
        final paint = Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(rect, start, sweep, false, paint);
        start += sweep;
      }
    }

    // Draw center text: total count and "Patients" label
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: '$totalPatients\n',
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2937),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2 + 2,
      ),
    );

    textPainter.text = const TextSpan(
      text: 'Patients',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Colors.grey,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy + textPainter.height / 2 - 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.totalPatients != totalPatients ||
      oldDelegate.breakdown != breakdown;
}

class _LegendItem extends StatelessWidget {
  final String label;
  final String percentage;
  final Color color;

  const _LegendItem({
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
          ),
        ),
        Text(
          percentage,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// 3. STATS GRID SECTION (unchanged, white cards)
// ==============================================================================

class _StatsGridSection extends StatelessWidget {
  final _DesktopPatientViewData viewData;

  const _StatsGridSection({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Total Patients',
                count: viewData.totalPatients,
                change: 'Live',
                icon: Icons.person_outline_rounded,
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'New This Month',
                count: viewData.newThisMonth,
                change: 'Created',
                icon: Icons.person_add_alt_1_outlined,
                color: const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'With Diagnosis',
                count: viewData.withDiagnosis,
                change: 'Recorded',
                icon: Icons.medical_services_outlined,
                color: const Color(0xFF9C27B0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'Package Balance',
                count: viewData.packageBalance,
                change: 'Total',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFFF9800),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String count;
  final String change;
  final IconData icon;
  final Color color;
  final double? width;

  const _StatCard({
    required this.title,
    required this.count,
    required this.change,
    required this.icon,
    required this.color,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(
                  count,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  change,
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Synced from patient records',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 4. TOOLBAR SECTION (adjusted for dark glass background)
// ==============================================================================

// Enums for sort and filter
enum PatientSortOption {
  nameAsc,
  nameDesc,
  newest,
  oldest,
  packageHigh,
  packageLow,
}

enum PatientFilterOption {
  all,
  male,
  female,
  notSpecified,
  active,
  stable,
  critical,
}

class _ToolbarSection extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onAddPatient;

  // Sort and filter
  final PatientSortOption sortOption;
  final PatientFilterOption filterOption;
  final ValueChanged<PatientSortOption> onSortChanged;
  final ValueChanged<PatientFilterOption> onFilterChanged;

  const _ToolbarSection({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    required this.onAddPatient,
    required this.sortOption,
    required this.filterOption,
    required this.onSortChanged,
    required this.onFilterChanged,
  });

  bool get _isFilterActive =>
      filterOption != PatientFilterOption.all ||
      sortOption != PatientSortOption.nameAsc;

  String _filterOptionLabel(PatientFilterOption option) {
    switch (option) {
      case PatientFilterOption.all:
        return 'All';
      case PatientFilterOption.male:
        return 'Male';
      case PatientFilterOption.female:
        return 'Female';
      case PatientFilterOption.notSpecified:
        return 'Not Specified';
      case PatientFilterOption.active:
        return 'Active';
      case PatientFilterOption.stable:
        return 'Stable';
      case PatientFilterOption.critical:
        return 'Critical';
    }
  }

  String _sortOptionLabel(PatientSortOption option) {
    switch (option) {
      case PatientSortOption.nameAsc:
        return 'Name A-Z';
      case PatientSortOption.nameDesc:
        return 'Name Z-A';
      case PatientSortOption.newest:
        return 'Newest';
      case PatientSortOption.oldest:
        return 'Oldest';
      case PatientSortOption.packageHigh:
        return 'Package High';
      case PatientSortOption.packageLow:
        return 'Package Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 900;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            // --- Search Bar with Integrated Filter Icon & Active Filter Chips ---
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: isWide ? 420 : 300,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isFilterActive
                          ? const Color(0xFF2563EB).withValues(alpha: 0.5)
                          : Colors.grey.shade300,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onChanged: onChanged,
                          decoration: const InputDecoration(
                            hintText:
                                'Search patient name, phone, diagnosis or ID...',
                            border: InputBorder.none,
                            isDense: true,
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          onPressed: onClear,
                        ),
                      const SizedBox(width: 4),
                      Container(
                        height: 20,
                        width: 1,
                        color: Colors.grey.shade200,
                      ),
                      const SizedBox(width: 4),

                      // Filter Icon directly in the Search Bar
                      PopupMenuButton<dynamic>(
                        tooltip: 'Filter & Sort Patients',
                        onSelected: (value) {
                          if (value is PatientFilterOption) {
                            onFilterChanged(value);
                          } else if (value is PatientSortOption) {
                            onSortChanged(value);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<dynamic>(
                            enabled: false,
                            height: 28,
                            child: Text(
                              'FILTER BY GENDER',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.all,
                            label: 'All Patients',
                            isSelected: filterOption == PatientFilterOption.all,
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.male,
                            label: 'Male',
                            isSelected: filterOption == PatientFilterOption.male,
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.female,
                            label: 'Female',
                            isSelected: filterOption == PatientFilterOption.female,
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.notSpecified,
                            label: 'Not Specified',
                            isSelected:
                                filterOption == PatientFilterOption.notSpecified,
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<dynamic>(
                            enabled: false,
                            height: 28,
                            child: Text(
                              'FILTER BY STATUS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.active,
                            label: 'Active',
                            isSelected: filterOption == PatientFilterOption.active,
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.stable,
                            label: 'Stable',
                            isSelected: filterOption == PatientFilterOption.stable,
                          ),
                          _buildFilterMenuItem(
                            option: PatientFilterOption.critical,
                            label: 'Critical',
                            isSelected:
                                filterOption == PatientFilterOption.critical,
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<dynamic>(
                            enabled: false,
                            height: 28,
                            child: Text(
                              'SORT BY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.nameAsc,
                            label: 'Name (A-Z)',
                            isSelected: sortOption == PatientSortOption.nameAsc,
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.nameDesc,
                            label: 'Name (Z-A)',
                            isSelected: sortOption == PatientSortOption.nameDesc,
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.newest,
                            label: 'Newest First',
                            isSelected: sortOption == PatientSortOption.newest,
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.oldest,
                            label: 'Oldest First',
                            isSelected: sortOption == PatientSortOption.oldest,
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.packageHigh,
                            label: 'Package Balance (High-Low)',
                            isSelected:
                                sortOption == PatientSortOption.packageHigh,
                          ),
                          _buildSortMenuItem(
                            option: PatientSortOption.packageLow,
                            label: 'Package Balance (Low-High)',
                            isSelected:
                                sortOption == PatientSortOption.packageLow,
                          ),
                        ],
                        child: Tooltip(
                          message: 'Filter & Sort Options',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isFilterActive
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 18,
                                  color: _isFilterActive
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF64748B),
                                ),
                                if (_isFilterActive)
                                  Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2563EB),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (filterOption != PatientFilterOption.all) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      _filterOptionLabel(filterOption),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: const Color(0xFFEFF6FF),
                    side: const BorderSide(color: Color(0xFF2563EB), width: 0.5),
                    deleteIcon: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF2563EB),
                    ),
                    onDeleted: () => onFilterChanged(PatientFilterOption.all),
                  ),
                ],
                if (sortOption != PatientSortOption.nameAsc) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      _sortOptionLabel(sortOption),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: const Color(0xFFEFF6FF),
                    side: const BorderSide(color: Color(0xFF2563EB), width: 0.5),
                    deleteIcon: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF2563EB),
                    ),
                    onDeleted: () => onSortChanged(PatientSortOption.nameAsc),
                  ),
                ],
              ],
            ),

            // Action Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text(
                    'Import/Export',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onAddPatient,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Add Patient',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  PopupMenuItem<dynamic> _buildFilterMenuItem({
    required PatientFilterOption option,
    required String label,
    required bool isSelected,
  }) {
    return PopupMenuItem<dynamic>(
      value: option,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF1F2937),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: Color(0xFF2563EB),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<dynamic> _buildSortMenuItem({
    required PatientSortOption option,
    required String label,
    required bool isSelected,
  }) {
    return PopupMenuItem<dynamic>(
      value: option,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF1F2937),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: Color(0xFF2563EB),
            ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 5. PATIENT DATA TABLE (scrollable in both directions, white background added)
// ==============================================================================

class _PatientTable extends StatefulWidget {
  final List<Patient> patients;
  final ValueChanged<Patient> onEditPatient;
  final ValueChanged<Patient> onPatientSelected;

  const _PatientTable({
    required this.patients,
    required this.onEditPatient,
    required this.onPatientSelected,
  });

  @override
  State<_PatientTable> createState() => _PatientTableState();
}

class _PatientTableState extends State<_PatientTable> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15.5),
        child: widget.patients.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 48,
                      color: Color(0xFFCBD5E1),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No patients found',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 15),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // --- Pinned Header Row ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: const [
                        SizedBox(
                          width: 36,
                          child: Text(
                            'No.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Text(
                            'Patient',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Date of Birth',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Gender',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Phone',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            'Diagnosis',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Package Balance',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Updated',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Status',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 68,
                          child: Text(
                            'Action',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Scrollable Vertical Data Rows ---
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _scrollController,
                        itemCount: widget.patients.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey.shade100,
                        ),
                        itemBuilder: (context, index) {
                          final patient = widget.patients[index];
                          final status = _statusForPatient(patient);
                          final initial = patient.firstName.isNotEmpty
                              ? patient.firstName[0].toUpperCase()
                              : 'P';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              hoverColor: const Color(0xFFF8FAFC),
                              onTap: () => widget.onPatientSelected(patient),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    // Index Number
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),

                                    // Patient Name + Avatar (No ID)
                                    Expanded(
                                      flex: 6,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 13,
                                            backgroundColor:
                                                const Color(0xFFEFF6FF),
                                            child: Text(
                                              initial,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              patient.fullName.trim().isEmpty
                                                  ? 'Unnamed Patient'
                                                  : patient.fullName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Color(0xFF1F2937),
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // DOB
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _patientDateFormatter
                                            .format(patient.dateOfBirth),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Gender
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        patient.gender.isEmpty
                                            ? '—'
                                            : patient.gender,
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Phone
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        patient.phone.isEmpty
                                            ? '—'
                                            : patient.phone,
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Diagnosis
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        patient.diagnosisDisplay.isEmpty
                                            ? '—'
                                            : patient.diagnosisDisplay,
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Package Balance
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _patientCurrencyFormatter
                                            .format(patient.packageBalance),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                          color: Color(0xFF1F2937),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Updated
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _patientDateFormatter
                                            .format(patient.updatedAt),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Status
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _StatusChip(status: status),
                                      ),
                                    ),

                                    // Actions
                                    SizedBox(
                                      width: 68,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.visibility_outlined,
                                              size: 17,
                                              color: Color(0xFF64748B),
                                            ),
                                            tooltip: 'View details',
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            onPressed: () =>
                                                widget.onPatientSelected(patient),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 17,
                                              color: Color(0xFF64748B),
                                            ),
                                            tooltip: 'Edit patient',
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(
                                              minWidth: 28,
                                              minHeight: 28,
                                            ),
                                            onPressed: () =>
                                                widget.onEditPatient(patient),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String _statusForPatient(Patient patient) {
  final combined = '${patient.diagnosisDisplay} ${patient.notes}'.toLowerCase();
  if (combined.contains('critical') ||
      combined.contains('emergency') ||
      combined.contains('icu')) {
    return 'Critical';
  }
  if (combined.trim().isNotEmpty) return 'Active';
  return 'Stable';
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bgColor;

    switch (status) {
      case 'Active':
        color = const Color(0xFF2563EB);
        bgColor = const Color(0xFFEFF6FF);
        break;
      case 'Stable':
        color = const Color(0xFF00C853);
        bgColor = const Color(0xFFE8F5E9);
        break;
      case 'Moderate':
        color = const Color(0xFFFFA000);
        bgColor = const Color(0xFFFFF3E0);
        break;
      case 'Critical':
        color = const Color(0xFFDC2626);
        bgColor = const Color(0xFFFEE2E2);
        break;
      default:
        color = const Color(0xFF6B7280);
        bgColor = const Color(0xFFF3F4F6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
