import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';

// ---------- Color Constants (Matching desktop palette) ----------
const Color _kFrostedBg     = Color(0xFFF0F9FF);
const Color _kInk           = Color(0xFF0F172A);
const Color _kMuted         = Color(0xFF64748B);
const Color _kFaint         = Color(0xFF94A3B8);
const Color _kLine          = Color(0xFFE2E8F0);
const Color _kSurface       = Color(0xFFF8FAFC);
const Color _kColumnBg      = Color(0xFFF1F5F9);
const Color _kAccentBlue    = Color(0xFF0284C7);
const Color _kAccentBlueBg  = Color(0xFFF0F9FF);
const Color _kGreen         = Color(0xFF10B981);
const Color _kGreenColumn   = Color(0xFFECFDF5);
const Color _kGreenBorder   = Color(0xFFBBF7D0);
const Color _kAmber         = Color(0xFFF59E0B);
const Color _kRed           = Color(0xFFF43F5E);
const Color _kIndigo        = Color(0xFF6366F1);

/// How long a patient may wait in line before their card is flagged
/// as breaching the target.
const Duration _kWaitTarget = Duration(minutes: 20);

/// How long a called patient may take to reach the room before their
/// card is flagged.
const Duration _kCalledTarget = Duration(minutes: 5);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtDuration(Duration d) {
  final mins = d.inMinutes;
  if (mins < 1) return '<1m';
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

Duration? _average(Iterable<Duration> durations) {
  final list = durations.toList();
  if (list.isEmpty) return null;
  final total = list.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
  return Duration(microseconds: total ~/ list.length);
}

/// How long a waiting patient has been in line, or null when it can't be
/// measured meaningfully (a token from another day, or a future appointment).
Duration? _waitingFor(QueueEntryWithPatient item, DateTime now) {
  final since = item.entry.checkedInAt;
  if (!_isSameDay(since, now) || since.isAfter(now)) return null;
  return now.difference(since);
}

bool _isCalledTooLong(QueueEntryWithPatient item, DateTime now) {
  final calledAt = item.entry.calledAt;
  return item.entry.status == QueueStatus.called &&
      calledAt != null &&
      _isSameDay(calledAt, now) &&
      now.difference(calledAt) > _kCalledTarget;
}

bool _isActiveUrgent(QueueEntryWithPatient item) =>
    item.entry.priority == QueuePriority.urgent &&
    (item.entry.status == QueueStatus.waiting || item.entry.isActiveServing);

/// Desktop walk-in queue management screen.
///
/// A patient-flow board: every token sits in a column for its lifecycle
/// stage (waiting → called → in consultation → seen, plus skipped), with
/// live wait timers, target-breach flags, and per-card actions.
class DesktopQueueScreen extends ConsumerStatefulWidget {
  const DesktopQueueScreen({super.key});

  @override
  ConsumerState<DesktopQueueScreen> createState() => _DesktopQueueScreenState();
}

class _DesktopQueueScreenState extends ConsumerState<DesktopQueueScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isCallingNext = false;
  bool _sortLongestWait = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keeps wait timers and breach flags current without new data arriving.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _kRed : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _callNextToken() async {
    setState(() => _isCallingNext = true);
    try {
      final repo = ref.read(queueRepositoryProvider);
      final next = await repo.callNext();
      _showFeedback('Token #${next.tokenNumber} called to consultation room.');
    } on QueueAlreadyServingException catch (e) {
      _showFeedback(e.message, isError: true);
    } on QueueEmptyException {
      _showFeedback('No patients are waiting in the queue.', isError: true);
    } catch (e) {
      _showFeedback('Error calling next token: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isCallingNext = false);
    }
  }

  Future<void> _startConsultation(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.startConsultation(entryId);
      _showFeedback('Started consultation with Token #$tokenNumber.');
    } catch (e) {
      _showFeedback('Could not start consultation: $e', isError: true);
    }
  }

  Future<void> _completeConsultation(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.complete(entryId);
      _showFeedback('Token #$tokenNumber consultation completed.');
    } catch (e) {
      _showFeedback('Could not complete consultation: $e', isError: true);
    }
  }

  Future<void> _skipToken(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.skip(entryId);
      _showFeedback('Token #$tokenNumber marked as skipped.');
    } catch (e) {
      _showFeedback('Could not skip token: $e', isError: true);
    }
  }

  Future<void> _requeueToken(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.requeue(entryId);
      _showFeedback('Token #$tokenNumber requeued in original numeric order.');
    } catch (e) {
      _showFeedback('Could not requeue token: $e', isError: true);
    }
  }

  Future<void> _cancelToken(String entryId, int tokenNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Token'),
        content: Text('Are you sure you want to cancel Token #$tokenNumber?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Token'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repo = ref.read(queueRepositoryProvider);
        await repo.cancel(entryId);
        _showFeedback('Token #$tokenNumber has been cancelled.');
      } catch (e) {
        _showFeedback('Could not cancel token: $e', isError: true);
      }
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final currentCustom = ref.read(queueCustomDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: currentCustom ??
          DateTimeRange(start: now, end: now.add(const Duration(days: 6))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kAccentBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _kInk,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(queueCustomDateRangeProvider.notifier).state = picked;
      ref.read(queuePeriodProvider.notifier).state = QueuePeriod.custom;
    }
  }

  Future<void> _checkInPrebooked(QueueEntryWithPatient item) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      if (item.linkedVisit != null) {
        final created = await repo.checkInVisit(item.linkedVisit!);
        _showFeedback('Appointment for ${item.displayName} checked into queue as Token #${created.tokenNumber}!');
      }
    } catch (e) {
      _showFeedback('Could not check in appointment: $e', isError: true);
    }
  }

  Future<void> _openCheckIn() async {
    final created = await CheckInDialog.show(context);
    if (created != null) {
      _showFeedback('Token #${created.tokenNumber} issued successfully!');
    }
  }

  bool _matchesSearch(QueueEntryWithPatient item) {
    if (_searchQuery.isEmpty) return true;
    final name = item.displayName.toLowerCase();
    final tokenStr = '#${item.entry.tokenNumber}';
    final reason = item.entry.reason?.toLowerCase() ?? '';
    return name.contains(_searchQuery) ||
        tokenStr.contains(_searchQuery) ||
        reason.contains(_searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(todaysQueueWithPatientsProvider);
    final activeServing = ref.watch(activeQueueEntryProvider);
    final waitingTokens = ref.watch(waitingQueueProvider);
    final bounds = ref.watch(activeQueueDateBoundsProvider);
    final selectedPeriod = ref.watch(queuePeriodProvider);
    final selectedSession = ref.watch(queueSessionFilterProvider);
    final selectedSource = ref.watch(queueSourceFilterProvider);
    final isAppointmentsEnabled = ref.watch(isAppointmentsFeatureEnabledProvider);

    final now = DateTime.now();
    final isToday = selectedPeriod == QueuePeriod.today;
    final allTokens = queueAsync.value ?? const <QueueEntryWithPatient>[];
    final prebookedCount = allTokens.where((t) => t.isPrebooked).length;
    final waitingCount = waitingTokens.length;

    int countStatus(QueueStatus s) => allTokens.where((t) => t.entry.status == s).length;
    final calledCount = countStatus(QueueStatus.called);
    final consultCount = countStatus(QueueStatus.inConsultation);
    final completedCount = countStatus(QueueStatus.completed);

    final currentWaits = waitingTokens
        .map((t) => _waitingFor(t, now))
        .whereType<Duration>()
        .toList();
    final avgWaitNow = _average(currentWaits);
    final breachingCount = currentWaits.where((d) => d > _kWaitTarget).length;
    final inClinicCount = currentWaits.length + calledCount + consultCount;
    final urgentCount = allTokens.where(_isActiveUrgent).length;

    final visibleTokens = allTokens.where(_matchesSearch).toList();

    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: _kFrostedBg.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===========================================================
                  // 1. HEADER — title, period, primary actions
                  // ===========================================================
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kAccentBlueBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.format_list_numbered_rounded,
                          color: _kAccentBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Flexible(
                                  child: Text(
                                    'Walk-in Queue',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: _kInk,
                                      fontFamily: AppColors.headingFontFamily,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _kSurface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _kLine),
                                  ),
                                  child: Text(
                                    _periodCaption(bounds),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _kMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAppointmentsEnabled
                                  ? 'Live patient flow across walk-ins and pre-booked appointments'
                                  : 'Live patient flow and triage for walk-in patients',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _kMuted,
                                fontFamily: AppColors.bodyFontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SegmentedPills<QueuePeriod>(
                        selected: selectedPeriod,
                        options: const [
                          _Segment(QueuePeriod.today, 'Today'),
                          _Segment(QueuePeriod.tomorrow, 'Tomorrow'),
                          _Segment(QueuePeriod.thisWeek, 'This Week'),
                          _Segment(QueuePeriod.custom, 'Custom', icon: Icons.date_range_rounded),
                        ],
                        onChanged: (p) {
                          if (p == QueuePeriod.custom) {
                            _pickCustomDateRange();
                          } else {
                            ref.read(queuePeriodProvider.notifier).state = p;
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: (_isCallingNext || waitingCount == 0 || activeServing != null)
                              ? null
                              : _callNextToken,
                          icon: _isCallingNext
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.campaign_rounded, size: 18),
                          label: Text(
                            activeServing != null ? 'Serving Active' : 'Call Next Token',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kAccentBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _openCheckIn,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Check In Patient',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kInk,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ===========================================================
                  // 2. LIVE STATS STRIP
                  // ===========================================================
                  _StatsStrip(
                    stats: [
                      _StatData(
                        icon: Icons.groups_rounded,
                        color: _kIndigo,
                        label: 'In the clinic now',
                        value: '$inClinicCount',
                        suffix: inClinicCount == 1 ? 'patient' : 'patients',
                        badge: urgentCount > 0 ? '$urgentCount urgent' : null,
                        badgeTone: _Tone.red,
                      ),
                      _StatData(
                        icon: Icons.hourglass_top_rounded,
                        color: _kAmber,
                        label: 'Avg wait right now',
                        value: avgWaitNow == null ? '—' : _fmtDuration(avgWaitNow),
                        badge: avgWaitNow == null
                            ? null
                            : (avgWaitNow <= _kWaitTarget ? 'On target' : 'Over target'),
                        badgeTone: avgWaitNow != null && avgWaitNow <= _kWaitTarget
                            ? _Tone.green
                            : _Tone.red,
                      ),
                      _StatData(
                        icon: Icons.timer_outlined,
                        color: _kRed,
                        label: 'Waiting over ${_kWaitTarget.inMinutes} min',
                        value: '$breachingCount',
                        badge: breachingCount > 0 ? 'breach' : 'clear',
                        badgeTone: breachingCount > 0 ? _Tone.red : _Tone.green,
                      ),
                      _StatData(
                        icon: Icons.task_alt_rounded,
                        color: _kGreen,
                        label: isToday ? 'Seen today' : 'Seen (${bounds.label})',
                        value: '$completedCount',
                        suffix: 'of ${allTokens.length}',
                        badge: isAppointmentsEnabled && prebookedCount > 0
                            ? '$prebookedCount pre-booked'
                            : null,
                        badgeTone: _Tone.indigo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ===========================================================
                  // 3. FILTER ROW — source, session, sort, search
                  // ===========================================================
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (isAppointmentsEnabled) ...[
                                _SegmentedPills<QueueSourceFilter>(
                                  selected: selectedSource,
                                  options: const [
                                    _Segment(QueueSourceFilter.all, 'Everyone'),
                                    _Segment(QueueSourceFilter.walkInOnly, 'Walk-ins'),
                                    _Segment(QueueSourceFilter.prebookedOnly, 'Pre-booked'),
                                  ],
                                  onChanged: (s) =>
                                      ref.read(queueSourceFilterProvider.notifier).state = s,
                                ),
                                const SizedBox(width: 8),
                              ],
                              _SegmentedPills<QueueSessionFilter>(
                                selected: selectedSession,
                                options: const [
                                  _Segment(QueueSessionFilter.all, 'All day'),
                                  _Segment(QueueSessionFilter.morning, 'Morning'),
                                  _Segment(QueueSessionFilter.afternoon, 'Afternoon'),
                                  _Segment(QueueSessionFilter.evening, 'Evening'),
                                ],
                                onChanged: (s) =>
                                    ref.read(queueSessionFilterProvider.notifier).state = s,
                              ),
                              const SizedBox(width: 8),
                              _SortPill(
                                value: _sortLongestWait ? 'Longest wait' : 'Queue order',
                                onTap: () => setState(() => _sortLongestWait = !_sortLongestWait),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_searchQuery.isNotEmpty) ...[
                        Text(
                          'Showing ${visibleTokens.length} of ${allTokens.length} patients',
                          style: const TextStyle(fontSize: 12, color: _kMuted),
                        ),
                        const SizedBox(width: 10),
                      ],
                      SizedBox(
                        width: 240,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                          style: const TextStyle(fontSize: 12.5, color: _kInk),
                          decoration: InputDecoration(
                            hintText: 'Search patient / token #...',
                            hintStyle: const TextStyle(fontSize: 12.5, color: _kFaint),
                            prefixIcon: const Icon(Icons.search_rounded, size: 17, color: _kMuted),
                            prefixIconConstraints: const BoxConstraints(minWidth: 34),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kLine),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kLine),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kAccentBlue, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ===========================================================
                  // 4. PATIENT FLOW BOARD
                  // ===========================================================
                  Expanded(
                    child: queueAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, st) => Center(
                        child: Text(
                          'Failed to load queue: $err',
                          style: const TextStyle(color: _kRed),
                        ),
                      ),
                      data: (_) => _buildBoard(
                        allTokens: allTokens,
                        waitingTokens: waitingTokens,
                        activeServing: activeServing,
                        isToday: isToday,
                        now: now,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  String _periodCaption(DateBounds bounds) {
    final now = DateTime.now();
    if (bounds.label == 'Today') return DateFormat('EEEE, MMM d').format(now);
    if (bounds.label == 'Tomorrow') {
      return DateFormat('EEEE, MMM d').format(now.add(const Duration(days: 1)));
    }
    return '${DateFormat('MMM d').format(bounds.start)} – ${DateFormat('MMM d, yyyy').format(bounds.end)}';
  }

  Widget _buildBoard({
    required List<QueueEntryWithPatient> allTokens,
    required List<QueueEntryWithPatient> waitingTokens,
    required QueueEntryWithPatient? activeServing,
    required bool isToday,
    required DateTime now,
  }) {
    List<QueueEntryWithPatient> withStatus(Set<QueueStatus> statuses) => allTokens
        .where((t) => statuses.contains(t.entry.status) && _matchesSearch(t))
        .toList();

    final waiting = waitingTokens.where(_matchesSearch).toList();
    if (_sortLongestWait) {
      waiting.sort((a, b) => a.entry.checkedInAt.compareTo(b.entry.checkedInAt));
    }
    final called = withStatus({QueueStatus.called});
    final inConsult = withStatus({QueueStatus.inConsultation});
    final skipped = withStatus({QueueStatus.skipped, QueueStatus.cancelled})
      ..sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
    final done = withStatus({QueueStatus.completed})
      ..sort((a, b) => (b.entry.completedAt ?? b.entry.updatedAt)
          .compareTo(a.entry.completedAt ?? a.entry.updatedAt));

    // The token `callNext` will pick: provider order mirrors the repository's
    // (urgent first, then lowest token number). Only callable for today.
    String? nextUpId;
    if (isToday && activeServing == null) {
      for (final t in waitingTokens) {
        if (t.entry.tokenNumber > 0) {
          nextUpId = t.entry.id;
          break;
        }
      }
    }

    // Summary stats come from the whole period, not the search results.
    final completedAll = allTokens.where((t) => t.entry.status == QueueStatus.completed);
    final avgConsult = _average(completedAll
        .where((t) => t.entry.consultationStartedAt != null && t.entry.completedAt != null)
        .map((t) => t.entry.completedAt!.difference(t.entry.consultationStartedAt!))
        .where((d) => !d.isNegative));
    final avgWaitSeen = _average(completedAll
        .where((t) => t.entry.calledAt != null)
        .map((t) => t.entry.calledAt!.difference(t.entry.checkedInAt))
        .where((d) => !d.isNegative));
    final droppedCount = allTokens
        .where((t) =>
            t.entry.status == QueueStatus.skipped || t.entry.status == QueueStatus.cancelled)
        .length;

    final columns = <Widget>[
      _BoardColumn(
        title: 'Waiting',
        count: waiting.length,
        meta: 'target ${_kWaitTarget.inMinutes}m',
        cards: [for (final t in waiting) _buildCard(t, now, isNextUp: t.entry.id == nextUpId)],
        footer: _AddPatientButton(onTap: _openCheckIn),
      ),
      _BoardColumn(
        title: 'Called',
        count: called.length,
        meta: 'at the door',
        cards: [for (final t in called) _buildCard(t, now)],
      ),
      _BoardColumn(
        title: 'In Consultation',
        count: inConsult.length,
        meta: avgConsult == null ? null : 'avg ${_fmtDuration(avgConsult)}',
        cards: [for (final t in inConsult) _buildCard(t, now)],
      ),
      _BoardColumn(
        title: 'Skipped',
        count: skipped.length,
        meta: 'no-show / cancelled',
        cards: [for (final t in skipped) _buildCard(t, now)],
      ),
      _BoardColumn(
        title: isToday ? 'Seen today' : 'Seen',
        count: done.length,
        meta: avgWaitSeen == null ? null : 'avg wait ${_fmtDuration(avgWaitSeen)}',
        tinted: true,
        header: _SummaryCard(
          title: isToday ? 'Today so far' : 'This period so far',
          seen: completedAll.length,
          total: allTokens.length,
          avgConsult: avgConsult,
          dropped: droppedCount,
        ),
        cards: [for (final t in done) _buildCard(t, now)],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const minColumnWidth = 232.0;
        final needed = columns.length * minColumnWidth + (columns.length - 1) * gap;

        if (constraints.maxWidth >= needed) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: columns[i]),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(width: minColumnWidth, child: columns[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(QueueEntryWithPatient item, DateTime now, {bool isNextUp = false}) {
    final entry = item.entry;

    final chips = <Widget>[
      _Chip(
        label: entry.tokenNumber > 0 ? '#${entry.tokenNumber}' : 'Appt',
        tone: _Tone.neutral,
        bold: true,
      ),
      _timeChip(item, now),
      if (entry.priority == QueuePriority.urgent)
        const _Chip(label: 'Urgent', icon: Icons.priority_high_rounded, tone: _Tone.red),
      if (item.isPrebooked)
        _Chip(
          label: item.appointmentTime != null
              ? DateFormat('h:mm a').format(item.appointmentTime!)
              : 'Pre-booked',
          icon: Icons.event_available_rounded,
          tone: _Tone.indigo,
        ),
    ];

    String? note;
    if (entry.status == QueueStatus.waiting) {
      final waited = _waitingFor(item, now);
      if (waited != null && waited > _kWaitTarget) {
        note = '${_fmtDuration(waited - _kWaitTarget)} over the '
            '${_kWaitTarget.inMinutes}m wait target.';
      }
    } else if (_isCalledTooLong(item, now)) {
      note = 'Called ${_fmtDuration(now.difference(entry.calledAt!))} ago '
          'and not in the room yet.';
    }

    final cancel = _CardAction(
      'Cancel token',
      Icons.close_rounded,
      () => _cancelToken(entry.id, entry.tokenNumber),
      destructive: true,
    );
    final skip = _CardAction(
      'Skip',
      Icons.skip_next_rounded,
      () => _skipToken(entry.id, entry.tokenNumber),
    );

    _CardAction? primary;
    final menu = <_CardAction>[];
    switch (entry.status) {
      case QueueStatus.waiting:
        if (item.isPrebooked && entry.tokenNumber == 0) {
          primary = _CardAction('Check in', Icons.login_rounded, () => _checkInPrebooked(item));
        } else if (isNextUp) {
          primary = _CardAction(
            _isCallingNext ? 'Calling…' : 'Call next',
            Icons.campaign_rounded,
            _isCallingNext ? null : _callNextToken,
            filled: true,
          );
        }
        menu.addAll([skip, cancel]);
      case QueueStatus.called:
        primary = _CardAction(
          'Start consult',
          Icons.play_arrow_rounded,
          () => _startConsultation(entry.id, entry.tokenNumber),
          filled: true,
        );
        menu.addAll([
          _CardAction(
            'Complete now',
            Icons.check_rounded,
            () => _completeConsultation(entry.id, entry.tokenNumber),
          ),
          skip,
          cancel,
        ]);
      case QueueStatus.inConsultation:
        primary = _CardAction(
          'Complete',
          Icons.check_rounded,
          () => _completeConsultation(entry.id, entry.tokenNumber),
          filled: true,
          color: _kGreen,
        );
        menu.add(cancel);
      case QueueStatus.skipped:
        primary = _CardAction(
          'Requeue',
          Icons.replay_rounded,
          () => _requeueToken(entry.id, entry.tokenNumber),
        );
        menu.add(cancel);
      case QueueStatus.completed:
      case QueueStatus.cancelled:
        break;
    }

    return _PatientCard(
      name: item.displayName,
      reason: (entry.reason == null || entry.reason!.trim().isEmpty) ? null : entry.reason!.trim(),
      chips: chips,
      note: note,
      primary: primary,
      menu: menu,
      dimmed: false,
      raised: isNextUp || note != null,
      muted: entry.status == QueueStatus.completed || entry.status == QueueStatus.cancelled,
    );
  }

  Widget _timeChip(QueueEntryWithPatient item, DateTime now) {
    final entry = item.entry;
    switch (entry.status) {
      case QueueStatus.waiting:
        final waited = _waitingFor(item, now);
        if (waited != null) {
          final tone = waited > _kWaitTarget
              ? _Tone.red
              : (waited > _kWaitTarget ~/ 2 ? _Tone.amber : _Tone.neutral);
          return _Chip(label: _fmtDuration(waited), icon: Icons.schedule_rounded, tone: tone);
        }
        if (entry.checkedInAt.isAfter(now)) {
          return const _Chip(label: 'Upcoming', icon: Icons.schedule_rounded, tone: _Tone.neutral);
        }
        return _Chip(
          label: DateFormat('MMM d').format(entry.checkedInAt),
          icon: Icons.calendar_today_rounded,
          tone: _Tone.neutral,
        );
      case QueueStatus.called:
        final calledAt = entry.calledAt;
        if (calledAt != null && _isSameDay(calledAt, now)) {
          final since = now.difference(calledAt);
          return _Chip(
            label: 'Called ${_fmtDuration(since)}',
            icon: Icons.campaign_rounded,
            tone: since > _kCalledTarget ? _Tone.red : _Tone.amber,
          );
        }
        return const _Chip(label: 'Called', icon: Icons.campaign_rounded, tone: _Tone.amber);
      case QueueStatus.inConsultation:
        final startedAt = entry.consultationStartedAt;
        if (startedAt != null && _isSameDay(startedAt, now)) {
          return _Chip(
            label: 'In room ${_fmtDuration(now.difference(startedAt))}',
            icon: Icons.meeting_room_outlined,
            tone: _Tone.blue,
          );
        }
        return const _Chip(label: 'In room', icon: Icons.meeting_room_outlined, tone: _Tone.blue);
      case QueueStatus.completed:
        return _Chip(
          label: 'Done ${DateFormat('h:mm a').format(entry.completedAt ?? entry.updatedAt)}',
          icon: Icons.check_circle_outline_rounded,
          tone: _Tone.green,
        );
      case QueueStatus.skipped:
        return const _Chip(label: 'Skipped', icon: Icons.skip_next_rounded, tone: _Tone.amber);
      case QueueStatus.cancelled:
        return const _Chip(label: 'Cancelled', icon: Icons.block_rounded, tone: _Tone.red);
    }
  }
}

// =============================================================================
// BOARD COLUMN
// =============================================================================

class _BoardColumn extends StatelessWidget {
  final String title;
  final int count;
  final String? meta;
  final List<Widget> cards;
  final Widget? header;
  final Widget? footer;
  final bool tinted;

  const _BoardColumn({
    required this.title,
    required this.count,
    required this.cards,
    this.meta,
    this.header,
    this.footer,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: tinted ? _kGreenColumn : _kColumnBg,
        borderRadius: BorderRadius.circular(14),
        border: tinted ? Border.all(color: _kGreenBorder) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    meta ?? '',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _kMuted),
                  ),
                ),
              ],
            ),
          ),
          if (header != null) ...[
            header!,
            const SizedBox(height: 8),
          ],
          if (cards.isEmpty && header == null)
            const _EmptySlot()
          else if (cards.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 2),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => cards[i],
              ),
            ),
          if (footer != null) ...[
            const SizedBox(height: 4),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: const Text(
        'No patients',
        style: TextStyle(fontSize: 12, color: _kFaint),
      ),
    );
  }
}

class _AddPatientButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPatientButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _kMuted,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text(
        '+ Check in patient',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final int seen;
  final int total;
  final Duration? avgConsult;
  final int dropped;

  const _SummaryCard({
    required this.title,
    required this.seen,
    required this.total,
    required this.avgConsult,
    required this.dropped,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : seen / total;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kInk),
          ),
          const SizedBox(height: 8),
          _row('Seen', '$seen'),
          _row('Avg consult', avgConsult == null ? '—' : _fmtDuration(avgConsult!)),
          _row('Skipped / cancelled', '$dropped'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: _kColumnBg,
              valueColor: const AlwaysStoppedAnimation(_kGreen),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(ratio * 100).round()}% of queue seen',
            style: const TextStyle(fontSize: 11, color: _kMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kInk),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PATIENT CARD
// =============================================================================

class _CardAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool destructive;

  /// Fill colour for a [filled] action.
  final Color color;

  const _CardAction(
    this.label,
    this.icon,
    this.onTap, {
    this.filled = false,
    this.destructive = false,
    this.color = _kAccentBlue,
  });
}

class _PatientCard extends StatelessWidget {
  final String name;
  final String? reason;
  final List<Widget> chips;
  final String? note;
  final _CardAction? primary;
  final List<_CardAction> menu;
  final bool dimmed;
  final bool raised;
  final bool muted;

  const _PatientCard({
    required this.name,
    required this.reason,
    required this.chips,
    required this.note,
    required this.primary,
    required this.menu,
    required this.dimmed,
    required this.raised,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: dimmed ? 0.4 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: muted ? Colors.white.withValues(alpha: 0.65) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: raised ? _kAccentBlue.withValues(alpha: 0.35) : _kLine),
          boxShadow: muted
              ? null
              : raised
                  ? const [
                      BoxShadow(color: Color(0x140284C7), blurRadius: 14, offset: Offset(0, 4)),
                    ]
                  : const [
                      BoxShadow(color: Color(0x040F172A), blurRadius: 10, offset: Offset(0, 2)),
                    ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: name),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kInk,
                        ),
                      ),
                      if (reason != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          reason!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: _kMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (menu.isNotEmpty) _CardMenu(actions: menu),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
            if (note != null) ...[
              const SizedBox(height: 8),
              _NoteBanner(text: note!),
            ],
            if (primary != null) ...[
              const SizedBox(height: 10),
              _CardButton(action: primary!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  static const _palette = [
    _kAccentBlue,
    _kIndigo,
    Color(0xFF8B5CF6),
    _kGreen,
    _kAmber,
    _kRed,
    Color(0xFF0EA5E9),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final seed = trimmed.codeUnits.fold<int>(0, (sum, c) => sum + c);
    final color = _palette[seed % _palette.length];
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  final List<_CardAction> actions;

  const _CardMenu({required this.actions});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<int>(
        tooltip: 'More actions',
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: const Icon(Icons.more_horiz_rounded, color: _kMuted),
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onSelected: (i) => actions[i].onTap?.call(),
        itemBuilder: (_) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 36,
              enabled: actions[i].onTap != null,
              child: Row(
                children: [
                  Icon(
                    actions[i].icon,
                    size: 16,
                    color: actions[i].destructive ? _kRed : _kMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    actions[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      color: actions[i].destructive ? _kRed : _kInk,
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

class _CardButton extends StatelessWidget {
  final _CardAction action;

  const _CardButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      action.label,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
    final icon = Icon(action.icon, size: 15);

    return SizedBox(
      width: double.infinity,
      height: 32,
      child: action.filled
          ? ElevatedButton.icon(
              onPressed: action.onTap,
              icon: icon,
              label: label,
              style: ElevatedButton.styleFrom(
                backgroundColor: action.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: action.color.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
            )
          : OutlinedButton.icon(
              onPressed: action.onTap,
              icon: icon,
              label: label,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccentBlue,
                backgroundColor: Colors.white,
                side: const BorderSide(color: _kLine),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
            ),
    );
  }
}

class _NoteBanner extends StatelessWidget {
  final String text;

  const _NoteBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFD97706)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, height: 1.3, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CHIPS
// =============================================================================

enum _Tone { neutral, amber, red, green, blue, indigo }

extension on _Tone {
  Color get background => switch (this) {
        _Tone.neutral => _kColumnBg,
        _Tone.amber => const Color(0xFFFFFBEB),
        _Tone.red => const Color(0xFFFFF1F2),
        _Tone.green => const Color(0xFFECFDF5),
        _Tone.blue => const Color(0xFFE0F2FE),
        _Tone.indigo => _kIndigo.withValues(alpha: 0.12),
      };

  Color get foreground => switch (this) {
        _Tone.neutral => const Color(0xFF475569),
        _Tone.amber => const Color(0xFFD97706),
        _Tone.red => _kRed,
        _Tone.green => const Color(0xFF059669),
        _Tone.blue => _kAccentBlue,
        _Tone.indigo => _kIndigo,
      };
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final _Tone tone;
  final bool bold;

  const _Chip({
    required this.label,
    required this.tone,
    this.icon,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone.foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: tone.foreground,
            ),
          ),
        ],
      ),
    );
  }
}


// =============================================================================
// STATS STRIP
// =============================================================================

class _StatData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? suffix;
  final String? badge;
  final _Tone badgeTone;

  const _StatData({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.suffix,
    this.badge,
    this.badgeTone = _Tone.neutral,
  });
}

class _StatsStrip extends StatelessWidget {
  final List<_StatData> stats;

  const _StatsStrip({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
        boxShadow: const [
          BoxShadow(color: Color(0x040F172A), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 1, height: 36, color: _kLine),
            Expanded(child: _StatTile(data: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final _StatData data;

  const _StatTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, size: 20, color: data.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: _kMuted),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: data.value,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _kInk,
                                fontFamily: AppColors.headingFontFamily,
                              ),
                            ),
                            if (data.suffix != null)
                              TextSpan(
                                text: ' ${data.suffix}',
                                style: const TextStyle(fontSize: 12.5, color: _kMuted),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (data.badge != null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: _Chip(label: data.badge!, tone: data.badgeTone)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SEGMENTED PILLS & SORT
// =============================================================================

class _Segment<T> {
  final T value;
  final String label;
  final IconData? icon;

  const _Segment(this.value, this.label, {this.icon});
}

class _SegmentedPills<T> extends StatelessWidget {
  final List<_Segment<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const _SegmentedPills({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kColumnBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final o in options) _item(o)],
      ),
    );
  }

  Widget _item(_Segment<T> option) {
    final isSelected = option.value == selected;
    return InkWell(
      onTap: () => onChanged(option.value),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? const [
                  BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 1)),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon, size: 14, color: isSelected ? _kAccentBlue : _kMuted),
              const SizedBox(width: 5),
            ],
            Text(
              option.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _kAccentBlue : _kMuted,
                fontFamily: AppColors.bodyFontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _SortPill({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded, size: 15, color: _kMuted),
            const SizedBox(width: 6),
            const Text('Sort', style: TextStyle(fontSize: 12, color: _kMuted)),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kAccentBlue),
            ),
          ],
        ),
      ),
    );
  }
}
