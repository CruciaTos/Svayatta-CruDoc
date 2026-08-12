import 'package:flutter/material.dart';
import 'dart:math';

/// Desktop version of the Patient Records tab.
///
/// A fully realized, interactive patient management dashboard matching the
/// provided design. Includes a donut chart, stats cards, a searchable toolbar,
/// and a rich data table with status chips.
/// Non‑scrollable outer container – the table scrolls internally.
class DesktopPatientRecordsScreen extends StatelessWidget {
  const DesktopPatientRecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1200,
              maxHeight: constraints.maxHeight,   // fill all vertical space
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24.0),
              child: const _PatientDashboardView(),
            ),
          ),
        );
      },
    );
  }
}

// ==============================================================================
// MAIN DASHBOARD VIEW
// ==============================================================================

class _PatientDashboardView extends StatelessWidget {
  const _PatientDashboardView();

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
                        Expanded(flex: 5, child: _ChartSection()),
                        const SizedBox(width: 24),
                        Expanded(flex: 7, child: _StatsGridSection()),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _ChartSection(),
                        const SizedBox(height: 24),
                        _StatsGridSection(),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // Toolbar (fixed)
              const _ToolbarSection(),
              const SizedBox(height: 16),

              // Table takes all remaining vertical space and scrolls
              const Expanded(
                child: _PatientTable(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// 1. HEADER SECTION (unchanged)
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
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
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
                  Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF4B5563)),
                  SizedBox(width: 8),
                  Text('Monthly', style: TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                  SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF4B5563)),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('Export', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }
}

// ==============================================================================
// 2. CHART SECTION (unchanged)
// ==============================================================================

class _ChartSection extends StatelessWidget {
  const _ChartSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Insurance Coverage Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 4),
          Text('Patient distribution by payment & insurance type this month.', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(painter: _DonutChartPainter()),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _LegendItem(label: 'Private Insurance', percentage: '36% (420)', color: const Color(0xFF2196F3)),
                    const SizedBox(height: 8),
                    _LegendItem(label: 'Government Insurance', percentage: '30% (350)', color: const Color(0xFF673AB7)),
                    const SizedBox(height: 8),
                    _LegendItem(label: 'Employer Provided', percentage: '21% (240)', color: const Color(0xFFFF9800)),
                    const SizedBox(height: 8),
                    _LegendItem(label: 'Self-Pay', percentage: '13% (160)', color: const Color(0xFFE91E63)),
                  ],
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
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeWidth = 22.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final paints = [
      Paint()..color = const Color(0xFF2196F3)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
      Paint()..color = const Color(0xFF673AB7)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
      Paint()..color = const Color(0xFFFF9800)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
      Paint()..color = const Color(0xFFE91E63)..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
    ];

    final angles = [0.36, 0.30, 0.21, 0.13];
    double start = -pi / 2;
    for (int i = 0; i < 4; i++) {
      double sweep = angles[i] * 2 * pi;
      canvas.drawArc(rect, start, sweep, false, paints[i]);
      start += sweep;
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = const TextSpan(
      text: '1170\n',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2 + 2));

    textPainter.text = const TextSpan(
      text: 'Patients',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy + textPainter.height / 2 - 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendItem extends StatelessWidget {
  final String label;
  final String percentage;
  final Color color;

  const _LegendItem({required this.label, required this.percentage, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)))),
        Text(percentage, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
      ],
    );
  }
}

// ==============================================================================
// 3. STATS GRID SECTION (unchanged)
// ==============================================================================

class _StatsGridSection extends StatelessWidget {
  const _StatsGridSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = (constraints.maxWidth / 2) - 8;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(title: 'Total Patients', count: '1170', change: '+128', icon: Icons.person_outline_rounded, color: const Color(0xFF2196F3)),
            _StatCard(title: 'Outpatients', count: '390', change: '+48', icon: Icons.medical_services_outlined, color: const Color(0xFF4CAF50)),
            _StatCard(title: 'Inpatients', count: '780', change: '+78', icon: Icons.local_hospital_outlined, color: const Color(0xFF9C27B0)),
            _StatCard(title: 'Critical Cases', count: '58', change: '+7', icon: Icons.warning_amber_rounded, color: const Color(0xFFFF9800)),
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

  const _StatCard({
    required this.title,
    required this.count,
    required this.change,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              Icon(icon, size: 18, color: color.withOpacity(0.7)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(count, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                child: Text(change, style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('New patients this month', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }
}

// ==============================================================================
// 4. TOOLBAR SECTION (unchanged)
// ==============================================================================

class _ToolbarSection extends StatelessWidget {
  const _ToolbarSection();

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
              width: isWide ? 300 : 200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Expanded(child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search patient name or ID...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  )),
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
                  icon: const Icon(Icons.download_rounded, size: 16, color: Color(0xFF4B5563)),
                  label: const Text('Import/Export', style: TextStyle(color: Color(0xFF1F2937), fontSize: 13)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Patient', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
          Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey),
        ],
      ),
    );
  }
}

