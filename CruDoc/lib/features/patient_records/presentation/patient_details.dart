import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

class PatientDetailsPage extends StatelessWidget {
  final String name;
  final int age;
  final String gender;
  final String condition;
  final String address;
  final String contact;
  final String secondContact;
  final int sessionsAttended;
  final String lastVisit;

  const PatientDetailsPage({
    super.key,
    required this.name,
    required this.age,
    required this.gender,
    required this.condition,
    required this.address,
    required this.contact,
    required this.secondContact,
    required this.sessionsAttended,
    required this.lastVisit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.midnightBlue,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 24),
                // Avatar and name
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppColors.silver.withOpacity(0.2),
                        child: Text(
                          name[0],
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$gender, $age years',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Condition: $condition',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Personal & Contact Information Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Address
                      _DetailRow(
                        icon: Icons.location_on,
                        label: 'Address',
                        value: address,
                      ),
                      const SizedBox(height: 16),
                      // Primary Contact
                      _DetailRow(
                        icon: Icons.phone,
                        label: 'Primary Contact',
                        value: contact,
                      ),
                      const SizedBox(height: 16),
                      // Secondary Contact
                      _DetailRow(
                        icon: Icons.phone_android,
                        label: 'Secondary Contact',
                        value: secondContact,
                      ),
                      const SizedBox(height: 16),
                      // Sessions Attended
                      _DetailRow(
                        icon: Icons.calendar_month,
                        label: 'Sessions Attended',
                        value: '$sessionsAttended sessions',
                      ),
                      const SizedBox(height: 16),
                      // Last Visit (already displayed above, but added here too)
                      _DetailRow(
                        icon: Icons.history,
                        label: 'Last Visit',
                        value: lastVisit,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Recent Appointments Section
                const Text(
                  'Recent Appointments',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(),
                    children: const [
                      _AppointmentCard(
                        date: 'June 20, 2026',
                        time: '10:30 AM',
                        reason: 'General checkup',
                      ),
                      _AppointmentCard(
                        date: 'May 15, 2026',
                        time: '02:00 PM',
                        reason: 'Follow-up visit',
                      ),
                      _AppointmentCard(
                        date: 'April 02, 2026',
                        time: '09:00 AM',
                        reason: 'Blood test results',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Detail Row Widget ----------
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.silver, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- Appointment Card (sample) ----------
class _AppointmentCard extends StatelessWidget {
  final String date;
  final String time;
  final String reason;
  const _AppointmentCard({
    required this.date,
    required this.time,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: AppColors.silver, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$time  •  $reason',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}