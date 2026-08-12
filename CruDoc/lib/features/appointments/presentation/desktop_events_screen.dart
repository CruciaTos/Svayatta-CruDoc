import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Desktop version of the Appointments & Events tab.
///
/// The calendar is backed by live visit providers instead of static demo data,
/// so desktop reflects local writes and Firebase-backed updates immediately.
class DesktopEventsScreen extends StatelessWidget {
  const DesktopEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: const SingleChildScrollView(child: _CalendarDashboardView()),
      ),
    );
  }
}

class _CalendarEvent {
  final VisitWithPatient item;

  const _CalendarEvent(this.item);

  Visit get visit => item.visit;

  String get title {
    final treatment = visit.treatmentType?.trim();
    if (treatment != null && treatment.isNotEmpty) return treatment;
    return visit.visitType == VisitType.home
        ? 'Home visitation'
        : 'Clinic appointment';
  }

  String get patientName {
    final name = item.patient?.fullName.trim() ?? '';
    return name.isEmpty ? 'Unknown patient' : name;
  }

  String get patientPhone => item.patient?.phone.trim() ?? '';

  String get address {
    final rawAddress = visit.address.trim();
    if (rawAddress.isNotEmpty) return rawAddress;
    return visit.visitType == VisitType.home
        ? 'Patient home address not set'
        : 'Clinic address not set';
  }

  String get pillType {
    switch (visit.status) {
      case VisitStatus.cancelled:
      case VisitStatus.missed:
        return 'red';
      case VisitStatus.completed:
        return 'white';
      case VisitStatus.scheduled:
        return visit.visitType == VisitType.home ? 'purple' : 'red';
    }
  }

  String get statusLabel {
    switch (visit.status) {
      case VisitStatus.scheduled:
        return 'Scheduled';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.cancelled:
        return 'Cancelled';
      case VisitStatus.missed:
        return 'Missed';
    }
  }

  IconData get statusIcon {
    switch (visit.status) {
      case VisitStatus.scheduled:
        return Icons.event_available_rounded;
      case VisitStatus.completed:
        return Icons.check_circle_rounded;
      case VisitStatus.cancelled:
        return Icons.cancel_rounded;
      case VisitStatus.missed:
        return Icons.error_rounded;
    }
  }

  Color get statusColor {
    switch (visit.status) {
      case VisitStatus.scheduled:
        return const Color(0xFF7C3AED);
      case VisitStatus.completed:
        return const Color(0xFF10B981);
      case VisitStatus.cancelled:
      case VisitStatus.missed:
        return const Color(0xFFDC2626);
    }
  }
}

class _CalendarDashboardView extends ConsumerStatefulWidget {
  const _CalendarDashboardView();

  @override
  ConsumerState<_CalendarDashboardView> createState() =>
      _CalendarDashboardViewState();
}

