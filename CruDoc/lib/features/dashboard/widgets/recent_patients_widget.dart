import 'package:flutter/material.dart';

class RecentPatientsWidget extends StatelessWidget {
  const RecentPatientsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Patients',
                style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Patient'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey[50]),
              columns: const [
                DataColumn(label: Text('Patient Info', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Next Visit', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Insurance', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: const [
                DataRow(cells: [
                  DataCell(Row(
                    children: [
                      CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=1'), radius: 12),
                      SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Liam Carter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('1st visit', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ]),
                    ],
                  )),
                  DataCell(_StatusBadge(text: 'Neutral', color: Colors.purple)),
                  DataCell(Text('Today', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  DataCell(_TypeIcon(Icons.phone, 'Phone call')),
                  DataCell(Text('No', style: TextStyle(color: Colors.red, fontSize: 12))),
                ]),
                DataRow(cells: [
                  DataCell(Row(
                    children: [
                      CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=5'), radius: 12),
                      SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Emily Parker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('3d visit', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ]),
                    ],
                  )),
                  DataCell(_StatusBadge(text: 'Hard', color: Colors.red)),
                  DataCell(Text('Tomorrow', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  DataCell(_TypeIcon(Icons.computer, 'Online')),
                  DataCell(Text('Yes', style: TextStyle(color: Colors.green, fontSize: 12))),
                ]),
                DataRow(cells: [
                  DataCell(Row(
                    children: [
                      CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=9'), radius: 12),
                      SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Mia Smith', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('3d visit', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ]),
                    ],
                  )),
                  DataCell(_StatusBadge(text: 'Easy', color: Colors.green)),
                  DataCell(Text('21 Sep 2025', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  DataCell(_TypeIcon(Icons.phonelink_ring, 'Offline')),
                  DataCell(Text('No', style: TextStyle(color: Colors.red, fontSize: 12))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TypeIcon(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      ],
    );
  }
}