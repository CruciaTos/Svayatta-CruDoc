import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appts_header.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter/services.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';

/// How long a patient may wait in line before their card is flagged
/// as breaching the target.
const Duration _kWaitTarget = Duration(minutes: 20);

/// How long a called patient may take to reach the room before their
/// card is flagged.
const Duration _kCalledTarget = Duration(minutes: 5);

/// Board columns never get narrower than this; below it the board scrolls.
const double _kMinColumnWidth = 212;

/// Opacity of an action that can't run right now.
const double _kDisabledOpacity = 0.45;

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

/// A pre-booked patient whose slot hasn't come and who hasn't been marked
/// arrived: in the queue, but not here yet.
bool _isExpected(QueueEntryWithPatient item, DateTime now) =>
    item.entry.status == QueueStatus.waiting &&
    item.isPrebooked &&
    item.entry.checkedInAt.isAfter(now);

bool _isActiveUrgent(QueueEntryWithPatient item) =>
    item.entry.priority == QueuePriority.urgent &&
    (item.entry.status == QueueStatus.waiting || item.entry.isActiveServing);

/// The Schedule's Live view: today's patient flow.
///
/// A board with a column per stage (expected → waiting → called → in
/// consultation, plus skipped), live wait timers, target-breach flags and
/// per-card actions. The header's main button is always the one next
/// step: call next, start consult, or finish & call next.
class DesktopQueueScreen extends ConsumerStatefulWidget {
  const DesktopQueueScreen({super.key});

  @override
  ConsumerState<DesktopQueueScreen> createState() => _DesktopQueueScreenState();
}

