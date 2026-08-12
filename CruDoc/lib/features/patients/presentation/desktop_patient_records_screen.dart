import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

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
/// Non‑scrollable outer container – the table scrolls internally.
class DesktopPatientRecordsScreen extends ConsumerStatefulWidget {
  const DesktopPatientRecordsScreen({super.key});

  @override
  ConsumerState<DesktopPatientRecordsScreen> createState() =>
      _DesktopPatientRecordsScreenState();
}

class _DesktopPatientRecordsScreenState
    extends ConsumerState<DesktopPatientRecordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(
      patientsStreamProvider.select(
        (patientsAsync) => patientsAsync.whenData(_mapPatientsToViewData),
      ),
    );
    final viewData = patientsAsync.value ?? _emptyDesktopPatientViewData;
    final filteredPatients = _filterPatients(viewData.patients, _searchQuery);

    return Stack(
      children: [
        SizedBox.expand(
          child: Container(
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
            padding: const EdgeInsets.all(20),
            child: _PatientDashboardView(
              viewData: viewData,
              patients: filteredPatients,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: (value) {
                setState(() => _searchQuery = value.trim());
              },
              onClearSearch: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
            ),
          ),
        ),
        if (patientsAsync.hasError)
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
        else if (patientsAsync.isLoading)
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
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const _PatientDashboardView({
    required this.viewData,
    required this.patients,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header (fixed) ---
        const _HeaderSection(),
        const SizedBox(height: 24),

        // --- Remaining area: chart/stats + toolbar + scrollable table ---
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chart & Stats Row (fixed)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isWide = constraints.maxWidth > 850;
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
                        const SizedBox(width: 24),
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
                        const SizedBox(height: 24),
                        _StatsGridSection(viewData: viewData),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // Toolbar (fixed)
              _ToolbarSection(
                controller: searchController,
                searchQuery: searchQuery,
                onChanged: onSearchChanged,
                onClear: onClearSearch,
              ),
              const SizedBox(height: 16),

              // Table takes all remaining vertical space and scrolls
              Expanded(child: _PatientTable(patients: patients)),
            ],
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// 1. HEADER SECTION
// ==============================================================================

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

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
              'Overview of registered patients and their current status.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Color(0xFF4B5563),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Monthly',
                    style: TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Color(0xFF4B5563),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
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
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text(
                'Export',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==============================================================================
// 2. CHART SECTION
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
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

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = const TextSpan(
      text: '',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2937),
      ),
    );
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
// 3. STATS GRID SECTION
// ==============================================================================

class _StatsGridSection extends StatelessWidget {
  final _DesktopPatientViewData viewData;

  const _StatsGridSection({required this.viewData});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = (constraints.maxWidth / 2) - 8;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(
              title: 'Total Patients',
              count: viewData.totalPatients,
              change: 'Live',
              icon: Icons.person_outline_rounded,
              color: const Color(0xFF2196F3),
              width: width,
            ),
            _StatCard(
              title: 'New This Month',
              count: viewData.newThisMonth,
              change: 'Created',
              icon: Icons.person_add_alt_1_outlined,
              color: const Color(0xFF4CAF50),
              width: width,
            ),
            _StatCard(
              title: 'With Diagnosis',
              count: viewData.withDiagnosis,
              change: 'Recorded',
              icon: Icons.medical_services_outlined,
              color: const Color(0xFF9C27B0),
              width: width,
            ),
            _StatCard(
              title: 'Package Balance',
              count: viewData.packageBalance,
              change: 'Total',
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFFFF9800),
              width: width,
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String count;
  final String change;
  final IconData icon;
  final Color color;
  final double width;

  const _StatCard({
    required this.title,
    required this.count,
    required this.change,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
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
// 4. TOOLBAR SECTION
// ==============================================================================

class _ToolbarSection extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _ToolbarSection({
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
  });

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
            Container(
              width: isWide ? 340 : 240,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Colors.grey,
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
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ),
                  if (searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear,
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
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DropdownButton(text: 'Sort'),
                const SizedBox(width: 8),
                _DropdownButton(text: 'Filter'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: Color(0xFF4B5563),
                  ),
                  label: const Text(
                    'Import/Export',
                    style: TextStyle(color: Color(0xFF1F2937), fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
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
}

class _DropdownButton extends StatelessWidget {
  final String text;

  const _DropdownButton({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vertical_split_rounded, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey),
        ],
      ),
    );
  }
}

// ==============================================================================
// 5. PATIENT DATA TABLE (scrollable in both directions)
// ==============================================================================

class _PatientTable extends StatelessWidget {
  final List<Patient> patients;

  const _PatientTable({required this.patients});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: patients.isEmpty
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
          : SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey[50]),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                    fontSize: 13,
                  ),
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 60,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(
                      label: Text(
                        '#',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(label: Text('Patient')),
                    DataColumn(label: Text('Date of Birth')),
                    DataColumn(label: Text('Gender')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Diagnosis')),
                    DataColumn(label: Text('Package Balance')),
                    DataColumn(label: Text('Updated')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows: patients.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final patient = entry.value;
                    final status = _statusForPatient(patient);
                    final initial = patient.firstName.isNotEmpty
                        ? patient.firstName[0].toUpperCase()
                        : 'P';
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              SizedBox(
                                width: 16,
                                child: Checkbox(
                                  value: false,
                                  onChanged: (v) {},
                                ),
                              ),
                              Text(
                                '#$index',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFFEFF6FF),
                                child: Text(
                                  initial,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    patient.fullName.trim().isEmpty
                                        ? 'Unnamed Patient'
                                        : patient.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    patient.id,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            _patientDateFormatter.format(patient.dateOfBirth),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            patient.gender.isEmpty ? '—' : patient.gender,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            patient.phone.isEmpty ? '—' : patient.phone,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            patient.diagnosisDisplay.isEmpty
                                ? '—'
                                : patient.diagnosisDisplay,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _patientCurrencyFormatter.format(
                              patient.packageBalance,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _patientDateFormatter.format(patient.updatedAt),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(_StatusChip(status: status)),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () {},
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
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
      case 'Stable':
        color = const Color(0xFF00C853);
        bgColor = const Color(0xFFE8F5E9);
        break;
      case 'Moderate':
        color = const Color(0xFFFFA000);
        bgColor = const Color(0xFFFFF3E0);
        break;
      case 'Critical':
        color = const Color(0xFFD32F2F);
        bgColor = const Color(0xFFFFEBEE);
        break;
      default:
        color = Colors.grey;
        bgColor = Colors.grey[100]!;
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