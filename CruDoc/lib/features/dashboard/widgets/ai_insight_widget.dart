import 'package:flutter/material.dart';

class AiInsightWidget extends StatelessWidget {
  const AiInsightWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E24), // Dark background like reference
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber[400], size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI Smart Insights',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _InsightItem(
            icon: Icons.flash_on,
            text: 'AI Insight: Patient influx is 15% higher this week. Consider scheduling an extra nurse.',
          ),
          const SizedBox(height: 8),
          const _InsightItem(
            icon: Icons.chat_bubble,
            text: 'Provide 2 short, professional summaries for the clinic administrator.',
          ),
          const SizedBox(height: 8),
          const _InsightItem(
            icon: Icons.notifications,
            text: 'Dr. Smith has requested to review the Q3 strategy ahead of schedule.',
          ),
        ],
      ),
    );
  }
}

class _InsightItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InsightItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}