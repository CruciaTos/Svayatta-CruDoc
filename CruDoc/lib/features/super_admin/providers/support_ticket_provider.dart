import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/enums.dart';
import '../models/support_ticket_model.dart';

/// State for the Support Tickets management screen.
class SupportTicketState {
  final List<SupportTicketModel> tickets;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;
  final TicketCategory? categoryFilter;
  final TicketStatus? statusFilter;
  final TicketPriority? priorityFilter;

  const SupportTicketState({
    this.tickets = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery = '',
    this.categoryFilter,
    this.statusFilter,
    this.priorityFilter,
  });

  SupportTicketState copyWith({
    List<SupportTicketModel>? tickets,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
    TicketCategory? categoryFilter,
    TicketStatus? statusFilter,
    TicketPriority? priorityFilter,
    bool clearError = false,
    bool clearCategory = false,
    bool clearStatus = false,
    bool clearPriority = false,
  }) {
    return SupportTicketState(
      tickets: tickets ?? this.tickets,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter:
          clearCategory ? null : (categoryFilter ?? this.categoryFilter),
      statusFilter:
          clearStatus ? null : (statusFilter ?? this.statusFilter),
      priorityFilter:
          clearPriority ? null : (priorityFilter ?? this.priorityFilter),
    );
  }

