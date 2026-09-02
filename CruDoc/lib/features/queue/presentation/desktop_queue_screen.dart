import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/queue/presentation/check_in_dialog.dart';
import 'package:doctor_management_app/features/queue/widget/queue_token_card.dart';

// ---------- Color Constants (Matching desktop palette) ----------
const Color _kPrimaryText   = Color(0xFF1F2937);
const Color _kSecondaryText = Color(0xFF6B7280);
const Color _kBorder        = Color(0xFFE2E8F0);
const Color _kAccentBlue    = Color(0xFF2563EB);
const Color _kAccentBlueBg  = Color(0xFFEFF6FF);
const Color _kGreen         = Color(0xFF16A34A);
const Color _kGreenBg       = Color(0xFFF0FDF4);
const Color _kAmber         = Color(0xFFF59E0B);
const Color _kAmberBg       = Color(0xFFFFFBEB);
const Color _kRed           = Color(0xFFDC2626);
const Color _kRedBg         = Color(0xFFFEF2F2);
const Color _kSurface       = Color(0xFFF8FAFC);

/// Desktop walk-in queue management screen.
///
/// Provides live token tracking, hero spotlight for current consultation,
/// atomic check-in modal, line-jump priority management, and history.
class DesktopQueueScreen extends ConsumerStatefulWidget {
  const DesktopQueueScreen({super.key});

  @override
  ConsumerState<DesktopQueueScreen> createState() => _DesktopQueueScreenState();
}

