import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_flow.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/providers/whatsapp_providers.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';

/// Available calendar viewing modes
enum CalendarViewMode { month, week, day, agenda }

/// Desktop version of the Appointments & Events tab.
/// Backed by live visit providers, with support for Month, Week (hourly),
/// Day (hourly), and Agenda (sticky headers) views.
class DesktopEventsScreen extends StatelessWidget {
  const DesktopEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
            ),
            padding: const EdgeInsets.all(20),
            child: const _CalendarDashboardView(),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// EVENT MODEL
// ==============================================================================

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

// ==============================================================================
// MAIN CALENDAR DASHBOARD VIEW
// ==============================================================================

class _CalendarDashboardView extends ConsumerStatefulWidget {
  const _CalendarDashboardView();

  @override
  ConsumerState<_CalendarDashboardView> createState() =>
      _CalendarDashboardViewState();
}

class _CalendarDashboardViewState
    extends ConsumerState<_CalendarDashboardView> {
  CalendarViewMode _viewMode = CalendarViewMode.month;
  late DateTime _anchorDate;
  late DateTime _baseDate;
  static const int _initialPage = 1200;
  late PageController _pageController;

  bool _isSearchExpanded = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  VisitStatus? _statusFilter;
  double _visibleHours = 12.0;

  // Gesture scaling helper for pinch-to-zoom
  DateTime _lastPinchTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.now();
    _anchorDate = DateTime.now();
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DateTime _getDateForPage(int pageIndex) {
    final delta = pageIndex - _initialPage;
    final normBase = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    switch (_viewMode) {
      case CalendarViewMode.month:
      case CalendarViewMode.agenda:
        return DateTime(normBase.year, normBase.month + delta, 1);
      case CalendarViewMode.week:
        return normBase.add(Duration(days: delta * 7));
      case CalendarViewMode.day:
        return normBase.add(Duration(days: delta));
    }
  }

  int _getPageForDate(DateTime date) {
    final normDate = DateTime(date.year, date.month, date.day);
    final normBase = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    switch (_viewMode) {
      case CalendarViewMode.month:
      case CalendarViewMode.agenda:
        final diff =
            (normDate.year - normBase.year) * 12 +
            (normDate.month - normBase.month);
        return _initialPage + diff;
      case CalendarViewMode.week:
        final diff = normDate.difference(normBase).inDays ~/ 7;
        return _initialPage + diff;
      case CalendarViewMode.day:
        final diff = normDate.difference(normBase).inDays;
        return _initialPage + diff;
    }
  }

  void _onViewModeChanged(CalendarViewMode mode) {
    if (_viewMode == mode) return;
    setState(() {
      final now = DateTime.now();
      // If switching to Day or Week view and anchor was at start of month,
      // land on today so the user immediately sees current appointments
      if ((mode == CalendarViewMode.day || mode == CalendarViewMode.week) &&
          _anchorDate.year == now.year &&
          _anchorDate.month == now.month) {
        _anchorDate = DateTime(now.year, now.month, now.day);
      }
      _viewMode = mode;
      _baseDate = DateTime(
        _anchorDate.year,
        _anchorDate.month,
        _anchorDate.day,
      );
      _pageController.dispose();
      _pageController = PageController(initialPage: _initialPage);
    });
  }

  void _onPageChanged(int pageIndex) {
    final newDate = _getDateForPage(pageIndex);
    setState(() {
      _anchorDate = newDate;
    });
  }

  void _navigate(int delta) {
    if (_pageController.hasClients) {
      final currentPage = _pageController.page?.round() ?? _initialPage;
      _pageController.animateToPage(
        currentPage + delta,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() => _anchorDate = today);
    final targetPage = _getPageForDate(today);
    if (_pageController.hasClients) {
      if (targetPage == (_pageController.page?.round() ?? _initialPage)) {
        return;
      }
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _jumpToDate(DateTime date) {
    final targetPage = _getPageForDate(date);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      setState(() => _anchorDate = date);
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  Future<void> _createNewAppointment() async {
    await promptScheduleVisit(
      context,
      pickerTitle: 'Schedule an appointment for',
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final now = DateTime.now();
    // 2-finger pinch gesture for zoom in / zoom out
    if (details.pointerCount >= 2) {
      if (now.difference(_lastPinchTime).inMilliseconds < 250) return;

      // When in Week or Day mode, pinch adjusts hour zoom
      if (_viewMode == CalendarViewMode.week ||
          _viewMode == CalendarViewMode.day) {
        if (details.scale > 1.08 && _visibleHours > 4.0) {
          setState(() {
            _visibleHours = math.max(4.0, _visibleHours - 1.0);
          });
          _lastPinchTime = now;
          return;
        } else if (details.scale < 0.92 && _visibleHours < 12.0) {
          setState(() {
            _visibleHours = math.min(12.0, _visibleHours + 1.0);
          });
          _lastPinchTime = now;
          return;
        }
      }

      if (details.scale > 1.35) {
        // Zoom in: Month -> Week -> Day
        if (_viewMode == CalendarViewMode.month) {
          _onViewModeChanged(CalendarViewMode.week);
          _lastPinchTime = now;
        } else if (_viewMode == CalendarViewMode.week) {
          _onViewModeChanged(CalendarViewMode.day);
          _lastPinchTime = now;
        }
      } else if (details.scale < 0.68) {
        // Zoom out: Day -> Week -> Month
        if (_viewMode == CalendarViewMode.day) {
          _onViewModeChanged(CalendarViewMode.week);
          _lastPinchTime = now;
        } else if (_viewMode == CalendarViewMode.week) {
          _onViewModeChanged(CalendarViewMode.month);
          _lastPinchTime = now;
        }
      }
    }
  }

  List<VisitWithPatient> _applyFilters(List<VisitWithPatient> visits) {
    var result = visits;

    if (_statusFilter != null) {
      result = result.where((v) => v.visit.status == _statusFilter).toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((v) {
        final patientName = v.patient?.fullName.toLowerCase() ?? '';
        final treatment = v.visit.treatmentType?.toLowerCase() ?? '';
        return patientName.contains(query) || treatment.contains(query);
      }).toList();
    }

    return result;
  }

  String _getHeaderTitle() {
    switch (_viewMode) {
      case CalendarViewMode.month:
        return DateFormat('MMMM yyyy').format(_anchorDate);
      case CalendarViewMode.week:
        final firstDayOfWeek = _anchorDate.subtract(
          Duration(days: _anchorDate.weekday - 1),
        );
        final lastDayOfWeek = firstDayOfWeek.add(const Duration(days: 6));
        if (firstDayOfWeek.month == lastDayOfWeek.month) {
          return '${DateFormat('MMM d').format(firstDayOfWeek)} – ${DateFormat('d, yyyy').format(lastDayOfWeek)}';
        }
        return '${DateFormat('MMM d').format(firstDayOfWeek)} – ${DateFormat('MMM d, yyyy').format(lastDayOfWeek)}';
      case CalendarViewMode.day:
        return DateFormat('EEEE, MMMM d, yyyy').format(_anchorDate);
      case CalendarViewMode.agenda:
        return 'Agenda • ${DateFormat('MMMM yyyy').format(_anchorDate)}';
    }
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
      final localDate = event.visit.scheduledStart.toLocal();
      grouped.putIfAbsent(_dateKey(localDate), () => []).add(event);
    }
    return grouped;
  }

  List<Map<String, dynamic>> _generateMonthData(
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
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final totalDays = (offset + daysInMonth) > 35 ? 42 : 35;
    final today = DateTime.now();

    for (var i = 0; i < totalDays; i++) {
      final currentDate = startDate.add(Duration(days: i));
      final dateKey = _dateKey(currentDate);
      final isCurrentMonth =
          currentDate.year == year && currentDate.month == month;

      weeks.add({
        'day': currentDate.day.toString(),
        'dateKey': dateKey,
        'date': currentDate,
        'isPrev': currentDate.isBefore(firstDayOfMonth),
        'isNext': !isCurrentMonth && !currentDate.isBefore(firstDayOfMonth),
        'isCurrentMonth': isCurrentMonth,
        'isSelected': _isSameDate(currentDate, today),
        'events': eventsData[dateKey] ?? const <_CalendarEvent>[],
      });
    }
    return weeks;
  }

  void _openDayDetail(String dateKey, List<_CalendarEvent> events) {
    showDialog(
      context: context,
      builder: (context) => _DayDetailDialog(dateKey: dateKey, events: events),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visitsAsync = ref.watch(allVisitsWithPatientsProvider);

    return visitsAsync.when(
      loading: () => _buildContent(
        eventsData: const <String, List<_CalendarEvent>>{},
        isLoading: true,
      ),
      error: (error, _) => _buildContent(
        eventsData: const <String, List<_CalendarEvent>>{},
        error: error,
      ),
      data: (visits) =>
          _buildContent(eventsData: _groupEvents(_applyFilters(visits))),
    );
  }

  Widget _buildContent({
    required Map<String, List<_CalendarEvent>> eventsData,
    bool isLoading = false,
    Object? error,
  }) {
    final hasActiveFilter =
        _statusFilter != null || _searchQuery.trim().isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleUpdate: _handleScaleUpdate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation & Control Header
          _CalendarHeaderControls(
            titleText: _getHeaderTitle(),
            viewMode: _viewMode,
            anchorDate: _anchorDate,
            onViewModeChanged: _onViewModeChanged,
            onPrev: () => _navigate(-1),
            onNext: () => _navigate(1),
            onJumpToToday: _jumpToToday,
            onJumpToDate: _jumpToDate,
            isSearchExpanded: _isSearchExpanded,
            onToggleSearch: _toggleSearch,
            searchController: _searchController,
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            statusFilter: _statusFilter,
            onStatusFilterChanged: (value) =>
                setState(() => _statusFilter = value),
            onNewAppointment: _createNewAppointment,
          ),

          const SizedBox(height: 12),

          if (isLoading) const LinearProgressIndicator(minHeight: 2),

          if (error != null)
            _CalendarMessage(
              icon: Icons.cloud_off_rounded,
              color: const Color(0xFFDC2626),
              text: 'Could not load live appointments: $error',
            ),

          const SizedBox(height: 10),

          // Main View Body with Dynamic PageView Swiping
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, pageIndex) {
                final pageDate = _getDateForPage(pageIndex);
                switch (_viewMode) {
                  case CalendarViewMode.month:
                    final monthDays = _generateMonthData(
                      pageDate.year,
                      pageDate.month,
                      eventsData,
                    );
                    return _CalendarGrid(
                      calendarDays: monthDays,
                      onDayTap: (dateKey, events) =>
                          _openDayDetail(dateKey, events),
                    );

                  case CalendarViewMode.week:
                    return _WeekHourlyView(
                      anchorDate: pageDate,
                      eventsData: eventsData,
                      visibleHours: _visibleHours,
                      onVisibleHoursChanged: (val) =>
                          setState(() => _visibleHours = val),
                      onDayTap: (dateKey, events) =>
                          _openDayDetail(dateKey, events),
                      onEmptySlotTap: (slotDate) => _createNewAppointment(),
                    );

                  case CalendarViewMode.day:
                    return _DayHourlyView(
                      date: pageDate,
                      events:
                          eventsData[_dateKey(pageDate)] ??
                          const <_CalendarEvent>[],
                      visibleHours: _visibleHours,
                      onVisibleHoursChanged: (val) =>
                          setState(() => _visibleHours = val),
                      onEmptySlotTap: (slotDate) => _createNewAppointment(),
                      onEventTap: (dateKey, events) =>
                          _openDayDetail(dateKey, events),
                    );

                  case CalendarViewMode.agenda:
                    return _AgendaView(
                      anchorDate: pageDate,
                      eventsData: eventsData,
                      onEventTap: (event) => _openDayDetail(
                        _dateKey(event.visit.scheduledStart.toLocal()),
                        [event],
                      ),
                      onNewAppointment: _createNewAppointment,
                    );
                }
              },
            ),
          ),

          if (!isLoading && error == null && eventsData.isEmpty)
            _CalendarMessage(
              icon: Icons.event_busy_rounded,
              color: const Color(0xFF6B7280),
              text: hasActiveFilter
                  ? 'No appointments match your search or filter.'
                  : 'No appointments or visitations scheduled yet.',
            ),
        ],
      ),
    );
  }
}

