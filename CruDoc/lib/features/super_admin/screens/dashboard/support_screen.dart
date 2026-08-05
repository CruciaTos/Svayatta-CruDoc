import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/enums.dart';
import '../../models/support_ticket_model.dart';
import '../../providers/support_ticket_provider.dart';

/// Super Admin Support Tickets Management Screen.
class SuperAdminSupportScreen extends ConsumerStatefulWidget {
  const SuperAdminSupportScreen({super.key});

  @override
  ConsumerState<SuperAdminSupportScreen> createState() =>
      _SuperAdminSupportScreenState();
}

class _SuperAdminSupportScreenState
    extends ConsumerState<SuperAdminSupportScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketState = ref.watch(supportTicketProvider);
    final notifier = ref.read(supportTicketProvider.notifier);
    final isMobile = MediaQuery.of(context).size.width < 768;
    final filtered = ticketState.filteredTickets;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          _buildHeader(context, ticketState, notifier),
          const SizedBox(height: 20),

          // 2. Category Summary Cards
          _buildCategorySummary(context, ticketState, notifier, isMobile),
          const SizedBox(height: 20),

          // 3. Status Quick Stats Row
          _buildStatusRow(context, ticketState, isMobile),
          const SizedBox(height: 24),

          // 4. Search & Filters
          _buildSearchFilters(context, ticketState, notifier, isMobile),
          const SizedBox(height: 20),

          // 5. Tickets List
          _buildTicketsList(context, ticketState, filtered, notifier, isMobile),
        ],
      ),
    );
  }

  // ==================== 1. HEADER ====================
  Widget _buildHeader(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Support Center',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${state.filteredTickets.length} Tickets',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Manage doctor-reported bugs, complaints, feedback, and feature requests',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: state.isLoading ? null : () => notifier.loadTickets(),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ==================== 2. CATEGORY SUMMARY CARDS ====================
  Widget _buildCategorySummary(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    final cards = [
      _buildCategoryCard(
        context,
        notifier: notifier,
        category: TicketCategory.bug,
        count: state.countByCategory(TicketCategory.bug),
        icon: Icons.bug_report_rounded,
        color: const Color(0xFFEF4444),
        bg: const Color(0xFFFEF2F2),
        isSelected: state.categoryFilter == TicketCategory.bug,
      ),
      _buildCategoryCard(
        context,
        notifier: notifier,
        category: TicketCategory.complaint,
        count: state.countByCategory(TicketCategory.complaint),
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFF59E0B),
        bg: const Color(0xFFFFFBEB),
        isSelected: state.categoryFilter == TicketCategory.complaint,
      ),
      _buildCategoryCard(
        context,
        notifier: notifier,
        category: TicketCategory.feedback,
        count: state.countByCategory(TicketCategory.feedback),
        icon: Icons.thumb_up_alt_rounded,
        color: const Color(0xFF10B981),
        bg: const Color(0xFFECFDF5),
        isSelected: state.categoryFilter == TicketCategory.feedback,
      ),
      _buildCategoryCard(
        context,
        notifier: notifier,
        category: TicketCategory.suggestion,
        count: state.countByCategory(TicketCategory.suggestion),
        icon: Icons.lightbulb_rounded,
        color: const Color(0xFF8B5CF6),
        bg: const Color(0xFFF5F3FF),
        isSelected: state.categoryFilter == TicketCategory.suggestion,
      ),
      _buildCategoryCard(
        context,
        notifier: notifier,
        category: TicketCategory.featureRequest,
        count: state.countByCategory(TicketCategory.featureRequest),
        icon: Icons.rocket_launch_rounded,
        color: const Color(0xFF2563EB),
        bg: const Color(0xFFEFF6FF),
        isSelected: state.categoryFilter == TicketCategory.featureRequest,
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(width: 170, child: c),
                  ))
              .toList(),
        ),
      );
    }

    return Row(
      children: cards
          .map((c) => Expanded(
                child:
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: c),
              ))
          .toList(),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required SupportTicketNotifier notifier,
    required TicketCategory category,
    required int count,
    required IconData icon,
    required Color color,
    required Color bg,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        if (isSelected) {
          notifier.setCategoryFilter(null);
        } else {
          notifier.setCategoryFilter(category);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 3. STATUS QUICK STATS ====================
  Widget _buildStatusRow(
    BuildContext context,
    SupportTicketState state,
    bool isMobile,
  ) {
    final items = [
      _StatusItem('Open', state.openCount, const Color(0xFF2563EB), Icons.circle_outlined),
      _StatusItem('In Progress', state.inProgressCount, const Color(0xFFF59E0B), Icons.pending_rounded),
      _StatusItem('Resolved', state.resolvedCount, const Color(0xFF10B981), Icons.check_circle_rounded),
      _StatusItem('Critical', state.criticalCount, const Color(0xFFEF4444), Icons.warning_amber_rounded),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: item.color, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${item.count}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: item.color,
                  ),
                ),
                const SizedBox(width: 4),
                if (!isMobile)
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==================== 4. SEARCH & FILTERS ====================
  Widget _buildSearchFilters(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search Input
          SizedBox(
            width: isMobile ? double.infinity : 320,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => notifier.setSearchQuery(val),
              decoration: InputDecoration(
                hintText: 'Search tickets by subject, doctor, or ID...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ),

          // Status Filter Dropdown
          _buildFilterDropdown<TicketStatus>(
            hint: 'Status',
            value: state.statusFilter,
            items: TicketStatus.values,
            labelOf: (s) => s.label,
            onChanged: (val) => notifier.setStatusFilter(val),
          ),

          // Priority Filter Dropdown
          _buildFilterDropdown<TicketPriority>(
            hint: 'Priority',
            value: state.priorityFilter,
            items: TicketPriority.values,
            labelOf: (p) => p.label,
            onChanged: (val) => notifier.setPriorityFilter(val),
          ),

          // Clear All Filters
          if (state.searchQuery.isNotEmpty ||
              state.categoryFilter != null ||
              state.statusFilter != null ||
              state.priorityFilter != null)
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                notifier.clearFilters();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label:
                  const Text('Clear All', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T extends Enum>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          hint: Text('All $hint', style: const TextStyle(fontSize: 13)),
          isDense: true,
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text('All $hint', style: const TextStyle(fontSize: 13)),
            ),
            ...items.map(
              (item) => DropdownMenuItem<T?>(
                value: item,
                child: Text(labelOf(item), style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ==================== 5. TICKETS LIST ====================
  Widget _buildTicketsList(
    BuildContext context,
    SupportTicketState state,
    List<SupportTicketModel> tickets,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (tickets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.support_agent_rounded,
                  size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No support tickets match your filters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try expanding your search or adjusting category / status filters',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildTicketCard(context, tickets[index], notifier);
      },
    );
  }

  Widget _buildTicketCard(
    BuildContext context,
    SupportTicketModel ticket,
    SupportTicketNotifier notifier,
  ) {
    final dateFormat = DateFormat('MMM d, yyyy • hh:mm a');
    final categoryColors = _categoryColorMap(ticket.category);
    final priorityColors = _priorityColorMap(ticket.priority);
    final statusColors = _statusColorMap(ticket.status);

    return InkWell(
      onTap: () => _showTicketDetailsDialog(context, ticket, notifier),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ticket.priority == TicketPriority.critical
                ? const Color(0xFFFECACA)
                : Colors.grey.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Badges + Ticket ID + Timestamp
            Row(
              children: [
                // Category Badge
                _buildChip(
                    ticket.category.label, categoryColors.fg, categoryColors.bg),
                const SizedBox(width: 8),
                // Priority Badge
                _buildChip(
                    ticket.priority.label, priorityColors.fg, priorityColors.bg),
                const SizedBox(width: 8),
                // Status Badge
                _buildStatusBadge(ticket.status, statusColors),
                const Spacer(),
                Text(
                  ticket.id,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 2: Subject
            Text(
              ticket.subject,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Row 3: Description preview
            Text(
              ticket.description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Row 4: Doctor info + Assigned + Messages count + Timestamp
            Row(
              children: [
                // Doctor Avatar + Name
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.12),
                  child: Text(
                    ticket.doctorName.isNotEmpty
                        ? ticket.doctorName[0].toUpperCase()
                        : 'D',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ticket.doctorName,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 16),

                // Assigned
                if (ticket.assignedToName != null) ...[
                  Icon(Icons.person_outline_rounded,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    ticket.assignedToName!,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                ],

                // Messages count
                if (ticket.messages.isNotEmpty) ...[
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    '${ticket.messages.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],

                const Spacer(),
                Text(
                  dateFormat.format(ticket.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 6. TICKET DETAIL DIALOG ====================
  void _showTicketDetailsDialog(
    BuildContext context,
    SupportTicketModel ticket,
    SupportTicketNotifier notifier,
  ) {
    final dateFormat = DateFormat('MMMM d, yyyy • hh:mm:ss a');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 640,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _categoryColorMap(ticket.category).fg.withValues(alpha: 0.9),
                            _categoryColorMap(ticket.category).fg,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _categoryIcon(ticket.category),
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${ticket.category.label} — ${ticket.id}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Body
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subject
                            Text(
                              ticket.subject,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Badges Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildChip(ticket.category.label,
                                    _categoryColorMap(ticket.category).fg,
                                    _categoryColorMap(ticket.category).bg),
                                _buildChip(ticket.priority.label,
                                    _priorityColorMap(ticket.priority).fg,
                                    _priorityColorMap(ticket.priority).bg),
                                _buildStatusBadge(ticket.status,
                                    _statusColorMap(ticket.status)),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Description
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                ticket.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Meta Details
                            _buildSectionHeader('TICKET DETAILS'),
                            const SizedBox(height: 8),
                            _buildDetailRow('Doctor', ticket.doctorName),
                            _buildDetailRow('Email', ticket.doctorEmail),
                            _buildDetailRow(
                                'Created', dateFormat.format(ticket.createdAt)),
                            _buildDetailRow(
                                'Updated', dateFormat.format(ticket.updatedAt)),
                            _buildDetailRow('Assigned To',
                                ticket.assignedToName ?? 'Unassigned'),

                            if (ticket.resolution != null) ...[
                              const SizedBox(height: 16),
                              _buildSectionHeader('RESOLUTION'),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFA7F3D0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ticket.resolution!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                    if (ticket.resolvedBy != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Resolved by ${ticket.resolvedBy}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],

                            // Conversation Thread
                            if (ticket.messages.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _buildSectionHeader(
                                  'CONVERSATION (${ticket.messages.length})'),
                              const SizedBox(height: 10),
                              ...ticket.messages.map(
                                (msg) => _buildMessageBubble(context, msg),
                              ),
                            ],

                            // Internal Notes (admin only)
                            if (ticket.internalNotes.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _buildSectionHeader('INTERNAL NOTES (ADMIN ONLY)'),
                              const SizedBox(height: 10),
                              ...ticket.internalNotes.map(
                                (note) => _buildInternalNote(note),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Footer Actions
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(16)),
                        border: const Border(
                          top: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (ticket.status == TicketStatus.open)
                            _buildActionButton(
                              'Mark In Progress',
                              Icons.pending_actions_rounded,
                              const Color(0xFFF59E0B),
                              () {
                                notifier.updateTicketStatus(
                                    ticket.id, TicketStatus.inProgress);
                                Navigator.pop(dialogCtx);
                              },
                            ),
                          if (ticket.status == TicketStatus.open ||
                              ticket.status == TicketStatus.inProgress) ...[
                            const SizedBox(width: 8),
                            _buildActionButton(
                              'Resolve',
                              Icons.check_circle_rounded,
                              const Color(0xFF10B981),
                              () {
                                notifier.updateTicketStatus(
                                    ticket.id, TicketStatus.resolved);
                                Navigator.pop(dialogCtx);
                              },
                            ),
                          ],
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, TicketMessage msg) {
    final isAdmin = msg.senderRole == 'admin';
    final timeFormat = DateFormat('MMM d, hh:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAdmin ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: isAdmin
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF10B981),
                    child: Text(
                      msg.senderName.isNotEmpty
                          ? msg.senderName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    msg.senderName,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAdmin
                          ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                          : const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isAdmin ? 'Admin' : 'Doctor',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isAdmin
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                timeFormat.format(msg.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            msg.content,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInternalNote(TicketNote note) {
    final timeFormat = DateFormat('MMM d, hh:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Text(
                    note.adminName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
              Text(
                timeFormat.format(note.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.content,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================
  Widget _buildChip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(TicketStatus status, _ChipColors colors) {
    IconData icon;
    switch (status) {
      case TicketStatus.open:
        icon = Icons.circle_outlined;
        break;
      case TicketStatus.inProgress:
        icon = Icons.pending_rounded;
        break;
      case TicketStatus.resolved:
        icon = Icons.check_circle_rounded;
        break;
      case TicketStatus.closed:
        icon = Icons.lock_rounded;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(TicketCategory cat) {
    switch (cat) {
      case TicketCategory.bug:
        return Icons.bug_report_rounded;
      case TicketCategory.complaint:
        return Icons.report_problem_rounded;
      case TicketCategory.feedback:
        return Icons.thumb_up_alt_rounded;
      case TicketCategory.suggestion:
        return Icons.lightbulb_rounded;
      case TicketCategory.featureRequest:
        return Icons.rocket_launch_rounded;
    }
  }

  _ChipColors _categoryColorMap(TicketCategory cat) {
    switch (cat) {
      case TicketCategory.bug:
        return const _ChipColors(Color(0xFFEF4444), Color(0xFFFEF2F2));
      case TicketCategory.complaint:
        return const _ChipColors(Color(0xFFF59E0B), Color(0xFFFFFBEB));
      case TicketCategory.feedback:
        return const _ChipColors(Color(0xFF10B981), Color(0xFFECFDF5));
      case TicketCategory.suggestion:
        return const _ChipColors(Color(0xFF8B5CF6), Color(0xFFF5F3FF));
      case TicketCategory.featureRequest:
        return const _ChipColors(Color(0xFF2563EB), Color(0xFFEFF6FF));
    }
  }

  _ChipColors _priorityColorMap(TicketPriority p) {
    switch (p) {
      case TicketPriority.low:
        return const _ChipColors(Color(0xFF6B7280), Color(0xFFF3F4F6));
      case TicketPriority.medium:
        return const _ChipColors(Color(0xFF2563EB), Color(0xFFEFF6FF));
      case TicketPriority.high:
        return const _ChipColors(Color(0xFFF59E0B), Color(0xFFFFFBEB));
      case TicketPriority.critical:
        return const _ChipColors(Color(0xFFEF4444), Color(0xFFFEF2F2));
    }
  }

  _ChipColors _statusColorMap(TicketStatus s) {
    switch (s) {
      case TicketStatus.open:
        return const _ChipColors(Color(0xFF2563EB), Color(0xFFEFF6FF));
      case TicketStatus.inProgress:
        return const _ChipColors(Color(0xFFF59E0B), Color(0xFFFFFBEB));
      case TicketStatus.resolved:
        return const _ChipColors(Color(0xFF10B981), Color(0xFFECFDF5));
      case TicketStatus.closed:
        return const _ChipColors(Color(0xFF6B7280), Color(0xFFF3F4F6));
    }
  }
}

class _ChipColors {
  final Color fg;
  final Color bg;
  const _ChipColors(this.fg, this.bg);
}

class _StatusItem {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatusItem(this.label, this.count, this.color, this.icon);
}
