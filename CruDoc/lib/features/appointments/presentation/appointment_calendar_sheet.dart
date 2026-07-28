import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

enum CalendarViewMode { timeGrid, monthGrid }

/// Representation of a timed event item for the time-grid view.
class _TimeGridEvent {
  final String id;
  final String patientName;
  final String? procedure;
  final DateTime startTime;
  final int durationMinutes;
  final Color backgroundColor;
  final Color borderColor;
  final VisitWithPatient? visitWithPatient;

  const _TimeGridEvent({
    required this.id,
    required this.patientName,
    this.procedure,
    required this.startTime,
    required this.durationMinutes,
    required this.backgroundColor,
    required this.borderColor,
    this.visitWithPatient,
  });
}

/// Representation of an event item for the month grid view.
class _CalendarEvent {
  final String id;
  final String title;
  final String category;
  final Color backgroundColor;
  final Color textColor;
  final DateTime date;
  final VisitWithPatient? visitWithPatient;

  const _CalendarEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.backgroundColor,
    required this.textColor,
    required this.date,
    this.visitWithPatient,
  });
}

class AppointmentCalendarSheet extends ConsumerStatefulWidget {
  const AppointmentCalendarSheet({super.key});

  /// Static helper to display the calendar as a full-page screen.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AppointmentCalendarSheet(),
      ),
    );
  }

  @override
  ConsumerState<AppointmentCalendarSheet> createState() =>
      _AppointmentCalendarSheetState();
}

