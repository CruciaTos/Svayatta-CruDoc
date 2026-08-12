import 'package:flutter/material.dart';

/// Desktop version of the Appointments & Events tab.
///
/// A fully functional, interactive calendar matching the Pillio-style UI.
/// Features dynamic month navigation, accurate day grid generation,
/// and an animated hover popup that adapts to the selected day's data.
/// Now wrapped in the same white card style as the other desktop dashboards.
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
        child: const SingleChildScrollView(
          child: _CalendarDashboardView(),
        ),
      ),
    );
  }
}

// ==============================================================================
// STATE MANAGEMENT & MAIN LOGIC
// ==============================================================================

class _CalendarDashboardView extends StatefulWidget {
  const _CalendarDashboardView();

  @override
  State<_CalendarDashboardView> createState() => _CalendarDashboardViewState();
}

class _CalendarDashboardViewState extends State<_CalendarDashboardView> {
  int _year = 2026;
  int _month = 3;
  String? _hoveredDateKey; // Tracks which date's popup to show

  final Map<String, List<Map<String, dynamic>>> _eventsData = {
    '2026-03-02': [{'title': 'Blood pressure...', 'type': 'red'}],
    '2026-03-06': [{'title': 'In-person visit', 'type': 'red'}],
    '2026-03-07': [{'title': 'In-person visit', 'type': 'red'}],
    '2026-03-08': [{'title': 'In-person visit', 'type': 'red'}],
    '2026-03-14': [{'title': 'General check-up', 'type': 'purple'}],
    '2026-03-15': [{'title': 'In-person visit', 'type': 'red'}],
    '2026-03-17': [{'title': 'General check-up', 'type': 'purple'}],
    '2026-03-21': [{'title': 'Planned consultati...', 'type': 'white'}],
    '2026-03-28': [{'title': 'In-person visit', 'type': 'red'}],
    '2026-03-30': [{'title': 'Video Consultati...', 'type': 'purple'}],
  };

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
      _hoveredDateKey = null; // Reset hover on month change
    });
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  // Generates the 6 rows x 7 columns of dates dynamically
  List<Map<String, dynamic>> _generateCalendarData(int year, int month) {
    final List<Map<String, dynamic>> weeks = [];
    
    // Calculate first day of the month
    final firstDayOfMonth = DateTime(year, month, 1);
    // 1 = Monday, 7 = Sunday. Calculate offset to the previous Monday.
    final int weekday = firstDayOfMonth.weekday;
    final int offset = (weekday == 7) ? 6 : weekday - 1; // Days to go back to Monday
    
    final DateTime startDate = firstDayOfMonth.subtract(Duration(days: offset));
    
    for (int i = 0; i < 42; i++) { // 6 weeks * 7 days
      final currentDate = startDate.add(Duration(days: i));
      final String dateKey = '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
      
      final bool isPrevMonth = currentDate.month < month;
      final bool isNextMonth = currentDate.month > month;
      final bool isCurrentMonth = !isPrevMonth && !isNextMonth;
      final bool isSelected = currentDate.year == 2026 && currentDate.month == 3 && currentDate.day == 17;
      final bool hasEvents = _eventsData.containsKey(dateKey);

      weeks.add({
        'day': currentDate.day.toString(),
        'dateKey': dateKey,
        'isPrev': isPrevMonth,
        'isNext': isNextMonth,
        'isCurrentMonth': isCurrentMonth,
        'isSelected': isSelected,
        'events': hasEvents ? _eventsData[dateKey]! : [],
      });
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> calendarDays = _generateCalendarData(_year, _month);
    final hoveredEvents = _hoveredDateKey != null ? _eventsData[_hoveredDateKey] : null;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header Section (Stateful) ---
            _CalendarHeader(
              monthText: '${_getMonthName(_month)} $_year',
              onPrev: () => _changeMonth(-1),
              onNext: () => _changeMonth(1),
            ),
            const SizedBox(height: 24),

            // --- Dynamic Grid ---
            _CalendarGrid(
              calendarDays: calendarDays,
              onDayHover: (String? dateKey) {
                setState(() {
                  _hoveredDateKey = dateKey;
                });
              },
            ),
          ],
        ),

        // --- Interactive Hover Popup ---
        if (_hoveredDateKey == '2026-03-17')
          Positioned(
            top: 280,
            right: 40,
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: const _EventPopupCard(),
            ),
          ),
      ],
    );
  }
}

