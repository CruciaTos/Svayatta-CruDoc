import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/features/appointments/presentation/visit.dart'; // VisitCard

// ---------- DATA MODELS ----------
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
      _showError('Unable to open link. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------- ADD ONLINE SESSION DIALOG ----------
  Future<void> _addOnlineSession() async {
    final titleController = TextEditingController();
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final linkController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: const Text('Add Online Session',
            style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField('Title', titleController),
              _buildDialogField('Date (e.g., July 18, 2026)', dateController),
              _buildDialogField('Time (e.g., 11:00 AM)', timeController),
              _buildDialogField('Meeting Link (URL)', linkController),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  dateController.text.isNotEmpty &&
                  timeController.text.isNotEmpty &&
                  linkController.text.isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        onlineSessions.add(OnlineSession(
          title: titleController.text,
          date: dateController.text,
          time: timeController.text,
          link: linkController.text,
        ));
      });
    }
  }

  // ---------- ADD VISIT DIALOG ----------
  Future<void> _addVisit() async {
    final nameController = TextEditingController();
    final dateController = TextEditingController();
    final dayController = TextEditingController();
    final timeController = TextEditingController();
    final durationController = TextEditingController();
    final addressController = TextEditingController();
    final mapsQueryController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: const Text('Add Visit',
            style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField('Patient Name', nameController),
              _buildDialogField('Date (e.g., July 15, 2026)', dateController),
              _buildDialogField('Day (e.g., Tuesday)', dayController),
              _buildDialogField('Time (e.g., 10:30 AM)', timeController),
              _buildDialogField('Duration (e.g., 45 min)', durationController),
              _buildDialogField('Address', addressController),
              _buildDialogField('Maps Query (e.g., 123+Main+St)', mapsQueryController),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty &&
                  dateController.text.isNotEmpty &&
                  timeController.text.isNotEmpty &&
                  addressController.text.isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        upcomingVisits.add(Visit(
          patientName: nameController.text,
          date: dateController.text,
          day: dayController.text,
          time: timeController.text,
          duration: durationController.text,
          address: addressController.text,
          mapsQuery: mapsQueryController.text,
        ));
      });
    }
  }

  Widget _buildDialogField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          filled: true,
          fillColor: AppColors.cardSurfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
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
              // ----- ONLINE SESSIONS HEADER WITH ADD BUTTON -----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Online Sessions',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: _addOnlineSession,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.slateBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: AppColors.textPrimary, size: 18),
                          SizedBox(width: 4),
                          Text('Add', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (onlineSessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    'No upcoming online sessions',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
              // ----- UPCOMING VISITS HEADER WITH ADD BUTTON -----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Visits',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: _addVisit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.slateBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: AppColors.textPrimary, size: 18),
                          SizedBox(width: 4),
                          Text('Add', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  itemCount: upcomingVisits.length,
                  itemBuilder: (context, index) {
                    final visit = upcomingVisits[index];
                    return VisitCard(
                      patientName: visit.patientName,
                      date: visit.date,
                      day: visit.day,
                      time: visit.time,
                      duration: visit.duration,
                      address: visit.address,
                      mapsQuery: visit.mapsQuery,
                      onMapTap: (query) => _launchUrl(
                        'https://www.google.com/maps/search/?api=1&query=$query',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- ONLINE SESSION CARD (unchanged) ----------
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