// ==============================================================================
// TOP CONTROLS & HEADER
// ==============================================================================

class _CalendarHeaderControls extends StatelessWidget {
  final String titleText;
  final CalendarViewMode viewMode;
  final DateTime anchorDate;
  final ValueChanged<CalendarViewMode> onViewModeChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onJumpToToday;
  final ValueChanged<DateTime> onJumpToDate;
  final bool isSearchExpanded;
  final VoidCallback onToggleSearch;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VisitStatus? statusFilter;
  final ValueChanged<VisitStatus?> onStatusFilterChanged;
  final VoidCallback onNewAppointment;

  const _CalendarHeaderControls({
    required this.titleText,
    required this.viewMode,
    required this.anchorDate,
    required this.onViewModeChanged,
    required this.onPrev,
    required this.onNext,
    required this.onJumpToToday,
    required this.onJumpToDate,
    required this.isSearchExpanded,
    required this.onToggleSearch,
    required this.searchController,
    required this.onSearchChanged,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onNewAppointment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Left Group: Navigation (< Today >) + Title + Mini Picker
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous button
                IconButton(
                  onPressed: onPrev,
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  tooltip: 'Previous',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),

                // Persistent "Today" Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    onPressed: onJumpToToday,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E293B),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: const Size(54, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),

                // Next button
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  tooltip: 'Next',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),

                const SizedBox(width: 8),

                // Date Title Text
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(width: 4),

                // Mini Date Picker Button
                IconButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: anchorDate,
                      firstDate: DateTime(anchorDate.year - 5),
                      lastDate: DateTime(anchorDate.year + 5),
                      helpText: 'Select date or month to jump',
                    );
                    if (picked != null) onJumpToDate(picked);
                  },
                  icon: const Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  tooltip: 'Jump to specific date',
                  splashRadius: 18,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Center / Right Group: View Mode Switcher + Filter + Search + New
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // View Mode Segmented Control (Month / Week / Day / Agenda)
                _ViewModeSegmentedControl(
                  activeMode: viewMode,
                  onChanged: onViewModeChanged,
                ),

                const SizedBox(width: 10),

                // Search Toggle Button
                IconButton(
                  onPressed: onToggleSearch,
                  icon: Icon(
                    isSearchExpanded
                        ? Icons.search_off_rounded
                        : Icons.search_rounded,
                    size: 20,
                    color: isSearchExpanded
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF64748B),
                  ),
                  tooltip: 'Search appointments',
                  splashRadius: 18,
                ),

                // Status Filter Menu
                PopupMenuButton<VisitStatus?>(
                  tooltip: 'Filter by status',
                  initialValue: statusFilter,
                  onSelected: onStatusFilterChanged,
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: statusFilter != null
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF64748B),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: null, child: Text('All appointments')),
                    PopupMenuItem(
                      value: VisitStatus.scheduled,
                      child: Text('Scheduled'),
                    ),
                    PopupMenuItem(
                      value: VisitStatus.completed,
                      child: Text('Completed'),
                    ),
                    PopupMenuItem(
                      value: VisitStatus.cancelled,
                      child: Text('Cancelled'),
                    ),
                    PopupMenuItem(
                      value: VisitStatus.missed,
                      child: Text('Missed'),
                    ),
                  ],
                ),

                const SizedBox(width: 8),

                // Quick New Appointment Button
                ElevatedButton.icon(
                  onPressed: onNewAppointment,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('New appointment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        if (isSearchExpanded) ...[
          const SizedBox(height: 10),
          TextField(
            controller: searchController,
            autofocus: true,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by patient name or appointment type…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }
}

// ==============================================================================
// VIEW MODE SEGMENTED CONTROL (Month / Week / Day / Agenda)
// ==============================================================================

class _ViewModeSegmentedControl extends StatelessWidget {
  final CalendarViewMode activeMode;
  final ValueChanged<CalendarViewMode> onChanged;

  const _ViewModeSegmentedControl({
    required this.activeMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentItem('Month', CalendarViewMode.month),
          _buildSegmentItem('Week', CalendarViewMode.week),
          _buildSegmentItem('Day', CalendarViewMode.day),
          _buildSegmentItem('Agenda', CalendarViewMode.agenda),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String label, CalendarViewMode mode) {
    final isSelected = activeMode == mode;
    return InkWell(
      onTap: () => onChanged(mode),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF1E293B)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

Color _getLoadIntensityColor(int count) {
  if (count >= 10) {
    return const Color(0xFF1E3A8A); // Deep dark blue (max intensity)
  }
  if (count >= 8) return const Color(0xFF1D4ED8); // Rich dark blue
  if (count >= 6) return const Color(0xFF2563EB); // Royal blue
  if (count >= 4) return const Color(0xFF93C5FD); // Soft sky blue
  if (count >= 2) return const Color(0xFFDBEAFE); // Light blue tint
  if (count >= 1) return const Color(0xFFEFF6FF); // Very light subtle blue tint
  return Colors.white;
}

bool _isDarkLoadColor(int count) => count >= 6;

// ==============================================================================
// MONTH VIEW: 7x6 GRID WITH MORE ROUNDED DATE CELLS & LOAD COLOR-CODING
// ==============================================================================

class _CalendarGrid extends StatelessWidget {
  final List<Map<String, dynamic>> calendarDays;
  final void Function(String dateKey, List<_CalendarEvent> events) onDayTap;

  const _CalendarGrid({required this.calendarDays, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final numRows = calendarDays.length ~/ 7;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
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
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: List.generate(numRows, (rowIndex) {
                final startIndex = rowIndex * 7;
                final weekData = calendarDays.sublist(
                  startIndex,
                  startIndex + 7,
                );
                return Expanded(
                  child: Row(
                    children: weekData.map((data) {
                      final events =
                          (data['events'] as List<_CalendarEvent>?) ??
                          const <_CalendarEvent>[];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3.5,
                            vertical: 3,
                          ),
                          child: _DayCell(
                            data: data,
                            onTap: () =>
                                onDayTap(data['dateKey'] as String, events),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------- Day Cell (More Rounded) ----------
class _DayCell extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _DayCell({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth = data['isCurrentMonth'] as bool? ?? false;

    // For dates outside the current month, keep the box structure in the grid but leave it blank (no date numbers)
    if (!isCurrentMonth) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const ui.Color.fromARGB(255, 237, 237, 237),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const ui.Color.fromARGB(
              255,
              220,
              235,
              255,
            ).withValues(alpha: 0.6),
            width: 1.0,
          ),
        ),
      );
    }

    final day = data['day'] as String;
    final isSelected = data['isSelected'] as bool? ?? false;
    final events =
        (data['events'] as List<_CalendarEvent>?) ?? const <_CalendarEvent>[];
    final count = events.length;

    // Dark blue intensity scaling (max intensity at 10+ appointments)
    Color cellBgColor = Colors.white;
    Border? customBorder;
    bool isDarkBg = false;

    if (count > 0) {
      cellBgColor = _getLoadIntensityColor(count);
      isDarkBg = _isDarkLoadColor(count);
    }

    var textColor = isDarkBg ? Colors.white : const Color(0xFF1F2937);
    if (isSelected) {
      textColor = isDarkBg ? Colors.white : const Color(0xFF7C3AED);
      customBorder = Border.all(
        color: isDarkBg ? Colors.white : const Color(0xFF7C3AED),
        width: 2.0,
      );
    }

    Widget cellContent = Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: cellBgColor,
        borderRadius: BorderRadius.circular(16),
        border: customBorder,
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0F172A,
            ).withValues(
              alpha: isSelected ? 0.132 : (isDarkBg ? 0.176 : 0.0605),
            ),
            blurRadius: isDarkBg ? 7 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellHeight = constraints.maxHeight;
          final maxVisible = cellHeight >= 95
              ? (cellHeight >= 120 ? 3 : 2)
              : (cellHeight >= 55 ? 1 : 0);
          final visibleEvents = events.take(maxVisible).toList(growable: false);
          final overflowCount = count - visibleEvents.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Day Number + Count Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    day,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: (isSelected || isDarkBg)
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5.5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDarkBg
                            ? Colors.white.withValues(alpha: 0.25)
                            : const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isDarkBg
                              ? Colors.white
                              : const Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                ],
              ),
              if (maxVisible > 0) const SizedBox(height: 2),
              // Event pills
              ...visibleEvents.map(
                (event) => _EventPill(
                  patientName: event.patientName.isNotEmpty
                      ? event.patientName
                      : event.title,
                  type: event.pillType,
                  isDarkBg: isDarkBg,
                ),
              ),
              if (overflowCount > 0 && cellHeight >= 65)
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 1),
                  child: Text(
                    '+$overflowCount more',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isDarkBg
                          ? Colors.white.withValues(alpha: 0.85)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: cellContent,
    );
  }
}

// ---------- Event Pill ----------
class _EventPill extends StatelessWidget {
  final String patientName;
  final String type;
  final bool isDarkBg;

  const _EventPill({
    required this.patientName,
    required this.type,
    this.isDarkBg = false,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor = const Color(0xFF3B82F6);
    if (type == 'purple') {
      dotColor = const Color(0xFF7C3AED);
    } else if (type == 'red') {
      dotColor = const Color(0xFFEF4444);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 2.5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDarkBg
              ? Colors.white.withValues(alpha: 0.9)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkBg ? 0.10 : 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 5, color: dotColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              patientName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// VERTICAL HOUR ZOOM SLIDER (4 to 12 visible hours)
// ==============================================================================

class _HourZoomSlider extends StatelessWidget {
  final double visibleHours;
  final ValueChanged<double> onChanged;

  const _HourZoomSlider({
    required this.visibleHours,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Color(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const thumbRadius = 12.0;
          final trackPadding = thumbRadius + 4.0;
          final trackHeight = constraints.maxHeight - 2 * trackPadding;

          // t goes from 0.0 (4h, at bottom) to 1.0 (12h, at top)
          final t = ((visibleHours - 4.0) / 8.0).clamp(0.0, 1.0);
          final thumbCenterY = trackPadding + (1.0 - t) * trackHeight;

          void updateFromDy(double dy) {
            final clampedDy =
                (dy - trackPadding).clamp(0.0, trackHeight);
            final newT = 1.0 - (clampedDy / trackHeight);
            final newHours = (4.0 + newT * 8.0).roundToDouble();
            onChanged(newHours.clamp(4.0, 12.0));
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) =>
                updateFromDy(details.localPosition.dy),
            onVerticalDragUpdate: (details) =>
                updateFromDy(details.localPosition.dy),
            onTapDown: (details) =>
                updateFromDy(details.localPosition.dy),
            child: SizedBox(
              width: 32,
              height: constraints.maxHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // Inactive track (background line)
                  Positioned(
                    top: trackPadding,
                    bottom: trackPadding,
                    width: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Active track (from thumb down to bottom)
                  Positioned(
                    top: thumbCenterY,
                    bottom: trackPadding,
                    width: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Subtle tick indicators for every step
                  ...List.generate(9, (i) {
                    final tickY = trackPadding + (i / 8.0) * trackHeight;
                    return Positioned(
                      top: tickY - 1,
                      child: Container(
                        width: 6,
                        height: 2,
                        decoration: BoxDecoration(
                          color: (1.0 - (i / 8.0)) <= t
                              ? const Color(0xFF7C3AED)
                                  .withValues(alpha: 0.5)
                              : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  }),

                  // Blob / Thumb with HR text rendered right on it
                  Positioned(
                    top: thumbCenterY - thumbRadius,
                    child: Container(
                      width: thumbRadius * 2,
                      height: thumbRadius * 2,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED)
                                .withValues(alpha: 0.35),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${visibleHours.round()}h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==============================================================================
// WEEK VIEW WITH HOURLY TIME SLOTS (07:00 AM – 09:00 PM)
// ==============================================================================

class _WeekHourlyView extends StatefulWidget {
  final DateTime anchorDate;
  final Map<String, List<_CalendarEvent>> eventsData;
  final double visibleHours;
  final ValueChanged<double> onVisibleHoursChanged;
  final void Function(String dateKey, List<_CalendarEvent> events) onDayTap;
  final void Function(DateTime slotDate) onEmptySlotTap;

  const _WeekHourlyView({
    required this.anchorDate,
    required this.eventsData,
    required this.visibleHours,
    required this.onVisibleHoursChanged,
    required this.onDayTap,
    required this.onEmptySlotTap,
  });

  @override
  State<_WeekHourlyView> createState() => _WeekHourlyViewState();
}

class _WeekHourlyViewState extends State<_WeekHourlyView> {
  final ScrollController _scrollController = ScrollController();
  static const int _startHour = 0; // Full 24-hour day starting at midnight
  static const int _endHour = 24;
  double _lastHourHeight = 56.0;

  @override
  void initState() {
    super.initState();
    // Auto-scroll to 7:00 AM after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(7 * _lastHourHeight);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _WeekHourlyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleHours != widget.visibleHours &&
        _scrollController.hasClients &&
        _lastHourHeight > 0) {
      final currentTopHour = _scrollController.offset / _lastHourHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _lastHourHeight > 0) {
          final newOffset = currentTopHour * _lastHourHeight;
          _scrollController.jumpTo(
            newOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<DateTime> _getWeekDays() {
    final normalizedAnchor = DateTime(
      widget.anchorDate.year,
      widget.anchorDate.month,
      widget.anchorDate.day,
    );
    final startOfWeek = normalizedAnchor.subtract(
      Duration(days: normalizedAnchor.weekday - 1),
    );
    return List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _getWeekDays();
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Weekday Header Cards with Load Heatmap and Count Badges
          Container(
            padding: const EdgeInsets.only(
              left: 88, // 32 (slider) + 56 (time gutter) = 88
              right: 12,
              top: 10,
              bottom: 10,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
              ),
            ),
            child: Row(
              children: weekDays.map((date) {
                final isToday = _isSameDate(date, today);
                final dayName = DateFormat('EEE').format(date);
                final dayNumber = date.day.toString();
                final dateKey = _dateKey(date);
                final dayEvents =
                    widget.eventsData[dateKey] ?? const <_CalendarEvent>[];
                final count = dayEvents.length;
                final isDarkBg = _isDarkLoadColor(count);
                final bgColor = count > 0
                    ? _getLoadIntensityColor(count)
                    : const Color(0xFFF8FAFC);
                final textColor = isDarkBg
                    ? Colors.white
                    : (count > 0
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFF1E293B));

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: InkWell(
                      onTap: () => widget.onDayTap(dateKey, dayEvents),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(14),
                          border: isToday
                              ? Border.all(
                                  color: const Color(0xFF7C3AED),
                                  width: 2,
                                )
                              : Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 0.8,
                                ),
                          boxShadow: count > 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDarkBg ? 0.132 : 0.044,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayName.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDarkBg
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : (isToday
                                              ? const Color(0xFF7C3AED)
                                              : const Color(0xFF64748B)),
                                  ),
                                ),
                                if (count > 0) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDarkBg
                                          ? Colors.white.withValues(alpha: 0.25)
                                          : const Color(
                                              0xFF1E3A8A,
                                            ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: isDarkBg
                                            ? Colors.white
                                            : const Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dayNumber,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Time Grid with dynamic hourHeight fitting
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalHours = _endHour - _startHour;
                final targetHourHeight =
                    constraints.maxHeight / widget.visibleHours;
                final hourHeight = math.max(48.0, targetHourHeight);
                _lastHourHeight = hourHeight;
                final totalGridHeight = hourHeight * totalHours;

                Widget gridBody = SizedBox(
                  height: totalGridHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Time Gutter
                      SizedBox(
                        width: 56,
                        child: Column(
                          children: List.generate(totalHours, (i) {
                            final hour = _startHour + i;
                            final timeStr = DateFormat(
                              'h a',
                            ).format(DateTime(2026, 1, 1, hour));
                            return SizedBox(
                              height: hourHeight,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 4,
                                  ),
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // 7 Columns for Days of the Week
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              // Horizontal hour grid divider lines
                              Positioned.fill(
                                child: Column(
                                  children: List.generate(totalHours, (i) {
                                    return Container(
                                      height: hourHeight,
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: Color(0xFFF1F5F9),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),

                              // Vertical day dividers
                              Positioned.fill(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: List.generate(7, (i) {
                                    return Expanded(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: Color(0xFFF1F5F9),
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),

                              // Interactive Columns with Events
                              Positioned.fill(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: weekDays.map((date) {
                                    final dateKey = _dateKey(date);
                                    final events =
                                        widget.eventsData[dateKey] ??
                                        const <_CalendarEvent>[];

                                    return Expanded(
                                      child: Stack(
                                        children: [
                                          // Empty Slot Tap Area
                                          Positioned.fill(
                                            child: InkWell(
                                              onTap: () =>
                                                  widget.onEmptySlotTap(date),
                                            ),
                                          ),

                                          // Event Cards
                                          ...events.map((event) {
                                            final start = event
                                                .visit
                                                .scheduledStart
                                                .toLocal();
                                            final end = event.visit.scheduledEnd
                                                .toLocal();

                                            final startMinutes =
                                                (start.hour - _startHour) * 60 +
                                                start.minute;
                                            final durationMinutes = math.max(
                                              30,
                                              end.difference(start).inMinutes,
                                            );

                                            final top =
                                                (startMinutes / 60.0) *
                                                hourHeight;
                                            final height =
                                                (durationMinutes / 60.0) *
                                                    hourHeight -
                                                2;

                                            final clampedTop = math.max(
                                              0.0,
                                              math.min(top, totalGridHeight - 32),
                                            );
                                            final clampedHeight = math.max(
                                              28.0,
                                              math.min(
                                                height,
                                                totalGridHeight - clampedTop,
                                              ),
                                            );

                                            Color dotColor = const Color(
                                              0xFF2563EB,
                                            );
                                            if (event.visit.visitType ==
                                                VisitType.home) {
                                              dotColor = const Color(0xFF7C3AED);
                                            } else if (event.visit.status ==
                                                VisitStatus.completed) {
                                              dotColor = const Color(0xFF10B981);
                                            } else if (event.visit.status ==
                                                VisitStatus.cancelled) {
                                              dotColor = const Color(0xFFEF4444);
                                            }

                                            return Positioned(
                                              top: clampedTop,
                                              left: 2,
                                              right: 2,
                                              height: clampedHeight,
                                              child: InkWell(
                                                onTap: () => widget.onDayTap(
                                                  dateKey,
                                                  [event],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 3.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFE2E8F0,
                                                      ),
                                                      width: 0.8,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.05,
                                                            ),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.circle,
                                                        size: 6,
                                                        color: dotColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              event.patientName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        10.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: Color(
                                                                      0xFF1E293B,
                                                                    ),
                                                                  ),
                                                            ),
                                                            if (clampedHeight >=
                                                                40)
                                                              Text(
                                                                '${DateFormat('h:mm a').format(start)} • ${event.title}',
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize: 9,
                                                                      color: Color(
                                                                        0xFF64748B,
                                                                      ),
                                                                    ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),

                              // Red Current Time Line Indicator (if today is in the week)
                              if (weekDays.any((d) => _isSameDate(d, today))) ...[
                                _buildNowIndicator(weekDays, today, hourHeight),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Vertical Hour Zoom Slider
                    _HourZoomSlider(
                      visibleHours: widget.visibleHours,
                      onChanged: widget.onVisibleHoursChanged,
                    ),
                    // Scrollable Grid Area
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: gridBody,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowIndicator(
    List<DateTime> weekDays,
    DateTime now,
    double hourHeight,
  ) {
    final nowMinutes = (now.hour - _startHour) * 60 + now.minute;
    if (nowMinutes < 0 || nowMinutes > (_endHour - _startHour) * 60) {
      return const SizedBox.shrink();
    }
    final top = (nowMinutes / 60.0) * hourHeight;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFFEF4444), thickness: 1.5, height: 1),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// DAY VIEW WITH DETAILED HOURLY SLOTS
// ==============================================================================

class _DayHourlyView extends StatefulWidget {
  final DateTime date;
  final List<_CalendarEvent> events;
  final double visibleHours;
  final ValueChanged<double> onVisibleHoursChanged;
  final void Function(DateTime slotDate) onEmptySlotTap;
  final void Function(String dateKey, List<_CalendarEvent> events)? onEventTap;

  const _DayHourlyView({
    required this.date,
    required this.events,
    required this.visibleHours,
    required this.onVisibleHoursChanged,
    required this.onEmptySlotTap,
    this.onEventTap,
  });

  @override
  State<_DayHourlyView> createState() => _DayHourlyViewState();
}

class _DayHourlyViewState extends State<_DayHourlyView> {
  final ScrollController _scrollController = ScrollController();
  static const int _startHour = 0; // Full 24-hour day
  static const int _endHour = 24;
  double _lastHourHeight = 56.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(7 * _lastHourHeight);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DayHourlyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleHours != widget.visibleHours &&
        _scrollController.hasClients &&
        _lastHourHeight > 0) {
      final currentTopHour = _scrollController.offset / _lastHourHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _lastHourHeight > 0) {
          final newOffset = currentTopHour * _lastHourHeight;
          _scrollController.jumpTo(
            newOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildNowIndicator(DateTime now, double hourHeight) {
    final nowMinutes = (now.hour - _startHour) * 60 + now.minute;
    if (nowMinutes < 0 || nowMinutes > (_endHour - _startHour) * 60) {
      return const SizedBox.shrink();
    }
    final top = (nowMinutes / 60.0) * hourHeight;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFFEF4444), thickness: 1.5, height: 1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDate(widget.date, DateTime.now());
    final count = widget.events.length;
    final confirmedCount = widget.events
        .where((e) => e.visit.status == VisitStatus.scheduled)
        .length;
    final completedCount = widget.events
        .where((e) => e.visit.status == VisitStatus.completed)
        .length;
    final isDarkLoad = _isDarkLoadColor(count);
    final loadBgColor = count > 0
        ? _getLoadIntensityColor(count)
        : const Color(0xFFF8FAFC);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Day Overview Banner with Load Intensity Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(widget.date),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count ${count == 1 ? 'appointment' : 'appointments'} scheduled • $confirmedCount confirmed • $completedCount completed',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: loadBgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDarkLoad
                            ? Colors.transparent
                            : const Color(0xFFCBD5E1),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color: isDarkLoad
                              ? Colors.white
                              : const Color(0xFF1E3A8A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$count visits scheduled',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDarkLoad
                                ? Colors.white
                                : const Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Day Hourly Schedule with Dynamic Height Fitting
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalHours = _endHour - _startHour;
                final targetHourHeight =
                    constraints.maxHeight / widget.visibleHours;
                final hourHeight = math.max(48.0, targetHourHeight);
                _lastHourHeight = hourHeight;
                final totalGridHeight = hourHeight * totalHours;

                Widget gridBody = SizedBox(
                  height: totalGridHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Time Gutter
                      SizedBox(
                        width: 58,
                        child: Column(
                          children: List.generate(totalHours, (i) {
                            final hour = _startHour + i;
                            final timeStr = DateFormat(
                              'h a',
                            ).format(DateTime(2026, 1, 1, hour));
                            return SizedBox(
                              height: hourHeight,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 4,
                                  ),
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // Day Column with Hour Grid & Event Cards
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            // Horizontal grid lines
                            Positioned.fill(
                              child: Column(
                                children: List.generate(totalHours, (i) {
                                  return Container(
                                    height: hourHeight,
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Color(0xFFF1F5F9),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),

                            // Empty slot tap area
                            Positioned.fill(
                              child: InkWell(
                                onTap: () => widget.onEmptySlotTap(widget.date),
                              ),
                            ),

                            // Event cards (White Cards, Full Width, Patient Name Prominent)
                            ...widget.events.map((event) {
                              final start = event.visit.scheduledStart
                                  .toLocal();
                              final end = event.visit.scheduledEnd.toLocal();

                              final startMinutes =
                                  (start.hour - _startHour) * 60 + start.minute;
                              final durationMinutes = math.max(
                                45,
                                end.difference(start).inMinutes,
                              );

                              final top = (startMinutes / 60.0) * hourHeight;
                              final height =
                                  (durationMinutes / 60.0) * hourHeight - 4;

                              final clampedTop = math.max(
                                0.0,
                                math.min(top, totalGridHeight - 56),
                              );
                              final clampedHeight = math.max(
                                56.0,
                                math.min(height, totalGridHeight - clampedTop),
                              );

                              return Positioned(
                                top: clampedTop,
                                left: 16,
                                right: 24,
                                height: clampedHeight,
                                child: InkWell(
                                  onTap: () => widget.onEventTap?.call(
                                    _dateKey(widget.date),
                                    [event],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            event.visit.visitType ==
                                                VisitType.home
                                            ? const Color(0xFFC4B5FD)
                                            : const Color(0xFFBFDBFE),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 15,
                                          backgroundColor:
                                              event.visit.visitType ==
                                                  VisitType.home
                                              ? const Color(0xFFEDE9FE)
                                              : const Color(0xFFDBEAFE),
                                          child: Text(
                                            _initials(event.patientName),
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  event.visit.visitType ==
                                                      VisitType.home
                                                  ? const Color(0xFF6D28D9)
                                                  : const Color(0xFF1E40AF),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Patient Name First & Bold
                                              Text(
                                                event.patientName,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF1E293B),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 1),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${event.title} • ${_formatVisitRange(event.visit)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        color: Color(0xFF64748B),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            event.statusLabel,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: event.statusColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                            // Red Current Time Line Indicator
                            if (isToday) ...[
                              _buildNowIndicator(DateTime.now(), hourHeight),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Vertical Hour Zoom Slider
                    _HourZoomSlider(
                      visibleHours: widget.visibleHours,
                      onChanged: widget.onVisibleHoursChanged,
                    ),
                    // Scrollable Grid Area
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: gridBody,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// AGENDA VIEW: CHRONOLOGICAL FLAT LIST WITH STICKY HEADERS
// ==============================================================================

class _AgendaView extends StatelessWidget {
  final DateTime anchorDate;
  final Map<String, List<_CalendarEvent>> eventsData;
  final ValueChanged<_CalendarEvent> onEventTap;
  final VoidCallback onNewAppointment;
  const _AgendaView({
    required this.anchorDate,
    required this.eventsData,
    required this.onEventTap,
    required this.onNewAppointment,
  });

  @override
  Widget build(BuildContext context) {
    // Sort all dates chronologically and filter to active anchor month for dynamic month swipe paging
    final sortedKeys = eventsData.keys.toList()..sort();
    final activeEntries = sortedKeys
        .where((k) {
          final date = DateTime.tryParse(k);
          if (date == null) return false;
          return date.year == anchorDate.year && date.month == anchorDate.month;
        })
        .where((k) => (eventsData[k] ?? const []).isNotEmpty)
        .toList();

    if (activeEntries.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
        ),
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.event_note_rounded,
                size: 56,
                color: Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 14),
              Text(
                'No appointments in ${DateFormat('MMMM yyyy').format(anchorDate)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Schedule a clinic visit or home appointment to see it on your agenda.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onNewAppointment,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Schedule Appointment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CustomScrollView(
          slivers: activeEntries.expand((dateKey) {
            final events = eventsData[dateKey] ?? const <_CalendarEvent>[];
            final parsedDate = DateTime.tryParse(dateKey) ?? DateTime.now();

            return [
              // Sticky Date Section Header with Load Heatmap Badge
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyDateHeaderDelegate(
                  date: parsedDate,
                  count: events.length,
                ),
              ),

              // Appointment items for this date
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final event = events[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DayEventCard(event: event),
                    );
                  }, childCount: events.length),
                ),
              ),
            ];
          }).toList(),
        ),
      ),
    );
  }
}

class _StickyDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final DateTime date;
  final int count;

  _StickyDateHeaderDelegate({required this.date, required this.count});

  @override
  double get minExtent => 44.0;

  @override
  double get maxExtent => 44.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(date);
    final isToday = _isSameDate(date, DateTime.now());
    final isDarkLoad = _isDarkLoadColor(count);
    final loadColor = _getLoadIntensityColor(count);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFE2E8F0),
            width: overlapsContent ? 1.5 : 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_rounded,
            size: 16,
            color: isToday ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Text(
            formattedDate,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isToday
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF1E293B),
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ),
          ],
          const Spacer(),
          // Load intensity badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: loadColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDarkLoad
                    ? Colors.transparent
                    : const Color(0xFFCBD5E1),
                width: 0.5,
              ),
            ),
            child: Text(
              '$count ${count == 1 ? 'visit' : 'visits'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDarkLoad
                    ? Colors.white
                    : (count > 0
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFF64748B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyDateHeaderDelegate oldDelegate) {
    return oldDelegate.date != date || oldDelegate.count != count;
  }
}

// ==============================================================================
// DAY DETAIL DIALOG & APPOINTMENT CARD
// ==============================================================================

class _DayDetailDialog extends ConsumerWidget {
  final String dateKey;
  final List<_CalendarEvent> events;

  const _DayDetailDialog({required this.dateKey, required this.events});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsedDate = DateTime.tryParse(dateKey) ?? DateTime.now();
    final formattedDate = DateFormat('EEEE, d MMMM yyyy').format(parsedDate);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            // Events list
            Flexible(
              child: events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy_rounded,
                            size: 48,
                            color: Color(0xFFD1D5DB),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No appointments for this day',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: events.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _DayEventCard(event: events[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Individual event card inside dialog and agenda ----------
class _DayEventCard extends ConsumerWidget {
  final _CalendarEvent event;

  const _DayEventCard({required this.event});

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = event.patientPhone;
    if (!WhatsAppTemplateService.isValidWhatsAppPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid WhatsApp mobile number for this patient.'),
        ),
      );
      return;
    }

    final message = WhatsAppTemplateService.buildConfirmationMessage(
      visit: event.visit,
      patient:
          event.item.patient ??
          Patient(
            id: event.visit.patientId,
            firstName: event.patientName,
            lastName: '',
            phone: phone,
            gender: 'Other',
            dateOfBirth: DateTime(2000),
            diagnosis: const [],
            packageBalance: 0,
            isArchived: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
      doctorName: 'Doctor',
    );

    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
      rawPhone: phone,
      message: message,
    );

    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isQueueEnabled = ref.watch(isQueueFeatureEnabledProvider);
    final queueEntries = isQueueEnabled
        ? (ref.watch(todaysQueueWithPatientsProvider).value ?? const [])
        : const <QueueEntryWithPatient>[];
    final queueEntry = queueEntries
        .where((e) => e.entry.linkedVisitId == event.visit.id)
        .firstOrNull;

    final statusAsync = ref.watch(visitWhatsAppStatusProvider(event.visit.id));
    final log = statusAsync.asData?.value;
    final hasValidPhone = WhatsAppTemplateService.isValidWhatsAppPhone(
      event.patientPhone,
    );

    Color badgeColor = const Color(0xFF25D366);
    IconData badgeIcon = Icons.check_circle_outline;
    String badgeLabel = 'WhatsApp Notified';

    if (log != null) {
      switch (log.status) {
        case WhatsAppNotificationStatus.delivered:
          badgeColor = const Color(0xFF10B981);
          badgeIcon = Icons.done_all_rounded;
          badgeLabel = 'WhatsApp: Delivered';
          break;
        case WhatsAppNotificationStatus.read:
          badgeColor = const Color(0xFF2D9CDB);
          badgeIcon = Icons.done_all_rounded;
          badgeLabel = 'WhatsApp: Read';
          break;
        case WhatsAppNotificationStatus.sent:
          badgeColor = const Color(0xFF25D366);
          badgeIcon = Icons.check_rounded;
          badgeLabel = 'WhatsApp: Sent';
          break;
        case WhatsAppNotificationStatus.pending:
          badgeColor = const Color(0xFFF59E0B);
          badgeIcon = Icons.hourglass_top_rounded;
          badgeLabel = 'WhatsApp: Sending...';
          break;
        case WhatsAppNotificationStatus.failed:
          badgeColor = const Color(0xFFEF4444);
          badgeIcon = Icons.error_outline_rounded;
          badgeLabel = 'WhatsApp: Failed';
          break;
        case WhatsAppNotificationStatus.skipped:
          badgeColor = const Color(0xFF6B7280);
          badgeIcon = Icons.phone_disabled_outlined;
          badgeLabel = 'WhatsApp: Skipped';
          break;
      }
    } else if (!hasValidPhone) {
      badgeColor = const Color(0xFF6B7280);
      badgeIcon = Icons.phone_disabled_outlined;
      badgeLabel = 'WhatsApp: No Number';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: event.visit.visitType == VisitType.home
                    ? const Color(0xFFEDE9FE)
                    : const Color(0xFFDBEAFE),
                child: Text(
                  _initials(event.patientName),
                  style: TextStyle(
                    color: event.visit.visitType == VisitType.home
                        ? const Color(0xFF6D28D9)
                        : const Color(0xFF1E40AF),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Patient Name First & Bold
                    Text(
                      event.patientName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(event.statusIcon, size: 12, color: event.statusColor),
                    const SizedBox(width: 4),
                    Text(
                      event.statusLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: event.statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.access_time_rounded,
            text: _formatVisitRange(event.visit),
          ),
          const SizedBox(height: 4),
          _DetailRow(icon: Icons.location_on_outlined, text: event.address),
          if (event.patientPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            _DetailRow(icon: Icons.phone_outlined, text: event.patientPhone),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 13, color: badgeColor),
                const SizedBox(width: 5),
                Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
          if (isQueueEnabled && event.visit.visitType == VisitType.clinic) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.groups_rounded, size: 13, color: Color(0xFF6366F1)),
                  const SizedBox(width: 5),
                  Text(
                    queueEntry != null
                        ? (queueEntry.entry.tokenNumber > 0
                            ? 'OPD Queue #${queueEntry.entry.tokenNumber} • ${queueEntry.entry.status.name.toUpperCase()}'
                            : 'In OPD Queue • ${queueEntry.entry.status.name.toUpperCase()}')
                        : 'Clinic OPD • Not in Live Queue',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasValidPhone) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openWhatsApp(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.chat_outlined, size: 15),
                label: const Text(
                  'Chat on WhatsApp',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- Small detail row ----------
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
          ),
        ),
      ],
    );
  }
}

// ---------- Message widget ----------
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

// ---------- Helper functions ----------
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