  /// Filtered view of tickets.
  List<SupportTicketModel> get filteredTickets {
    return tickets.where((ticket) {
      // 1. Search
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final matchesSubject = ticket.subject.toLowerCase().contains(q);
        final matchesDoctor = ticket.doctorName.toLowerCase().contains(q) ||
            ticket.doctorEmail.toLowerCase().contains(q) ||
            (ticket.doctorPhone?.toLowerCase().contains(q) ?? false);
        final matchesDescription = ticket.description.toLowerCase().contains(q);
        final matchesId = ticket.id.toLowerCase().contains(q);
        if (!matchesSubject &&
            !matchesDoctor &&
            !matchesDescription &&
            !matchesId) {
          return false;
        }
      }

      // 2. Category
      if (categoryFilter != null && ticket.category != categoryFilter) {
        return false;
      }

      // 3. Status
      if (statusFilter != null && ticket.status != statusFilter) {
        return false;
      }

      // 4. Priority
      if (priorityFilter != null && ticket.priority != priorityFilter) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Category-wise ticket counts for the summary cards.
  int countByCategory(TicketCategory cat) =>
      tickets.where((t) => t.category == cat).length;

  int get openCount =>
      tickets.where((t) => t.status == TicketStatus.open).length;

  int get inProgressCount =>
      tickets.where((t) => t.status == TicketStatus.inProgress).length;

  int get resolvedCount =>
      tickets.where((t) => t.status == TicketStatus.resolved).length;

  int get criticalCount =>
      tickets.where((t) => t.priority == TicketPriority.critical).length;
}

/// Riverpod Notifier for Support Ticket state management.
class SupportTicketNotifier extends Notifier<SupportTicketState> {
  @override
  SupportTicketState build() {
    Future.microtask(() => loadTickets());
    return const SupportTicketState();
  }

  /// Seed mock tickets for immediate presentation.
  List<SupportTicketModel> _getMockTickets() {
    final now = DateTime.now();
    return [
      SupportTicketModel(
        id: 'TK-1001',
        doctorId: 'doc-991',
        doctorName: 'Dr. Venom Mhatre',
        doctorEmail: 'venom@crudoc.com',
        doctorPhone: '+91 98765 43210',
        subject: 'App crashes on adding patient with special characters',
        description:
            'When I add a patient whose name contains special characters like apostrophes or accented letters, the app freezes and crashes. This happens consistently on both web and mobile.',
        category: TicketCategory.bug,
        priority: TicketPriority.critical,
        status: TicketStatus.open,
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 1)),
        messages: [
          TicketMessage(
            senderId: 'doc-991',
            senderName: 'Dr. Venom Mhatre',
            senderRole: 'doctor',
            content:
                'This has been happening since the last update. I have 3 patients I cannot add.',
            timestamp: now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
      SupportTicketModel(
        id: 'TK-1002',
        doctorId: 'doc-882',
        doctorName: 'Dr. Smit Mhatre',
        doctorEmail: 'smit@crudoc.com',
        doctorPhone: '+91 98123 45678',
        subject: 'Revenue report shows wrong totals for last month',
        description:
            'The monthly revenue summary on the dashboard is displaying an incorrect total. It seems to be double-counting some visit fees. The CSV export is also reflecting the wrong numbers.',
        category: TicketCategory.bug,
        priority: TicketPriority.high,
        status: TicketStatus.inProgress,
        createdAt: now.subtract(const Duration(days: 1, hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 6)),
        assignedTo: 'admin-02',
        assignedToName: 'Rahul Sharma',
        messages: [
          TicketMessage(
            senderId: 'doc-882',
            senderName: 'Dr. Smit Mhatre',
            senderRole: 'doctor',
            content:
                'I noticed this when I exported the CSV for tax filing.',
            timestamp: now.subtract(const Duration(days: 1, hours: 5)),
          ),
          TicketMessage(
            senderId: 'admin-02',
            senderName: 'Rahul Sharma',
            senderRole: 'admin',
            content:
                'Thank you for reporting. We are investigating the revenue aggregation logic. Will keep you updated.',
            timestamp: now.subtract(const Duration(hours: 6)),
          ),
        ],
        internalNotes: [
          TicketNote(
            adminId: 'admin-02',
            adminName: 'Rahul Sharma',
            content: 'Likely related to the encryption migration for amount fields. Checking revenue_repo.dart.',
            timestamp: now.subtract(const Duration(hours: 5)),
          ),
        ],
      ),
      SupportTicketModel(
        id: 'TK-1003',
        doctorId: 'doc-773',
        doctorName: 'Dr. Ananya Roy',
        doctorEmail: 'ananya@royhealth.com',
        doctorPhone: '+91 97654 32109',
        subject: 'Slow appointment loading on dashboard',
        description:
            'The dashboard takes over 10 seconds to load the appointment list when I have more than 50 appointments for the day. This is making my workflow very slow.',
        category: TicketCategory.complaint,
        priority: TicketPriority.medium,
        status: TicketStatus.open,
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
        updatedAt: now.subtract(const Duration(days: 2, hours: 3)),
      ),
      SupportTicketModel(
        id: 'TK-1004',
        doctorId: 'doc-664',
        doctorName: 'Dr. Rajesh Kumar',
        doctorEmail: 'rkumar@citycare.com',
        subject: 'Suggestion: Add dark mode to web dashboard',
        description:
            'It would be great if the web dashboard had a dark mode option. I often work late hours and the bright white interface is straining on the eyes. Many modern apps support this.',
        category: TicketCategory.suggestion,
        priority: TicketPriority.low,
        status: TicketStatus.open,
        createdAt: now.subtract(const Duration(days: 3, hours: 8)),
        updatedAt: now.subtract(const Duration(days: 3, hours: 8)),
      ),
      SupportTicketModel(
        id: 'TK-1005',
        doctorId: 'doc-555',
        doctorName: 'Dr. Meera Patel',
        doctorEmail: 'meera@patelclinic.in',
        subject: 'Great experience with the new invoice system!',
        description:
            'Just wanted to share that the new invoice generation and receipt download feature is excellent. My patients love receiving digital receipts. Keep up the good work!',
        category: TicketCategory.feedback,
        priority: TicketPriority.low,
        status: TicketStatus.closed,
        createdAt: now.subtract(const Duration(days: 4, hours: 2)),
        updatedAt: now.subtract(const Duration(days: 3)),
        resolvedAt: now.subtract(const Duration(days: 3)),
        resolvedBy: 'Super Admin',
        resolution: 'Acknowledged with thanks. Shared with the team.',
      ),
      SupportTicketModel(
        id: 'TK-1006',
        doctorId: 'doc-446',
        doctorName: 'Dr. Alex Mercer',
        doctorEmail: 'alex.m@clinic.org',
        subject: 'Feature Request: WhatsApp integration for appointment reminders',
        description:
            'I would love to have WhatsApp integration to send automatic appointment reminders to patients. This would reduce no-shows significantly. Many of my patients prefer WhatsApp over SMS.',
        category: TicketCategory.featureRequest,
        priority: TicketPriority.medium,
        status: TicketStatus.open,
        createdAt: now.subtract(const Duration(days: 5, hours: 1)),
        updatedAt: now.subtract(const Duration(days: 5, hours: 1)),
      ),
      SupportTicketModel(
        id: 'TK-1007',
        doctorId: 'doc-337',
        doctorName: 'Dr. John Doe',
        doctorEmail: 'john.doe@expired.com',
        subject: 'Cannot access inventory after plan downgrade',
        description:
            'After my plan was downgraded from Professional to Starter, I can no longer access the inventory module. But my existing medicine data should still be viewable even if read-only.',
        category: TicketCategory.complaint,
        priority: TicketPriority.high,
        status: TicketStatus.resolved,
        createdAt: now.subtract(const Duration(days: 6, hours: 4)),
        updatedAt: now.subtract(const Duration(days: 5)),
        resolvedAt: now.subtract(const Duration(days: 5)),
        resolvedBy: 'Sarah Jenkins',
        resolution:
            'Granted read-only access to inventory data for downgraded plans. Doctor confirmed the fix.',
        assignedTo: 'admin-03',
        assignedToName: 'Sarah Jenkins',
        messages: [
          TicketMessage(
            senderId: 'doc-337',
            senderName: 'Dr. John Doe',
            senderRole: 'doctor',
            content: 'I need to view my medicine stock even on the Starter plan.',
            timestamp: now.subtract(const Duration(days: 6, hours: 4)),
          ),
          TicketMessage(
            senderId: 'admin-03',
            senderName: 'Sarah Jenkins',
            senderRole: 'admin',
            content:
                'We have enabled read-only inventory access for your account. Please check and confirm.',
            timestamp: now.subtract(const Duration(days: 5, hours: 2)),
          ),
          TicketMessage(
            senderId: 'doc-337',
            senderName: 'Dr. John Doe',
            senderRole: 'doctor',
            content: 'Yes, I can see it now. Thank you!',
            timestamp: now.subtract(const Duration(days: 5)),
          ),
        ],
      ),
      SupportTicketModel(
        id: 'TK-1008',
        doctorId: 'doc-228',
        doctorName: 'Dr. Priya Sharma',
        doctorEmail: 'priya.sharma@wellness.in',
        subject: 'Prescription PDF not generating correctly',
        description:
            'When I generate a prescription PDF for a patient, the medicine dosage instructions are cut off on the right side. The print layout seems to have a margin issue.',
        category: TicketCategory.bug,
        priority: TicketPriority.high,
        status: TicketStatus.open,
        createdAt: now.subtract(const Duration(hours: 8)),
        updatedAt: now.subtract(const Duration(hours: 8)),
      ),
    ];
  }

  Future<void> loadTickets() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final mockTickets = _getMockTickets();
      state = state.copyWith(
        tickets: mockTickets,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load support tickets: $e',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setCategoryFilter(TicketCategory? category) {
    state = state.copyWith(
      categoryFilter: category,
      clearCategory: category == null,
    );
  }

  void setStatusFilter(TicketStatus? status) {
    state = state.copyWith(
      statusFilter: status,
      clearStatus: status == null,
    );
  }

  void setPriorityFilter(TicketPriority? priority) {
    state = state.copyWith(
      priorityFilter: priority,
      clearPriority: priority == null,
    );
  }

  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      clearCategory: true,
      clearStatus: true,
      clearPriority: true,
    );
  }

  void updateTicketStatus(String ticketId, TicketStatus newStatus) {
    final updatedTickets = state.tickets.map((t) {
      if (t.id == ticketId) {
        return SupportTicketModel(
          id: t.id,
          doctorId: t.doctorId,
          doctorName: t.doctorName,
          doctorEmail: t.doctorEmail,
          doctorPhone: t.doctorPhone,
          subject: t.subject,
          description: t.description,
          category: t.category,
          priority: t.priority,
          status: newStatus,
          createdAt: t.createdAt,
          updatedAt: DateTime.now(),
          assignedTo: t.assignedTo,
          assignedToName: t.assignedToName,
          messages: t.messages,
          internalNotes: t.internalNotes,
          resolvedAt: newStatus == TicketStatus.resolved ? DateTime.now() : t.resolvedAt,
          resolvedBy: newStatus == TicketStatus.resolved ? 'Super Admin' : t.resolvedBy,
          resolution: t.resolution,
          isArchived: t.isArchived,
        );
      }
      return t;
    }).toList();
    state = state.copyWith(tickets: updatedTickets);
  }
}

/// Provider for Support Tickets state.
final supportTicketProvider =
    NotifierProvider<SupportTicketNotifier, SupportTicketState>(() {
  return SupportTicketNotifier();
});