class _AppointmentCalendarSheetState
    extends ConsumerState<AppointmentCalendarSheet> {
  CalendarViewMode _viewMode = CalendarViewMode.timeGrid;
  late DateTime _selectedDate;
  late final ScrollController _timeGridScrollController;
  bool _initializedDatePosition = false;

  static const double _hourRowHeight = 64.0;
  static const int _startHour = 6; // 6 AM
  static const int _endHour = 23;  // 11 PM

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    // Initial scroll offset near 9 AM
    final initialOffset = (9 - _startHour) * _hourRowHeight;
    _timeGridScrollController = ScrollController(
      initialScrollOffset: initialOffset.clamp(0.0, 1000.0),
    );
  }

  @override
  void dispose() {
    _timeGridScrollController.dispose();
    super.dispose();
  }

  void _previousPeriod() {
    setState(() {
      if (_viewMode == CalendarViewMode.timeGrid) {
        _selectedDate = _selectedDate.subtract(const Duration(days: 3));
      } else {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      if (_viewMode == CalendarViewMode.timeGrid) {
        _selectedDate = _selectedDate.add(const Duration(days: 3));
      } else {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      }
    });
  }

  void _goToToday() {
    setState(() {
      final now = DateTime.now();
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  // --- TIME GRID DATA ---
  List<_TimeGridEvent> _getTimeGridEvents(
      List<DateTime> visibleDays, List<VisitWithPatient> realVisits) {
    final list = <_TimeGridEvent>[];

    // 1. Convert ALL real database visits
    for (final vp in realVisits) {
      final v = vp.visit;
      final name = vp.patient?.fullName ?? 'Patient';
      final isHome = v.visitType == VisitType.home;

      Color bg;
      Color border;
      if (v.status == VisitStatus.completed) {
        bg = const Color(0xFF16A34A); // Green for completed
        border = const Color(0xFF14532D);
      } else if (v.status == VisitStatus.cancelled ||
          v.status == VisitStatus.missed) {
        bg = const Color(0xFFEF6C57); // Coral for cancelled
        border = const Color(0xFF7F1D1D);
      } else {
        bg = isHome ? const Color(0xFFEF6C57) : const Color(0xFF00897B);
        border = const Color(0xFF064E3B);
      }

      list.add(
        _TimeGridEvent(
          id: v.id,
          patientName: name,
          procedure: isHome ? 'Home Visit' : 'Clinic Visit',
          startTime: v.scheduledStart,
          durationMinutes: v.durationMinutes > 0 ? v.durationMinutes : 45,
          backgroundColor: bg,
          borderColor: border,
          visitWithPatient: vp,
        ),
      );
    }

    // 2. Add sample events ONLY if no real visits exist in the database
    if (realVisits.isEmpty && visibleDays.length >= 3) {
      final sat = visibleDays[0];
      final sun = visibleDays[1];
      final mon = visibleDays[2];

      const teal = Color(0xFF00897B);
      const coral = Color(0xFFEF6C57);
      const border = Color(0xFF6B1D2F);

      list.addAll([
        _TimeGridEvent(
          id: 's_vinay',
          patientName: 'Vinay',
          startTime: DateTime(mon.year, mon.month, mon.day, 17, 0),
          durationMinutes: 45,
          backgroundColor: coral,
          borderColor: border,
        ),
        _TimeGridEvent(
          id: 's_bhargav',
          patientName: 'Bhargav',
          startTime: DateTime(mon.year, mon.month, mon.day, 17, 30),
          durationMinutes: 45,
          backgroundColor: teal,
          borderColor: border,
        ),
        _TimeGridEvent(
          id: 's_siddharth',
          patientName: 'Dr Siddharth N...',
          startTime: DateTime(sat.year, sat.month, sat.day, 19, 0),
          durationMinutes: 40,
          backgroundColor: teal,
          borderColor: border,
        ),
        _TimeGridEvent(
          id: 's_ashish',
          patientName: 'Dr Ashish',
          startTime: DateTime(sat.year, sat.month, sat.day, 19, 45),
          durationMinutes: 40,
          backgroundColor: teal,
          borderColor: border,
        ),
        _TimeGridEvent(
          id: 's_sanjay',
          patientName: 'Sanjay AAA',
          startTime: DateTime(sat.year, sat.month, sat.day, 21, 0),
          durationMinutes: 45,
          backgroundColor: teal,
          borderColor: border,
        ),
        _TimeGridEvent(
          id: 's_priya',
          patientName: 'Priya Rajput',
          procedure: 'RCT',
          startTime: DateTime(sun.year, sun.month, sun.day, 20, 0),
          durationMinutes: 50,
          backgroundColor: teal,
          borderColor: border,
        ),
      ]);
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visitsAsync = ref.watch(allVisitsWithPatientsProvider);
    final realVisits = visitsAsync.value ?? [];

    // Auto-center calendar on the date of the scheduled visit if present
    if (!_initializedDatePosition && realVisits.isNotEmpty) {
      _initializedDatePosition = true;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final upcoming = realVisits
          .where((v) => !v.visit.scheduledStart.isBefore(todayStart))
          .toList();
      final targetList = upcoming.isNotEmpty ? upcoming : realVisits;
      targetList.sort((a, b) => a.visit.scheduledStart.compareTo(b.visit.scheduledStart));
      final targetDate = targetList.first.visit.scheduledStart;
      _selectedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    }

    return ShellBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Top Header & Period Controls (Theme matched & Non-overflowing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                    child: Column(
                      children: [
                        // Row 1: Back Arrow + Title + Today Button
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.black87),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _viewMode == CalendarViewMode.timeGrid
                                    ? 'Schedule'
                                    : '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
                                style: const TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: _goToToday,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.accentBlue,
                              ),
                              child: const Text('Today'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Row 2: Navigation Arrows (< >) + View Switcher (Time Grid | Month)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.chevron_left, size: 20),
                                  onPressed: _previousPeriod,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 6),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.chevron_right, size: 20),
                                  onPressed: _nextPeriod,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  _ViewToggleButton(
                                    label: 'Time Grid',
                                    isSelected: _viewMode == CalendarViewMode.timeGrid,
                                    onTap: () => setState(
                                      () => _viewMode = CalendarViewMode.timeGrid,
                                    ),
                                  ),
                                  _ViewToggleButton(
                                    label: 'Month',
                                    isSelected: _viewMode == CalendarViewMode.monthGrid,
                                    onTap: () => setState(
                                      () => _viewMode = CalendarViewMode.monthGrid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Main View Content
                  Expanded(
                    child: _viewMode == CalendarViewMode.timeGrid
                        ? _buildTimeGridView(realVisits)
                        : _buildMonthGridView(realVisits),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 1. TIME GRID VIEW ====================
  Widget _buildTimeGridView(List<VisitWithPatient> realVisits) {
    final baseDate = _selectedDate;
    final visibleDays = [
      baseDate,
      baseDate.add(const Duration(days: 1)),
      baseDate.add(const Duration(days: 2)),
    ];

    final events = _getTimeGridEvents(visibleDays, realVisits);

    return Column(
      children: [
        // Top Day Header Bar (Grey Background, Underlined Header Text)
        Container(
          color: const Color(0xFFEEEEEE),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 60),
              ...visibleDays.map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      '${_getDayAbbr(day.weekday)} ${day.day}/${_getMonthAbbr(day.month)}',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF424242),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFE0E0E0)),

        // Hourly Time Grid Body
        Expanded(
          child: SingleChildScrollView(
            controller: _timeGridScrollController,
            child: SizedBox(
              height: (_endHour - _startHour + 1) * _hourRowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Time Axis Column
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: List.generate(
                        _endHour - _startHour + 1,
                        (index) {
                          final hour = _startHour + index;
                          return SizedBox(
                            height: _hourRowHeight,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  _formatHourLabel(hour),
                                  style: const TextStyle(
                                    fontFamily: AppColors.bodyFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF757575),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Day Columns Grid Area
                  Expanded(
                    child: Stack(
                      children: [
                        // Background Horizontal Grid Lines
                        Column(
                          children: List.generate(
                            _endHour - _startHour + 1,
                            (index) => Container(
                              height: _hourRowHeight,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Color(0xFFEEEEEE),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Vertical Column Dividers
                        Row(
                          children: List.generate(
                            visibleDays.length,
                            (index) => Expanded(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Color(0xFFEEEEEE),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Positioned Appointment Blocks/Cards
                        ..._buildPositionedTimeEvents(visibleDays, events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPositionedTimeEvents(
      List<DateTime> visibleDays, List<_TimeGridEvent> events) {
    final widgets = <Widget>[];

    for (int dayIdx = 0; dayIdx < visibleDays.length; dayIdx++) {
      final day = visibleDays[dayIdx];

      final dayEvents = events.where((e) {
        return e.startTime.year == day.year &&
            e.startTime.month == day.month &&
            e.startTime.day == day.day;
      }).toList();

      dayEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

      final slots = <List<_TimeGridEvent>>[];
      for (final ev in dayEvents) {
        bool added = false;
        for (final slot in slots) {
          if (slot.any((e) => (ev.startTime.difference(e.startTime).inMinutes).abs() < 25)) {
            slot.add(ev);
            added = true;
            break;
          }
        }
        if (!added) {
          slots.add([ev]);
        }
      }

      for (final slot in slots) {
        final count = slot.length;
        for (int i = 0; i < count; i++) {
          final ev = slot[i];
          final startMinutesFromBase =
              ((ev.startTime.hour - _startHour) * 60 + ev.startTime.minute)
                  .clamp(0, (24 - _startHour) * 60);
          final topOffset = (startMinutesFromBase / 60.0) * _hourRowHeight;
          final height = (ev.durationMinutes / 60.0) * _hourRowHeight;

          final leftPercent = (dayIdx + (i / count)) / visibleDays.length;
          final widthPercent = (1.0 / visibleDays.length) / count;

          widgets.add(
            Positioned(
              top: topOffset,
              height: height.clamp(44.0, 140.0),
              left: (MediaQuery.of(context).size.width - 60) * leftPercent,
              width: (MediaQuery.of(context).size.width - 60) * widthPercent - 2,
              child: GestureDetector(
                onTap: () {
                  if (ev.visitWithPatient != null) {
                    showSessionDetailsSheet(context, ev.visitWithPatient!);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: ev.backgroundColor,
                    border: Border.all(color: ev.borderColor, width: 1.2),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final showProcedure = constraints.maxHeight >= 38.0 &&
                          ev.procedure != null &&
                          ev.procedure!.isNotEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ev.patientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppColors.bodyFontFamily,
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                          if (showProcedure)
                            Text(
                              ev.procedure!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppColors.bodyFontFamily,
                                color: Colors.white70,
                                fontSize: 9.5,
                                height: 1.1,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  // ==================== 2. MONTH GRID VIEW ====================
  Widget _buildMonthGridView(List<VisitWithPatient> realVisits) {
    final monthEvents = _getMonthEvents(realVisits);

    final firstDayOfMonth =
        DateTime(_selectedDate.year, _selectedDate.month, 1);
    final daysInMonth =
        DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final startingWeekday = firstDayOfMonth.weekday % 7;

    final totalGridCells = startingWeekday + daysInMonth;
    final totalRows = (totalGridCells / 7).ceil();

    return Column(
      children: [
        Container(
          color: const Color(0xFFFAFAFA),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: const Row(
            children: [
              _WeekdayHeader('SUN'),
              _WeekdayHeader('MON'),
              _WeekdayHeader('TUE'),
              _WeekdayHeader('WED'),
              _WeekdayHeader('THUR'),
              _WeekdayHeader('FRI'),
              _WeekdayHeader('SAT'),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            itemCount: totalRows * 7,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) {
              final dayOffset = index - startingWeekday;
              final isCurrentMonthDay =
                  dayOffset >= 0 && dayOffset < daysInMonth;

              if (!isCurrentMonthDay) {
                return Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFFF1F5F9), width: 0.5),
                    color: const Color(0xFFFAFAFA),
                  ),
                );
              }

              final dayNumber = dayOffset + 1;
              final dateOfCell = DateTime(
                  _selectedDate.year, _selectedDate.month, dayNumber);
              final isToday = _isSameDate(dateOfCell, DateTime.now());

              final dayEvents = monthEvents
                  .where((e) => _isSameDate(e.date, dateOfCell))
                  .toList();

              return Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
                  color: isToday ? const Color(0xFFF0F9FF) : Colors.white,
                ),
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.w800 : FontWeight.w700,
                        color:
                            isToday ? AppColors.accentBlue : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: dayEvents.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, evIdx) {
                          final event = dayEvents[evIdx];
                          return InkWell(
                            onTap: () {
                              if (event.visitWithPatient != null) {
                                showSessionDetailsSheet(
                                  context,
                                  event.visitWithPatient!,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: event.backgroundColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                event.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppColors.bodyFontFamily,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: event.textColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_CalendarEvent> _getMonthEvents(List<VisitWithPatient> visits) {
    final events = <_CalendarEvent>[];
    for (final vp in visits) {
      final v = vp.visit;
      final name = vp.patient?.fullName ?? 'Patient';
      final isHome = v.visitType == VisitType.home;
      final cat = '$name (${isHome ? "Home" : "Clinic"})';

      events.add(
        _CalendarEvent(
          id: v.id,
          title: cat,
          category: cat,
          backgroundColor:
              isHome ? const Color(0xFFFFEDD5) : const Color(0xFFE0F2FE),
          textColor:
              isHome ? const Color(0xFFEA580C) : const Color(0xFF0284C7),
          date: DateTime(
            v.scheduledStart.year,
            v.scheduledStart.month,
            v.scheduledStart.day,
          ),
          visitWithPatient: vp,
        ),
      );
    }
    return events;
  }

  // --- HELPER FORMATTERS ---
  String _getDayAbbr(int weekday) {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THUR', 'FRI', 'SAT'];
    return days[weekday % 7];
  }

  String _getMonthAbbr(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  String _getMonthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  String _formatHourLabel(int hour) {
    if (hour == 12) return '12 PM';
    if (hour > 12) return '${hour - 12} PM';
    return '$hour AM';
  }

  bool _isSameDate(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }
}

class _ViewToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewToggleButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.accentBlue : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  const _WeekdayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