// ==============================================================================
// 5. PATIENT DATA TABLE (now scrollable in both directions)
// ==============================================================================

class _PatientTable extends StatelessWidget {
  const _PatientTable();

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> patients = [
      {'id': 'P-202501', 'name': 'Johnathan Doe', 'dob': '22/05/1993', 'gender': 'Male', 'provider': 'Dr. Carter', 'diagnosis': 'Asthma', 'room': 'Ward A-12', 'date': '26/08/2025', 'time': '11:00AM', 'status': 'Stable'},
      {'id': 'P-202502', 'name': 'Amelia Wong', 'dob': '12/01/1980', 'gender': 'Female', 'provider': 'Dr. Sutanto', 'diagnosis': 'Diabetes', 'room': 'Outpatient', 'date': '24/08/2025', 'time': '02:00AM', 'status': 'Moderate'},
      {'id': 'P-202503', 'name': 'Michael Tan', 'dob': '04/10/1965', 'gender': 'Male', 'provider': 'Dr. Rahman', 'diagnosis': 'Heart Failure', 'room': 'ICU-03', 'date': 'ICU Monitoring', 'time': '', 'status': 'Critical'},
      {'id': 'P-202504', 'name': 'Sophia Lim', 'dob': '18/12/1998', 'gender': 'Female', 'provider': 'Dr. Setiawan', 'diagnosis': 'Seasonal Allergy', 'room': 'Outpatient', 'date': '02/09/2025', 'time': '09:00AM', 'status': 'Stable'},
      {'id': 'P-202505', 'name': 'Daniel Kim', 'dob': '30/03/1986', 'gender': 'Male', 'provider': 'Dr. Hakim', 'diagnosis': 'Hypertension', 'room': 'Ward B-07', 'date': '30/08/2025', 'time': '01:30PM', 'status': 'Moderate'},
      {'id': 'P-202506', 'name': 'Olivia Rodrigo', 'dob': '14/02/1971', 'gender': 'Female', 'provider': 'Dr. Pratama', 'diagnosis': 'Osteoarthritis', 'room': 'Ward C-15', 'date': '05/09/2025', 'time': '10:15AM', 'status': 'Stable'},
      {'id': 'P-202507', 'name': 'David Park', 'dob': '11/11/1984', 'gender': 'Male', 'provider': 'Dr. Nugraha', 'diagnosis': 'Kidney Stones', 'room': 'Ward D-09', 'date': '01/09/2025', 'time': '08:45AM', 'status': 'Moderate'},
      {'id': 'P-202508', 'name': 'Grace Lee', 'dob': '09/08/1989', 'gender': 'Female', 'provider': 'Dr. Hasan', 'diagnosis': 'Migraine', 'room': 'Outpatient', 'date': '06/09/2025', 'time': '03:00PM', 'status': 'Stable'},
      {'id': 'P-202509', 'name': 'Richard Evans', 'dob': '02/04/1975', 'gender': 'Male', 'provider': 'Dr. Kartika', 'diagnosis': 'Stroke', 'room': 'ICU-01', 'date': 'Emergency Ward', 'time': '', 'status': 'Critical'},
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      // Outer vertical scroll so the table can overflow within the Expanded area
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.grey[50]),
            headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F2937), fontSize: 13),
            dataRowHeight: 60,
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Patient')),
              DataColumn(label: Text('Date of Birth')),
              DataColumn(label: Text('Gender')),
              DataColumn(label: Text('Provider')),
              DataColumn(label: Text('Diagnosis')),
              DataColumn(label: Text('Room')),
              DataColumn(label: Text('Next Appointment')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: patients.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final p = entry.value;
              return DataRow(cells: [
                DataCell(Row(children: [
                  SizedBox(width: 16, child: Checkbox(value: false, onChanged: (v) {})),
                  Text('#$index', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ])),
                DataCell(Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=${index + 10}'),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(p['id'], style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ]),
                ])),
                DataCell(Text(p['dob'], style: TextStyle(color: Colors.grey[700], fontSize: 13))),
                DataCell(Text(p['gender'], style: TextStyle(color: Colors.grey[700], fontSize: 13))),
                DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['provider'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  Text(p['diagnosis'].split(' ').last, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ])),
                DataCell(Text(p['diagnosis'], style: TextStyle(color: Colors.grey[700], fontSize: 13))),
                DataCell(Text(p['room'], style: TextStyle(color: Colors.grey[700], fontSize: 13))),
                DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['date'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  if (p['time'].isNotEmpty) Text(p['time'], style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ])),
                DataCell(_StatusChip(status: p['status'])),
                DataCell(Row(children: [
                  IconButton(icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey), onPressed: () {}),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey), onPressed: () {}),
                  IconButton(icon: Icon(Icons.more_vert, size: 18, color: Colors.grey), onPressed: () {}),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
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
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}