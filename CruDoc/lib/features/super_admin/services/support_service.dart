import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/support_ticket_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for managing support tickets from doctors.
class SuperAdminSupportService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Get paginated support tickets.
  Future<List<SupportTicketModel>> getTickets({
    int limit = 50,
    String? lastDocId,
    TicketStatus? statusFilter,
    TicketPriority? priorityFilter,
    String? doctorSearch,
  }) async {
    try {
      Query query = _fb.supportTicketsCollection
          .where('isArchived', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (statusFilter != null) {
        query = query.where('status', isEqualTo: statusFilter.name);
      }
      if (priorityFilter != null) {
        query = query.where('priority', isEqualTo: priorityFilter.name);
      }
      if (lastDocId != null) {
        final lastDoc = await _fb.supportTicketsCollection.doc(lastDocId).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      final snapshot = await query.get();
      var tickets = snapshot.docs.map((doc) {
        return SupportTicketModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      // Client-side doctor search
      if (doctorSearch != null && doctorSearch.isNotEmpty) {
        final queryLower = doctorSearch.toLowerCase();
        tickets = tickets.where((t) {
          return t.doctorName.toLowerCase().contains(queryLower) ||
              t.doctorEmail.toLowerCase().contains(queryLower) ||
              t.subject.toLowerCase().contains(queryLower);
        }).toList();
      }

      return tickets;
    } catch (e) {
      throw Exception('Failed to fetch tickets: ${e.toString()}');
    }
  }

  /// Get a single ticket by ID.
  Future<SupportTicketModel?> getTicketById(String ticketId) async {
    try {
      final doc = await _fb.supportTicketsCollection.doc(ticketId).get();
      if (!doc.exists) return null;
      return SupportTicketModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      return null;
    }
  }

  /// Reply to a support ticket.
  Future<void> replyToTicket({
    required String ticketId,
    required String content,
  }) async {
    try {
      final message = {
        'senderId': _fb.currentUserId,
        'senderName': _fb.currentUser?.displayName ?? 'Admin',
        'senderRole': 'admin',
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _fb.supportTicketsCollection.doc(ticketId).update({
        'messages': FieldValue.arrayUnion([message]),
        'status': TicketStatus.inProgress.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to send reply: ${e.toString()}');
    }
  }

  /// Update ticket status.
  Future<void> updateTicketStatus({
    required String ticketId,
    required TicketStatus newStatus,
    String? resolution,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == TicketStatus.resolved) {
        updates['resolvedAt'] = FieldValue.serverTimestamp();
        updates['resolvedBy'] = _fb.currentUserEmail;
        if (resolution != null) updates['resolution'] = resolution;
      }

      await _fb.supportTicketsCollection.doc(ticketId).update(updates);
    } catch (e) {
      throw Exception('Failed to update ticket status: ${e.toString()}');
    }
  }

  /// Assign ticket to an admin.
  Future<void> assignTicket({
    required String ticketId,
    required String adminId,
    required String adminName,
  }) async {
    try {
      await _fb.supportTicketsCollection.doc(ticketId).update({
        'assignedTo': adminId,
        'assignedToName': adminName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to assign ticket: ${e.toString()}');
    }
  }

  /// Add internal note to a ticket.
  Future<void> addInternalNote({
    required String ticketId,
    required String content,
  }) async {
    try {
      final note = {
        'adminId': _fb.currentUserId,
        'adminName': _fb.currentUser?.displayName ?? 'Admin',
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _fb.supportTicketsCollection.doc(ticketId).update({
        'internalNotes': FieldValue.arrayUnion([note]),
      });
    } catch (e) {
      throw Exception('Failed to add note: ${e.toString()}');
    }
  }

  /// Archive a ticket.
  Future<void> archiveTicket(String ticketId) async {
    try {
      await _fb.supportTicketsCollection.doc(ticketId).update({
        'isArchived': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to archive ticket: ${e.toString()}');
    }
  }

  /// Get ticket counts by status.
  Future<Map<String, int>> getTicketCounts() async {
    try {
      final snapshot = await _fb.supportTicketsCollection
          .where('isArchived', isEqualTo: false)
          .get();

      final counts = <String, int>{
        'open': 0,
        'inProgress': 0,
        'resolved': 0,
        'closed': 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'open';
        counts[status] = (counts[status] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      return {};
    }
  }
}