class _CalendarDashboardViewState
    extends ConsumerState<_CalendarDashboardView> {
  late int _year;
  late int _month;
  String? _hoveredDateKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _changeMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month > 12) {
        _month = 1;
        _year++;
      } else if (_month < 1) {
        _month = 12;
        _year--;
      }
      _hoveredDateKey = null;
    });
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
      'December',
    ];
    return months[month - 1];
  }

  Map<String, List<_CalendarEvent>> _groupEvents(
    List<VisitWithPatient> visits,
  ) {
    final events = visits.map(_CalendarEvent.new).toList()
      ..sort(
        (a, b) => a.visit.scheduledStart.compareTo(b.visit.scheduledStart),
      );

    final grouped = <String, List<_CalendarEvent>>{};
    for (final event in events) {
      grouped
          .putIfAbsent(_dateKey(event.visit.scheduledStart), () => [])
          .add(event);
    }
    return grouped;
  }

  List<Map<String, dynamic>> _generateCalendarData(
    int year,
    int month,
    Map<String, List<_CalendarEvent>> eventsData,
  ) {
    final weeks = <Map<String, dynamic>>[];
    final firstDayOfMonth = DateTime(year, month);
    final offset = firstDayOfMonth.weekday == DateTime.sunday
        ? 6
        : firstDayOfMonth.weekday - 1;
    final startDate = firstDayOfMonth.subtract(Duration(days: offset));
    final today = DateTime.now();

    for (var i = 0; i < 42; i++) {
      final currentDate = startDate.add(Duration(days: i));
      final dateKey = _dateKey(currentDate);
      final isCurrentMonth =
          currentDate.year == year && currentDate.month == month;

      weeks.add({
        'day': currentDate.day.toString(),
        'dateKey': dateKey,
        'isPrev': currentDate.isBefore(firstDayOfMonth),
        'isNext': !isCurrentMonth && !currentDate.isBefore(firstDayOfMonth),
        'isCurrentMonth': isCurrentMonth,
        'isSelected': _isSameDate(currentDate, today),
        'events': eventsData[dateKey] ?? const <_CalendarEvent>[],
      });
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final visitsAsync = ref.watch(allVisitsWithPatientsProvider);

    return visitsAsync.when(
      loading: () => _buildCalendar(
        eventsData: const <String, List<_CalendarEvent>>{},
        isLoading: true,
      ),
      error: (error, _) => _buildCalendar(
        eventsData: const <String, List<_CalendarEvent>>{},
        error: error,
      ),
      data: (visits) => _buildCalendar(eventsData: _groupEvents(visits)),
    );
  }

  Widget _buildCalendar({
    required Map<String, List<_CalendarEvent>> eventsData,
    bool isLoading = false,
    Object? error,
  }) {
    final calendarDays = _generateCalendarData(_year, _month, eventsData);
    final hoveredEvents = _hoveredDateKey == null
        ? null
        : eventsData[_hoveredDateKey];

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CalendarHeader(
              monthText: '${_getMonthName(_month)} $_year',
              onPrev: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
            ),
            const SizedBox(height: 12),
            if (isLoading) const LinearProgressIndicator(minHeight: 2),
            if (error != null)
              _CalendarMessage(
                icon: Icons.cloud_off_rounded,
                color: const Color(0xFFDC2626),
                text: 'Could not load live appointments: $error',
              ),
            const SizedBox(height: 12),
            _CalendarGrid(
              calendarDays: calendarDays,
              onDayHover: (dateKey) {
                setState(() => _hoveredDateKey = dateKey);
              },
            ),
            if (!isLoading && error == null && eventsData.isEmpty)
              const _CalendarMessage(
                icon: Icons.event_busy_rounded,
                color: Color(0xFF6B7280),
                text: 'No appointments or visitations scheduled yet.',
              ),
          ],
        ),
        if (hoveredEvents != null && hoveredEvents.isNotEmpty)
          Positioned(
            top: 92,
            right: 40,
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: _EventPopupCard(
                event: hoveredEvents.first,
                additionalCount: hoveredEvents.length - 1,
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _CalendarMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  final String monthText;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _CalendarHeader({
    required this.monthText,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            InkWell(
              onTap: onPrev,
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              monthText,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onNext,
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () => _showDemoDialog(context, 'Search functionality'),
              icon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: Color(0xFF6B7280),
              ),
            ),
            IconButton(
              onPressed: () =>
                  _showDemoDialog(context, 'Filter & tune options'),
              icon: const Icon(
                Icons.tune_rounded,
                size: 20,
                color: Color(0xFF6B7280),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: () =>
                    _showDemoDialog(context, 'Monthly dropdown clicked'),
                child: const Row(
                  children: [
                    Text(
                      'Monthly',
                      style: TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _showDemoDialog(context, 'More options'),
              icon: const Icon(
                Icons.more_horiz,
                size: 20,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDemoDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feature Demo'),
        content: Text('You clicked: $message'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final List<Map<String, dynamic>> calendarDays;
  final ValueChanged<String?> onDayHover;

  const _CalendarGrid({required this.calendarDays, required this.onDayHover});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            _WeekdayHeader(label: 'Mon'),
            _WeekdayHeader(label: 'Tue'),
            _WeekdayHeader(label: 'Wed'),
            _WeekdayHeader(label: 'Thu'),
            _WeekdayHeader(label: 'Fri'),
            _WeekdayHeader(label: 'Sat'),
            _WeekdayHeader(label: 'Sun'),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: List.generate(6, (rowIndex) {
            final startIndex = rowIndex * 7;
            final weekData = calendarDays.sublist(startIndex, startIndex + 7);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: weekData.map((data) {
                  final events =
                      (data['events'] as List<_CalendarEvent>?) ??
                      const <_CalendarEvent>[];
                  final hasEvents = events.isNotEmpty;
                  return Expanded(
                    child: _DayCell(
                      data: data,
                      isHoverTarget: hasEvents,
                      onHover: hasEvents ? onDayHover : null,
                    ),
                  );
                }).toList(),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;

  const _WeekdayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isHoverTarget;
  final ValueChanged<String?>? onHover;

  const _DayCell({
    required this.data,
    this.isHoverTarget = false,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final day = data['day'] as String;
    final isCurrentMonth = data['isCurrentMonth'] as bool? ?? false;
    final isSelected = data['isSelected'] as bool? ?? false;
    final events =
        (data['events'] as List<_CalendarEvent>?) ?? const <_CalendarEvent>[];
    final visibleEvents = events.take(3).toList(growable: false);
    final overflowCount = events.length - visibleEvents.length;

    var textColor = Colors.grey[400]!;
    if (isCurrentMonth) textColor = const Color(0xFF1F2937);
    if (isSelected) textColor = const Color(0xFF7C3AED);

    final cellContent = Container(
      height: 110,
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF3E8FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(color: const Color(0xFF7C3AED), width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(
              day,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ...visibleEvents.map(
            (event) => _EventPill(title: event.title, type: event.pillType),
          ),
          if (overflowCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Text(
                '+$overflowCount more',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
        ],
      ),
    );

    if (!isHoverTarget) return cellContent;

    return MouseRegion(
      onEnter: (_) => onHover?.call(data['dateKey'] as String),
      onExit: (_) => onHover?.call(null),
      child: cellContent,
    );
  }
}

class _EventPill extends StatelessWidget {
  final String title;
  final String type;

  const _EventPill({required this.title, required this.type});

  @override
  Widget build(BuildContext context) {
    late final Color bgColor;
    late final Color iconColor;
    late final Color textColor;

    if (type == 'red') {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFF991B1B);
      iconColor = const Color(0xFFDC2626);
    } else if (type == 'purple') {
      bgColor = const Color(0xFFEDE9FE);
      textColor = const Color(0xFF6D28D9);
      iconColor = const Color(0xFF7C3AED);
    } else {
      bgColor = Colors.grey[100]!;
      textColor = const Color(0xFF374151);
      iconColor = const Color(0xFF6B7280);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: iconColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventPopupCard extends StatelessWidget {
  final _CalendarEvent event;
  final int additionalCount;

  const _EventPopupCard({required this.event, required this.additionalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: event.visit.visitType == VisitType.home
                    ? const Color(0xFFEDE9FE)
                    : const Color(0xFFFEE2E2),
                child: Text(
                  _initials(event.patientName),
                  style: TextStyle(
                    color: event.visit.visitType == VisitType.home
                        ? const Color(0xFF6D28D9)
                        : const Color(0xFF991B1B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.patientName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(event.statusIcon, size: 12, color: event.statusColor),
                    const SizedBox(width: 4),
                    Text(
                      event.statusLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.access_time_rounded,
            text: _formatVisitRange(event.visit),
          ),
          const SizedBox(height: 8),
          _DetailRow(icon: Icons.location_on_outlined, text: event.address),
          if (event.patientPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(icon: Icons.phone_outlined, text: event.patientPhone),
          ],
          if (additionalCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              '+$additionalCount more visit${additionalCount == 1 ? '' : 's'} on this day',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: const Text(
                'Live appointment data',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
        ),
      ],
    );
  }
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatVisitRange(Visit visit) {
  final date = DateFormat('EEE, d MMM').format(visit.scheduledStart);
  final start = DateFormat('h:mm a').format(visit.scheduledStart);
  final end = DateFormat('h:mm a').format(visit.scheduledEnd);
  return '$date • $start - $end';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty || name == 'Unknown patient') return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
