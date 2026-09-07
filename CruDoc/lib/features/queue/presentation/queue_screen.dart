import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';
import 'package:doctor_management_app/features/queue/widget/queue_token_card.dart';

/// Mobile / Responsive Walk-in Queue Screen.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isCallingNext = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.negativeRed : const Color(0xFF1E293B),
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
      _showFeedback('Error: $e', isError: true);
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
      _showFeedback('Token #$tokenNumber requeued in original order.');
    } catch (e) {
      _showFeedback('Could not requeue token: $e', isError: true);
    }
  }

  Future<void> _cancelToken(String entryId, int tokenNumber) async {
    try {
      final repo = ref.read(queueRepositoryProvider);
      await repo.cancel(entryId);
      _showFeedback('Token #$tokenNumber has been cancelled.');
    } catch (e) {
      _showFeedback('Could not cancel token: $e', isError: true);
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

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: ref.read(queueCustomDateRangeProvider) ??
          DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked != null) {
      ref.read(queueCustomDateRangeProvider.notifier).state = picked;
      ref.read(queuePeriodProvider.notifier).state = QueuePeriod.custom;
    }
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(todaysQueueWithPatientsProvider);
    final activeServing = ref.watch(activeQueueEntryProvider);
    final waitingTokens = ref.watch(waitingQueueProvider);
    final resolvedTokens = ref.watch(resolvedQueueProvider);
    final selectedPeriod = ref.watch(queuePeriodProvider);
    final selectedSession = ref.watch(queueSessionFilterProvider);
    final bounds = ref.watch(activeQueueDateBoundsProvider);
    final isAppointmentsEnabled = ref.watch(isAppointmentsFeatureEnabledProvider);

    final allTokens = queueAsync.value ?? const <QueueEntryWithPatient>[];
    final waitingCount = waitingTokens.length;
    final prebookedCount = allTokens.where((t) => t.isPrebooked).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Walk-in Queue',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.charcoalGray,
                          fontFamily: AppColors.headingFontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bounds.label == 'Today'
                            ? DateFormat('EEEE, MMM d').format(DateTime.now())
                            : (bounds.label == 'Tomorrow'
                                ? DateFormat('EEEE, MMM d').format(DateTime.now().add(const Duration(days: 1)))
                                : '${DateFormat('MMM d').format(bounds.start)} – ${DateFormat('MMM d').format(bounds.end)}'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slateBlue,
                        ),
                      ),
                      if (isAppointmentsEnabled && prebookedCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$prebookedCount pre-booked appointment${prebookedCount > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (waitingCount > 0 && activeServing == null)
                        IconButton(
                          icon: _isCallingNext
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.campaign_rounded, color: AppColors.accentBlue),
                          tooltip: 'Call Next',
                          onPressed: _isCallingNext ? null : _callNextToken,
                        ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final created = await CheckInDialog.show(context);
                          if (created != null) {
                            _showFeedback('Token #${created.tokenNumber} issued successfully!');
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Check In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Period Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _periodChip('Today', QueuePeriod.today, selectedPeriod),
                    const SizedBox(width: 6),
                    _periodChip('Tomorrow', QueuePeriod.tomorrow, selectedPeriod),
                    const SizedBox(width: 6),
                    _periodChip('This Week', QueuePeriod.thisWeek, selectedPeriod),
                    const SizedBox(width: 6),
                    _periodChip('Custom Range', QueuePeriod.custom, selectedPeriod, onTap: _pickCustomDateRange),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Session Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _sessionChip('All Day', QueueSessionFilter.all, selectedSession),
                    const SizedBox(width: 6),
                    _sessionChip('Morning', QueueSessionFilter.morning, selectedSession),
                    const SizedBox(width: 6),
                    _sessionChip('Afternoon', QueueSessionFilter.afternoon, selectedSession),
                    const SizedBox(width: 6),
                    _sessionChip('Evening', QueueSessionFilter.evening, selectedSession),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Active Serving Banner (if any)
              if (activeServing != null) ...[
                _buildActiveCard(activeServing),
                const SizedBox(height: 14),
              ],

              // Tab Bar
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.accentBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.slateBlue,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                  tabs: [
                    Tab(text: 'Waiting ($waitingCount)'),
                    Tab(text: 'All (${allTokens.length})'),
                    Tab(text: 'Resolved (${resolvedTokens.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Tab Bar Content
              Expanded(
                child: queueAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (_) => TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTokenList(waitingTokens),
                      _buildTokenList(allTokens),
                      _buildTokenList(resolvedTokens),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCard(QueueEntryWithPatient active) {
    final isCalled = active.entry.status == QueueStatus.called;
    final color = isCalled ? const Color(0xFFF59E0B) : AppColors.accentBlue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCalled ? 'NOW CALLING' : 'IN CONSULTATION',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
              ),
              const Spacer(),
              if (active.isPrebooked) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_rounded, size: 11, color: Color(0xFF6366F1)),
                      const SizedBox(width: 3),
                      Text(
                        active.appointmentTime != null
                            ? DateFormat('hh:mm a').format(active.appointmentTime!)
                            : 'Appt',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                active.entry.tokenNumber > 0
                    ? 'Token #${active.entry.tokenNumber}'
                    : 'Pre-booked',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: color,
                  fontFamily: AppColors.headingFontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            active.displayName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoalGray,
            ),
          ),
          if (active.entry.reason != null && active.entry.reason!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              active.entry.reason!,
              style: const TextStyle(fontSize: 12, color: AppColors.slateBlue),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (isCalled) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startConsultation(active.entry.id, active.entry.tokenNumber),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Start', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _skipToken(active.entry.id, active.entry.tokenNumber),
                    icon: const Icon(Icons.skip_next_rounded, size: 16),
                    label: const Text('Skip', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.slateBlue,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _completeConsultation(active.entry.id, active.entry.tokenNumber),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Complete', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.positiveGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokenList(List<QueueEntryWithPatient> tokens) {
    if (tokens.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox_outlined, size: 40, color: AppColors.slateBlue),
            SizedBox(height: 8),
            Text('No tokens in this section', style: TextStyle(color: AppColors.slateBlue, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: tokens.length,
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemBuilder: (context, index) {
        final item = tokens[index];
        final entry = item.entry;

        VoidCallback? onStart;
        VoidCallback? onComplete;
        VoidCallback? onSkip;
        VoidCallback? onRequeue;
        VoidCallback? onCancel;

        if (entry.status == QueueStatus.called) {
          onStart = () => _startConsultation(entry.id, entry.tokenNumber);
          onComplete = () => _completeConsultation(entry.id, entry.tokenNumber);
          onSkip = () => _skipToken(entry.id, entry.tokenNumber);
          onCancel = () => _cancelToken(entry.id, entry.tokenNumber);
        } else if (entry.status == QueueStatus.inConsultation) {
          onComplete = () => _completeConsultation(entry.id, entry.tokenNumber);
          onCancel = () => _cancelToken(entry.id, entry.tokenNumber);
        } else if (entry.status == QueueStatus.waiting) {
          onSkip = () => _skipToken(entry.id, entry.tokenNumber);
          onCancel = () => _cancelToken(entry.id, entry.tokenNumber);
        } else if (entry.status == QueueStatus.skipped) {
          onRequeue = () => _requeueToken(entry.id, entry.tokenNumber);
        }

        final isPrebooked = item.isPrebooked;
        final appointmentTime = item.appointmentTime;
        final isNotYetCheckedIn = isPrebooked && entry.tokenNumber == 0;

        return QueueTokenCard(
          tokenNumber: entry.tokenNumber,
          displayName: item.displayName,
          reason: entry.reason,
          status: entry.status,
          priority: entry.priority,
          checkedInAt: entry.checkedInAt,
          isPrebooked: isPrebooked,
          appointmentTime: appointmentTime,
          onCheckIn: isNotYetCheckedIn ? () => _checkInPrebooked(item) : null,
          onStartConsultation: onStart,
          onComplete: onComplete,
          onSkip: onSkip,
          onRequeue: onRequeue,
          onCancel: onCancel,
        );
      },
    );
  }

  Widget _periodChip(String label, QueuePeriod period, QueuePeriod selected, {VoidCallback? onTap}) {
    final isSelected = selected == period;
    return InkWell(
      onTap: onTap ?? () => ref.read(queuePeriodProvider.notifier).state = period,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accentBlue : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.slateBlue,
          ),
        ),
      ),
    );
  }

  Widget _sessionChip(String label, QueueSessionFilter session, QueueSessionFilter selected) {
    final isSelected = selected == session;
    return InkWell(
      onTap: () => ref.read(queueSessionFilterProvider.notifier).state = session,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBlue.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accentBlue : AppColors.divider.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.accentBlue : AppColors.slateBlue,
          ),
        ),
      ),
    );
  }
}