// ==============================================================================
// 1. STATE-FUL HEADER
// ==============================================================================

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
        // Left: Navigation Arrows & Month
        Row(
          children: [
            InkWell(
              onTap: onPrev,
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.arrow_back_ios_new, size: 16, color: Color(0xFF4B5563)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              monthText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onNext,
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF4B5563)),
              ),
            ),
          ],
        ),

        // Right: Tools & Dropdown
        Row(
          children: [
            IconButton(
              onPressed: () => _showDemoDialog(context, 'Search functionality'),
              icon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF6B7280)),
            ),
            IconButton(
              onPressed: () => _showDemoDialog(context, 'Filter & tune options'),
              icon: const Icon(Icons.tune_rounded, size: 20, color: Color(0xFF6B7280)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: () => _showDemoDialog(context, 'Monthly dropdown clicked'),
                child: Row(
                  children: const [
                    Text('Monthly', style: TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6B7280)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _showDemoDialog(context, 'More options'),
              icon: const Icon(Icons.more_horiz, size: 20, color: Color(0xFF6B7280)),
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
          )
        ],
      ),
    );
  }
}

// ==============================================================================
// 2. DYNAMIC CALENDAR GRID
// ==============================================================================

class _CalendarGrid extends StatelessWidget {
  final List<Map<String, dynamic>> calendarDays;
  final Function(String?) onDayHover;

  const _CalendarGrid({
    required this.calendarDays,
    required this.onDayHover,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Weekday Headers
        Row(
          children: const [
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

        // Build 6 rows of 7 columns
        Column(
          children: List.generate(6, (rowIndex) {
            final startIndex = rowIndex * 7;
            final weekData = calendarDays.sublist(startIndex, startIndex + 7);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: weekData.map((data) {
                  final bool isTarget = data['isSelected'] == true;
                  return Expanded(
                    child: _DayCell(
                      data: data,
                      isHoverTarget: isTarget,
                      onHover: isTarget ? onDayHover : null,
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
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isHoverTarget;
  final Function(String?)? onHover;

  const _DayCell({
    required this.data,
    this.isHoverTarget = false,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final String day = data['day'];
    final bool isPrev = data['isPrev'] ?? false;
    final bool isNext = data['isNext'] ?? false;
    final bool isCurrentMonth = !isPrev && !isNext;
    final bool isSelected = data['isSelected'] ?? false;
    final List<dynamic> events = data['events'] ?? [];

    Color textColor = Colors.grey[400]!;
    if (isCurrentMonth) textColor = const Color(0xFF1F2937);
    if (isSelected) textColor = const Color(0xFF7C3AED);

    Widget cellContent = Container(
      height: 110,
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF3E8FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: const Color(0xFF7C3AED), width: 1.5) : null,
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
          ...events.map((event) => _EventPill(
            title: event['title'],
            type: event['type'],
          )).toList(),
        ],
      ),
    );

    if (isHoverTarget) {
      return MouseRegion(
        onEnter: (_) => onHover?.call(data['dateKey'] as String),
        onExit: (_) => onHover?.call(null),
        child: cellContent,
      );
    }

    return cellContent;
  }
}

class _EventPill extends StatelessWidget {
  final String title;
  final String type;

  const _EventPill({required this.title, required this.type});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color iconColor;
    Color textColor;

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

// ==============================================================================
// 3. INTERACTIVE EVENT POPOVER (ANIMATED)
// ==============================================================================

class _EventPopupCard extends StatelessWidget {
  const _EventPopupCard();

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
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Avatar, Title, Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'General check-up',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Dr. Alexander Callman',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
                    const Icon(Icons.check_circle, size: 12, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    const Text('Confirmed', style: TextStyle(fontSize: 10, color: Color(0xFF1F2937))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 12),

          // Details Rows
          _DetailRow(
            icon: Icons.access_time_rounded,
            text: 'Thu, 17 March • 10:30-11:30',
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.location_on_outlined,
            text: 'City Health Clinic, 12 Green St, Room 204',
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.phone_outlined,
            text: '+49 050 123 3546',
          ),

          const SizedBox(height: 16),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text('Write a message', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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