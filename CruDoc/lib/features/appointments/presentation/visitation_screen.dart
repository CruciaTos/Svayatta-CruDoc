import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doctor_management_app/features/appointments/widgets/visitation_card.dart';
import 'package:doctor_management_app/features/appointments/widgets/appointment_card.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart' as vmodel;
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

// Import the provider that exposes VisitWithPatient and the stream
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Bottom sheet used for session details (replaces the old full-page
// VisitDetailsPage push below).
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_calendar_sheet.dart';

// ---------- SHARED BOTTOM-SHEET FORM HELPERS ----------
Widget _buildSheetHandle() {
  return Center(
    child: Container(
      width: 44,
      height: 5,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.silver.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

Widget _buildSheetActions({
  required BuildContext context,
  required VoidCallback onCancel,
  required VoidCallback onSubmit,
  required String submitLabel,
  bool isSaving = false,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TextButton(
        onPressed: isSaving ? null : onCancel,
        child: const Text(
          'Cancel',
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            color: AppColors.slateBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: isSaving ? null : onSubmit,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          backgroundColor: AppColors.chartBarLight,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          submitLabel,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

Widget _buildTextField(String label, TextEditingController controller,
    {String? hint, ValueChanged<String>? onChanged}) {
  return TextField(
    controller: controller,
    onChanged: onChanged,
    style: AppColors.bodyMedium,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AppColors.bodyMedium.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.chartBarLight,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_outlined,
              color: AppColors.chartBarLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dateStr,
              style: AppColors.bodyMedium,
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, color: AppColors.chartBarLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              timeStr,
              style: AppColors.bodyMedium,
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    ),
  );
}

Widget _buildDurationDropdown(
    String currentValue, ValueChanged<String?> onChanged) {
  const durations = [
    '15 min',
    '30 min',
    '45 min',
    '60 min',
    '90 min',
    '120 min'
  ];
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentValue,
        isExpanded: true,
        menuMaxHeight: 200,
        dropdownColor: Colors.white,
        style: AppColors.bodyMedium,
        items: durations.map((d) {
          return DropdownMenuItem(value: d, child: Text(d));
        }).toList(),
        onChanged: onChanged,
        icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
      ),
    ),
  );
}

// ---------- FORMAT HELPERS ----------
String _monthName(int month) {
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return months[month];
}

String _dayName(int weekday) {
  const days = [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
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
  final String? mapsLink;
  final vmodel.VisitType visitType;   // merged: added visitType field
  const _VisitDraft({
    required this.patient,
    required this.typedName,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.duration,
    required this.address,
    this.mapsLink,
    required this.visitType,          // merged: required
  });
}

// ---------- ONLINE SESSION DATA MODEL ----------
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
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});
  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen>
    with SingleTickerProviderStateMixin {
  final VisitRepository _visitRepository = VisitRepository();
  final PatientRepository _patientRepository = PatientRepository();

  // Drives the swipeable "Visitations" / "Appointments" category cards
  // (Instagram Posts/Reels/Tagged-style) below the online sessions list.
  late final TabController _categoryTabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void dispose() {
    _categoryTabController.dispose();
    super.dispose();
  }

  // Online sessions still use local state (no backend)
  List<OnlineSession> onlineSessions = [
    const OnlineSession(
      title: 'Monthly Webinar: Patient Care',
      date: 'July 18, 2026',
      time: '11:00 AM',
      link: 'https://meet.google.com/abc-defg-hij',
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
    final draft = await showModalBottomSheet<_OnlineSessionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _AddOnlineSessionSheet(),
    );

    if (draft == null || !mounted) return;

    final dateStr =
        '${draft.date.day} ${_monthName(draft.date.month)} ${draft.date.year}';
    final timeStr = draft.time.format(context);
    setState(() {
      onlineSessions.add(OnlineSession(
        title: draft.title,
        date: dateStr,
        time: timeStr,
        link: draft.link,
      ));
    });
  }

  Future<void> _addVisit() async {
    final draft = await showModalBottomSheet<_VisitDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _AddVisitSheet(
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
          .where(
              (p) => p.fullName.toLowerCase() == draft.typedName.toLowerCase())
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
      mapsLink: draft.mapsLink,
      visitType: draft.visitType,   // merged: pass visit type
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
    String? mapsLink,
    required vmodel.VisitType visitType,   // merged: required param
    bool acknowledgeOverlap = false,
  }) async {
    final now = DateTime.now();
    final visit = vmodel.Visit(
      id: '',
      patientId: patient.id,
      scheduledStart: scheduledStart,
      durationMinutes: durationMinutes,
      address: address,
      mapsLink: mapsLink,
      visitType: visitType,              // merged: set visit type
      status: vmodel.VisitStatus.scheduled,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _visitRepository.createVisit(
        visit,
        acknowledgeOverlap: acknowledgeOverlap,
      );
      // The provider will auto-update the list – no manual setState needed.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visit added successfully')),
      );
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color.fromARGB(255, 140, 188, 255),
          title: const Text(
            'Overlapping visit',
            style: AppColors.sectionHeading,
          ),
          content: Text(
            'This overlaps ${e.conflicts.length} existing visit(s) at this time. Save anyway?',
            style: AppColors.bodyMedium.copyWith(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: AppColors.bodyLarge),
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
          mapsLink: mapsLink,
          visitType: visitType,       // merged: recurse with same type
          acknowledgeOverlap: true,
        );
      }
    } on VisitException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Failed to save visit: $e');
    }
  }

  // ---------- Phase 3: Quick actions ----------
  Future<void> _markCompleted(String visitId) async {
    try {
      await _visitRepository.updateStatus(
          visitId, vmodel.VisitStatus.completed);
      ref.invalidate(visitsWithPatientsProvider);
    } catch (e) {
      _showError('Failed to mark completed: $e');
    }
  }

  Future<void> _cancelVisit(String visitId) async {
    try {
      await _visitRepository.cancelVisit(visitId);
      ref.invalidate(visitsWithPatientsProvider);
    } catch (e) {
      _showError('Failed to cancel: $e');
    }
  }

  Future<void> _deleteVisit(String visitId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Visit'),
        content: const Text('Are you sure you want to delete this visit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _visitRepository.softDeleteVisit(visitId);
      ref.invalidate(visitsWithPatientsProvider);
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  /// Opens a date + time picker pre-filled with the visit's current
  /// schedule, then hands off to [_performReschedule]. Used by both the
  /// "Visitations" and "Appointments" cards — rescheduling isn't
  /// specific to either booking type, it's just moving [Visit.scheduledStart].
  Future<void> _rescheduleVisit(String visitId) async {
    final existing = await _visitRepository.getVisit(visitId);
    if (!mounted) return;
    if (existing == null) {
      _showError('Could not find this visit.');
      return;
    }

    DateTime selectedDate = existing.scheduledStart;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(existing.scheduledStart);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 140, 188, 255),
              title:
                  const Text('Reschedule', style: AppColors.sectionHeading),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPickDateButton(context, selectedDate, (picked) {
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    }),
                    const SizedBox(height: 12),
                    _buildPickTimeButton(context, selectedTime, (picked) {
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: AppColors.bodyLarge),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Reschedule'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final newStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    await _performReschedule(visitId, newStart);
  }

  /// Calls [VisitRepository.rescheduleVisit], and — matching how
  /// [_saveVisit] handles a fresh booking — shows an overlap-confirm
  /// dialog and retries with `acknowledgeOverlap: true` if the doctor
  /// confirms, rather than silently blocking the reschedule.
  Future<void> _performReschedule(
    String visitId,
    DateTime newStart, {
    bool acknowledgeOverlap = false,
  }) async {
    try {
      await _visitRepository.rescheduleVisit(
        visitId,
        newStart: newStart,
        acknowledgeOverlap: acknowledgeOverlap,
      );
      if (!mounted) return;
      ref.invalidate(visitsWithPatientsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rescheduled successfully')),
      );
    } on VisitOverlapWarning catch (e) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color.fromARGB(255, 140, 188, 255),
          title: const Text(
            'Overlapping visit',
            style: AppColors.sectionHeading,
          ),
          content: Text(
            'This overlaps ${e.conflicts.length} existing visit(s) at this time. Reschedule anyway?',
            style: AppColors.bodyMedium.copyWith(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: AppColors.bodyLarge),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reschedule Anyway'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        await _performReschedule(visitId, newStart, acknowledgeOverlap: true);
      }
    } on VisitException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Failed to reschedule: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider that gives us all visits with their patient data
    final visitsAsync = ref.watch(visitsWithPatientsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Events', style: AppColors.pageHeading),
                  IconButton.filledTonal(
                    onPressed: () => AppointmentCalendarSheet.show(context),
                    icon: const Icon(Icons.calendar_month_rounded),
                    tooltip: 'Open Appointment Calendar',
                  ),
                ],
              ),

              // ---------- Upcoming Webinars section ----------
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Upcoming Webinars',
                    style: AppColors.pageHeading.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: _addOnlineSession,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.chartBarLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (onlineSessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    'No upcoming online sessions',
                    style: AppColors.bodyMedium,
                  ),
                )
              else
                ...onlineSessions.map(
                  (session) => _OnlineSessionCard(
                    session: session,
                    onTap: () => _launchUrl(session.link),
                  ),
                ),

              // ---------- Visitations / Appointments (swipeable, like
              // Instagram's Posts/Reels/Tagged profile tabs) ----------
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _categoryTabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorColor: AppColors.chartBarLight,
                      indicatorWeight: 3,
                      labelPadding: const EdgeInsets.only(right: 20),
                      labelColor: AppColors.textPrimary,
                      unselectedLabelColor:
                          AppColors.textSecondary.withValues(alpha: 0.5),
                      labelStyle: AppColors.pageHeading.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: AppColors.pageHeading.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: const [
                        Tab(text: 'Visitations'),
                        Tab(text: 'Appointments'),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _addVisit,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.chartBarLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              // CHANGED: pushed the card list further down (was height: 8)
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  controller: _categoryTabController,
                  children: [
                    // "Visitations" = home visits.
                    _buildVisitsList(
                      visitsAsync,
                      filterType: vmodel.VisitType.home,
                    ),
                    // "Appointments" = clinic bookings.
                    _buildVisitsList(
                      visitsAsync,
                      filterType: vmodel.VisitType.clinic,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds one swipeable tab's content: the same loading/error/data
  /// handling the old single "Upcoming Visits" list used, just filtered
  /// down to [filterType] (clinic vs. home) so "Visitations" and
  /// "Appointments" each show their own slice of the same underlying
  /// [visitsWithPatientsProvider] stream.
  Widget _buildVisitsList(
    AsyncValue<List<VisitWithPatient>> visitsAsync, {
    required vmodel.VisitType filterType,
  }) {
    return visitsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: AppColors.slateBlue,
        ),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(
              'Failed to load visits',
              style: AppColors.bodyLarge.copyWith(
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: AppColors.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(visitsWithPatientsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (visits) {
        final now = DateTime.now();
        // Filter: matching category, not yet ended, and has a valid patient.
        final upcoming = visits
            .where((vw) =>
                vw.patient != null &&
                vw.visit.visitType == filterType &&
                vw.visit.scheduledStart
                    .add(Duration(minutes: vw.visit.durationMinutes))
                    .isAfter(now))
            .toList()
          ..sort((a, b) =>
              a.visit.scheduledStart.compareTo(b.visit.scheduledStart));

        if (upcoming.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy,
                    color: AppColors.textSecondary, size: 48),
                const SizedBox(height: 12),
                Text(
                  filterType == vmodel.VisitType.home
                      ? 'No upcoming home visitations'
                      : 'No upcoming clinic appointments',
                  style: AppColors.bodyLarge,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          physics: const ClampingScrollPhysics(),
          // Horizontal inset so the two tabs' lists don't sit flush
          // against each other at the swipe boundary — without this,
          // dragging between "Visitations" and "Appointments" shows
          // the outgoing tab's last card touching the incoming tab's
          // first card with no gap.
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: upcoming.length,
          itemBuilder: (context, index) {
            final vw = upcoming[index];
            final visit = vw.visit;
            final patient = vw.patient!;

            // Format date strings for display
            final dateStr =
                '${visit.scheduledStart.day} ${_monthName(visit.scheduledStart.month)} ${visit.scheduledStart.year}';
            final dayStr = _dayName(visit.scheduledStart.weekday);
            final timeStr =
                '${visit.scheduledStart.hour.toString().padLeft(2, '0')}:${visit.scheduledStart.minute.toString().padLeft(2, '0')}';
            final durationLabel = '${visit.durationMinutes} min';

            // "Appointments" (clinic bookings) get their own card: no
            // map (there's nowhere to navigate to — it's always at the
            // clinic), but clinical patient context plus a live
            // countdown instead. "Visitations" (home visits) keep the
            // original VisitCard with its address/map preview.
            if (filterType == vmodel.VisitType.clinic) {
              return AppointmentCard(
                patientName: patient.fullName,
                age: patient.age,
                gender: patient.gender,
                condition: patient.diagnosisDisplay,
                date: dateStr,
                day: dayStr,
                time: timeStr,
                scheduledStart: visit.scheduledStart,
                scheduledEnd: visit.scheduledEnd,
                status: visit.status,
                onTap: () => showSessionDetailsSheet(context, vw),
                onReschedule: () => _rescheduleVisit(visit.id),
                onMarkCompleted: () => _markCompleted(visit.id),
                onCancel: () => _cancelVisit(visit.id),
                onDelete: () => _deleteVisit(visit.id),
              );
            }

            return VisitCard(
              patientName: patient.fullName,
              date: dateStr,
              day: dayStr,
              time: timeStr,
              duration: durationLabel,
              address: visit.address,
              latitude: visit.latitude,
              longitude: visit.longitude,
              mapsLink: visit.mapsLink,
              onMapTap: _launchUrl,
              // --- Phase 3 additions ---
              status: visit.status,
              visitType: visit.visitType,
              onTap: () => showSessionDetailsSheet(context, vw),
              onReschedule: () => _rescheduleVisit(visit.id),
              onMarkCompleted: () => _markCompleted(visit.id),
              onCancel: () => _cancelVisit(visit.id),
              onDelete: () => _deleteVisit(visit.id),
            );
          },
        );
      },
    );
  }
}

// ---------- ADD ONLINE SESSION SHEET ----------
class _OnlineSessionDraft {
  final String title;
  final DateTime date;
  final TimeOfDay time;
  final String link;

  const _OnlineSessionDraft({
    required this.title,
    required this.date,
    required this.time,
    required this.link,
  });
}

class _AddOnlineSessionSheet extends StatefulWidget {
  const _AddOnlineSessionSheet();

  @override
  State<_AddOnlineSessionSheet> createState() => _AddOnlineSessionSheetState();
}

class _AddOnlineSessionSheetState extends State<_AddOnlineSessionSheet> {
  final _titleController = TextEditingController();
  final _linkController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final link = _linkController.text.trim();
    if (title.isEmpty || link.isEmpty) return;

    Navigator.pop(
      context,
      _OnlineSessionDraft(
        title: title,
        date: _selectedDate,
        time: _selectedTime,
        link: link,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSheetHandle(),
            Text(
              'Add Online Session',
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            _buildTextField('Title', _titleController),
            const SizedBox(height: 12),
            _buildPickDateButton(context, _selectedDate, (picked) {
              if (picked != null) setState(() => _selectedDate = picked);
            }),
            const SizedBox(height: 12),
            _buildPickTimeButton(context, _selectedTime, (picked) {
              if (picked != null) setState(() => _selectedTime = picked);
            }),
            const SizedBox(height: 12),
            _buildTextField(
              'Meeting Link (URL)',
              _linkController,
              hint: 'https://meet.google.com/...',
            ),
            const SizedBox(height: 20),
            _buildSheetActions(
              context: context,
              onCancel: () => Navigator.pop(context),
              onSubmit: _submit,
              submitLabel: 'Add',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- ADD VISIT SHEET ----------
class _AddVisitSheet extends StatefulWidget {
  final PatientRepository patientRepository;
  const _AddVisitSheet({required this.patientRepository});

  @override
  State<_AddVisitSheet> createState() => _AddVisitSheetState();
}

class _AddVisitSheetState extends State<_AddVisitSheet> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mapsLinkController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  String _selectedDuration = '30 min';
  vmodel.VisitType _selectedType = vmodel.VisitType.clinic;   // merged: new toggle state

  Patient? _selectedPatient;
  List<Patient> _patientMatches = [];
  int _searchRequestId = 0;
  bool _isSearching = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _mapsLinkController.dispose();
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

    setState(() => _isSearching = true);

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

  // ---------- MODIFIED: address no longer required ----------
  void _submit() {
    // Only patient name is required
    if (_nameController.text.trim().isEmpty) {
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
        address: _addressController.text.trim(), // may be empty
        mapsLink: _mapsLinkController.text.trim().isEmpty
            ? null
            : _mapsLinkController.text.trim(),
        visitType: _selectedType,     // merged: pass selected type
      ),
    );
  }

  // ---------- Clinic Booking / Home Visitation toggle ----------
  Widget _buildVisitTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: vmodel.VisitType.values.map((type) {
          final selected = type == _selectedType;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      selected ? AppColors.chartBarLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  type == vmodel.VisitType.clinic
                      ? 'Clinic Booking'
                      : 'Home Visitation',
                  style: AppColors.bodyMedium.copyWith(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visiblePatientMatches =
        _patientMatches.take(5).toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSheetHandle(),
            Text(
              'Add Visit',
              style: AppColors.sectionHeading.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            _buildVisitTypeToggle(),
            const SizedBox(height: 12),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.chartBarDim.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0;
                        i < visiblePatientMatches.length;
                        i++) ...[
                      ListTile(
                        dense: true,
                        title: Text(
                          visiblePatientMatches[i].fullName,
                          style: AppColors.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          visiblePatientMatches[i].phone,
                          style: AppColors.bodySmall,
                        ),
                        onTap: () =>
                            _selectPatient(visiblePatientMatches[i]),
                      ),
                      if (i != visiblePatientMatches.length - 1)
                        Divider(
                          height: 1,
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.12),
                        ),
                    ],
                    if (_patientMatches.length >
                        visiblePatientMatches.length)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Text(
                          'Showing first ${visiblePatientMatches.length} matches. Keep typing to narrow results.',
                          style: AppColors.bodySmall.copyWith(
                            color: AppColors.textSecondary,
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
                  'No matching patient — add them in Patient Records first.',
                  style: AppColors.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
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
            _buildTextField(
              _selectedType == vmodel.VisitType.home
                  ? 'Home Address'
                  : 'Clinic Address (optional)',
              _addressController,
              hint: _selectedType == vmodel.VisitType.home
                  ? "Patient's home address"
                  : 'Clinic address',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              'Google Maps Link (optional)',
              _mapsLinkController,
              hint: 'https://maps.google.com/...',
            ),
            const SizedBox(height: 20),
            _buildSheetActions(
              context: context,
              onCancel: () => Navigator.pop(context),
              onSubmit: _submit,
              submitLabel: 'Add',
            ),
          ],
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
                  style: AppColors.sectionHeading.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.date}  •  ${session.time}',
                  style: AppColors.bodySmall,
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