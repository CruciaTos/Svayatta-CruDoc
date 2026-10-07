import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// Append-only record of which patient records and files were opened, kept
/// in Firestore `access_logs` so it survives losing the device.
///
/// firestore.rules lets a doctor add entries in their own name and read
/// them back, but never change or delete one.
///
/// Calls are fire-and-forget and never throw: a missing log line must not
/// stop a doctor from seeing a record. Firestore holds writes made offline
/// in memory and sends them on reconnect; they are lost if the app is
/// closed first (persistence is off, see main.dart).
class AccessAuditService {
  AccessAuditService._();

  static final AccessAuditService instance = AccessAuditService._();

  static const String collection = 'access_logs';
  static const String actionPatientView = 'patient.view';
  static const String actionFileDownload = 'file.download';

  /// Re-opening the same record within this window is not logged again, so
  /// screens can call [patientViewed] from build without flooding the log.
  static const Duration dedupeWindow = Duration(minutes: 5);

  final Map<String, DateTime> _lastLogged = {};

  void patientViewed(String patientId) {
    if (patientId.isEmpty) return;
    _log(actionPatientView, patientId: patientId);
  }

  void fileDownloaded(String storagePath) {
    _log(
      actionFileDownload,
      patientId: patientIdFromPath(storagePath),
      target: storagePath,
    );
  }

  /// The patient id in a `doctors/{doctor}/patients/{patient}/...` path, or
  /// null for clinic-level files.
  @visibleForTesting
  static String? patientIdFromPath(String storagePath) {
    final parts = storagePath.split('/');
    final i = parts.indexOf('patients');
    if (i < 0 || i + 1 >= parts.length || parts[i + 1].isEmpty) return null;
    return parts[i + 1];
  }

  /// Whether an entry for [key] should be written at [now]; records it if so.
  @visibleForTesting
  bool shouldLog(String key, DateTime now) {
    final last = _lastLogged[key];
    if (last != null && now.difference(last) < dedupeWindow) return false;
    _lastLogged[key] = now;
    return true;
  }

  void _log(String action, {String? patientId, String? target}) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final clinicId = ClinicSession.instance.tenantId;
      if (uid == null || clinicId == null) return;
      if (!shouldLog('$uid|$action|${target ?? patientId}', DateTime.now())) {
        return;
      }
      FirebaseFirestore.instance
          .collection(collection)
          .add({
            'doctorId': clinicId,
            'actorUid': uid,
            'action': action,
            'patientId': patientId,
            'target': target,
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
            'at': FieldValue.serverTimestamp(),
          })
          .then<void>(
            (_) {},
            onError: (Object e) =>
                debugPrint('AccessAuditService: log write failed: $e'),
          );
    } catch (e) {
      // Firebase not initialised (tests, demo without sign-in).
      debugPrint('AccessAuditService: skipped: $e');
    }
  }
}
