import 'package:flutter/material.dart';

class UpcomingVisitsWidget extends StatelessWidget {
  const UpcomingVisitsWidget({super.key});

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
            'Upcoming Visits',
            style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const _VisitTimelineItem(time: '08:00 AM', title: 'Routine Checkup', subtitle: 'John Doe'),
          const _VisitTimelineItem(time: '09:30 AM', title: 'Follow-up', subtitle: 'Sarah Smith'),
          const _VisitTimelineItem(time: '11:00 AM', title: 'Initial Visit', subtitle: 'Mike Ross'),
          const _VisitTimelineItem(time: '12:30 PM', title: 'Post-Op Review', subtitle: 'Rachel Zane'),
        ],
      ),
    );
  }
}

class _VisitTimelineItem extends StatelessWidget {
  final String time;
  final String title;
  final String subtitle;

  const _VisitTimelineItem({
    required this.time,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 30,
            color: Colors.grey[200],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}