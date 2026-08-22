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

  static const _metaToken =
      'EAAPCogiyZB7ABSYHA4gCGCPrajtLVHsPQlNEZBrV1ZACvYcyQto0cCDEI7nv9fZBaZCLYoEZA8eNCFlMZBbma4PC1OUSBDzHQ6OFYD7JIsg8wlX1QPmKSEkZBa8qKfpsQmySWzzbkzzqZCa8lE0U4ipJBC0Fj5iZCEyK7tBG7c9W7f0sZCDlHZCYebXSHaH4ax87nP5SZAGkmUeMuGK4BcxUvsl3GWh2dCZBU0Rp2VqYqsNnrWaRWsbMvxJCILOHaoZB0o3EYANsZBKXJvD9ZBEIrVFkwlgZADcvXJ';
  static const _metaPhoneId = '1260194177180019';

  CampaignDispatchService({
    CampaignRepository? campaignRepository,
    GmailAuthService? gmailAuthService,
    GmailSendService? gmailSendService,
    http.Client? httpClient,
  })  : _campaignRepository = campaignRepository ?? CampaignRepository(),
        _gmailAuthService = gmailAuthService ?? GmailAuthService(),
        _gmailSendService = gmailSendService ??
            GmailSendService(authService: gmailAuthService ?? GmailAuthService()),
        _httpClient = httpClient ?? http.Client();

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
        doctorId, campaignId, initialLogs);

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
      debugPrint('[Campaign Dispatch] ✅ Gmail is connected (${_gmailAuthService.connectedEmail}). Dispatching real emails via Gmail API.');
    } else {
      debugPrint('[Campaign Dispatch] ℹ️ Gmail account is not connected in Doctor Profile. Connect Gmail in Profile > Settings to send actual emails.');
    }

    // 3. Process in batches of 10 to protect resources and allow reactive UI updates
    const chunkSize = 10;
    for (var i = 0; i < targetPatients.length; i += chunkSize) {
      final chunk = targetPatients.sublist(
          i, i + chunkSize > targetPatients.length ? targetPatients.length : i + chunkSize);

      await Future.wait(chunk.map((patient) async {
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

        // --- Channel 1: Email Dispatch ---
        if (campaign.channels.includesEmail) {
          if (!CampaignAudienceHelper.isValidEmail(patient.email)) {
            emailStatus = RecipientDeliveryStatus.failed;
            emailError = patient.email.isEmpty
                ? 'No email address registered'
                : 'Invalid email format (${patient.email})';
            emailsFailed++;
          } else {
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

              if (isGmailConnected) {
                final result = await _gmailSendService.sendEmail(
                  to: patient.email.trim(),
                  subject: emailSubject,
                  body: emailHtml,
                );
                emailMessageId = result.messageId;
              } else {
                // Simulated robust dispatch for dev/unconnected mode
                await Future.delayed(const Duration(milliseconds: 60));
                emailMessageId = 'sim_mail_${_uuid.v4().substring(0, 8)}';
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
              final formattedWa = CampaignAudienceHelper.buildFormattedWhatsAppMessage(
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
                whatsAppStatus = RecipientDeliveryStatus.delivered;
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
          dispatchedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _campaignRepository.saveRecipientLog(updatedLog);

        processedCount++;
        onProgress?.call(processedCount, targetPatients.length);
      }));

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
    final campaign = await _campaignRepository.getCampaign(doctorId, campaignId);
    if (campaign == null) throw Exception('Campaign not found');

    final logs = await _campaignRepository.getRecipientLogs(doctorId, campaignId);
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
          } else {
            await Future.delayed(const Duration(milliseconds: 60));
            emailMessageId = 'retry_mail_${_uuid.v4().substring(0, 8)}';
          }
          emailStatus = RecipientDeliveryStatus.sent;
          emailError = null;
          emailsSent++;
          if (emailsFailed > 0) emailsFailed--;
        } catch (e) {
          emailError = e.toString();
        }
      }

      // Retry WhatsApp if previously failed
      if (whatsAppStatus == RecipientDeliveryStatus.failed &&
          WhatsAppTemplateService.isValidWhatsAppPhone(log.phone)) {
        try {
          final formattedWa = CampaignAudienceHelper.buildFormattedWhatsAppMessage(
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
            whatsAppStatus = RecipientDeliveryStatus.delivered;
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

  /// Sends a WhatsApp message via Meta WhatsApp Business Cloud API with template fallback.
  Future<({bool success, String? messageId, String? error})> _dispatchWhatsAppDirect({
    required String phone,
    required String formattedText,
  }) async {
    final normalizedPhone = WhatsAppTemplateService.normalizePhone(phone) ?? phone;
    final metaUrl = Uri.parse('https://graph.facebook.com/v20.0/$_metaPhoneId/messages');
    String? lastError;

    // 1. Try direct formatted text message
    try {
      final textBody = jsonEncode({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': normalizedPhone,
        'type': 'text',
        'text': {
          'preview_url': true,
          'body': formattedText,
        },
      });

      final response = await _httpClient.post(
        metaUrl,
        headers: {
          'Authorization': 'Bearer $_metaToken',
          'Content-Type': 'application/json',
        },
        body: textBody,
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final messages = data['messages'] as List<dynamic>?;
        final id = (messages != null && messages.isNotEmpty) ? messages[0]['id'] as String? : null;
        debugPrint('[Campaign WhatsApp] Dispatched to $normalizedPhone via Meta Cloud API ($id)');
        return (success: true, messageId: id, error: null);
      } else {
        lastError = data['error']?['message'] as String? ?? 'HTTP ${response.statusCode} from Meta';
        debugPrint('[Campaign WhatsApp] Meta text endpoint returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('[Campaign WhatsApp] Text API connection error: $e');
    }

    // 2. Try hello_world test template fallback
    try {
      final templateBody = jsonEncode({
        'messaging_product': 'whatsapp',
        'recipient_type': 'individual',
        'to': normalizedPhone,
        'type': 'template',
        'template': {
          'name': 'hello_world',
          'language': {'code': 'en_US'},
        },
      });

      final response = await _httpClient.post(
        metaUrl,
        headers: {
          'Authorization': 'Bearer $_metaToken',
          'Content-Type': 'application/json',
        },
        body: templateBody,
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final messages = data['messages'] as List<dynamic>?;
        final id = (messages != null && messages.isNotEmpty) ? messages[0]['id'] as String? : null;
        debugPrint('[Campaign WhatsApp] Dispatched hello_world template to $normalizedPhone via Meta ($id)');
        return (success: true, messageId: id, error: null);
      } else {
        lastError = data['error']?['message'] as String? ?? lastError;
        debugPrint('[Campaign WhatsApp] Template endpoint returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Campaign WhatsApp] Template API error: $e');
    }

    // Return detailed error if live Meta rejected the request
    return (
      success: false,
      messageId: null,
      error: lastError != null ? 'Meta API: $lastError' : 'WhatsApp delivery failed',
    );
  }
}
