import 'package:flutter/material.dart';

class PendingTasksSuggestionsWidget extends StatelessWidget {
  const PendingTasksSuggestionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Tasks',
                style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('2/8', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _TaskCheckItem(
            title: 'Interview',
            subtitle: 'Sep 15, 08:30',
            isComplete: true,
          ),
          const Divider(height: 8),
          const _TaskCheckItem(
            title: 'Team Meeting',
            subtitle: 'Sep 15, 10:30',
            isComplete: true,
          ),
          const Divider(height: 8),
          const _TaskCheckItem(
            title: 'Project Update',
            subtitle: 'Sep 15, 13:00',
            isComplete: false,
          ),
          const Divider(height: 8),
          const _TaskCheckItem(
            title: 'AI Follow-up: Schedule review',
            subtitle: 'Sep 16, 09:00',
            isComplete: false,
          ),
        ],
      ),
    );
  }
}

class _TaskCheckItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isComplete;

  const _TaskCheckItem({required this.title, required this.subtitle, required this.isComplete});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: isComplete,
          onChanged: (val) {},
          activeColor: Colors.purple,
          shape: const CircleBorder(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: const Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w500,
                  decoration: isComplete ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
              Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.grey),
          onPressed: () {},
        ),
      ],
    );
  }
}