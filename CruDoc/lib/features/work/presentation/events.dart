import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------- DATA MODEL ----------
class Visit {
  final String patientName;
  final String date;
  final String day;
  final String time;
  final String duration;
  final String address;
  final String mapsQuery;

  const Visit({
    required this.patientName,
    required this.date,
    required this.day,
    required this.time,
    required this.duration,
    required this.address,
    required this.mapsQuery,
  });
}

class OnlineSession {
  final String title;
  final String date;
  final String time;
  final String link;

  const OnlineSession({
    required this.title,
    required this.date,
    required this.time,
    required this.link,
  });
}

// ---------- EVENTS SCREEN ----------
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  // ---------- DYNAMIC DATA ----------
  List<OnlineSession> onlineSessions = [
    const OnlineSession(
      title: 'Monthly Webinar: Patient Care',
      date: 'July 18, 2026',
      time: '11:00 AM',
      link: 'https://meet.google.com/abc-defg-hij',
    ),
  ];

  List<Visit> upcomingVisits = [
    const Visit(
      patientName: 'Emily Clark',
      date: 'July 15, 2026',
      day: 'Tuesday',
      time: '10:30 AM',
      duration: '45 min',
      address: '123 Oak Street, Springfield',
      mapsQuery: '123+Oak+Street+Springfield',
    ),
    const Visit(
      patientName: 'Michael Brown',
      date: 'July 16, 2026',
      day: 'Wednesday',
      time: '02:00 PM',
      duration: '60 min',
      address: '456 Maple Ave, Shelbyville',
      mapsQuery: '456+Maple+Ave+Shelbyville',
    ),
    const Visit(
      patientName: 'Sophia Lee',
      date: 'July 20, 2026',
      day: 'Sunday',
      time: '09:30 AM',
      duration: '30 min',
      address: '789 Pine Road, Capital City',
      mapsQuery: '789+Pine+Road+Capital+City',
    ),
  ];

  // ---------- SAFELY OPEN A URL ----------
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not open the link');
      }
    } catch (e) {
      // Graceful fallback for MissingPluginException or any other error
      _showError('Unable to open link. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
                const Text(
                  'Events',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                // ----- ONLINE SESSIONS -----
                const Text(
                  'Upcoming Online Sessions',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (onlineSessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text(
                      'No upcoming online sessions',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  ...onlineSessions.map(
                    (session) => _OnlineSessionCard(
                      session: session,
                      onTap: () => _launchUrl(session.link),
                    ),
                  ),

                const SizedBox(height: 24),
                // ----- UPCOMING VISITS -----
                const Text(
                  'Upcoming Visits',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    physics: const ClampingScrollPhysics(),
                    itemCount: upcomingVisits.length,
                    itemBuilder: (context, index) => _VisitCard(
                      visit: upcomingVisits[index],
                      onMapTap: (query) => _launchUrl(
                        'https://www.google.com/maps/search/?api=1&query=$query',
                      ),
                    ),
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

// ---------- ONLINE SESSION CARD ----------
class _OnlineSessionCard extends StatelessWidget {
  final OnlineSession session;
  final VoidCallback onTap;
  const _OnlineSessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: AppColors.silver, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.date}  •  ${session.time}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: const Icon(Icons.open_in_new,
                color: AppColors.beige, size: 20),
          ),
        ],
      ),
    );
  }
}

// ---------- VISIT CARD ----------
class _VisitCard extends StatelessWidget {
  final Visit visit;
  final Function(String) onMapTap;
  const _VisitCard({required this.visit, required this.onMapTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            visit.patientName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Text(
                '${visit.date}  •  ${visit.day}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Text(
                '${visit.time}  •  ${visit.duration}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 16, color: AppColors.silver),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  visit.address,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onMapTap(visit.mapsQuery),
            child: Row(
              children: const [
                Icon(Icons.map, size: 16, color: AppColors.beige),
                SizedBox(width: 6),
                Text(
                  'Open in Google Maps',
                  style: TextStyle(
                    color: AppColors.beige,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}