class _DesktopQueueScreenState extends ConsumerState<DesktopQueueScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _busy = false;

  /// Everyone on each shared token (patients seen together), by group id;
  /// rebuilt with the board.
  Map<String, List<QueueEntryWithPatient>> _groups = const {};
  bool _sortLongestWait = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Live is today only (the calendar views cover other days).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(queuePeriodProvider) != QueuePeriod.today) {
        ref.read(queuePeriodProvider.notifier).state = QueuePeriod.today;
      }
    });
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

  void _showFeedback(String message) {
    if (!mounted) return;
    final c = context.cru;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: CruType.text.tint(c.surface)),
        backgroundColor: c.label,
        behavior: SnackBarBehavior.floating,
        shape: cruShape(CruRadius.control),
        margin: const EdgeInsets.all(CruSpace.s16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _callNextToken() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(queueRepositoryProvider);
      final next = await repo.callNext(
        allowConcurrent: ref.read(isPhysiotherapyProvider),
      );
      _showFeedback('Token #${next.tokenNumber} called to consultation room.');
    } on QueueAlreadyServingException catch (e) {
      _showFeedback(e.message);
    } on QueueEmptyException {
      _showFeedback('No patients are waiting in the queue.');
    } catch (e) {
      _showFeedback('Error calling next token: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One click between patients: completes the current consultation and
  /// calls the next token.
  Future<void> _finishAndCallNext(String entryId, int tokenNumber) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.complete(entryId);
      try {
        final next = await repo.callNext();
        _showFeedback(
          'Token #$tokenNumber done. Token #${next.tokenNumber} called.',
        );
      } on QueueEmptyException {
        _showFeedback('Token #$tokenNumber done. Nobody else is waiting.');
      }
    } catch (e) {
      _showFeedback('Could not finish the consultation: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Adds a patient to [item]'s token. A booked appointment gets a visit
  /// for them too (their own history); a walk-in token just the token.
  Future<void> _addToToken(QueueEntryWithPatient item) async {
    final root = Navigator.of(context, rootNavigator: true).context;
    final patient = await showPatientPickerDialog(root, title: 'Who else is coming?');
    if (patient == null || !mounted) return;
    try {
      final lead = item.linkedVisit;
      if (lead != null) {
        final now = DateTime.now();
        final added = await ref.read(visitRepositoryProvider).addToGroup(
              lead,
              Visit(
                id: '',
                patientId: patient.id,
                scheduledStart: lead.scheduledStart,
                durationMinutes: lead.durationMinutes,
                address: lead.address,
                visitType: lead.visitType,
                status: VisitStatus.scheduled,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await ref
            .read(queueRepositoryProvider)
            .adoptVisitGroup([lead.id], added.groupId);
      } else {
        await ref
            .read(queueRepositoryProvider)
            .addToToken(item.entry.id, patientId: patient.id);
      }
      _showFeedback('${patient.firstName} added to Token #${item.entry.tokenNumber}.');
    } catch (e) {
      _showFeedback('Could not add ${patient.firstName}: $e');
    }
  }

  Future<void> _leaveToken(QueueEntryWithPatient member) async {
    try {
      await ref.read(queueRepositoryProvider).leaveToken(member.entry.id);
      _showFeedback('${member.displayName} taken off the token.');
    } catch (e) {
      _showFeedback('Could not change the token: $e');
    }
  }

  Future<void> _markArrived(QueueEntryWithPatient item) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      var entryId = item.entry.id;
      var token = item.entry.tokenNumber;
      // Not registered yet (in memory until the database catches up).
      if (token == 0 && item.linkedVisit != null) {
        final created = await repo.checkInVisit(item.linkedVisit!);
        entryId = created.id;
        token = created.tokenNumber;
      }
      await repo.markArrived(entryId);
      _showFeedback('${item.displayName} is here: Token #$token is waiting.');
    } catch (e) {
      _showFeedback('Could not mark as arrived: $e');
    }
  }

  Future<void> _startConsultation(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.startConsultation(entryId);
      _showFeedback('Started consultation with Token #$tokenNumber.');
    } catch (e) {
      _showFeedback('Could not start consultation: $e');
    }
  }

  Future<void> _completeConsultation(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.complete(entryId);
      _showFeedback('Token #$tokenNumber consultation completed.');
    } catch (e) {
      _showFeedback('Could not complete consultation: $e');
    }
  }

  Future<void> _skipToken(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.skip(entryId);
      _showFeedback('Token #$tokenNumber marked as skipped.');
    } catch (e) {
      _showFeedback('Could not skip token: $e');
    }
  }

  Future<void> _requeueToken(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.requeue(entryId);
      _showFeedback('Token #$tokenNumber requeued in original numeric order.');
    } catch (e) {
      _showFeedback('Could not requeue token: $e');
    }
  }

  Future<void> _cancelToken(String entryId, int tokenNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CancelTokenDialog(tokenNumber: tokenNumber),
    );

    if (confirmed == true) {
      try {
        final repo = ref.read(queueRepositoryProvider);
        await repo.cancel(entryId);
        _showFeedback('Token #$tokenNumber has been cancelled.');
      } catch (e) {
        _showFeedback('Could not cancel token: $e');
      }
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
    final c = context.cru;
    final queueAsync = ref.watch(todaysQueueWithPatientsProvider);
    final activeServing = ref.watch(activeQueueEntryProvider);
    final serving = ref.watch(servingQueueEntriesProvider);
    // Physiotherapy runs several sessions at once.
    final concurrent = ref.watch(isPhysiotherapyProvider);
    final waitingTokens = ref.watch(waitingQueueProvider);
    final selectedPeriod = ref.watch(queuePeriodProvider);
    final selectedSession = ref.watch(queueSessionFilterProvider);
    final selectedSource = ref.watch(queueSourceFilterProvider);
    final isAppointmentsEnabled = ref.watch(
      isAppointmentsFeatureEnabledProvider,
    );

    final now = DateTime.now();
    final isToday = selectedPeriod == QueuePeriod.today;
    final loaded = queueAsync.hasValue;
    final allTokens = queueAsync.value ?? const <QueueEntryWithPatient>[];
    final expectedCount = waitingTokens
        .where((t) => _isExpected(t, now))
        .length;
    final waitingCount = waitingTokens.length - expectedCount;

    int countStatus(QueueStatus s) =>
        allTokens.where((t) => t.entry.status == s).length;
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

    final avgConsult = _avgConsult(allTokens);
    final droppedCount = allTokens
        .where(
          (t) =>
              t.entry.status == QueueStatus.skipped ||
              t.entry.status == QueueStatus.cancelled,
        )
        .length;
    final seenRatio = allTokens.isEmpty
        ? 0.0
        : completedCount / allTokens.length;

    final visibleTokens = allTokens.where(_matchesSearch).toList();
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header: the Schedule frame (same slots as the calendar);
          // the filled button is always the one next step.
          ScheduleHeaderFrame(
            stepLabel: 'day',
            onToday: ref.read(apptsControllerProvider.notifier).today,
            onStep: ref.read(apptsControllerProvider.notifier).step,
            title: ScheduleTitle(
              title: ApptFormat.dateLine(now),
              shortTitle: DateFormat('EEE, d MMMM').format(now),
              // What the token display shows: who is in, who is next.
              summary: loaded
                  ? _servingLine(serving, waitingTokens, now, concurrent)
                  : null,
            ),
            primary: _nextStepButton(serving, waitingCount, concurrent),
          ),
          const SizedBox(height: CruSpace.cardGap),

          // 2. Live stats.
          GlanceStrip(
            semanticLabel: 'Queue at a glance',
            cells: loaded
                ? [
                    _StatCell(
                      label: 'In the clinic now',
                      value: '$inClinicCount',
                      suffix: inClinicCount == 1 ? 'patient' : 'patients',
                      caption: urgentCount > 0
                          ? _DotCaption(
                              dot: CruDotKind.waiting,
                              text: '$urgentCount urgent',
                              color: c.amberText,
                            )
                          : Text(
                              expectedCount > 0
                                  ? '$expectedCount more booked for later'
                                  : 'No more bookings today',
                            ),
                    ),
                    _StatCell(
                      label: 'Avg wait right now',
                      value: avgWaitNow == null
                          ? '—'
                          : _fmtDuration(avgWaitNow),
                      caption: avgWaitNow == null
                          ? const Text('Nobody waiting')
                          : avgWaitNow <= _kWaitTarget
                          ? _DotCaption(
                              dot: CruDotKind.done,
                              text:
                                  'Within the ${_kWaitTarget.inMinutes} min target',
                              color: c.greenText,
                            )
                          : _DotCaption(
                              dot: CruDotKind.waiting,
                              text:
                                  'Over the ${_kWaitTarget.inMinutes} min target',
                              color: c.amberText,
                            ),
                    ),
                    _StatCell(
                      label: 'Waiting over ${_kWaitTarget.inMinutes} min',
                      value: '$breachingCount',
                      caption: breachingCount > 0
                          ? _DotCaption(
                              dot: CruDotKind.waiting,
                              text: 'Past the wait target',
                              color: c.amberText,
                            )
                          : const Text('Everyone within target'),
                    ),
                    _StatCell(
                      label: 'Seen today',
                      value: '$completedCount',
                      suffix: 'of ${allTokens.length}',
                      progress: seenRatio,
                      caption: Text(
                        [
                          '${(seenRatio * 100).round()}% seen',
                          if (avgConsult != null)
                            'avg consult ${_fmtDuration(avgConsult)}',
                          '$droppedCount skipped',
                        ].join(' · '),
                      ),
                    ),
                  ]
                : const [
                    GlanceCellSkeleton(),
                    GlanceCellSkeleton(),
                    GlanceCellSkeleton(),
                    GlanceCellSkeleton(),
                  ],
          ),
          const SizedBox(height: CruSpace.cardGap),

          // 3. Filters: source chips, session, search, sort, check in. Two
          // rows when narrow (tablets in portrait).
          LayoutBuilder(
            builder: (context, constraints) {
              final chips = <Widget>[
                if (isAppointmentsEnabled) ...[
                  for (final (source, label) in const [
                    (QueueSourceFilter.all, 'Everyone'),
                    (QueueSourceFilter.walkInOnly, 'Walk-ins'),
                    (QueueSourceFilter.prebookedOnly, 'Pre-booked'),
                  ]) ...[
                    _FilterChip(
                      label: label,
                      selected: selectedSource == source,
                      onTap: () =>
                          ref.read(queueSourceFilterProvider.notifier).state =
                              source,
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  const SizedBox(width: CruSpace.s4),
                ],
                _MenuSelect<QueueSessionFilter>(
                  prefix: 'Session',
                  value: selectedSession,
                  options: QueueSessionFilter.values,
                  shortLabel: _sessionShort,
                  itemLabel: (s) =>
                      s == QueueSessionFilter.all ? 'All day' : s.label,
                  onSelected: (s) =>
                      ref.read(queueSessionFilterProvider.notifier).state = s,
                ),
              ];
              final search = <Widget>[
                Expanded(
                  child: _QueueSearchField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  const SizedBox(width: CruSpace.s12),
                  Text(
                    'Showing ${visibleTokens.length} of ${allTokens.length}',
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                ],
              ];
              final sort = _MenuSelect<bool>(
                prefix: 'Sort',
                value: _sortLongestWait,
                options: const [false, true],
                shortLabel: (v) => v ? 'Longest wait' : 'Queue order',
                itemLabel: (v) => v ? 'Longest wait first' : 'Queue order',
                onSelected: (v) => setState(() => _sortLongestWait = v),
              );
              final checkIn = CruButton(
                label: 'Check in patient',
                kind: CruButtonKind.secondary,
                icon: CruIcons.userPlus,
                onPressed: _openCheckIn,
              );
              if (constraints.maxWidth >= kScheduleHeaderOneRow) {
                return SizedBox(
                  height: CruSize.control,
                  child: Row(
                    children: [
                      ...chips,
                      const SizedBox(width: CruSpace.s12),
                      ...search,
                      const SizedBox(width: CruSpace.s12),
                      sort,
                      const SizedBox(width: CruSpace.s12),
                      checkIn,
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: CruSize.control,
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: chips),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s12),
                        sort,
                      ],
                    ),
                  ),
                  const SizedBox(height: CruSpace.s12),
                  SizedBox(
                    height: CruSize.control,
                    child: Row(
                      children: [
                        ...search,
                        const SizedBox(width: CruSpace.s12),
                        checkIn,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: CruSpace.cardGap),

          // 4. Patient flow board.
          Expanded(
            child: queueAsync.when(
              loading: () => Center(
                child: SizedBox.square(
                  dimension: CruSpace.s24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: c.accent,
                  ),
                ),
              ),
              error: (err, st) => Center(
                child: Text(
                  'Failed to load queue: $err',
                  style: CruType.text.tint(c.label2),
                ),
              ),
              data: (_) => _buildBoard(
                allTokens: allTokens,
                waitingTokens: waitingTokens,
                activeServing: activeServing,
                isToday: isToday,
                concurrent: concurrent,
                showExpected: isAppointmentsEnabled,
                avgConsult: avgConsult,
                now: now,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _sessionShort(QueueSessionFilter s) => switch (s) {
    QueueSessionFilter.all => 'All day',
    QueueSessionFilter.morning => 'Morning',
    QueueSessionFilter.afternoon => 'Afternoon',
    QueueSessionFilter.evening => 'Evening',
  };

  /// "Now serving #6 · next #7" ("In session #6, #9 · next #7" when
  /// sessions run in parallel), or what the queue is waiting for.
  static TextSpan _servingLine(
    List<QueueEntryWithPatient> serving,
    List<QueueEntryWithPatient> waitingTokens,
    DateTime now,
    bool concurrent,
  ) {
    QueueEntryWithPatient? next;
    for (final t in waitingTokens) {
      if (t.entry.tokenNumber > 0 && !_isExpected(t, now)) {
        next = t;
        break;
      }
    }
    // A shared token appears once.
    final tokens =
        {for (final s in serving) '#${s.entry.tokenNumber}'}.join(', ');
    final parts = [
      serving.isEmpty
          ? (concurrent ? 'Nobody in session' : 'Nobody with the doctor')
          : (concurrent ? 'In session $tokens' : 'Now serving $tokens'),
      next == null ? 'nobody waiting' : 'next #${next.entry.tokenNumber}',
    ];
    return TextSpan(text: parts.join(' · '));
  }

  /// The header's filled button: always the one next step. With parallel
  /// sessions the next step is calling the next patient while anyone is
  /// waiting; each session is finished from its own card.
  Widget _nextStepButton(
    List<QueueEntryWithPatient> servingList,
    int waitingCount,
    bool concurrent,
  ) {
    final calledEntry = servingList
        .where((s) => s.entry.status == QueueStatus.called)
        .firstOrNull
        ?.entry;
    final entry = concurrent
        ? (waitingCount > 0 ? null : calledEntry)
        : servingList.firstOrNull?.entry;
    final String label;
    CruIconData? icon;
    VoidCallback? onPressed;
    if (entry != null && entry.status == QueueStatus.inConsultation) {
      final callAfter = waitingCount > 0;
      label = callAfter ? 'Finish & call next' : 'Finish consult';
      icon = callAfter ? CruIcons.megaphone : CruIcons.check;
      onPressed = callAfter
          ? () => _finishAndCallNext(entry.id, entry.tokenNumber)
          : () => _completeConsultation(entry.id, entry.tokenNumber);
    } else if (entry != null) {
      label = 'Start consult';
      onPressed = () => _startConsultation(entry.id, entry.tokenNumber);
    } else {
      label = 'Call next token';
      icon = CruIcons.megaphone;
      onPressed = waitingCount > 0 ? _callNextToken : null;
    }
    final enabled = !_busy && onPressed != null;
    return _Dimmed(
      enabled: enabled,
      child: CruButton(
        label: _busy ? 'Working…' : label,
        icon: icon,
        expand: true,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }

  Widget _buildBoard({
    required List<QueueEntryWithPatient> allTokens,
    required List<QueueEntryWithPatient> waitingTokens,
    required QueueEntryWithPatient? activeServing,
    required bool isToday,
    required bool concurrent,
    required bool showExpected,
    required Duration? avgConsult,
    required DateTime now,
  }) {
    List<QueueEntryWithPatient> withStatus(Set<QueueStatus> statuses) =>
        allTokens
            .where(
              (t) => statuses.contains(t.entry.status) && _matchesSearch(t),
            )
            .toList();

    final expected =
        waitingTokens
            .where((t) => _isExpected(t, now) && _matchesSearch(t))
            .toList()
          ..sort((a, b) => a.entry.checkedInAt.compareTo(b.entry.checkedInAt));
    // Patients seen together share a token: one card for the group.
    final groups = <String, List<QueueEntryWithPatient>>{};
    for (final t in allTokens) {
      final g = t.entry.groupId;
      if (g != null && g.isNotEmpty) groups.putIfAbsent(g, () => []).add(t);
    }
    _groups = groups;
    List<QueueEntryWithPatient> oneCardPerToken(
      List<QueueEntryWithPatient> list,
    ) {
      final seen = <String>{};
      return [
        for (final t in list)
          if (t.entry.groupId == null ||
              t.entry.groupId!.isEmpty ||
              seen.add(t.entry.groupId!))
            t,
      ];
    }

    final waiting = oneCardPerToken(
      waitingTokens
          .where((t) => !_isExpected(t, now) && _matchesSearch(t))
          .toList(),
    );
    final readyCount = waitingTokens.where((t) => !_isExpected(t, now)).length;
    if (_sortLongestWait) {
      waiting.sort(
        (a, b) => a.entry.checkedInAt.compareTo(b.entry.checkedInAt),
      );
    }
    final called = oneCardPerToken(withStatus({QueueStatus.called}));
    final inConsult = oneCardPerToken(withStatus({QueueStatus.inConsultation}));
    final skipped = withStatus({QueueStatus.skipped, QueueStatus.cancelled})
      ..sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
    // The token `callNext` will pick: provider order mirrors the repository's
    // (urgent first, then lowest token number). Only callable for today.
    String? nextUpId;
    if (isToday && (activeServing == null || concurrent)) {
      for (final t in waitingTokens) {
        if (t.entry.tokenNumber > 0 && !_isExpected(t, now)) {
          nextUpId = t.entry.id;
          break;
        }
      }
    }

    final columns = <Widget>[
      if (showExpected)
        _BoardColumn(
          title: 'Expected',
          dot: CruDotKind.booked,
          count: expected.length,
          cards: [for (final t in expected) _buildCard(t, now)],
        ),
      _BoardColumn(
        title: 'Waiting',
        dot: CruDotKind.waiting,
        count: waiting.length,
        cards: [
          for (final t in waiting)
            _buildCard(t, now, isNextUp: t.entry.id == nextUpId),
        ],
      ),
      _BoardColumn(
        title: 'Called',
        dot: CruDotKind.waiting,
        count: called.length,
        cards: [for (final t in called) _buildCard(t, now)],
      ),
      _BoardColumn(
        title: concurrent ? 'In session' : 'In consultation',
        dot: CruDotKind.now,
        ink: inConsult.isNotEmpty,
        count: inConsult.length,
        meta: avgConsult == null ? null : 'avg ${_fmtDuration(avgConsult)}',
        cards: [
          for (final t in inConsult)
            // Parallel sessions finish one by one; calling is separate.
            _buildCard(t, now, callAfter: !concurrent && readyCount > 0),
        ],
      ),
      _BoardColumn(
        title: 'Skipped',
        dot: CruDotKind.inactive,
        count: skipped.length,
        cards: [for (final t in skipped) _buildCard(t, now)],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = CruSpace.s12;
        final needed =
            columns.length * _kMinColumnWidth + (columns.length - 1) * gap;

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
                  SizedBox(width: _kMinColumnWidth, child: columns[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Average consultation length over the period's completed tokens.
  static Duration? _avgConsult(List<QueueEntryWithPatient> tokens) => _average(
    tokens
        .where(
          (t) =>
              t.entry.status == QueueStatus.completed &&
              t.entry.consultationStartedAt != null &&
              t.entry.completedAt != null,
        )
        .map(
          (t) =>
              t.entry.completedAt!.difference(t.entry.consultationStartedAt!),
        )
        .where((d) => !d.isNegative),
  );

  Widget _buildCard(
    QueueEntryWithPatient item,
    DateTime now, {
    bool isNextUp = false,
    bool callAfter = false,
  }) {
    final entry = item.entry;
    final expected = _isExpected(item, now);
    final group = entry.groupId == null ? null : _groups[entry.groupId];
    final members = group == null || group.length < 2 ? [item] : group;
    String names(List<String> n) => n.length == 1
        ? n.first
        : n.length == 2
        ? '${n[0]} & ${n[1]}'
        : '${n.first} + ${n.length - 1}';
    final reasons = {
      for (final m in members)
        if (m.entry.reason != null && m.entry.reason!.trim().isNotEmpty)
          m.entry.reason!.trim(),
    };

    final pills = <Widget>[
      _Tag(
        label: entry.tokenNumber > 0 ? '#${entry.tokenNumber}' : 'Appt',
        tone: _TagTone.surface,
        strong: true,
      ),
      _timeTag(item, now),
      if (entry.priority == QueuePriority.urgent)
        const _Tag(
          label: 'Urgent',
          icon: CruIcons.warning,
          tone: _TagTone.urgent,
        ),
      if (item.isPrebooked)
        _Tag(
          label: item.appointmentTime != null
              ? DashFormat.time(item.appointmentTime!)
              : 'Pre-booked',
          icon: CruIcons.calendar,
          tone: _TagTone.surface,
        ),
    ];

    String? note;
    if (entry.status == QueueStatus.waiting) {
      final waited = _waitingFor(item, now);
      if (waited != null && waited > _kWaitTarget) {
        note =
            '${_fmtDuration(waited - _kWaitTarget)} over the '
            '${_kWaitTarget.inMinutes}m wait target';
      }
    } else if (_isCalledTooLong(item, now)) {
      note =
          'Called ${_fmtDuration(now.difference(entry.calledAt!))} ago, '
          'not in the room yet';
    }

    final cancel = _MenuAction(
      'Cancel token',
      () => _cancelToken(entry.id, entry.tokenNumber),
    );
    final skip = _MenuAction(
      'Skip',
      () => _skipToken(entry.id, entry.tokenNumber),
    );

    Widget? primary;
    final menu = <_MenuAction>[];
    switch (entry.status) {
      case QueueStatus.waiting:
        if (expected) {
          primary = _CapsuleAction(
            label: 'Arrived',
            icon: CruIcons.check,
            onPressed: () => _markArrived(item),
          );
          menu.addAll([
            if (entry.tokenNumber > 0)
              _MenuAction('No-show (skip)', skip.onTap),
            cancel,
          ]);
          break;
        }
        if (isNextUp) {
          primary = _Dimmed(
            enabled: !_busy,
            child: CruButton(
              label: _busy ? 'Calling…' : 'Call next',
              icon: CruIcons.megaphone,
              expand: true,
              onPressed: _busy ? null : _callNextToken,
            ),
          );
        }
        menu.addAll([skip, cancel]);
      case QueueStatus.called:
        primary = CruButton(
          label: 'Start consult',
          expand: true,
          onPressed: () => _startConsultation(entry.id, entry.tokenNumber),
        );
        menu.addAll([
          _MenuAction(
            'Complete now',
            () => _completeConsultation(entry.id, entry.tokenNumber),
          ),
          skip,
          cancel,
        ]);
      case QueueStatus.inConsultation:
        primary = _Dimmed(
          enabled: !_busy,
          child: CruButton(
            label: callAfter
                ? 'Finish & call next'
                : (ref.read(isPhysiotherapyProvider)
                      ? 'Finish session'
                      : 'Finish consult'),
            icon: callAfter ? CruIcons.megaphone : CruIcons.check,
            expand: true,
            onPressed: _busy
                ? null
                : callAfter
                ? () => _finishAndCallNext(entry.id, entry.tokenNumber)
                : () => _completeConsultation(entry.id, entry.tokenNumber),
          ),
        );
        menu.addAll([
          if (callAfter)
            _MenuAction(
              'Finish without calling next',
              () => _completeConsultation(entry.id, entry.tokenNumber),
            ),
          cancel,
        ]);
      case QueueStatus.skipped:
        primary = _CapsuleAction(
          label: 'Requeue',
          onPressed: () => _requeueToken(entry.id, entry.tokenNumber),
        );
        menu.add(cancel);
      case QueueStatus.completed:
      case QueueStatus.cancelled:
        break;
    }

    // Seen together: add or take off patients on this token.
    final open = entry.status != QueueStatus.completed &&
        entry.status != QueueStatus.cancelled;
    if (open && members.length < kMaxGroupPatients) {
      menu.add(_MenuAction('Add a patient to this token', () => _addToToken(item)));
    }
    if (open && members.length > 1) {
      for (final m in members) {
        menu.add(
          _MenuAction(
            'Take ${m.displayName.split(' ').first} off this token',
            () => _leaveToken(m),
          ),
        );
      }
    }

    return _PatientTile(
      name: names([for (final m in members) m.displayName]),
      reason: reasons.isEmpty ? null : reasons.join(' · '),
      pills: pills,
      note: note,
      primary: primary,
      menu: menu,
      highlighted: isNextUp,
      current: entry.status == QueueStatus.inConsultation,
      onOpenPatient: item.patient == null
          ? null
          : () => DashboardActions.openPatient(context, item.patient!),
      muted:
          entry.status == QueueStatus.completed ||
          entry.status == QueueStatus.cancelled,
    );
  }

  Widget _timeTag(QueueEntryWithPatient item, DateTime now) {
    final entry = item.entry;
    switch (entry.status) {
      case QueueStatus.waiting:
        final waited = _waitingFor(item, now);
        if (waited != null) {
          return _Tag(
            label: _fmtDuration(waited),
            icon: CruIcons.clock,
            tone: waited > _kWaitTarget ~/ 2
                ? _TagTone.waiting
                : _TagTone.surface,
          );
        }
        if (entry.checkedInAt.isAfter(now)) {
          return _Tag(
            label: 'in ${_fmtDuration(entry.checkedInAt.difference(now))}',
            icon: CruIcons.clock,
            tone: _TagTone.surface,
          );
        }
        return _Tag(
          label: DashFormat.shortDate(entry.checkedInAt),
          icon: CruIcons.calendar,
          tone: _TagTone.surface,
        );
      case QueueStatus.called:
        final calledAt = entry.calledAt;
        if (calledAt != null && _isSameDay(calledAt, now)) {
          return _Tag(
            label: 'Called ${_fmtDuration(now.difference(calledAt))}',
            icon: CruIcons.megaphone,
            tone: _TagTone.waiting,
          );
        }
        return const _Tag(
          label: 'Called',
          icon: CruIcons.megaphone,
          tone: _TagTone.waiting,
        );
      case QueueStatus.inConsultation:
        final startedAt = entry.consultationStartedAt;
        if (startedAt != null && _isSameDay(startedAt, now)) {
          return _Tag(
            label: 'In room ${_fmtDuration(now.difference(startedAt))}',
            icon: CruIcons.clock,
            tone: _TagTone.now,
          );
        }
        return const _Tag(
          label: 'In room',
          icon: CruIcons.clock,
          tone: _TagTone.now,
        );
      case QueueStatus.completed:
        return _Tag(
          label:
              'Done ${DashFormat.time(entry.completedAt ?? entry.updatedAt)}',
          icon: CruIcons.check,
          tone: _TagTone.done,
        );
      case QueueStatus.skipped:
        return const _Tag(label: 'Skipped', tone: _TagTone.surface);
      case QueueStatus.cancelled:
        return const _Tag(
          label: 'Cancelled',
          icon: CruIcons.close,
          tone: _TagTone.surface,
        );
    }
  }
}

// =============================================================================
// STATS
// =============================================================================

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.caption,
    this.suffix,
    this.progress,
  });

  final String label;
  final String value;
  final String? suffix;
  final Widget caption;

  /// 0-1: a thin green bar above the caption ("Seen today").
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(value, suffix: suffix),
        if (progress != null) ...[
          const SizedBox(height: CruSpace.s4),
          CruProgressBar(
            value: progress!,
            color: context.cru.green,
            semanticLabel: 'Share of queue seen',
          ),
          const SizedBox(height: CruSpace.s6),
        ],
        GlanceCaption(caption),
      ],
    );
  }
}

/// A status dot followed by a coloured caption ("Over the 20 min target").
class _DotCaption extends StatelessWidget {
  const _DotCaption({
    required this.dot,
    required this.text,
    required this.color,
  });

  final CruDotKind dot;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CruStatusDot(dot, size: CruSize.smallDot),
        const SizedBox(width: CruSpace.s6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CruType.caption.w500.tabular.tint(color),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// FILTERS
// =============================================================================

/// A fully round source filter ("Everyone", "Walk-ins", "Pre-booked"),
/// as the Inventory chips: surface + hairline, accent tint when selected.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.control,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? c.hoverFill : c.surface),
            // A transparent ring when selected so the size never changes.
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? c.hairline.withValues(alpha: 0) : c.hairline,
              ),
            ),
          ),
          child: Text(
            label,
            style: (selected ? CruType.chip.w600 : CruType.chip).tint(
              selected ? c.accentText : c.label,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Session  All day" / "Sort  Queue order" with a chevron: a surface
/// button with a small on-token menu, as the Inventory sort button.
class _MenuSelect<T> extends StatelessWidget {
  const _MenuSelect({
    required this.prefix,
    required this.value,
    required this.options,
    required this.shortLabel,
    required this.itemLabel,
    required this.onSelected,
  });

  final String prefix;
  final T value;
  final List<T> options;
  final String Function(T) shortLabel;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control - CruSpace.s6),
    );
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(
          c.surface.withValues(alpha: 0),
        ),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        elevation: WidgetStatePropertyAll(c.isEvening ? 0 : 8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        for (final o in options)
          MenuItemButton(
            onPressed: () => onSelected(o),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(0, CruSize.control),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: CruSpace.s12),
              ),
              shape: WidgetStatePropertyAll(itemShape),
              overlayColor: WidgetStatePropertyAll(
                c.hoverFill.withValues(alpha: 0),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)
                    ? c.hoverFill
                    : c.surface,
              ),
            ),
            trailingIcon: o == value
                ? CruIcon(
                    CruIcons.check,
                    size: 16,
                    strokeWidth: 2.2,
                    color: c.accentText,
                  )
                : null,
            child: Text(
              itemLabel(o),
              style: (o == value ? CruType.text.w600 : CruType.text.w500).tint(
                c.label,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => CruPressable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        semanticLabel: '$prefix: ${shortLabel(value)}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.control,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
            shadows: c.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(prefix, style: CruType.text.w500.tint(c.label2)),
              const SizedBox(width: CruSpace.s6),
              Text(shortLabel(value), style: CruType.text.w500.tint(c.label)),
              const SizedBox(width: CruSpace.s6),
              CruIcon(
                CruIcons.chevronDown,
                size: 14,
                strokeWidth: 2.2,
                color: c.label2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Search patient or token #", 40 px to line up with the filter row.
class _QueueSearchField extends StatelessWidget {
  const _QueueSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.control,
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, 0, CruSpace.s6, 0),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: c.cardShadow,
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.search, size: 16, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: CruType.subhead.tint(c.label),
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hint: Text(
                  'Search patient or token #',
                  style: CruType.subhead.tint(c.label3),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            CruIconButton(
              icon: CruIcons.close,
              size: CruSize.rowCapsule,
              iconSize: 14,
              semanticLabel: 'Clear search',
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            )
          else
            const SizedBox(width: CruSpace.s8),
        ],
      ),
    );
  }
}

// =============================================================================
// BOARD COLUMN
// =============================================================================

/// One lifecycle stage: a card with a dot + title + count header, its
/// patient tiles.
class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.dot,
    required this.count,
    required this.cards,
    this.meta,
    this.ink = false,
  });

  final String title;
  final CruDotKind dot;

  /// Paint the whole column on the ink (blue) surface: someone is with
  /// the doctor right now.
  final bool ink;
  final int count;
  final String? meta;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = '$title, $count';
    const padding = EdgeInsets.all(CruSpace.s12);
    if (ink) {
      return CruInkCard(
        semanticLabel: semanticLabel,
        padding: padding,
        child: _OnInk(child: Builder(builder: _content)),
      );
    }
    return CruCard(
      semanticLabel: semanticLabel,
      padding: padding,
      child: Builder(builder: _content),
    );
  }

  /// Built under the card so it reads the card's (possibly on-ink) colours.
  Widget _content(BuildContext context) {
    final c = context.cru;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s4,
            CruSpace.s4,
            CruSpace.s4,
            CruSpace.s12,
          ),
          child: Row(
            children: [
              if (ink)
                // The accent dot would vanish on ink.
                Container(
                  width: CruSize.statusDot,
                  height: CruSize.statusDot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.label,
                  ),
                )
              else
                CruStatusDot(dot),
              const SizedBox(width: CruSpace.s8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.callout.tint(c.label),
                ),
              ),
              const SizedBox(width: CruSpace.s6),
              Text(
                '$count',
                style: CruType.callout.w500.tabular.tint(c.label3),
              ),
              // The title keeps the room; a short meta ("avg 12m") sits right.
              if (meta != null) ...[
                const Spacer(),
                Text(
                  meta!,
                  maxLines: 1,
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ],
            ],
          ),
        ),
        if (cards.isEmpty)
          const _EmptySlot()
        else if (cards.isNotEmpty)
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: CruSpace.s8),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
      ],
    );
  }
}

