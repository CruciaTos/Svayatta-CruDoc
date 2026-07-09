import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/features/appointments/presentation/visitation_card.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart' as vmodel;
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

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

// ---------- SHARED DIALOG FORM HELPERS ----------
Widget _buildTextField(String label, TextEditingController controller,
    {String? hint, ValueChanged<String>? onChanged}) {
  return TextField(
    controller: controller,
    onChanged: onChanged,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
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
  final dateStr = '${date.day} ${_monthName(date.month)} ${date.year}';
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
  return SizedBox(
    height: 48,
    width: double.infinity,   // ← width constraint fixes the expand issue
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          menuMaxHeight: 200,
          dropdownColor: AppColors.cardSurface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: durations.map((d) {
            return DropdownMenuItem(value: d, child: Text(d));
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.silver),
        ),
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

// ---------- ADD VISIT DIALOG RESULT ----------
class _VisitDraft {
  final Patient? patient;
  final String typedName;
  final DateTime scheduledDate;
  final TimeOfDay scheduledTime;
  final String duration;
  final String address;
  final String mapsQuery;
  const _VisitDraft({
    required this.patient,
    required this.typedName,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.duration,
    required this.address,
    required this.mapsQuery,
  });
}

// ---------- EVENTS SCREEN ----------
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final VisitRepository _visitRepository = VisitRepository();
  final PatientRepository _patientRepository = PatientRepository();

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

  Future<void> _addOnlineSession() async {
    final titleController = TextEditingController();
    final linkController = TextEditingController();
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
                    _buildPickDateButton(context, selectedDate,
                        (picked) {
                          if (picked != null) setDialogState(() => selectedDate = picked);
                        }),
                    const SizedBox(height: 12),
                    _buildPickTimeButton(context, selectedTime,
                        (picked) {
                          if (picked != null) setDialogState(() => selectedTime = picked);
                        }),
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
                    if (titleController.text.isNotEmpty && linkController.text.isNotEmpty) {
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
      if (!mounted) return;
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

  Future<void> _addVisit() async {
    final draft = await showDialog<_VisitDraft>(
      context: context,
      builder: (context) => _AddVisitDialog(
        patientRepository: _patientRepository,
      ),
    );
    if (draft == null) return;
    if (!mounted) return;

    final timeStr = draft.scheduledTime.format(context);

    var patient = draft.patient;
    if (patient == null && draft.typedName.isNotEmpty) {
      final matches = await _patientRepository.searchPatients(
        draft.typedName,
        includeArchived: false,
      );
      final exactMatches = matches
          .where((p) => p.fullName.toLowerCase() == draft.typedName.toLowerCase())
          .toList();
      if (exactMatches.length == 1) {
        patient = exactMatches.first;
      }
    }

    if (patient == null) {
      _showError(
        'No matching patient named "${draft.typedName}". Pick a '
        'suggestion from the list, or add this patient first from '
        'Patient Records.',
      );
      return;
    }

    final dateStr = '${draft.scheduledDate.day} '
        '${_monthName(draft.scheduledDate.month)} '
        '${draft.scheduledDate.year}';
    final dayStr = _dayName(draft.scheduledDate.weekday);
    final scheduledStart = DateTime(
      draft.scheduledDate.year,
      draft.scheduledDate.month,
      draft.scheduledDate.day,
      draft.scheduledTime.hour,
      draft.scheduledTime.minute,
    );
    final durationMinutes = int.tryParse(draft.duration.split(' ').first) ?? 30;

    await _saveVisit(
      patient: patient,
      scheduledStart: scheduledStart,
      durationMinutes: durationMinutes,
      address: draft.address,
      dateStr: dateStr,
      dayStr: dayStr,
      timeStr: timeStr,
      durationLabel: draft.duration,
      mapsQuery: draft.mapsQuery,
    );
  }

  Future<void> _saveVisit({
    required Patient patient,
    required DateTime scheduledStart,
    required int durationMinutes,
    required String address,
    required String dateStr,
    required String dayStr,
    required String timeStr,
    required String durationLabel,
    required String mapsQuery,
    bool acknowledgeOverlap = false,
  }) async {
    final now = DateTime.now();
    final visit = vmodel.Visit(
      id: '',
      patientId: patient.id,
      scheduledStart: scheduledStart,
      durationMinutes: durationMinutes,
      address: address,
      status: vmodel.VisitStatus.scheduled,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _visitRepository.createVisit(
        visit,
        acknowledgeOverlap: acknowledgeOverlap,
      );
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.cardSurface,
          title: const Text('Overlapping visit',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'This overlaps ${e.conflicts.length} existing visit(s) at this time. Save anyway?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        await _saveVisit(
          patient: patient,
          scheduledStart: scheduledStart,
          durationMinutes: durationMinutes,
          address: address,
          dateStr: dateStr,
          dayStr: dayStr,
          timeStr: timeStr,
          durationLabel: durationLabel,
          mapsQuery: mapsQuery,
          acknowledgeOverlap: true,
        );
      }
      return;
    } on VisitException catch (e) {
      _showError(e.message);
      return;
    } catch (e) {
      _showError('Failed to save visit: $e');
      return;
    }

    if (!mounted) return;
    setState(() {
      upcomingVisits.add(Visit(
        patientName: patient.fullName,
        date: dateStr,
        day: dayStr,
        time: timeStr,
        duration: durationLabel,
        address: address,
        mapsQuery: mapsQuery,
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visit added successfully')),
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
                          Text('Add',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
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
                          Text('Add',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
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

// ---------- ADD VISIT DIALOG ----------
class _AddVisitDialog extends StatefulWidget {
  final PatientRepository patientRepository;
  const _AddVisitDialog({required this.patientRepository});

  @override
  State<_AddVisitDialog> createState() => _AddVisitDialogState();
}

class _AddVisitDialogState extends State<_AddVisitDialog> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mapsQueryController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  String _selectedDuration = '30 min';

  Patient? _selectedPatient;
  List<Patient> _patientMatches = [];
  int _searchRequestId = 0;
  bool _isSearching = false;   // so the user knows something is happening

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _mapsQueryController.dispose();
    super.dispose();
  }

  Future<void> _onNameChanged(String value) async {
    _selectedPatient = null;
    final query = value.trim();
    final requestId = ++_searchRequestId;

    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _patientMatches = [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() => _isSearching = true);   // show a small indicator

    List<Patient> matches;
    try {
      matches = await widget.patientRepository.searchPatients(query);
    } catch (e) {
      matches = [];
    }

    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _patientMatches = matches;
      _isSearching = false;
    });
  }

  void _selectPatient(Patient match) {
    _nameController.text = match.fullName;
    setState(() {
      _selectedPatient = match;
      _patientMatches = [];
    });
  }

  void _submit() {
    if (_nameController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      _VisitDraft(
        patient: _selectedPatient,
        typedName: _nameController.text.trim(),
        scheduledDate: _selectedDate,
        scheduledTime: _selectedTime,
        duration: _selectedDuration,
        address: _addressController.text.trim(),
        mapsQuery: _mapsQueryController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visiblePatientMatches = _patientMatches.take(5).toList(growable: false);

    return AlertDialog(
      backgroundColor: AppColors.cardSurface,
      title:
          const Text('Add Visit', style: TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              'Patient Name',
              _nameController,
              hint: 'Start typing to search existing patients',
              onChanged: _onNameChanged,
            ),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_patientMatches.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < visiblePatientMatches.length; i++) ...[
                      ListTile(
                        dense: true,
                        title: Text(
                          visiblePatientMatches[i].fullName,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                        ),
                        subtitle: Text(
                          visiblePatientMatches[i].phone,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                        onTap: () => _selectPatient(visiblePatientMatches[i]),
                      ),
                      if (i != visiblePatientMatches.length - 1)
                        Divider(
                          height: 1,
                          color: AppColors.textSecondary.withValues(alpha: 0.12),
                        ),
                    ],
                    if (_patientMatches.length > visiblePatientMatches.length)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Text(
                          'Showing first ${visiblePatientMatches.length} matches. Keep typing to narrow results.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else if (_selectedPatient == null &&
                _nameController.text.trim().length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'No matching patient — add them in Patient '
                  'Records first.',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _buildPickDateButton(
              context,
              _selectedDate,
              (picked) {
                if (picked != null) setState(() => _selectedDate = picked);
              },
            ),
            const SizedBox(height: 12),
            _buildPickTimeButton(
              context,
              _selectedTime,
              (picked) {
                if (picked != null) setState(() => _selectedTime = picked);
              },
            ),
            const SizedBox(height: 12),
            _buildDurationDropdown(
              _selectedDuration,
              (value) {
                if (value != null) setState(() => _selectedDuration = value);
              },
            ),
            const SizedBox(height: 12),
            _buildTextField('Address', _addressController),
            const SizedBox(height: 12),
            _buildTextField('Maps Query (e.g., 123+Main+St)',
                _mapsQueryController,
                hint: '123+Main+St'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
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