class _DesktopQueueScreenState extends ConsumerState<DesktopQueueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isCallingNext = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(todaysQueueWithPatientsProvider);
    final activeServing = ref.watch(activeQueueEntryProvider);
    final waitingTokens = ref.watch(waitingQueueProvider);
    final resolvedTokens = ref.watch(resolvedQueueProvider);

    final allTokens = queueAsync.value ?? const <QueueEntryWithPatient>[];
    final totalCheckedIn = allTokens.length;
    final waitingCount = waitingTokens.length;
    final urgentCount = waitingTokens.where((t) => t.entry.priority == QueuePriority.urgent).length;
    final completedCount = allTokens.where((t) => t.entry.status == QueueStatus.completed).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===============================================================
              // 1. TOP HEADER & ACTION CONTROLS
              // ===============================================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                            const Text(
                              'Walk-in Queue',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _kPrimaryText,
                                fontFamily: AppColors.headingFontFamily,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _kSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _kBorder),
                              ),
                              child: Text(
                                DateFormat('EEEE, MMM d').format(DateTime.now()),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _kSecondaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Live token flow and triage management for walk-in patients',
                          style: TextStyle(
                            fontSize: 13,
                            color: _kSecondaryText,
                            fontFamily: AppColors.bodyFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Call Next Button
                  ElevatedButton.icon(
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
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Issue Token / Check In Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final created = await CheckInDialog.show(context);
                      if (created != null) {
                        _showFeedback('Token #${created.tokenNumber} issued successfully!');
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'Check In Patient',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D422C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ===============================================================
              // 2. METRICS CARDS ROW
              // ===============================================================
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Total Today',
                      value: '$totalCheckedIn',
                      icon: Icons.groups_rounded,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Waiting in Line',
                      value: '$waitingCount',
                      badge: urgentCount > 0 ? '$urgentCount urgent' : null,
                      badgeColor: _kRed,
                      icon: Icons.hourglass_top_rounded,
                      color: _kAmber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Now Serving',
                      value: activeServing != null ? '#${activeServing.entry.tokenNumber}' : 'None',
                      icon: Icons.hearing_rounded,
                      color: _kAccentBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Completed',
                      value: '$completedCount',
                      icon: Icons.task_alt_rounded,
                      color: _kGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ===============================================================
              // 3. ACTIVE CONSULTATION SPOTLIGHT HERO CARD
              // ===============================================================
              _buildActiveSpotlight(activeServing),
              const SizedBox(height: 20),

              // ===============================================================
              // 4. QUEUE LIST TABS & SEARCH
              // ===============================================================
              Row(
                children: [
                  Container(
                    height: 40,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      labelColor: _kPrimaryText,
                      unselectedLabelColor: _kSecondaryText,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      tabs: [
                        Tab(text: 'Waiting ($waitingCount)'),
                        Tab(text: 'All Tokens ($totalCheckedIn)'),
                        Tab(text: 'Resolved (${resolvedTokens.length})'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Search Field
                  SizedBox(
                    width: 260,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search patient / token #...',
                        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6B7280)),
                        filled: true,
                        fillColor: _kSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kAccentBlue, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ===============================================================
              // 5. QUEUE LIST CONTENT AREA
              // ===============================================================
              Expanded(
                child: queueAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, st) => Center(
                    child: Text(
                      'Failed to load queue: $err',
                      style: const TextStyle(color: _kRed),
                    ),
                  ),
                  data: (_) => TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Waiting List
                      _buildTokensList(waitingTokens),
                      // Tab 2: All Tokens
                      _buildTokensList(allTokens),
                      // Tab 3: Resolved List
                      _buildTokensList(resolvedTokens),
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

  Widget _buildActiveSpotlight(QueueEntryWithPatient? active) {
    if (active == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.chair_alt_rounded, color: _kSecondaryText, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'No Active Consultation In Progress',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _kPrimaryText,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Click "Call Next Token" above or select a patient from the waiting list to begin consultation.',
                    style: TextStyle(fontSize: 12, color: _kSecondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isCalled = active.entry.status == QueueStatus.called;
    final statusColor = isCalled ? _kAmber : _kAccentBlue;
    final statusBg = isCalled ? _kAmberBg : _kAccentBlueBg;
    final statusLabel = isCalled ? 'CALLED — AT DOOR' : 'IN CONSULTATION';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusBg, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Large Token Number Badge
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              '#${active.entry.tokenNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                fontFamily: AppColors.headingFontFamily,
              ),
            ),
          ),
          const SizedBox(width: 18),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (active.entry.priority == QueuePriority.urgent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kRed,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'URGENT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  active.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _kPrimaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (active.entry.reason == null || active.entry.reason!.isEmpty)
                      ? 'No specific triage note entered'
                      : 'Reason: ${active.entry.reason}',
                  style: const TextStyle(fontSize: 12.5, color: _kSecondaryText),
                ),
              ],
            ),
          ),

          // Action Buttons
          Wrap(
            spacing: 10,
            children: [
              if (isCalled) ...[
                ElevatedButton.icon(
                  onPressed: () => _startConsultation(active.entry.id, active.entry.tokenNumber),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start Consult'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccentBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _skipToken(active.entry.id, active.entry.tokenNumber),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: const Text('Skip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kSecondaryText,
                    side: const BorderSide(color: _kBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              ElevatedButton.icon(
                onPressed: () => _completeConsultation(active.entry.id, active.entry.tokenNumber),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: _kRed),
                tooltip: 'Cancel token',
                onPressed: () => _cancelToken(active.entry.id, active.entry.tokenNumber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokensList(List<QueueEntryWithPatient> tokens) {
    var filtered = tokens;
    if (_searchQuery.isNotEmpty) {
      filtered = tokens.where((t) {
        final name = t.displayName.toLowerCase();
        final tokenStr = '#${t.entry.tokenNumber}';
        final reason = t.entry.reason?.toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
            tokenStr.contains(_searchQuery) ||
            reason.contains(_searchQuery);
      }).toList();
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No tokens matching "$_searchQuery"' : 'No tokens in this list',
              style: const TextStyle(fontSize: 14, color: _kSecondaryText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemBuilder: (context, index) {
        final item = filtered[index];
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

        return QueueTokenCard(
          tokenNumber: entry.tokenNumber,
          displayName: item.displayName,
          reason: entry.reason,
          status: entry.status,
          priority: entry.priority,
          checkedInAt: entry.checkedInAt,
          onStartConsultation: onStart,
          onComplete: onComplete,
          onSkip: onSkip,
          onRequeue: onRequeue,
          onCancel: onCancel,
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? badge;
  final Color? badgeColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _kSecondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kPrimaryText,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (badgeColor ?? _kAccentBlue).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: badgeColor ?? _kAccentBlue,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
