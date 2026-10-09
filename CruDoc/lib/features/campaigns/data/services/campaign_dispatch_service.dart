import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_send_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import '../models/campaign_model.dart';
import '../models/campaign_recipient_log.dart';
import '../models/campaign_enums.dart';
import '../repo/campaign_repository.dart';
import 'campaign_audience_helper.dart';

/// Service orchestrating asynchronous dual-channel campaign dispatching,
/// batch processing, partial failure resilience, and idempotency protection.
class CampaignDispatchService {
  final CampaignRepository _campaignRepository;
  final GmailAuthService _gmailAuthService;
  final GmailSendService _gmailSendService;
  final http.Client _httpClient;

  /// Whether the debug delivery simulator may stand in for a real provider.
  /// Defaults to `!kReleaseMode`, so release builds never fake a delivery.
  /// Injectable so tests can exercise the production (fail-honestly) path.
  final bool allowSimulation;

  static const _devMetaToken = String.fromEnvironment(
    'WHATSAPP_DEV_TOKEN',
    defaultValue: '',
  );
  // No baked-in default: the developer escape hatch below is inert unless both
  // this and WHATSAPP_DEV_TOKEN are supplied via --dart-define.
  static const _metaPhoneId = String.fromEnvironment(
    'WHATSAPP_PHONE_NUMBER_ID',
    defaultValue: '',
  );

  static const _gmailNotConnectedError =
      'Email not sent — no Gmail account is connected. '
      'Connect Gmail in Profile > Settings, then retry.';
  static const _whatsAppNotConfiguredError =
      'WhatsApp campaigns are not available yet — CruDoc\'s shared number '
      'sends appointment reminders only. Campaigns are enabled once your '
      'clinic connects its own WhatsApp number. Use Email for now.';

  CampaignDispatchService({
    CampaignRepository? campaignRepository,
    GmailAuthService? gmailAuthService,
    GmailSendService? gmailSendService,
    http.Client? httpClient,
    bool? allowSimulation,
  }) : _campaignRepository = campaignRepository ?? CampaignRepository(),
       _gmailAuthService = gmailAuthService ?? GmailAuthService(),
       _gmailSendService =
           gmailSendService ??
           GmailSendService(
             authService: gmailAuthService ?? GmailAuthService(),
           ),
       _httpClient = httpClient ?? http.Client(),
       allowSimulation = allowSimulation ?? !kReleaseMode;

  static const _uuid = Uuid();

