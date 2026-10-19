import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_pdf.dart';
import 'package:doctor_management_app/features/messaging/data/models/generated_document.dart';
import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_send_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ─────────────────────────── Sending ───────────────────────────

/// "Dr. Smit Patil", without doubling a "Dr." the name already has.
String drName(String name) {
  final n = name.trim().isEmpty ? 'Doctor' : name.trim();
  return RegExp(r'^dr\.?\s', caseSensitive: false).hasMatch(n) ? n : 'Dr. $n';
}

/// Whether this device has a share sheet that can attach a file to an
/// app (WhatsApp, Gmail...). On a computer the letter is saved instead.
bool get _hasShareSheet => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Saves records without needing [ref] later: the dialog or list row a
/// flow starts from may be gone by the time a slow step (upload, sending,
/// the share sheet) finishes. Saving notifies
/// [DentalRecordsRepository.changes], which refreshes the lists.
Future<void> Function(DentalRecord) recordSaver(WidgetRef ref) {
  final repo = ref.read(dentalRecordsRepoProvider);
  final doctorId = ref.read(dentalDoctorIdProvider);
  return (r) => repo.save(doctorId, r);
}

/// Adds a history entry to a local referral and saves it.
Future<DentalReferral> _saveLocal(
  Future<void> Function(DentalRecord) save,
  DentalReferral referral, {
  required ReferralStatus status,
  required String note,
  String? shareId,
}) async {
  final record = referral.record.copyWith(
    data: {
      ...referral.record.data,
      'status': status.name,
      'shareId': ?shareId,
      'history': [
        ...referral.history.map((h) => h.toJson()),
        {
          'status': status.name,
          'at': DateTime.now().millisecondsSinceEpoch,
          'note': note,
        },
      ],
    },
  );
  await save(record);
  return DentalReferral.fromRecord(record);
}

/// Sends [referral] to [contact]'s CruDoc account: uploads its files, makes
/// the shared copy, and marks the local referral sent. Throws
/// [ReferralNetworkException] with a message to show.
Future<DentalReferral> sendReferralInCruDoc(
  WidgetRef ref, {
  required DentalReferral referral,
  required Patient patient,
  required ReferralContact contact,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    throw const ReferralNetworkException('Sign in again to continue.');
  }
  final save = recordSaver(ref);
  final clinicId = ref.read(dentalDoctorIdProvider);
  final api = ReferralNetworkApi.instance;
  final shareId = ReferralNetworkApi.newShareId();
  final names = await api.uploadAttachments(
    uid: uid,
    shareId: shareId,
    paths: referral.attachments,
  );
  await api.send(
    clinicId: clinicId,
    shareId: shareId,
    recipientUid: contact.crudocUid,
    referral: referral,
    patientName: patient.fullName.trim(),
    patientPhone: patient.phone,
    patientGender: patient.gender,
    patientAge: patient.age,
    attachmentNames: names,
  );
  return _saveLocal(
    save,
    referral,
    status: ReferralStatus.sent,
    note:
        'Sent to ${drName(contact.crudocName.isNotEmpty ? contact.crudocName : contact.name)} in CruDoc',
    shareId: shareId,
  );
}

/// Sends the referral letter by WhatsApp. On a phone the share sheet opens
/// with the letter attached; on a computer WhatsApp opens on the contact's
/// chat and the letter is saved to attach.
Future<void> sendReferralWhatsApp(
  BuildContext context,
  WidgetRef ref,
  DentalReferral referral,
  Patient patient,
) async {
  final contact = ref
      .read(referralContactsProvider)
      .where((cnt) => cnt.id == referral.contactId)
      .firstOrNull;
  final phone = contact?.phone ?? '';
  final save = recordSaver(ref);
  if (phone.isEmpty && !_hasShareSheet) {
    recToast(context, 'No phone number saved for ${referral.contactName}');
    return;
  }

  final pdfPath = await ReferralPdfService.saveLetterToFolder(
    referral: referral,
    patient: patient,
    ref: ref,
    isReply: referral.direction == ReferralDirection.inbound,
  );
  final message = referral.direction == ReferralDirection.out
      ? 'Hello ${drName(referral.contactName)}, referring patient ${patient.fullName} (${referral.reason}, Urgency: ${referral.urgency.label}). Referral letter attached.'
      : 'Hello ${drName(referral.contactName)}, here is the treatment summary for ${patient.fullName} (${referral.reason}). Summary letter attached.';

  if (_hasShareSheet) {
    await SharePlus.instance.share(
      ShareParams(text: message, files: [XFile(pdfPath)]),
    );
  } else {
    final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
      rawPhone: phone,
      message: message,
    );
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  if (referral.status == ReferralStatus.draft) {
    await _saveLocal(
      save,
      referral,
      status: ReferralStatus.sent,
      note: 'Sent via WhatsApp',
    );
  }
  if (context.mounted && !_hasShareSheet) _showSavedLetter(context, pdfPath);
}

