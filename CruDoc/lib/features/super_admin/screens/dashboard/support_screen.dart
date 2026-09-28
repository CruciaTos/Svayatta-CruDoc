import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/enums.dart';
import '../../models/support_ticket_model.dart';
import '../../providers/support_ticket_provider.dart';

/// Super Admin Support Tickets Management Screen redesigned in the CruDoc Calm Clinical design system.
/// Manages incoming clinic requests, bug reports, feature requests, and resolution workflows.
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
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          _buildHeader(context, ticketState, notifier),

          const SizedBox(height: CruSpace.s20),

          // 2. Category Summary Cards
          _buildCategorySummary(context, ticketState, notifier, isMobile),

          const SizedBox(height: CruSpace.s20),

          // 3. Search & Filter Bar
          _buildSearchFilters(context, ticketState, notifier),

          const SizedBox(height: CruSpace.s20),

          // 4. Tickets List
          _buildTicketsList(context, ticketState, filtered, notifier, isMobile),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER
  // ===========================================================================
  Widget _buildHeader(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
  ) {
    final c = context.cru;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Support Desk & Triage', style: CruType.largeTitle.tint(c.label)),
                  const SizedBox(width: CruSpace.s12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: ShapeDecoration(
                      color: c.accentTint,
                      shape: cruShape(CruRadius.full),
                    ),
                    child: Text(
                      '${state.filteredTickets.length} Tickets',
                      style: CruType.caption.w600.tabular.tint(c.accentText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Resolve doctor-reported issues, PACS connectivity tickets, feature feedback, and hardware bridge support.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        CruButton(
          label: 'Refresh',
          kind: CruButtonKind.secondary,
          icon: CruIcons.sparkle,
          onPressed: state.isLoading ? null : () => notifier.loadTickets(),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. CATEGORY SUMMARY CARDS
  // ===========================================================================
  Widget _buildCategorySummary(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    final c = context.cru;

    final categories = [
      (TicketCategory.bug, 'Bug Report', CruIcons.warning, c.redText, c.redTint),
      (TicketCategory.complaint, 'Clinical Issues', CruIcons.clock, c.amberText, c.amberTint),
      (TicketCategory.feedback, 'Doctor Feedback', CruIcons.whatsapp, c.greenText, c.greenTint),
      (TicketCategory.featureRequest, 'Feature Requests', CruIcons.sparkle, c.accentText, c.accentTint),
    ];

    if (isMobile) {
      return Column(
        children: categories.map((cat) {
          final count = state.countByCategory(cat.$1);
          final isSelected = state.categoryFilter == cat.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s8),
            child: _buildCategoryCard(c, notifier, cat.$1, cat.$2, count, cat.$3, cat.$4, isSelected),
          );
        }).toList(),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < categories.length; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s12),
          Expanded(
            child: _buildCategoryCard(
              c,
              notifier,
              categories[i].$1,
              categories[i].$2,
              state.countByCategory(categories[i].$1),
              categories[i].$3,
              categories[i].$4,
              state.categoryFilter == categories[i].$1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryCard(
    CruColors c,
    SupportTicketNotifier notifier,
    TicketCategory category,
    String title,
    int count,
    CruIconData icon,
    Color color,
    bool isSelected,
  ) {
    return CruPressable(
      onTap: () {
        notifier.setCategoryFilter(isSelected ? null : category);
      },
      scaleOnPress: false,
      builder: (ctx, hovered) {
        return CruCard(
          padding: const EdgeInsets.all(CruSpace.s16),
          borderColor: isSelected ? c.accent : null,
          borderWidth: isSelected ? 1.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: c.accentTint,
                      shape: cruShape(CruRadius.iconTile),
                    ),
                    child: CruIcon(icon, size: 16, color: color),
                  ),
                  const Spacer(),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: ShapeDecoration(
                        color: c.accent,
                        shape: cruShape(CruRadius.full),
                      ),
                      child: Text('ACTIVE', style: CruType.caption.w600.tint(CruBrand.white)),
                    ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              Text('$count', style: CruType.metric.tint(c.label)),
              const SizedBox(height: CruSpace.s2),
              Text(title, style: CruType.subhead.w600.tint(c.label)),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 3. SEARCH & FILTERS
  // ===========================================================================
  Widget _buildSearchFilters(
    BuildContext context,
    SupportTicketState state,
    SupportTicketNotifier notifier,
  ) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => notifier.setSearchQuery(val),
              style: CruType.text.tint(c.label),
              decoration: InputDecoration(
                hintText: 'Search tickets by subject, description, doctor, or clinic...',
                hintStyle: CruType.text.tint(c.label3),
                filled: true,
                fillColor: c.inset,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CruIcon(CruIcons.search, size: 16, color: c.label3),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: CruIcon(CruIcons.close, size: 14, color: c.label3),
                        onPressed: () {
                          _searchController.clear();
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Status:', style: CruType.caption.w600.tint(c.label3)),
              _buildPill(
                label: 'All Tickets',
                selected: state.statusFilter == null,
                onTap: () => notifier.setStatusFilter(null),
              ),
              for (final s in TicketStatus.values)
                _buildPill(
                  label: s.label,
                  selected: state.statusFilter == s,
                  onTap: () => notifier.setStatusFilter(s),
                ),
              const SizedBox(width: CruSpace.s10),
              Text('Priority:', style: CruType.caption.w600.tint(c.label3)),
              _buildPill(
                label: 'All',
                selected: state.priorityFilter == null,
                onTap: () => notifier.setPriorityFilter(null),
              ),
              for (final p in TicketPriority.values)
                _buildPill(
                  label: p.label,
                  selected: state.priorityFilter == p,
                  onTap: () => notifier.setPriorityFilter(p),
                ),
              if (_searchController.text.isNotEmpty ||
                  state.statusFilter != null ||
                  state.priorityFilter != null ||
                  state.categoryFilter != null) ...[
                const SizedBox(width: CruSpace.s8),
                CruPressable(
                  onTap: () {
                    _searchController.clear();
                    notifier.clearFilters();
                  },
                  builder: (ctx, hovered) => Text('Reset', style: CruType.caption.w600.tint(c.accentText)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      builder: (ctx, hovered) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: ShapeDecoration(
            color: selected
                ? c.accent
                : hovered
                    ? c.hoverFill
                    : c.inset,
            shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
          ),
          child: Text(
            label,
            style: CruType.caption
                .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500)
                .tint(selected ? CruBrand.white : c.label2),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 4. TICKETS LIST
  // ===========================================================================
  Widget _buildTicketsList(
    BuildContext context,
    SupportTicketState state,
    List<SupportTicketModel> tickets,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    final c = context.cru;

    if (state.isLoading && tickets.isEmpty) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }

    if (tickets.isEmpty) {
      return CruCard(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              CruIcon(CruIcons.help, size: 40, color: c.label3),
              const SizedBox(height: CruSpace.s12),
              Text('No support tickets match filters', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text('Adjust your category, priority, or search filters above.', style: CruType.text.tint(c.label2)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tickets.length,
      separatorBuilder: (_, _) => const SizedBox(height: CruSpace.s12),
      itemBuilder: (ctx, index) {
        final ticket = tickets[index];
        return _buildTicketCard(context, ticket, notifier, isMobile);
      },
    );
  }

  Widget _buildTicketCard(
    BuildContext context,
    SupportTicketModel ticket,
    SupportTicketNotifier notifier,
    bool isMobile,
  ) {
    final c = context.cru;

    final (prioColor, prioBg) = switch (ticket.priority) {
      TicketPriority.critical => (c.redText, c.redTint),
      TicketPriority.high => (c.redText, c.redTint),
      TicketPriority.medium => (c.amberText, c.amberTint),
      TicketPriority.low => (c.label2, c.inset),
    };

    final (statusDot, statusBg, statusFg) = switch (ticket.status) {
      TicketStatus.open => (CruDotKind.waiting, c.amberTint, c.amberText),
      TicketStatus.inProgress => (CruDotKind.now, c.accentTint, c.accentText),
      TicketStatus.resolved => (CruDotKind.done, c.greenTint, c.greenText),
      TicketStatus.closed => (CruDotKind.inactive, c.inset, c.label3),
    };

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
                ),
                child: Text(ticket.category.label, style: CruType.caption.w600.tint(c.label)),
              ),
              const SizedBox(width: CruSpace.s8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(color: prioBg, shape: cruShape(CruRadius.full)),
                child: Text(ticket.priority.label.toUpperCase(), style: CruType.caption.w600.tint(prioColor)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(color: statusBg, shape: cruShape(CruRadius.full)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruStatusDot(statusDot, size: 6),
                    const SizedBox(width: CruSpace.s6),
                    Text(ticket.status.label, style: CruType.caption.w600.tint(statusFg)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          Text(ticket.subject, style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(ticket.description, style: CruType.text.tint(c.label2)),
          const SizedBox(height: CruSpace.s16),
          Divider(height: 1, color: c.hairline),
          const SizedBox(height: CruSpace.s12),
          Row(
            children: [
              CruMonogram(name: ticket.doctorName, size: 28, background: c.track),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${ticket.doctorName} · ${ticket.doctorEmail}', style: CruType.caption.w600.tint(c.label)),
                    Text(
                      'Created ${DateFormat('dd MMM yyyy, HH:mm').format(ticket.createdAt)}',
                      style: CruType.caption.tabular.tint(c.label3),
                    ),
                  ],
                ),
              ),
              if (ticket.status == TicketStatus.open)
                CruButton(
                  label: 'Mark In Progress',
                  kind: CruButtonKind.secondary,
                  onPressed: () => notifier.updateTicketStatus(ticket.id, TicketStatus.inProgress),
                ),
              if (ticket.status == TicketStatus.open || ticket.status == TicketStatus.inProgress) ...[
                const SizedBox(width: CruSpace.s8),
                CruButton(
                  label: 'Resolve Ticket',
                  kind: CruButtonKind.primary,
                  onPressed: () => _showResolveDialog(context, ticket, notifier),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showResolveDialog(
    BuildContext context,
    SupportTicketModel ticket,
    SupportTicketNotifier notifier,
  ) {
    final c = context.cru;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        shape: cruShape(CruRadius.card),
        title: Text('Resolve Ticket #${ticket.id}', style: CruType.title.tint(c.label)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resolution Notes & Actions Taken:', style: CruType.caption.w600.tint(c.label3)),
              const SizedBox(height: CruSpace.s8),
              TextField(
                controller: notesController,
                maxLines: 4,
                style: CruType.text.tint(c.label),
                decoration: InputDecoration(
                  hintText: 'Enter resolution details sent to the doctor...',
                  hintStyle: CruType.caption.tint(c.label3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(CruRadius.control)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          CruButton(
            label: 'Resolve & Close',
            kind: CruButtonKind.primary,
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              notifier.updateTicketStatus(ticket.id, TicketStatus.resolved);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ticket resolved successfully!')),
              );
            },
          ),
        ],
      ),
    );
  }
}