  /// Dispatches a campaign to the targeted patient cohort asynchronously.
  Future<CampaignModel> dispatchCampaign({
    required CampaignModel campaign,
    required List<Patient> targetPatients,
    String? clinicName,
    String? doctorName,
    void Function(int processed, int total)? onProgress,
  }) async {
    final doctorId = campaign.doctorId;
    final campaignId = campaign.id;

    // 1. Initial State: Set to processing
    var currentCampaign = campaign.copyWith(
      status: CampaignStatus.processing,
      totalRecipients: targetPatients.length,
      updatedAt: DateTime.now(),
    );
    await _campaignRepository.createCampaign(currentCampaign);

    if (targetPatients.isEmpty) {
      currentCampaign = currentCampaign.copyWith(
        status: CampaignStatus.completed,
        updatedAt: DateTime.now(),
      );
      await _campaignRepository.updateCampaign(currentCampaign);
      return currentCampaign;
    }

    // 2. Pre-generate Queued Recipient Logs
    final initialLogs = <CampaignRecipientLog>[];
    for (final patient in targetPatients) {
      final logId = 'rec_${campaignId}_${patient.id}';
      initialLogs.add(
        CampaignRecipientLog(
          id: logId,
          campaignId: campaignId,
          doctorId: doctorId,
          patientId: patient.id,
          patientName: patient.fullName,
          email: patient.email,
          phone: patient.phone,
          emailStatus: campaign.channels.includesEmail
              ? RecipientDeliveryStatus.queued
              : RecipientDeliveryStatus.skipped,
          whatsAppStatus: campaign.channels.includesWhatsApp
              ? RecipientDeliveryStatus.queued
              : RecipientDeliveryStatus.skipped,
          dispatchedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
    await _campaignRepository.saveRecipientLogsBatch(
      doctorId,
      campaignId,
      initialLogs,
    );

    int emailsSent = 0;
    int emailsFailed = 0;
    int whatsAppSent = 0;
    int whatsAppFailed = 0;
    int processedCount = 0;
    var isGmailConnected = _gmailAuthService.isConnected;
    if (!isGmailConnected) {
      isGmailConnected = await _gmailAuthService.restoreSession();
    }

    if (isGmailConnected) {
      debugPrint(
        '[Campaign Dispatch] ✅ Gmail is connected (${_gmailAuthService.connectedEmail}). Dispatching real emails via Gmail API.',
      );
    } else {
      debugPrint(
        '[Campaign Dispatch] ℹ️ Gmail account is not connected in Doctor Profile. Connect Gmail in Profile > Settings to send actual emails.',
      );
    }

    // 3. Process in batches of 10 to protect resources and allow reactive UI updates
    const chunkSize = 10;
    for (var i = 0; i < targetPatients.length; i += chunkSize) {
      final chunk = targetPatients.sublist(
        i,
        i + chunkSize > targetPatients.length
            ? targetPatients.length
            : i + chunkSize,
      );

      await Future.wait(
        chunk.map((patient) async {
          final logId = 'rec_${campaignId}_${patient.id}';
          var emailStatus = campaign.channels.includesEmail
              ? RecipientDeliveryStatus.queued
              : RecipientDeliveryStatus.skipped;
          var whatsAppStatus = campaign.channels.includesWhatsApp
              ? RecipientDeliveryStatus.queued
              : RecipientDeliveryStatus.skipped;
          String? emailMessageId;
          String? whatsAppMessageId;
          String? emailError;
          String? whatsAppError;
          var emailSimulated = false;
          var whatsAppSimulated = false;

          // --- Channel 1: Email Dispatch ---
          if (campaign.channels.includesEmail) {
            if (!CampaignAudienceHelper.isValidEmail(patient.email)) {
              emailStatus = RecipientDeliveryStatus.failed;
              emailError = patient.email.isEmpty
                  ? 'No email address registered'
                  : 'Invalid email format (${patient.email})';
              emailsFailed++;
            } else if (!isGmailConnected && !allowSimulation) {
              // Production: never fake a send. Record an actionable failure so
              // the doctor knows the email did not reach the patient.
              emailStatus = RecipientDeliveryStatus.failed;
              emailError = _gmailNotConnectedError;
              emailsFailed++;
            } else {
              try {
                final emailSubject = CampaignAudienceHelper.buildEmailSubject(
                  campaign.title,
                  clinicName: clinicName,
                );
                final emailHtml =
                    CampaignAudienceHelper.buildFormattedEmailHtml(
                      campaign.message,
                      title: campaign.title,
                      patient: patient,
                      category: campaign.category,
                      clinicName: clinicName,
                      doctorName: doctorName,
                      mediaUrl: campaign.mediaUrl,
                    );

                if (isGmailConnected) {
                  final result = await _gmailSendService.sendEmail(
                    to: patient.email.trim(),
                    subject: emailSubject,
                    body: emailHtml,
                  );
                  emailMessageId = result.messageId;
                } else {
                  // Debug only: simulate so the flow can be exercised without a
                  // connected Gmail account. Flagged so the UI never presents
                  // it as a real delivery.
                  await Future.delayed(const Duration(milliseconds: 60));
                  emailMessageId = 'sim_mail_${_uuid.v4().substring(0, 8)}';
                  emailSimulated = true;
                }

                emailStatus = RecipientDeliveryStatus.sent;
                emailsSent++;
              } catch (e) {
                debugPrint('Campaign Email Error for ${patient.email}: $e');
                emailStatus = RecipientDeliveryStatus.failed;
                emailError = e.toString().replaceAll('Exception: ', '');
                emailsFailed++;
              }
            }
          }

          // --- Channel 2: WhatsApp Dispatch ---
          if (campaign.channels.includesWhatsApp) {
            if (!WhatsAppTemplateService.isValidWhatsAppPhone(patient.phone)) {
              whatsAppStatus = RecipientDeliveryStatus.failed;
              whatsAppError = patient.phone.isEmpty
                  ? 'No phone number registered'
                  : 'Invalid phone number format (${patient.phone})';
              whatsAppFailed++;
            } else {
              try {
                final formattedWa =
                    CampaignAudienceHelper.buildFormattedWhatsAppMessage(
                      campaign.message,
                      title: campaign.title,
                      patient: patient,
                      category: campaign.category,
                      clinicName: clinicName,
                      doctorName: doctorName,
                      mediaUrl: campaign.mediaUrl,
                    );

                final res = await _dispatchWhatsAppDirect(
                  phone: patient.phone,
                  formattedText: formattedWa,
                );

                if (res.success) {
                  whatsAppMessageId = res.messageId;
                  whatsAppSimulated = res.simulated;
                  // A simulated message is not a confirmed delivery.
                  whatsAppStatus = res.simulated
                      ? RecipientDeliveryStatus.sent
                      : RecipientDeliveryStatus.delivered;
                  whatsAppSent++;
                } else {
                  whatsAppStatus = RecipientDeliveryStatus.failed;
                  whatsAppError = res.error ?? 'WhatsApp delivery error';
                  whatsAppFailed++;
                }
              } catch (e) {
                debugPrint('Campaign WhatsApp Error for ${patient.phone}: $e');
                whatsAppStatus = RecipientDeliveryStatus.failed;
                whatsAppError = e.toString().replaceAll('Exception: ', '');
                whatsAppFailed++;
              }
            }
          }

          // Save updated recipient log
          final updatedLog = CampaignRecipientLog(
            id: logId,
            campaignId: campaignId,
            doctorId: doctorId,
            patientId: patient.id,
            patientName: patient.fullName,
            email: patient.email,
            phone: patient.phone,
            emailStatus: emailStatus,
            whatsAppStatus: whatsAppStatus,
            emailMessageId: emailMessageId,
            whatsAppMessageId: whatsAppMessageId,
            emailError: emailError,
            whatsAppError: whatsAppError,
            emailSimulated: emailSimulated,
            whatsAppSimulated: whatsAppSimulated,
            dispatchedAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await _campaignRepository.saveRecipientLog(updatedLog);

          processedCount++;
          onProgress?.call(processedCount, targetPatients.length);
        }),
      );

      // Periodic batch aggregate update
      currentCampaign = currentCampaign.copyWith(
        emailsSent: emailsSent,
        emailsFailed: emailsFailed,
        whatsAppSent: whatsAppSent,
        whatsAppFailed: whatsAppFailed,
        updatedAt: DateTime.now(),
      );
      await _campaignRepository.createCampaign(currentCampaign);
    }

    // 4. Final Status Evaluation
    final totalSent = emailsSent + whatsAppSent;
    final totalFailed = emailsFailed + whatsAppFailed;
    CampaignStatus finalStatus;
    if (totalFailed == 0 && totalSent > 0) {
      finalStatus = CampaignStatus.completed;
    } else if (totalSent > 0 && totalFailed > 0) {
      finalStatus = CampaignStatus.partiallyFailed;
    } else if (totalSent == 0 && totalFailed > 0) {
      finalStatus = CampaignStatus.failed;
    } else {
      finalStatus = CampaignStatus.completed;
    }

    currentCampaign = currentCampaign.copyWith(
      status: finalStatus,
      emailsSent: emailsSent,
      emailsFailed: emailsFailed,
      whatsAppSent: whatsAppSent,
      whatsAppFailed: whatsAppFailed,
      updatedAt: DateTime.now(),
    );
    await _campaignRepository.createCampaign(currentCampaign);

    return currentCampaign;
  }

  /// Retries sending only to failed recipients/channels for an existing campaign.
  Future<CampaignModel> retryFailedRecipients({
    required String doctorId,
    required String campaignId,
    String? clinicName,
    String? doctorName,
    void Function(int processed, int total)? onProgress,
  }) async {
    final campaign = await _campaignRepository.getCampaign(
      doctorId,
      campaignId,
    );
    if (campaign == null) throw Exception('Campaign not found');

    final logs = await _campaignRepository.getRecipientLogs(
      doctorId,
      campaignId,
    );
    final failedLogs = logs.where((l) => l.hasFailed).toList();

    if (failedLogs.isEmpty) return campaign;

    var currentCampaign = campaign.copyWith(
      status: CampaignStatus.processing,
      updatedAt: DateTime.now(),
    );
    await _campaignRepository.updateCampaign(currentCampaign);

    int emailsSent = campaign.emailsSent;
    int emailsFailed = campaign.emailsFailed;
    int whatsAppSent = campaign.whatsAppSent;
    int whatsAppFailed = campaign.whatsAppFailed;
    int processedCount = 0;

    for (final log in failedLogs) {
      var emailStatus = log.emailStatus;
      var whatsAppStatus = log.whatsAppStatus;
      String? emailError = log.emailError;
      String? whatsAppError = log.whatsAppError;
      String? emailMessageId = log.emailMessageId;
      String? whatsAppMessageId = log.whatsAppMessageId;
      var emailSimulated = log.emailSimulated;
      var whatsAppSimulated = log.whatsAppSimulated;

      // Dummy Patient wrapper for interpolation
      final patient = Patient(
        id: log.patientId,
        firstName: log.patientName.split(' ').first,
        lastName: log.patientName.split(' ').length > 1
            ? log.patientName.split(' ').sublist(1).join(' ')
            : '',
        phone: log.phone,
        email: log.email,
        gender: '',
        dateOfBirth: DateTime.now(),
        diagnosis: const [],
        packageBalance: 0,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Retry Email if previously failed
      if (emailStatus == RecipientDeliveryStatus.failed &&
          CampaignAudienceHelper.isValidEmail(log.email)) {
        try {
          final emailSubject = CampaignAudienceHelper.buildEmailSubject(
            campaign.title,
            clinicName: clinicName,
          );
          final emailHtml = CampaignAudienceHelper.buildFormattedEmailHtml(
            campaign.message,
            title: campaign.title,
            patient: patient,
            category: campaign.category,
            clinicName: clinicName,
            doctorName: doctorName,
            mediaUrl: campaign.mediaUrl,
          );

          var isGmailConnected = _gmailAuthService.isConnected;
          if (!isGmailConnected) {
            isGmailConnected = await _gmailAuthService.restoreSession();
          }

          if (isGmailConnected) {
            final res = await _gmailSendService.sendEmail(
              to: log.email.trim(),
              subject: emailSubject,
              body: emailHtml,
            );
            emailMessageId = res.messageId;
            emailSimulated = false;
            emailStatus = RecipientDeliveryStatus.sent;
            emailError = null;
            emailsSent++;
            if (emailsFailed > 0) emailsFailed--;
          } else if (allowSimulation) {
            await Future.delayed(const Duration(milliseconds: 60));
            emailMessageId = 'retry_mail_${_uuid.v4().substring(0, 8)}';
            emailSimulated = true;
            emailStatus = RecipientDeliveryStatus.sent;
            emailError = null;
            emailsSent++;
            if (emailsFailed > 0) emailsFailed--;
          } else {
            // Production: keep it failed with an actionable reason.
            emailError = _gmailNotConnectedError;
          }
        } catch (e) {
          emailError = e.toString();
        }
      }

      // Retry WhatsApp if previously failed
      if (whatsAppStatus == RecipientDeliveryStatus.failed &&
          WhatsAppTemplateService.isValidWhatsAppPhone(log.phone)) {
        try {
          final formattedWa =
              CampaignAudienceHelper.buildFormattedWhatsAppMessage(
                campaign.message,
                title: campaign.title,
                patient: patient,
                category: campaign.category,
                clinicName: clinicName,
                doctorName: doctorName,
                mediaUrl: campaign.mediaUrl,
              );

          final res = await _dispatchWhatsAppDirect(
            phone: log.phone,
            formattedText: formattedWa,
          );

          if (res.success) {
            whatsAppMessageId = res.messageId;
            whatsAppSimulated = res.simulated;
            whatsAppStatus = res.simulated
                ? RecipientDeliveryStatus.sent
                : RecipientDeliveryStatus.delivered;
            whatsAppError = null;
            whatsAppSent++;
            if (whatsAppFailed > 0) whatsAppFailed--;
          } else {
            whatsAppError = res.error;
          }
        } catch (e) {
          whatsAppError = e.toString();
        }
      }

      final updatedLog = log.copyWith(
        emailStatus: emailStatus,
        whatsAppStatus: whatsAppStatus,
        emailMessageId: emailMessageId,
        whatsAppMessageId: whatsAppMessageId,
        emailError: emailError,
        whatsAppError: whatsAppError,
        emailSimulated: emailSimulated,
        whatsAppSimulated: whatsAppSimulated,
        updatedAt: DateTime.now(),
      );
      await _campaignRepository.saveRecipientLog(updatedLog);

      processedCount++;
      onProgress?.call(processedCount, failedLogs.length);
    }

    final totalSent = emailsSent + whatsAppSent;
    final totalFailed = emailsFailed + whatsAppFailed;
    CampaignStatus finalStatus;
    if (totalFailed == 0 && totalSent > 0) {
      finalStatus = CampaignStatus.completed;
    } else if (totalSent > 0 && totalFailed > 0) {
      finalStatus = CampaignStatus.partiallyFailed;
    } else {
      finalStatus = CampaignStatus.failed;
    }

    currentCampaign = currentCampaign.copyWith(
      status: finalStatus,
      emailsSent: emailsSent,
      emailsFailed: emailsFailed,
      whatsAppSent: whatsAppSent,
      whatsAppFailed: whatsAppFailed,
      updatedAt: DateTime.now(),
    );
    await _campaignRepository.updateCampaign(currentCampaign);

    return currentCampaign;
  }

  /// Attempts to send a campaign WhatsApp message.
  ///
  /// There is deliberately no production route here. CruDoc's WhatsApp number
  /// is shared across every clinic and is reminders-only; broadcasting
  /// marketing from it would risk Meta's quality rating for all clinics at
  /// once, so the campaign Cloud Function was removed on the backend (see
  /// handoff/whatsapp_shared_number.md §5, §8). Campaigns become available per
  /// clinic once a clinic connects its own number.
  ///
  /// The only real send below is a developer escape hatch gated on
  /// WHATSAPP_DEV_TOKEN (never set in production), used to exercise the flow
  /// against a test number. `simulated` is true only when the debug simulator
  /// produced the result; it is never true in release builds, where the
  /// absence of a route fails honestly instead.
  Future<({bool success, String? messageId, String? error, bool simulated})>
  _dispatchWhatsAppDirect({
    required String phone,
    required String formattedText,
  }) async {
    final normalizedPhone =
        WhatsAppTemplateService.normalizePhone(phone) ?? phone;

    // Developer-only direct Meta dispatch against a test number.
    if (_devMetaToken.isNotEmpty && _metaPhoneId.isNotEmpty) {
      final metaUrl = Uri.parse(
        'https://graph.facebook.com/v20.0/$_metaPhoneId/messages',
      );
      String? lastError;

      try {
        final textBody = jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type': 'individual',
          'to': normalizedPhone,
          'type': 'text',
          'text': {'preview_url': true, 'body': formattedText},
        });

        final response = await _httpClient
            .post(
              metaUrl,
              headers: {
                'Authorization': 'Bearer $_devMetaToken',
                'Content-Type': 'application/json',
              },
              body: textBody,
            )
            .timeout(const Duration(seconds: 12));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200) {
          final messages = data['messages'] as List<dynamic>?;
          final id = (messages != null && messages.isNotEmpty)
              ? messages[0]['id'] as String?
              : null;
          return (success: true, messageId: id, error: null, simulated: false);
        } else {
          lastError =
              data['error']?['message'] as String? ??
              'HTTP ${response.statusCode} from Meta';
        }
      } catch (e) {
        lastError = e.toString();
      }

      return (
        success: false,
        messageId: null,
        error: 'Meta API: $lastError',
        simulated: false,
      );
    }

    // No real delivery route available (the expected production state until a
    // clinic connects its own WhatsApp number). Never fake a delivery.
    if (!allowSimulation) {
      return (
        success: false,
        messageId: null,
        error: _whatsAppNotConfiguredError,
        simulated: false,
      );
    }

    // Debug only: simulate so the flow can be exercised without a live route.
    final simId = 'sim_wa_${_uuid.v4().substring(0, 8)}';
    debugPrint(
      '[Campaign WhatsApp] Simulated delivery to $normalizedPhone ($simId)',
    );
    return (success: true, messageId: simId, error: null, simulated: true);
  }
}