/// Marks a subtree painted on the ink surface, so tags pick readable
/// translucent fills instead of white.
class _OnInk extends InheritedWidget {
  const _OnInk({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnInk>() != null;

  @override
  bool updateShouldNotify(_OnInk oldWidget) => false;
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s20),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Text('No patients', style: CruType.caption.tint(c.label3)),
    );
  }
}

// =============================================================================
// PATIENT TILE
// =============================================================================

class _MenuAction {
  const _MenuAction(this.label, this.onTap);

  final String label;
  final VoidCallback? onTap;
}

/// One token: monogram, name, reason, tags, an optional flag line and the
/// stage's main action. Inset fill inside the column card; the next
/// patient to call is raised onto the surface with an accent ring, and
/// the patient in consultation sits in the ink column.
class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.name,
    required this.reason,
    required this.pills,
    required this.note,
    required this.primary,
    required this.menu,
    required this.highlighted,
    required this.current,
    required this.muted,
    this.onOpenPatient,
  });

  final String name;
  final String? reason;
  final List<Widget> pills;
  final String? note;
  final Widget? primary;
  final List<_MenuAction> menu;
  final bool highlighted;

  /// In consultation right now.
  final bool current;
  final bool muted;

  /// Offered in the long-press menu when the token has a patient record.
  final VoidCallback? onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return _TileMenuRegion(
      actions: [
        ...menu,
        if (onOpenPatient != null) _MenuAction('Open patient', onOpenPatient),
      ],
      child: AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.all(CruSpace.s12),
        decoration: ShapeDecoration(
          color: highlighted ? c.surface : c.inset,
          shape: cruShape(
            CruRadius.control,
            side: highlighted
                ? BorderSide(
                    color: c.accent.withValues(alpha: 0.45),
                    width: 1.5,
                  )
                : BorderSide.none,
          ),
          shadows: highlighted ? c.cardShadow : null,
        ),
        child: Opacity(
          opacity: muted ? 0.7 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CruMonogram(
                    // Seen together: the first patient's initials.
                    name: name.split(' & ').first.split(' + ').first,
                    size: CruSize.rowCapsule,
                    background: current || highlighted ? c.track : c.surface,
                    foreground: current ? c.label : null,
                  ),
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          // Two lines so both names of a shared token fit.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.callout.tint(c.label),
                        ),
                        if (reason != null)
                          Text(
                            reason!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.caption.tint(c.label2),
                          ),
                      ],
                    ),
                  ),
                  if (menu.isNotEmpty) _TileMenu(actions: menu),
                ],
              ),
              const SizedBox(height: CruSpace.s10),
              Wrap(
                spacing: CruSpace.s6,
                runSpacing: CruSpace.s6,
                children: pills,
              ),
              if (note != null) ...[
                const SizedBox(height: CruSpace.s10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: CruIcon(
                        CruIcons.warning,
                        size: 14,
                        strokeWidth: 2,
                        color: c.amberText,
                      ),
                    ),
                    const SizedBox(width: CruSpace.s6),
                    Expanded(
                      child: Text(
                        note!,
                        style: CruType.caption.w500.tabular.tint(c.amberText),
                      ),
                    ),
                  ],
                ),
              ],
              if (primary != null) ...[
                const SizedBox(height: CruSpace.s12),
                primary!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press (touch, with a haptic tick) or right-click (mouse) on a
/// tile: its actions, opened where the finger or pointer is.
class _TileMenuRegion extends StatelessWidget {
  const _TileMenuRegion({required this.actions, required this.child});

  final List<_MenuAction> actions;
  final Widget child;

  Future<void> _show(BuildContext context, Offset global) async {
    if (actions.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(global);
    final chosen = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: CruSize.actionButton,
            enabled: actions[i].onTap != null,
            child: Text(actions[i].label),
          ),
      ],
    );
    if (chosen != null && context.mounted) actions[chosen].onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (d) {
        HapticFeedback.mediumImpact();
        _show(context, d.globalPosition);
      },
      onSecondaryTapUp: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({required this.actions});

  final List<_MenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (i) => actions[i].onTap?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: CruSize.control,
            enabled: actions[i].onTap != null,
            // The menu's own text style: the tile may sit on ink.
            child: Text(actions[i].label),
          ),
      ],
      child: SizedBox.square(
        dimension: cruIsTouchPlatform ? CruSize.squareButton : CruSize.rowCapsule,
        child: Center(child: CruIcon(CruIcons.more, size: 18, color: c.label2)),
      ),
    );
  }
}

