import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_log_local_service.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// Reads whether a patient got their appointment reminder.
///
/// The app does not send WhatsApp messages. A Cloud Function sweeps tomorrow's
/// appointments each evening at 18:00 IST and sends from CruDoc's number, and
/// Meta's delivery receipts come back to a webhook. So this repository only
/// reads, and `whatsapp_notification_logs` has exactly one writer.
///
/// It used to send. That path POSTed to a hardcoded URL for a project that
/// does not exist (`svayatta-crudoc` rather than `svayatta-crudoc-dev`), so it
/// never reached a function, and then returned success with an invented
/// message id — which is why appointments showed a green "WhatsApp: Sent"
/// badge for messages nobody ever received. Reporting a send that did not
/// happen is worse than reporting nothing, so none of that is kept.
class WhatsAppRepository {
  WhatsAppRepository({
    WhatsAppLogLocalService? logLocalService,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    String? currentDoctorId,
  }) : _logLocalService = logLocalService ?? WhatsAppLogLocalService(),
       _authOverride = auth,
       _firestoreOverride = firestore,
       _doctorIdOverride = currentDoctorId;

  final WhatsAppLogLocalService _logLocalService;
  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  final String? _doctorIdOverride;

  static const String _collection = 'whatsapp_notification_logs';

  FirebaseAuth? get _auth {
    if (_authOverride != null) return _authOverride;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    if (_firestoreOverride != null) return _firestoreOverride;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  String get _currentDoctorId {
    final override = _doctorIdOverride;
    if (override != null && override.isNotEmpty) return override;
    try {
      final uid =
          ClinicSession.instance.access?.clinicId ?? _auth?.currentUser?.uid;
      return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
    } catch (_) {
      return 'anonymous';
    }
  }

  /// The reminder status for one visit, or null when none was recorded.
  ///
  /// Reads the local copy first so the status still shows without a
  /// connection; the local row is a cache of what the server wrote, kept up to
  /// date by [watchVisitWhatsAppStatus].
  Future<WhatsAppNotificationLog?> getLogForVisit(String visitId) async {
    if (visitId.isEmpty) return null;

    if (!kIsWeb) {
      final local = await _logLocalService.getLogByVisitId(
        visitId,
        _currentDoctorId,
      );
      if (local != null) return local;
    }

    try {
      final firestore = _firestore;
      if (firestore == null) return null;

      final doc = await firestore.collection(_collection).doc(visitId).get();
      if (doc.exists && doc.data() != null) {
        final log = WhatsAppNotificationLog.fromFirestore(doc);
        await _cacheLocally(log);
        return log;
      }
    } catch (e) {
      debugPrint('[WhatsApp] could not read the log for $visitId: $e');
    }

    return null;
  }

  /// Watches the reminder status for one visit.
  ///
  /// The document id is the appointment id, which is how the server keys it.
  Stream<WhatsAppNotificationLog?> watchVisitWhatsAppStatus(String visitId) {
    if (visitId.isEmpty) return Stream.value(null);

    final firestore = _firestore;
    if (firestore == null) return Stream.value(null);

    return firestore
        .collection(_collection)
        .doc(visitId)
        .snapshots()
        .map((snap) {
          if (snap.exists && snap.data() != null) {
            final log = WhatsAppNotificationLog.fromFirestore(snap);
            // Not awaited: the badge should not wait on a cache write.
            unawaited(_cacheLocally(log));
            return log;
          }
          return null;
        })
        .handleError((_) => null);
  }

  /// Keeps a local copy so a reopened appointment shows its last known status
  /// offline. Never the source of truth, and never written back to Firestore.
  Future<void> _cacheLocally(WhatsAppNotificationLog log) async {
    if (kIsWeb) return;
    try {
      await _logLocalService.insertLog(log);
    } catch (e) {
      debugPrint('[WhatsApp] could not cache the log locally: $e');
    }
  }
}
