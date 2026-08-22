import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/campaign_model.dart';
import '../models/campaign_recipient_log.dart';

/// Repository managing multi-tenant Campaign persistence and audit log subcollections.
///
/// Data Hierarchy:
/// `users/{doctorId}/campaigns/{campaignId}`
///   └─ `recipients/{recipientLogId}`
class CampaignRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CampaignRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _currentDoctorId {
    return _auth.currentUser?.uid ?? 'anonymous';
  }

  CollectionReference<Map<String, dynamic>> _campaignsCol(String doctorId) {
    return _firestore.collection('users').doc(doctorId).collection('campaigns');
  }

  CollectionReference<Map<String, dynamic>> _recipientsCol(
      String doctorId, String campaignId) {
    return _campaignsCol(doctorId).doc(campaignId).collection('recipients');
  }

  /// Creates a new campaign document in Firestore.
  Future<void> createCampaign(CampaignModel campaign) async {
    final doctorId = campaign.doctorId.isNotEmpty ? campaign.doctorId : _currentDoctorId;
    if (doctorId == 'anonymous') {
      throw Exception('Unauthenticated: Doctor must be logged in to create campaigns.');
    }

    final docRef = _campaignsCol(doctorId).doc(campaign.id);
    await docRef.set(campaign.toMap(), SetOptions(merge: true));
  }

  /// Updates an existing campaign document.
  Future<void> updateCampaign(CampaignModel campaign) async {
    final doctorId = campaign.doctorId.isNotEmpty ? campaign.doctorId : _currentDoctorId;
    final docRef = _campaignsCol(doctorId).doc(campaign.id);
    await docRef.update(campaign.toMap());
  }

  /// Retrieves a specific campaign by ID.
  Future<CampaignModel?> getCampaign(String doctorId, String campaignId) async {
    final doc = await _campaignsCol(doctorId).doc(campaignId).get();
    if (!doc.exists || doc.data() == null) return null;
    return CampaignModel.fromFirestore(doc);
  }

  /// Deletes a campaign and its recipient logs.
  Future<void> deleteCampaign(String doctorId, String campaignId) async {
    final recCol = _recipientsCol(doctorId, campaignId);
    final recSnap = await recCol.limit(500).get();
    final batch = _firestore.batch();
    for (final doc in recSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_campaignsCol(doctorId).doc(campaignId));
    await batch.commit();
  }

  /// Real-time stream of all campaigns belonging to the specified doctor.
  Stream<List<CampaignModel>> watchDoctorCampaigns([String? doctorIdOverride]) {
    final doctorId = doctorIdOverride ?? _currentDoctorId;
    if (doctorId == 'anonymous') {
      return Stream.value([]);
    }

    return _campaignsCol(doctorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => CampaignModel.fromFirestore(doc)).toList());
  }

  /// Real-time stream of recipient delivery logs for a specific campaign.
  Stream<List<CampaignRecipientLog>> watchRecipientLogs(
      String doctorId, String campaignId) {
    return _recipientsCol(doctorId, campaignId)
        .orderBy('dispatchedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => CampaignRecipientLog.fromFirestore(doc))
            .toList());
  }

  /// Fetches recipient logs with a single query.
  Future<List<CampaignRecipientLog>> getRecipientLogs(
      String doctorId, String campaignId) async {
    final snap = await _recipientsCol(doctorId, campaignId)
        .orderBy('dispatchedAt', descending: false)
        .get();
    return snap.docs
        .map((doc) => CampaignRecipientLog.fromFirestore(doc))
        .toList();
  }

  /// Saves or updates a recipient log entry.
  Future<void> saveRecipientLog(CampaignRecipientLog log) async {
    await _recipientsCol(log.doctorId, log.campaignId)
        .doc(log.id)
        .set(log.toMap(), SetOptions(merge: true));
  }

  /// Batch writes multiple recipient logs.
  Future<void> saveRecipientLogsBatch(
      String doctorId, String campaignId, List<CampaignRecipientLog> logs) async {
    if (logs.isEmpty) return;
    const batchSize = 450;
    for (var i = 0; i < logs.length; i += batchSize) {
      final chunk = logs.sublist(
          i, i + batchSize > logs.length ? logs.length : i + batchSize);
      final batch = _firestore.batch();
      for (final log in chunk) {
        final docRef = _recipientsCol(doctorId, campaignId).doc(log.id);
        batch.set(docRef, log.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  /// Fetches aggregate KPI metrics across all doctor campaigns.
  Future<Map<String, dynamic>> getAggregateStats(String doctorId) async {
    try {
      final snap = await _campaignsCol(doctorId).get();
      int totalCampaigns = snap.docs.length;
      int totalRecipients = 0;
      int totalEmailsSent = 0;
      int totalEmailsFailed = 0;
      int totalWhatsAppSent = 0;
      int totalWhatsAppFailed = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        totalRecipients += (data['totalRecipients'] as num?)?.toInt() ?? 0;
        totalEmailsSent += (data['emailsSent'] as num?)?.toInt() ?? 0;
        totalEmailsFailed += (data['emailsFailed'] as num?)?.toInt() ?? 0;
        totalWhatsAppSent += (data['whatsAppSent'] as num?)?.toInt() ?? 0;
        totalWhatsAppFailed += (data['whatsAppFailed'] as num?)?.toInt() ?? 0;
      }

      final totalSent = totalEmailsSent + totalWhatsAppSent;
      final totalFailed = totalEmailsFailed + totalWhatsAppFailed;
      final totalAttempts = totalSent + totalFailed;
      final double overallSuccessRate =
          totalAttempts > 0 ? (totalSent / totalAttempts) * 100.0 : 100.0;

      return {
        'totalCampaigns': totalCampaigns,
        'totalRecipients': totalRecipients,
        'totalEmailsSent': totalEmailsSent,
        'totalEmailsFailed': totalEmailsFailed,
        'totalWhatsAppSent': totalWhatsAppSent,
        'totalWhatsAppFailed': totalWhatsAppFailed,
        'overallSuccessRate': overallSuccessRate,
      };
    } catch (e) {
      debugPrint('CampaignRepository stats error: $e');
      return {
        'totalCampaigns': 0,
        'totalRecipients': 0,
        'totalEmailsSent': 0,
        'totalEmailsFailed': 0,
        'totalWhatsAppSent': 0,
        'totalWhatsAppFailed': 0,
        'overallSuccessRate': 0.0,
      };
    }
  }
}