/// A full-width surface capsule for a tile's secondary main action
/// ("Check in", "Requeue").
class _CapsuleAction extends StatelessWidget {
  const _CapsuleAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final CruIconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CruCapsuleButton(
        label: label,
        icon: icon,
        kind: CruCapsuleKind.surface,
        height: CruSize.panelCapsule,
        onPressed: onPressed,
      ),
    );
  }
}

/// Fades an action that can't run right now.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      opacity: enabled ? 1 : _kDisabledOpacity,
      child: child,
    );
  }
}

// =============================================================================
// TAGS
// =============================================================================

enum _TagTone {
  /// Token number, pre-booked time, quiet states.
  surface,

  /// Waiting longer than half the target, called.
  waiting,

  /// In the room now.
  now,

  /// Seen.
  done,

  /// Urgent priority (patient safety).
  urgent,
}

/// A small fully round tag on a patient tile.
class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.tone,
    this.icon,
    this.strong = false,
  });

  final String label;
  final CruIconData? icon;
  final _TagTone tone;

  /// Label colour and weight 600 (the token number).
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final onInk = _OnInk.of(context);
    final (Color bg, Color fg) = switch (tone) {
      _ when onInk => (c.track, c.label),
      _TagTone.surface => (c.surface, strong ? c.label : c.label2),
      _TagTone.waiting => (c.amberTint, c.amberText),
      _TagTone.now => (c.accentTint, c.accentText),
      _TagTone.done => (c.greenTint, c.greenText),
      _TagTone.urgent => (c.redTint, c.redText),
    };
    return Container(
      height: CruSize.pill - CruSpace.s2,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: tone == _TagTone.surface && !onInk
              ? BorderSide(color: c.hairline)
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 12, strokeWidth: 2.2, color: fg),
            const SizedBox(width: CruSpace.s4),
          ],
          Text(
            label,
            style: CruType.micro.tabular.copyWith(
              color: fg,
              fontWeight: strong || tone != _TagTone.surface
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DIALOGS
// =============================================================================

class _CancelTokenDialog extends StatelessWidget {
  const _CancelTokenDialog({required this.tokenNumber});

  final int tokenNumber;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: cruShape(CruRadius.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CruSize.dialog),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancel token #$tokenNumber?',
                style: CruType.headline.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                'The patient leaves the queue. This can\'t be undone.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: 'Keep token',
                    kind: CruButtonKind.inset,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  CruButton(
                    label: 'Cancel token',
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
