import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/features/appointments/presentation/visitation_card.dart'; // VisitCard

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
    final linkController = TextEditingController();

    // Use stateful variables inside the dialog
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardSurface,
              title: const Text('Add Online Session',
                  style: TextStyle(color: AppColors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField('Title', titleController),
                    const SizedBox(height: 12),
                    // Date picker button
                    _buildPickDateButton(
                      context,
                      selectedDate,
                      (picked) {
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Time picker button
                    _buildPickTimeButton(
                      context,
                      selectedTime,
                      (picked) {
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTextField('Meeting Link (URL)', linkController,
                        hint: 'https://meet.google.com/...'),
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
                        linkController.text.isNotEmpty) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      // Format date and time nicely
      final dateStr =
          '${selectedDate.day} ${_monthName(selectedDate.month)} ${selectedDate.year}';
      final timeStr = selectedTime.format(context);

      setState(() {
        onlineSessions.add(OnlineSession(
          title: titleController.text.trim(),
          date: dateStr,
          time: timeStr,
          link: linkController.text.trim(),
        ));
      });
    }
  }

  // ---------- ADD VISIT DIALOG ----------
  Future<void> _addVisit() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final mapsQueryController = TextEditingController();

    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    String selectedDuration = '30 min'; // default duration

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardSurface,
              title: const Text('Add Visit',
                  style: TextStyle(color: AppColors.textPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextField('Patient Name', nameController),
                    const SizedBox(height: 12),
                    _buildPickDateButton(
                      context,
                      selectedDate,
                      (picked) {
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPickTimeButton(
                      context,
                      selectedTime,
                      (picked) {
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Duration dropdown
                    _buildDurationDropdown(
                      selectedDuration,
                      (value) {
                        if (value != null) {
                          setDialogState(() => selectedDuration = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTextField('Address', addressController),
                    const SizedBox(height: 12),
                    _buildTextField('Maps Query (e.g., 123+Main+St)',
                        mapsQueryController,
                        hint: '123+Main+St'),
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
                        addressController.text.isNotEmpty) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final dateStr =
          '${selectedDate.day} ${_monthName(selectedDate.month)} ${selectedDate.year}';
      final timeStr = selectedTime.format(context);
      final dayStr = _dayName(selectedDate.weekday);

      setState(() {
        upcomingVisits.add(Visit(
          patientName: nameController.text.trim(),
          date: dateStr,
          day: dayStr,
          time: timeStr,
          duration: selectedDuration,
          address: addressController.text.trim(),
          mapsQuery: mapsQueryController.text.trim(),
        ));
      });
    }
  }

  // ---------- HELPER WIDGETS ----------
  Widget _buildTextField(String label, TextEditingController controller,
      {String? hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
        filled: true,
        fillColor: AppColors.cardSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildPickDateButton(
      BuildContext context, DateTime date, ValueChanged<DateTime?> onPicked) {
    final dateStr =
        '${date.day} ${_monthName(date.month)} ${date.year}';
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.slateBlue,
                  onPrimary: AppColors.textPrimary,
                  surface: AppColors.cardSurface,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );
        onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardSurfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Text(
              dateStr,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickTimeButton(
      BuildContext context, TimeOfDay time, ValueChanged<TimeOfDay?> onPicked) {
    final timeStr = time.format(context);
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.slateBlue,
                  onPrimary: AppColors.textPrimary,
                  surface: AppColors.cardSurface,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );
        onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardSurfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Text(
              timeStr,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationDropdown(
      String currentValue, ValueChanged<String?> onChanged) {
    const durations = ['15 min', '30 min', '45 min', '60 min', '90 min', '120 min'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: AppColors.cardSurface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: durations.map((d) {
            return DropdownMenuItem(value: d, child: Text(d));
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.silver),
        ),
      ),
    );
  }

  // ---------- FORMAT HELPERS ----------
  String _monthName(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month];
  }

  String _dayName(int weekday) {
    const days = [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return days[weekday];
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