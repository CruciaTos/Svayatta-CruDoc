import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/messaging/data/models/email_log_entry.dart';
import 'package:doctor_management_app/features/messaging/data/services/appointment_email_template.dart';
import 'package:doctor_management_app/features/messaging/data/services/email_log_local_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_send_service.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';

/// Repository that orchestrates email dispatching, audit logging, and appointment email triggers.
///
/// Ensures:
/// - Asynchronous, non-blocking execution: appointment creation in VisitRepository is never
///   blocked or aborted by email sending failures.
/// - Multi-tenant isolation: every email operation is scoped to the signed-in doctor's UID.
/// - Idempotency & duplicate prevention: prevents multiple duplicate emails for the same visit.
/// - Safe error handling: failures are recorded in the audit log without exposing sensitive tokens.
class MessagingRepository {
  MessagingRepository({
    GmailAuthService? authService,
    GmailSendService? sendService,
    EmailLogLocalService? logLocalService,
    PatientRepository? patientRepository,
    FirebaseAuth? auth,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _authService = authService ?? GmailAuthService(),
        _logLocalService = logLocalService ?? EmailLogLocalService(),
        _patientRepository = patientRepository ?? PatientRepository() {
    _sendService = sendService ?? GmailSendService(authService: _authService);
  }

  final FirebaseAuth _auth;
  final GmailAuthService _authService;
  late final GmailSendService _sendService;
  final EmailLogLocalService _logLocalService;
  final PatientRepository _patientRepository;

  String get _currentDoctorId {
    final uid = _auth.currentUser?.uid;
    return (uid != null && uid.isNotEmpty) ? uid : 'anonymous';
  }

  /// Sends an automated appointment confirmation email to the patient.
  ///
  /// This method is deliberately safe and non-throwing so callers (e.g. [VisitRepository])
  /// can fire-and-forget without wrapping in try-catch.
  Future<bool> sendAppointmentConfirmation({
    required Visit visit,
  }) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return false;

    // 1. Verify doctor has a connected Gmail account
    if (!_authService.isConnected) {
      // Attempt silent restore before giving up
      final restored = await _authService.restoreSession();
      if (!restored || !_authService.isConnected) {
        return false;
      }
    }

    final senderEmail = _authService.connectedEmail;
    if (senderEmail == null || senderEmail.isEmpty) return false;

    try {
      // 2. Fetch patient details to retrieve email and full name
      final patient = await _patientRepository.getPatient(visit.patientId);
      if (patient == null) {
        debugPrint('[Gmail Messaging] Patient lookup returned null for patientId: ${visit.patientId}');
        return false;
      }

      final recipientEmail = patient.email.trim();
      if (recipientEmail.isEmpty || !recipientEmail.contains('@')) {
        debugPrint('[Gmail Messaging] Skipping email: Patient "${patient.fullName}" (id: ${patient.id}) has no registered email address on profile.');
        return false;
      }

      debugPrint('[Gmail Messaging] Preparing confirmation email for patient "${patient.fullName}" -> $recipientEmail');

      // 3. Prevent duplicate sends for the same visit
      final existingLog = await _logLocalService.getLogByVisitId(visit.id, doctorId);
      if (existingLog != null) {
        if (existingLog.isSent) {
          debugPrint('[Gmail Messaging] Email already sent for visit ${visit.id}. Skipping duplicate.');
          return true;
        }
        if (existingLog.isPending &&
            DateTime.now().difference(existingLog.attemptedAt).inMinutes < 2) {
          debugPrint('[Gmail Messaging] Email is currently in-flight for visit ${visit.id}. Skipping.');
          return true;
        }
      }

      // 4. Retrieve doctor profile details for formatting
      final user = _auth.currentUser;
      Map<String, dynamic>? profileData;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(doctorId)
            .get();
        if (doc.exists) profileData = doc.data();
      } catch (_) {}

      final doctorName = DoctorProfileHelper.formatDoctorName(user, profileData);
      final specialty = DoctorProfileHelper.formatSpecialty(profileData, user);

      // 5. Generate plain-text confirmation template
      final content = AppointmentEmailTemplate.buildConfirmation(
        visit: visit,
        patient: patient,
        doctorName: doctorName,
        specialty: specialty,
      );

      // 6. Create audit log entry with status 'pending'
      final logId = const Uuid().v4();
      final now = DateTime.now();
      final pendingEntry = EmailLogEntry(
        id: logId,
        doctorId: doctorId,
        patientId: patient.id,
        visitId: visit.id,
        recipientEmail: recipientEmail,
        recipientName: patient.fullName,
        subject: content.subject,
        status: EmailLogStatus.pending,
        senderEmail: senderEmail,
        attemptedAt: now,
        createdAt: now,
      );

      await _logLocalService.insertLog(pendingEntry);

      // 7. Dispatch email via Gmail REST API
      try {
        final result = await _sendService.sendEmail(
          to: recipientEmail,
          subject: content.subject,
          body: content.body,
          fromEmail: senderEmail,
        );

        // 8. Update log status to 'sent'
        await _logLocalService.updateLogStatus(
          logId,
          EmailLogStatus.sent,
          gmailMessageId: result.messageId,
          gmailThreadId: result.threadId,
          sentAt: DateTime.now(),
        );

        debugPrint('[Gmail Messaging] Successfully sent confirmation email to $recipientEmail (Message ID: ${result.messageId})');
        return true;
      } on GmailException catch (e) {
        debugPrint('[Gmail Messaging] Gmail API error sending to $recipientEmail: $e');
        await _logLocalService.updateLogStatus(
          logId,
          EmailLogStatus.failed,
          failureReason: e.runtimeType.toString(),
        );
        return false;
      } catch (e) {
        debugPrint('[Gmail Messaging] Unexpected error sending to $recipientEmail: $e');
        await _logLocalService.updateLogStatus(
          logId,
          EmailLogStatus.failed,
          failureReason: 'unexpected_error',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[Gmail Messaging] Error in sendAppointmentConfirmation: $e');
      return false;
    }
  }

  /// Retrieves recent email logs for the current doctor.
  Future<List<EmailLogEntry>> getRecentLogs({int limit = 50}) async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return [];
    return _logLocalService.getLogsForDoctor(doctorId, limit: limit);
  }

  /// Reconciles any abandoned pending logs after an application crash.
  Future<void> reconcilePendingLogs() async {
    final doctorId = _currentDoctorId;
    if (doctorId == 'anonymous') return;

    try {
      final pendingLogs = await _logLocalService.getPendingLogs(doctorId);
      final now = DateTime.now();

      for (final log in pendingLogs) {
        if (now.difference(log.attemptedAt).inMinutes >= 5) {
          if (log.gmailMessageId != null && log.gmailMessageId!.isNotEmpty) {
            await _logLocalService.updateLogStatus(
              log.id,
              EmailLogStatus.sent,
              sentAt: log.attemptedAt,
            );
          } else {
            await _logLocalService.updateLogStatus(
              log.id,
              EmailLogStatus.failed,
              failureReason: 'interrupted_or_timeout',
            );
          }
        }
      }
    } catch (_) {}
  }
}