/// Sends the referral letter by email: from the doctor's connected Gmail
/// when there is one, else through the phone's share sheet, else a new
/// email in the computer's mail app with the letter saved to attach.
Future<void> sendReferralEmail(
  BuildContext context,
  WidgetRef ref,
  DentalReferral referral,
  Patient patient,
  ReferralContact contact,
) async {
  final identity = ref.read(doctorIdentityProvider);
  final gmail = ref.read(gmailAuthServiceProvider);
  final save = recordSaver(ref);
  final pdfPath = await ReferralPdfService.saveLetterToFolder(
    referral: referral,
    patient: patient,
    ref: ref,
  );
  final subject = 'Referral: ${patient.fullName} - ${referral.reason}';
  final body =
      'Dear ${drName(contact.name)},\n\n'
      'I am referring ${patient.fullName} to you: ${referral.reason} '
      '(urgency: ${referral.urgency.label}). The referral letter is attached.\n\n'
      'Regards,\n${identity.fullName ?? ''}';

  var how = '';
  final connected =
      gmail.isConnected || (await gmail.restoreSession() && gmail.isConnected);
  if (connected && contact.email.isNotEmpty) {
    try {
      await GmailSendService(authService: gmail).sendEmail(
        to: contact.email,
        subject: subject,
        body: body,
        attachments: [
          GeneratedDocument(
            bytes: await File(pdfPath).readAsBytes(),
            fileName: p.basename(pdfPath),
          ),
        ],
      );
      how = 'Emailed from ${gmail.connectedEmail}';
    } catch (e) {
      if (context.mounted) recToast(context, 'Couldn\'t send the email: $e');
      return;
    }
  } else if (_hasShareSheet) {
    await SharePlus.instance.share(
      ShareParams(subject: subject, text: body, files: [XFile(pdfPath)]),
    );
    how = 'Sent by email';
  } else {
    if (contact.email.isEmpty) {
      if (context.mounted) {
        recToast(context, 'No email saved for ${contact.name}');
      }
      return;
    }
    await launchUrl(
      Uri(
        scheme: 'mailto',
        path: contact.email,
        query: _query({'subject': subject, 'body': body}),
      ),
    );
    how = 'Sent by email';
    if (context.mounted) _showSavedLetter(context, pdfPath, attach: true);
  }

  if (referral.status == ReferralStatus.draft) {
    await _saveLocal(save, referral, status: ReferralStatus.sent, note: how);
  }
  if (context.mounted && how.startsWith('Emailed')) recToast(context, how);
}

/// Asks [contact] to join CruDoc so referrals reach them in the app.
Future<void> inviteToCruDoc(
  BuildContext context,
  WidgetRef ref,
  ReferralContact contact,
) async {
  final me = ref.read(doctorIdentityProvider).fullName ?? 'A colleague';
  final message =
      'Hello ${drName(contact.name)}, I use CruDoc to send patient referrals. '
      'Join CruDoc and my referrals will reach you in the app, with the '
      'patient\'s details and files: $kPlayStoreLink\n\n- $me';
  if (_hasShareSheet) {
    await SharePlus.instance.share(ShareParams(text: message));
    return;
  }
  final wa = contact.phone.isEmpty
      ? null
      : WhatsAppTemplateService.buildDirectWhatsAppUrl(
          rawPhone: contact.phone,
          message: message,
        );
  if (wa != null) {
    await launchUrl(wa, mode: LaunchMode.externalApplication);
  } else if (contact.email.isNotEmpty) {
    await launchUrl(
      Uri(
        scheme: 'mailto',
        path: contact.email,
        query: _query({'subject': 'Join me on CruDoc', 'body': message}),
      ),
    );
  } else if (context.mounted) {
    recToast(context, 'Add a phone or email for ${contact.name} first');
  }
}

