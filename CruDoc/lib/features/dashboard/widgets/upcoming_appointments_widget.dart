import 'package:flutter/material.dart';

class UpcomingAppointmentsWidget extends StatelessWidget {
  const UpcomingAppointmentsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF3F51B5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF00BCD4),
            blurRadius: 12,
            offset: Offset(0, 6),
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
                'Your Appointments',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _AppointmentItem(
            name: 'Mia Smith',
            time: '9:30 - 10:00 am',
            type: 'Online',
            avatarUrl: 'https://i.pravatar.cc/150?img=5',
          ),
          const SizedBox(height: 8),
          const _AppointmentItem(
            name: 'Sam Johnson',
            time: '9:30 - 10:00 am',
            type: 'Phone Call',
            avatarUrl: 'https://i.pravatar.cc/150?img=12',
          ),
          const SizedBox(height: 8),
          const _AppointmentItem(
            name: 'Emily Parker',
            time: '10:30 - 10:45 am',
            type: 'Online',
            avatarUrl: 'https://i.pravatar.cc/150?img=9',
          ),
          const SizedBox(height: 8),
          const _AppointmentItem(
            name: 'Anna Reed',
            time: '10:45 - 11:00 am',
            type: 'Offline',
            avatarUrl: 'https://i.pravatar.cc/150?img=4',
          ),
        ],
      ),
    );
  }
}

class _AppointmentItem extends StatelessWidget {
  final String name;
  final String time;
  final String type;
  final String avatarUrl;

  const _AppointmentItem({
    required this.name,
    required this.time,
    required this.type,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundImage: NetworkImage(avatarUrl),
          radius: 16,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(time, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            type,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
      ],
    );
  }
}