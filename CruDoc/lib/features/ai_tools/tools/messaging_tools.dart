import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_enums.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_model.dart';
import 'package:doctor_management_app/features/campaigns/data/providers/campaign_providers.dart';
import 'package:doctor_management_app/features/messaging/data/providers/whatsapp_providers.dart';
import 'package:doctor_management_app/features/messaging/data/repo/messaging_repository.dart';
import 'package:doctor_management_app/features/messaging/data/services/email_log_local_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';

import '../core/ai_tool.dart';

const _maxItems = 15;

String? _str(Map<String, Object?> a, String k) {
  final v = a[k];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

List<AiTool> messagingTools() => [
  AiTool(
    name: 'get_message_status',
    description:
        'Check whether the WhatsApp reminder and the email confirmation for '
        'an appointment were sent, delivered, read or failed.',
    group: AiToolGroup.messaging,
    risk: AiToolRisk.read,
    permission: ClinicPermission.messaging,
    params: const {'visitId': AiParam.string('Appointment (visit) id.')},
    run: (ctx, args) async {
      final id = _str(args, 'visitId');
      if (id == null) return AiToolResult.error('A visit id is needed.');
      final wa = await ctx.read(whatsappRepositoryProvider).getLogForVisit(id);
      final doctorId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final mail = doctorId.isEmpty
          ? null
          : await EmailLogLocalService().getLogByVisitId(id, doctorId);
      if (wa == null && mail == null) {
        return AiToolResult.ok({
          'visitId': id,
          'whatsapp': 'none',
          'email': 'none',
        }, summary: 'No message was recorded for this appointment');
      }
      return AiToolResult.ok({
        'visitId': id,
        'whatsapp': wa == null
            ? 'none'
            : {
                'status': wa.status.name,
                'attempts': wa.attemptCount,
                if (wa.failureReason != null) 'reason': wa.failureReason,
                'at': (wa.sentAt ?? wa.attemptedAt).toIso8601String(),
              },
        'email': mail == null
            ? 'none'
            : {
                'status': mail.status.name,
                if (mail.failureReason != null) 'reason': mail.failureReason,
                'at': (mail.sentAt ?? mail.attemptedAt).toIso8601String(),
              },
      });
    },
  ),
  AiTool(
    name: 'list_failed_reminders',
    description: 'List WhatsApp reminders that failed to send, newest first.',
    group: AiToolGroup.messaging,
    risk: AiToolRisk.read,
    permission: ClinicPermission.messaging,
    run: (ctx, args) async {
      final all = await ctx.read(failedRemindersProvider.future);
      return AiToolResult.ok({
        'count': all.length,
        'failed': [
          for (final l in all.take(_maxItems))
            {
              'visitId': l.visitId,
              'patientId': l.patientId,
              'patientName': l.recipientName,
              if (l.failureReason != null) 'reason': l.failureReason,
              'attempts': l.attemptCount,
              'at': l.attemptedAt.toIso8601String(),
            },
        ],
        if (all.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'send_reminder',
    description:
        'Message a patient about an appointment. Email sends the appointment '
        'confirmation through the clinic Gmail (needs visitId). WhatsApp opens '
        'WhatsApp with the message ready and the user presses send (the app '
        'has no silent WhatsApp send from the device). Needs ids from '
        'find_patient and list_appointments.',
    group: AiToolGroup.messaging,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.messaging,
    params: {
      'patientId': const AiParam.string('Patient id.'),
      'patientName': const AiParam.string(
        'Patient name, shown on the confirm card.',
        required: false,
      ),
      'channel': AiParam.enumOf(const ['whatsapp', 'email'], 'How to send.'),
      'template': AiParam.enumOf(const [
        'appointment_confirmation',
        'appointment_reminder',
        'general',
      ], 'Message. appointment_* need visitId; general is WhatsApp only.'),
      'visitId': const AiParam.string(
        'Appointment id the message is about.',
        required: false,
      ),
    },
    confirmText: (a) {
      final ch = a['channel'] == 'email' ? 'email' : 'WhatsApp';
      final name = a['patientName'];
      final who = name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'the patient';
      return 'Send $ch reminder to $who?';
    },
    run: (ctx, args) async {
      final pid = _str(args, 'patientId');
      final channel = _str(args, 'channel');
      final template = _str(args, 'template') ?? 'appointment_reminder';
      final visitId = _str(args, 'visitId');
      if (pid == null || channel == null) {
        return AiToolResult.error('A patient id and a channel are needed.');
      }
      final patient = await ctx.read(patientRepositoryProvider).getPatient(pid);
      if (patient == null) {
        return AiToolResult.error('No patient with that id.');
      }
      final visit = visitId == null
          ? null
          : await ctx.read(visitRepositoryProvider).getVisit(visitId);
      if (template != 'general' && visit == null) {
        return AiToolResult.error(
          visitId == null
              ? 'That message needs the appointment id (visitId).'
              : 'No appointment with that id.',
        );
      }
      if (visit != null && visit.patientId != pid) {
        return AiToolResult.error('That appointment belongs to someone else.');
      }
      final who = patient.fullName.trim();

      if (channel == 'email') {
        if (visit == null || template != 'appointment_confirmation') {
          return AiToolResult.error(
            'Email only sends the appointment confirmation. Use template '
            'appointment_confirmation with a visitId.',
          );
        }
        if (patient.email.trim().isEmpty) {
          return AiToolResult.error('$who has no email address.');
        }
        final ok = await MessagingRepository().sendAppointmentConfirmation(
          visit: visit,
        );
        return ok
            ? AiToolResult.ok({
                'sent': true,
                'channel': 'email',
              }, summary: 'Emailed $who')
            : AiToolResult.error(
                'The email did not go. Gmail may not be connected.',
              );
      }

      // WhatsApp: open the chat with the text ready; the person presses send.
      final clinicName = ctx.read(activeClinicProvider).value?.name;
      final members = ctx.read(clinicMembersProvider).value ?? const [];
      var doctor = '';
      for (final m in members) {
        if (visit != null && m.uid == visit.doctorId) doctor = m.name;
      }
      final first = who.split(RegExp(r'\s+')).first;
      final String message;
      if (template == 'appointment_confirmation' && visit != null) {
        message = WhatsAppTemplateService.buildConfirmationMessage(
          visit: visit,
          patient: patient,
          doctorName: doctor,
          clinicName: clinicName,
        );
      } else if (template == 'appointment_reminder' && visit != null) {
        message = WhatsAppTemplateService.buildReminderMessage(
          visit: visit,
          patient: patient,
          doctorName: doctor,
          clinicName: clinicName,
        );
      } else {
        message =
            'Hello $first, a friendly reminder from '
            '${clinicName ?? 'the clinic'}. Thank you.';
      }
      final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
        rawPhone: patient.phone,
        message: message,
      );
      if (uri == null) {
        return AiToolResult.error('$who has no valid phone number.');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? AiToolResult.ok({
              'opened': true,
              'channel': 'whatsapp',
              'sent': false,
            }, summary: 'WhatsApp is open for $who. Press send.')
          : AiToolResult.error('Could not open WhatsApp.');
    },
  ),
  AiTool(
    name: 'list_campaigns',
    description: 'List the clinic message campaigns, newest first.',
    group: AiToolGroup.messaging,
    risk: AiToolRisk.read,
    permission: ClinicPermission.messaging,
    run: (ctx, args) async {
      final list = await ctx
          .read(campaignRepositoryProvider)
          .watchDoctorCampaigns()
          .first;
      return AiToolResult.ok({
        'count': list.length,
        'campaigns': [
          for (final c in list.take(_maxItems))
            {
              'id': c.id,
              'title': c.title,
              'status': c.status.name,
              'channel': c.channels.name,
              'audience': c.audienceType.name,
              'recipients': c.totalRecipients,
              'sent': c.totalSent,
              'failed': c.totalFailed,
              'created': c.createdAt.toIso8601String(),
            },
        ],
        if (list.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'draft_campaign',
    description:
        'Save a message campaign as a DRAFT only. It is never sent; the user '
        'reviews and sends it from the Campaigns screen.',
    group: AiToolGroup.messaging,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.messaging,
    params: {
      'name': const AiParam.string('Campaign title.'),
      'channel': AiParam.enumOf([
        for (final c in CampaignChannel.values) c.name,
      ], 'email, whatsapp or both.'),
      'audience': AiParam.enumOf([
        for (final a in AudienceType.values) a.name,
      ], 'Who gets it (all = every active patient).'),
      'condition': const AiParam.string(
        'Medical condition, when audience is byDiagnosis.',
        required: false,
      ),
      'gender': const AiParam.string(
        'Gender, when audience is byGender.',
        required: false,
      ),
      'minAge': const AiParam.integer(
        'When audience is byAgeGroup.',
        required: false,
      ),
      'maxAge': const AiParam.integer(
        'When audience is byAgeGroup.',
        required: false,
      ),
      'patientIds': const AiParam.list(
        AiParam.string('Patient id.'),
        'When audience is customSelection.',
        required: false,
      ),
      'message': const AiParam.string('The message text.'),
    },
    confirmText: (a) => 'Save draft campaign "${a['name'] ?? ''}" (not sent)?',
    run: (ctx, args) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final name = _str(args, 'name');
      final message = _str(args, 'message');
      if (uid == null) return AiToolResult.error('Sign in first.');
      if (name == null || message == null) {
        return AiToolResult.error('A name and a message are needed.');
      }
      final audience = AudienceType.fromString(_str(args, 'audience'));
      final ids = [
        for (final p in (args['patientIds'] as List?) ?? const [])
          if (p is String && p.isNotEmpty) p,
      ];
      if (audience == AudienceType.customSelection && ids.isEmpty) {
        return AiToolResult.error('Give the patient ids for that audience.');
      }
      final condition = _str(args, 'condition');
      final gender = _str(args, 'gender');
      final filters = <String, dynamic>{
        if (audience == AudienceType.byDiagnosis && condition != null)
          'condition': condition,
        if (audience == AudienceType.byGender && gender != null)
          'gender': gender,
        if (audience == AudienceType.byAgeGroup && args['minAge'] is num)
          'minAge': (args['minAge'] as num).toInt(),
        if (audience == AudienceType.byAgeGroup && args['maxAge'] is num)
          'maxAge': (args['maxAge'] as num).toInt(),
      };
      final now = DateTime.now();
      final campaign = CampaignModel(
        id: 'camp_${now.microsecondsSinceEpoch}',
        doctorId: uid,
        title: name,
        message: message,
        channels: CampaignChannel.fromString(_str(args, 'channel')),
        audienceType: audience,
        targetFilters: filters,
        selectedPatientIds: ids,
        status: CampaignStatus.draft,
        createdAt: now,
        updatedAt: now,
      );
      await ctx.read(campaignRepositoryProvider).createCampaign(campaign);
      return AiToolResult.ok(
        {'id': campaign.id, 'status': 'draft', 'sent': false},
        summary: 'Saved draft "$name". Open Campaigns to review and send.',
      );
    },
  ),
];