String _query(Map<String, String> params) => params.entries
    .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
    .join('&');

void _showSavedLetter(
  BuildContext context,
  String path, {
  bool attach = false,
}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        attach
            ? 'Attach the letter: ${p.basename(path)}'
            : 'Referral letter saved: ${p.basename(path)}',
      ),
      action: SnackBarAction(
        label: 'Show in folder',
        onPressed: () => launchUrl(Uri.file(p.dirname(path))),
      ),
    ),
  );
}

/// How to send a referral to a doctor who isn't on CruDoc: WhatsApp, email,
/// or an invitation to join.
class ReferralSendOptionsDialog extends ConsumerWidget {
  const ReferralSendOptionsDialog({
    super.key,
    required this.referral,
    required this.patient,
    required this.contact,
  });

  final DentalReferral referral;
  final Patient patient;
  final ReferralContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    Widget option({
      required CruIconData icon,
      required String title,
      required String detail,
      required Future<void> Function() onTap,
    }) => DentalListRow(
      semanticLabel: title,
      onTap: () async {
        await onTap();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.neutral),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.w600.tint(c.label)),
                Text(detail, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
        ],
      ),
    );

    return DentalPanelDialog(
      title: 'Send to ${drName(contact.name)}',
      subtitle: '${contact.name} isn\'t on CruDoc yet',
      leading: const CruIconTile(
        icon: CruIcons.arrowUpRight,
        tone: CruTileTone.neutral,
      ),
      width: 480,
      footer: CruButton(
        label: 'Later',
        kind: CruButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option(
            icon: CruIcons.whatsapp,
            title: 'WhatsApp',
            detail: _hasShareSheet
                ? 'Share the referral letter'
                : (contact.phone.isEmpty
                      ? 'Add a phone number to the contact first'
                      : 'Open their chat; the letter is saved to attach'),
            onTap: () => sendReferralWhatsApp(context, ref, referral, patient),
          ),
          option(
            icon: CruIcons.fileText,
            title: 'Email',
            detail: contact.email.isEmpty && !_hasShareSheet
                ? 'Add an email to the contact first'
                : 'Send the referral letter as a PDF',
            onTap: () =>
                sendReferralEmail(context, ref, referral, patient, contact),
          ),
          option(
            icon: CruIcons.userPlus,
            title: 'Invite to CruDoc',
            detail: 'Next time, referrals reach them in the app',
            onTap: () => inviteToCruDoc(context, ref, contact),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Received in CruDoc ───────────────────────────

/// Runs one step on a shared referral, with a toast either way.
Future<bool> runShareStep(
  BuildContext context,
  DentalReferral referral,
  ShareStep step, {
  String note = '',
  String reply = '',
  String? done,
}) async {
  try {
    await ReferralNetworkApi.instance.update(
      referral.shareId,
      step,
      note: note,
      reply: reply,
    );
    if (context.mounted && done != null) recToast(context, done);
    return true;
  } on ReferralNetworkException catch (e) {
    if (context.mounted) recToast(context, e.message);
    return false;
  }
}

/// Files a referral received in CruDoc against a patient of this clinic:
/// a new patient made from what the referring doctor sent, or one picked.
/// Returns the patient, or null when cancelled.
Future<Patient?> fileSharedReferral(
  BuildContext context,
  WidgetRef ref,
  DentalReferral referral,
) async {
  final share = referral.share;
  if (share == null) return null;
  final save = recordSaver(ref);
  final patients = ref.read(patientRepositoryProvider);
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add to your patients'),
      content: Text(
        'File this referral under a patient of your clinic, so you can book '
        'visits and keep notes. ${share.patientName} isn\'t added anywhere '
        'until you choose.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'pick'),
          child: const Text('Existing patient'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'new'),
          child: const Text('New patient'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;

  Patient? patient;
  if (choice == 'pick') {
    patient = await pickRadPatient(
      context,
      initialQuery: share.patientName,
      title: 'File the referral',
      subtitle: 'The referral shows on their record',
    );
  } else {
    final parts = share.patientName.trim().split(RegExp(r'\s+'));
    final now = DateTime.now();
    final draft = Patient(
      id: '',
      firstName: parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      phone: share.patientPhone,
      gender: share.patientGender,
      // Only the age was shared: the birthday is a placeholder.
      dateOfBirth: DateTime(now.year - (share.patientAge ?? 0)),
      diagnosis: const [],
      notes: 'Referred by ${drName(share.senderName)}',
      packageBalance: 0,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final id = await patients.createPatient(draft);
      patient = await patients.getPatient(id);
    } catch (e) {
      if (context.mounted) recToast(context, 'Couldn\'t add the patient: $e');
      return null;
    }
  }
  if (patient == null) return null;

  final record = DentalRecord.create(patient.id, RecKind.referral, {
    ...referral.record.data,
    'shareId': share.id,
  }, at: share.createdAt);
  await save(record);
  if (context.mounted) {
    recToast(context, 'Filed under ${patient.fullName}');
  }
  return patient;
}

/// Opens one file attached to a shared referral.
Future<void> openSharedFile(
  BuildContext context,
  String shareId,
  SharedFile file,
) async {
  try {
    final url = await ReferralNetworkApi.instance.attachmentUrl(
      shareId,
      file.name,
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } on ReferralNetworkException catch (e) {
    if (context.mounted) recToast(context, e.message);
  }
}

/// A referral sent or received in CruDoc: the patient, the clinical
/// details, the files, what happened so far, and the next steps.
class SharedReferralDialog extends ConsumerStatefulWidget {
  const SharedReferralDialog({super.key, required this.referral});

  final DentalReferral referral;

  @override
  ConsumerState<SharedReferralDialog> createState() =>
      _SharedReferralDialogState();
}

class _SharedReferralDialogState extends ConsumerState<SharedReferralDialog> {
  bool _busy = false;

  /// The referral as it is now (the other doctor may move it on while this
  /// is open); refreshed on every build.
  late DentalReferral _live = widget.referral;

  Future<void> _step(
    ShareStep step, {
    String note = '',
    String reply = '',
    String? done,
  }) async {
    setState(() => _busy = true);
    await runShareStep(
      context,
      _live,
      step,
      note: note,
      reply: reply,
      done: done,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reply({required bool complete}) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _ReplyDialog(
        initial: _live.reply,
        complete: complete,
        to: _live.share?.senderName ?? '',
      ),
    );
    if (text == null || text.isEmpty) return;
    await _step(
      complete ? ShareStep.complete : ShareStep.reply,
      reply: text,
      done: complete ? 'Referral completed' : 'Reply sent',
    );
  }

  Future<void> _decline() async {
    final why = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (why == null) return;
    await _step(ShareStep.decline, note: why, done: 'Referral declined');
  }

  Future<void> _withdraw() async {
    final ok = await confirmDental(
      context,
      title: 'Withdraw this referral?',
      body:
          '${drName(_live.share?.recipientName ?? _live.contactName)} will no '
          'longer see the patient\'s details or files.',
      action: 'Withdraw',
    );
    if (ok) await _step(ShareStep.withdraw, done: 'Referral withdrawn');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    _live =
        ref
            .watch(allReferralsProvider)
            .where((x) => x.shareId == widget.referral.shareId)
            .firstOrNull ??
        _live;
    final r = _live;
    final s = r.share;
    final incoming = r.direction == ReferralDirection.inbound;
    final other = s == null
        ? r.contactName
        : (incoming ? s.senderName : s.recipientName);
    final otherSpecialty = s == null
        ? r.contactSpecialty
        : (incoming ? s.senderSpecialty : s.recipientSpecialty);
    final status = r.status;
    final open = status.isOpen;
    final withdrawn = status == ReferralStatus.withdrawn;

    Widget field(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CruType.caption.w600.tint(c.label2)),
                const SizedBox(height: CruSpace.s2),
                Text(value, style: CruType.body.tint(c.label)),
              ],
            ),
          );

    final actions = <Widget>[
      if (incoming && s != null) ...[
        if (status == ReferralStatus.sent)
          CruButton(
            label: 'Accept',
            icon: CruIcons.check,
            onPressed: _busy
                ? null
                : () => _step(ShareStep.accept, done: 'Referral accepted'),
          ),
        if (status == ReferralStatus.sent ||
            status == ReferralStatus.acknowledged)
          CruButton(
            label: 'Patient seen',
            kind: CruButtonKind.secondary,
            onPressed: _busy
                ? null
                : () => _step(ShareStep.seen, done: 'Marked as seen'),
          ),
        if (open)
          CruButton(
            label: 'Complete & reply',
            kind: CruButtonKind.secondary,
            onPressed: _busy ? null : () => _reply(complete: true),
          ),
        if (status == ReferralStatus.completed)
          CruButton(
            label: 'Send another reply',
            kind: CruButtonKind.secondary,
            onPressed: _busy ? null : () => _reply(complete: false),
          ),
        if (status == ReferralStatus.sent ||
            status == ReferralStatus.acknowledged)
          CruButton(
            label: 'Decline',
            kind: CruButtonKind.secondary,
            onPressed: _busy ? null : _decline,
          ),
        if (r.isUnfiledShare && !withdrawn)
          CruButton(
            label: 'Add to my patients',
            icon: CruIcons.userPlus,
            kind: CruButtonKind.secondary,
            onPressed: _busy
                ? null
                : () async {
                    final filed = await fileSharedReferral(context, ref, r);
                    if (filed != null && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
          ),
      ],
      if (!incoming && open)
        CruButton(
          label: 'Withdraw',
          kind: CruButtonKind.secondary,
          onPressed: _busy ? null : _withdraw,
        ),
    ];

    return DentalPanelDialog(
      title: '${incoming ? 'From' : 'To'} ${drName(other)}',
      subtitle: [
        if (otherSpecialty.isNotEmpty) otherSpecialty,
        if (incoming && (s?.senderClinicName ?? '').isNotEmpty)
          s!.senderClinicName,
        'via CruDoc',
      ].join(' · '),
      leading: CruIconTile(
        icon: incoming ? CruIcons.chevronLeft : CruIcons.arrowUpRight,
        tone: CruTileTone.accent,
      ),
      width: 600,
      footer: Wrap(
        spacing: CruSpace.s8,
        runSpacing: CruSpace.s8,
        alignment: WrapAlignment.end,
        children: [
          ...actions,
          CruButton(
            label: 'Close',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              CruPill(
                text: status.label,
                background: status == ReferralStatus.completed
                    ? c.greenTint
                    : c.accentTint,
                foreground: status == ReferralStatus.completed
                    ? c.greenText
                    : c.accent,
              ),
              if (r.urgency != ReferralUrgency.routine)
                CruPill(
                  text: r.urgency.label,
                  background: r.urgency == ReferralUrgency.urgent
                      ? c.amberTint
                      : c.inset,
                  foreground: r.urgency == ReferralUrgency.urgent
                      ? c.amberText
                      : c.label2,
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          if (withdrawn)
            Text(
              incoming
                  ? '${drName(other)} withdrew this referral. The patient\'s '
                        'details are no longer shared.'
                  : 'You withdrew this referral.',
              style: CruType.body.tint(c.label2),
            )
          else ...[
            if (s != null && incoming)
              field(
                'Patient',
                [
                  s.patientName,
                  if (s.patientAge != null) '${s.patientAge}y',
                  if (s.patientGender.isNotEmpty) s.patientGender.toUpperCase(),
                  if (s.patientPhone.isNotEmpty) s.patientPhone,
                ].join(' · '),
              ),
            field('Reason for referral', r.reason),
            if (r.teeth.isNotEmpty) field('Teeth (FDI)', r.teeth.join(', ')),
            field('Clinical findings & history', r.findings),
            field('Question or requested procedure', r.question),
            if (s != null && s.attachments.isNotEmpty) ...[
              Text(
                'Files (${s.attachments.length})',
                style: CruType.caption.w600.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s4),
              for (final f in s.attachments)
                DentalListRow(
                  semanticLabel: 'Open ${f.name}',
                  onTap: () => openSharedFile(context, s.id, f),
                  child: Row(
                    children: [
                      CruIcon(CruIcons.fileText, size: 16, color: c.label2),
                      const SizedBox(width: CruSpace.s8),
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.note.tint(c.label),
                        ),
                      ),
                      Text(
                        '${(f.size / 1024).ceil()} KB',
                        style: CruType.caption.tabular.tint(c.label3),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: CruSpace.s12),
            ],
          ],
          field(incoming ? 'Your reply' : 'Their reply', r.reply),
          if (r.history.isNotEmpty) ...[
            Text('History', style: CruType.caption.w600.tint(c.label2)),
            const SizedBox(height: CruSpace.s4),
            for (final h in r.history)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s4),
                child: Text(
                  '${DentalFormat.date(h.at)} · '
                  '${ReferralStatus.fromName(h.status).label}'
                  '${h.note.isNotEmpty ? ' · ${h.note}' : ''}',
                  style: CruType.caption.tint(c.label2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({
    required this.initial,
    required this.complete,
    required this.to,
  });

  final String initial;
  final bool complete;
  final String to;

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CruFormDialog(
    title: widget.complete ? 'Complete the referral' : 'Reply',
    subtitle: 'Sent to ${drName(widget.to)} in CruDoc',
    width: 500,
    submitLabel: widget.complete ? 'Complete & send' : 'Send reply',
    onSubmit: () {
      if (_text.text.trim().isEmpty) {
        recToast(context, 'Write the treatment summary first');
        return;
      }
      Navigator.of(context).pop(_text.text.trim());
    },
    body: CruTextField(
      label: 'Treatment summary & clinical outcome',
      controller: _text,
      maxLines: 8,
      autofocus: true,
      hint: 'What was done, findings, follow-up advice...',
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CruFormDialog(
    title: 'Decline the referral',
    subtitle: 'The referring doctor sees your reason',
    width: 460,
    submitLabel: 'Decline',
    onSubmit: () => Navigator.of(context).pop(_text.text.trim()),
    body: CruTextField(
      label: 'Reason',
      controller: _text,
      maxLines: 3,
      optional: true,
      hint: 'e.g. Not available that week; please try Dr. ...',
    ),
  );
}

// ─────────────────────────── Finding doctors ───────────────────────────

/// Checks which saved contacts are doctors on CruDoc and stores the result
/// on each. Contacts linked by hand from the directory are left alone.
/// Returns how many contacts are on CruDoc, or null when CruDoc couldn't
/// be reached. Never throws.
Future<int?> refreshContactMatches(
  WidgetRef ref, {
  List<ReferralContact>? only,
}) async {
  final List<ReferralContact> contacts =
      only ?? ref.read(referralContactsProvider);
  if (contacts.isEmpty) return 0;
  final save = recordSaver(ref);
  final clinicId = ref.read(dentalDoctorIdProvider);
  final repo = ref.read(dentalRecordsRepoProvider);
  final Map<String, CruDocDoctor> matches;
  try {
    matches = await ReferralNetworkApi.instance.matchContacts(
      clinicId: clinicId,
      contacts: contacts,
    );
  } catch (_) {
    return null;
  }
  // Read now, not before: a contact saved a moment ago is included.
  final records = await repo.all(clinicId, RecKind.referralContact);
  for (final c in contacts) {
    final record = records.where((r) => r.id == c.id).firstOrNull;
    if (record == null) continue;
    final m = matches[c.id];
    final byHand = record.str('crudocSource') == 'directory';
    if (m == null && (byHand || !c.onCruDoc)) continue;
    if (m != null &&
        m.uid == c.crudocUid &&
        m.name == c.crudocName &&
        m.specialty == c.crudocSpecialty) {
      continue;
    }
    await save(
      record.copyWith(
        data: {
          ...record.data,
          'crudocUid': m?.uid ?? '',
          'crudocName': m?.name ?? '',
          'crudocSpecialty': m?.specialty ?? '',
          'crudocSource': m == null ? '' : 'match',
        },
      ),
    );
  }
  return contacts.where((c) => matches.containsKey(c.id) || c.onCruDoc).length;
}

/// Searches the doctors listed on CruDoc; pops the one picked.
class FindDoctorDialog extends ConsumerStatefulWidget {
  const FindDoctorDialog({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<FindDoctorDialog> createState() => _FindDoctorDialogState();
}

class _FindDoctorDialogState extends ConsumerState<FindDoctorDialog> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  List<CruDocDoctor> _results = const [];
  bool _searching = false;
  String _searched = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() => _searching = true);
    try {
      final found = await searchDirectory(
        q,
        selfUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (mounted) setState(() => _results = found);
    } catch (_) {
      if (mounted) recToast(context, 'Couldn\'t search right now. Try again.');
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _searched = q;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'Find a doctor on CruDoc',
      subtitle: 'Doctors who chose to be listed',
      leading: const CruIconTile(
        icon: CruIcons.search,
        tone: CruTileTone.neutral,
      ),
      width: 520,
      footer: CruButton(
        label: 'Close',
        kind: CruButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Name, @handle, specialty or city',
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            trailing: CruCapsuleButton(
              label: _searching ? 'Searching…' : 'Search',
              icon: CruIcons.search,
              onPressed: _searching ? null : _search,
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          if (_results.isEmpty && _searched.isNotEmpty && !_searching)
            Text(
              'No listed doctor matches "$_searched". If they use CruDoc, '
              'save their phone number: it is matched even if they aren\'t '
              'listed.',
              style: CruType.caption.tint(c.label2),
            ),
          for (final d in _results)
            DentalListRow(
              semanticLabel: d.name,
              onTap: () => Navigator.of(context).pop(d),
              child: Row(
                children: [
                  CruMonogram(name: d.name),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drName(d.name),
                          style: CruType.callout.w600.tint(c.label),
                        ),
                        Text(
                          [
                            if (d.handle.isNotEmpty) '@${d.handle}',
                            if (d.specialty.isNotEmpty) d.specialty,
                            if (d.city.isNotEmpty) d.city,
                          ].join(' · '),
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The signed-in doctor's listing in the CruDoc directory.
class DirectoryProfileDialog extends ConsumerStatefulWidget {
  const DirectoryProfileDialog({super.key});

  @override
  ConsumerState<DirectoryProfileDialog> createState() =>
      _DirectoryProfileDialogState();
}

class _DirectoryProfileDialogState
    extends ConsumerState<DirectoryProfileDialog> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _specialty = TextEditingController();
  final _city = TextEditingController();
  final _clinic = TextEditingController();
  bool _listed = true;
  bool _busy = false;
  bool _filled = false;
  String? _notice;

  @override
  void dispose() {
    for (final t in [_handle, _name, _specialty, _city, _clinic]) {
      t.dispose();
    }
    super.dispose();
  }

  void _fill(DirectoryCard? card) {
    if (_filled) return;
    _filled = true;
    final me = ref.read(doctorIdentityProvider);
    _listed = card?.listed ?? true;
    _handle.text = card?.handle ?? '';
    _name.text = card?.displayName.isNotEmpty == true
        ? card!.displayName
        : (me.fullName ?? '');
    _specialty.text = card?.specialty.isNotEmpty == true
        ? card!.specialty
        : (me.specialty ?? '');
    _city.text = card?.city ?? '';
    _clinic.text = card?.clinicName.isNotEmpty == true
        ? card!.clinicName
        : (me.clinicName ?? '');
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ReferralNetworkApi.instance.saveDirectoryProfile(
        listed: _listed,
        handle: _handle.text.trim(),
        displayName: _name.text.trim(),
        specialty: _specialty.text.trim(),
        city: _city.text.trim(),
        clinicName: _clinic.text.trim(),
      );
      if (mounted) {
        recToast(
          context,
          _listed ? 'You\'re listed on CruDoc' : 'Your listing is hidden',
        );
        Navigator.of(context).pop();
      }
    } on ReferralNetworkException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final card = ref.watch(myDirectoryCardProvider);
    if (card.hasValue) _fill(card.value);
    return CruFormDialog(
      title: 'Your CruDoc listing',
      subtitle: 'How other doctors find you to send referrals',
      width: 480,
      busy: _busy,
      notice: _notice,
      submitLabel: 'Save',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruPressable(
            onTap: () => setState(() => _listed = !_listed),
            builder: (_, _) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'List me in the directory',
                        style: CruType.row.tint(c.label),
                      ),
                      Text(
                        'Any doctor on CruDoc can find you by name, handle, '
                        'specialty or city. Doctors who have your number can '
                        'always send you referrals.',
                        style: CruType.caption.tint(c.label3),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _listed,
                  onChanged: (v) => setState(() => _listed = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          CruTextField(
            label: 'Handle',
            controller: _handle,
            prefix: '@',
            hint: 'e.g. dr.smit_patil',
            optional: !_listed,
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Name', controller: _name),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Specialty',
            controller: _specialty,
            hint: 'e.g. Anaesthesiology, Endodontics',
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'City', controller: _city, optional: true),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Clinic / Hospital',
            controller: _clinic,
            optional: true,
          ),
        ],
      ),
    );
  }
}
