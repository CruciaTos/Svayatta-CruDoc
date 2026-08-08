import 'package:flutter/material.dart';

class ActivityLogsWidget extends StatelessWidget {
  const ActivityLogsWidget({super.key});

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
          const Text(
            'Activity Logs',
            style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const _LogItem(
            title: 'Dr. Ronald updated patient record',
            subtitle: 'Patient: Liam Carter',
            time: '10 min ago',
          ),
          const Divider(height: 8),
          const _LogItem(
            title: 'Appointment scheduled for Mia',
            subtitle: 'Online consultation confirmed',
            time: '1 hour ago',
          ),
          const Divider(height: 8),
          const _LogItem(
            title: 'New lab report uploaded',
            subtitle: 'Urgent results ready for review',
            time: '2 hours ago',
          ),
        ],
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;

  const _LogItem({required this.title, required this.subtitle, required this.time});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14, fontWeight: FontWeight.w500)),
              Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
      ],
    );
  }
}