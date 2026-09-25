import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_pdf.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ───────────────────────────── Create / Edit Referral Dialog ─────────────────────────────

/// Dialog to create or edit a dental referral (outgoing or incoming).
class ReferralEditDialog extends ConsumerStatefulWidget {
  const ReferralEditDialog({
    super.key,
    this.initialReferral,
    this.initialPatient,
  });

  final DentalReferral? initialReferral;
  final Patient? initialPatient;

  @override
  ConsumerState<ReferralEditDialog> createState() => _ReferralEditDialogState();
}

class _ReferralEditDialogState extends ConsumerState<ReferralEditDialog> {
  late ReferralDirection _direction;
  Patient? _patient;
  ReferralContact? _selectedContact;

  late final TextEditingController _reason;
  late final TextEditingController _teeth;
  late final TextEditingController _findings;
  late final TextEditingController _question;
  late ReferralUrgency _urgency;
  List<String> _attachments = [];

  bool _busy = false;
  String? _teethError;

  @override
  void initState() {
    super.initState();
    final r = widget.initialReferral;
    _direction = r?.direction ?? ReferralDirection.out;
    _patient = widget.initialPatient;
    _reason = TextEditingController(text: r?.reason ?? '');
    _teeth = TextEditingController(text: r?.teeth.join(', ') ?? '');
    _findings = TextEditingController(text: r?.findings ?? '');
    _question = TextEditingController(text: r?.question ?? '');
    _urgency = r?.urgency ?? ReferralUrgency.routine;
    _attachments = r != null ? [...r.attachments] : [];

    if (r != null && _patient == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final patients = ref.read(patientsStreamProvider).value ?? const [];
        final match = patients.where((p) => p.id == r.patientId).firstOrNull;
        if (match != null && mounted) {
          setState(() => _patient = match);
        }
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _teeth.dispose();
    _findings.dispose();
    _question.dispose();
    super.dispose();
  }

  List<String> _parseAndValidateTeeth(String raw) {
    if (raw.trim().isEmpty) return const [];
    final tokens = raw.split(RegExp(r'[, ]+')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    for (final t in tokens) {
      if (!DentalChart.isValid(t)) {
        throw FormatException('Invalid FDI tooth number: "$t"');
      }
    }
    return tokens;
  }

  Future<void> _pickPatient() async {
    final picked = await pickRadPatient(context);
    if (picked != null && mounted) {
      setState(() => _patient = picked);
    }
  }

  Future<void> _addAttachment() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final appSupport = await getApplicationSupportDirectory();
    final refId = widget.initialReferral?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final targetDir = Directory(p.join(appSupport.path, 'dental', 'referrals', refId));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final newPaths = <String>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final src = File(f.path!);
      final destPath = p.join(targetDir.path, p.basename(f.path!));
      await src.copy(destPath);
      newPaths.add(destPath);
    }

    if (mounted) {
      setState(() => _attachments.addAll(newPaths));
    }
  }

  Future<void> _addNewContact() async {
    final newContact = await showDialog<ReferralContact>(
      context: context,
      builder: (_) => const EditContactDialog(),
    );
    if (newContact != null && mounted) {
      setState(() => _selectedContact = newContact);
    }
  }

  Future<void> _save() async {
    if (_patient == null) {
      recToast(context, 'Please select a patient');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      recToast(context, 'Please enter a reason for referral');
      return;
    }

    List<String> parsedTeeth = [];
    try {
      parsedTeeth = _parseAndValidateTeeth(_teeth.text);
      _teethError = null;
    } catch (e) {
      setState(() => _teethError = e.toString());
      return;
    }

    setState(() => _busy = true);

    try {
      final r = widget.initialReferral;

      final contactName = _selectedContact?.name ?? r?.contactName ?? '';
      final contactSpecialty = _selectedContact?.specialty ?? r?.contactSpecialty ?? '';
      final contactId = _selectedContact?.id ?? r?.contactId ?? '';

      final now = DateTime.now();

      if (r == null) {
        // Create new
        final record = DentalRecord.create(
          _patient!.id,
          RecKind.referral,
          {
            'direction': _direction.wireName,
            'contactId': contactId,
            'contactName': contactName,
            'contactSpecialty': contactSpecialty,
            'reason': _reason.text.trim(),
            'teeth': parsedTeeth,
            'findings': _findings.text.trim(),
            'question': _question.text.trim(),
            'urgency': _urgency.name,
            'attachments': _attachments,
            'status': ReferralStatus.draft.name,
            'history': [
              {
                'status': ReferralStatus.draft.name,
                'at': now.millisecondsSinceEpoch,
                'note': 'Referral created as draft',
              }
            ],
            'reply': '',
          },
          at: now,
        );
        await saveDentalRecord(ref, record);
        if (mounted) recToast(context, 'Referral draft created');
      } else {
        // Update existing
        final updatedRecord = r.record.copyWith(
          data: {
            ...r.record.data,
            'direction': _direction.wireName,
            'contactId': contactId,
            'contactName': contactName,
            'contactSpecialty': contactSpecialty,
            'reason': _reason.text.trim(),
            'teeth': parsedTeeth,
            'findings': _findings.text.trim(),
            'question': _question.text.trim(),
            'urgency': _urgency.name,
            'attachments': _attachments,
          },
        );
        await saveDentalRecord(ref, updatedRecord);
        if (mounted) recToast(context, 'Referral updated');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving referral: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final contacts = ref.watch(referralContactsProvider);

    // Resolve contact selection if matching ID
    if (_selectedContact == null && widget.initialReferral != null) {
      final match = contacts.where((cnt) => cnt.id == widget.initialReferral!.contactId).firstOrNull;
      if (match != null) _selectedContact = match;
    }

    return CruFormDialog(
      title: widget.initialReferral == null ? 'New referral' : 'Edit referral',
      subtitle: _direction == ReferralDirection.out ? 'Referring to specialist' : 'Referred to this clinic',
      width: 580,
      busy: _busy,
      submitLabel: widget.initialReferral == null ? 'Create referral' : 'Save changes',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Direction segment
          CruSegmentedControl<ReferralDirection>(
            semanticLabel: 'Referral direction',
            segments: [
              CruSegment(
                ReferralDirection.out,
                ReferralDirection.out.formLabel,
              ),
              CruSegment(
                ReferralDirection.inbound,
                ReferralDirection.inbound.formLabel,
              ),
            ],
            selected: _direction,
            onChanged: (d) => setState(() => _direction = d),
          ),
          const SizedBox(height: CruSpace.s16),

          // Patient selector
          CruFieldFrame(
            label: 'Patient',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _patient != null
                        ? '${_patient!.fullName} (${_patient!.age}y, ${_patient!.gender.toUpperCase()})'
                        : 'No patient selected',
                    style: CruType.body.tint(_patient != null ? c.label : c.label3),
                  ),
                ),
                CruCapsuleButton(
                  label: _patient != null ? 'Change' : 'Pick patient',
                  icon: CruIcons.search,
                  onPressed: _pickPatient,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Contact selector
          CruFieldFrame(
            label: _direction == ReferralDirection.out ? 'Referring to' : 'Referred by',
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedContact?.id,
                      hint: Text(
                        'Select contact / doctor',
                        style: CruType.body.tint(c.label3),
                      ),
                      items: [
                        for (final cnt in contacts)
                          DropdownMenuItem<String>(
                            value: cnt.id,
                            child: Text(
                              '${cnt.name}${cnt.specialty.isNotEmpty ? ' · ${cnt.specialty}' : ''}',
                              style: CruType.body.tint(c.label),
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        setState(() {
                          _selectedContact = contacts.where((cnt) => cnt.id == id).firstOrNull;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                CruCapsuleButton(
                  label: 'Add contact',
                  icon: CruIcons.plus,
                  onPressed: _addNewContact,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),

          // Reason
          CruTextField(
            label: 'Reason for referral',
            controller: _reason,
            hint: 'e.g. Retreatment 36, Apicoectomy, Orthodontic consult',
          ),
          const SizedBox(height: CruSpace.s12),

          // Teeth (FDI)
          CruTextField(
            label: 'Teeth (FDI, comma-separated)',
            controller: _teeth,
            hint: 'e.g. 16, 26, 36 (always stored as FDI)',
            help: _teethError,
            onChanged: (_) {
              if (_teethError != null) setState(() => _teethError = null);
            },
          ),
          const SizedBox(height: CruSpace.s12),

          // Findings
          CruTextField(
            label: 'Clinical findings & history',
            controller: _findings,
            maxLines: 4,
            hint: 'Relevant symptoms, radiographic findings, prior treatments...',
          ),
          const SizedBox(height: CruSpace.s12),

          // Specific Question
          CruTextField(
            label: 'Specific question or requested procedure',
            controller: _question,
            maxLines: 4,
            hint: 'e.g. Please evaluate for surgical extraction vs endodontic retreat',
          ),
          const SizedBox(height: CruSpace.s12),

          // Urgency
          CruFieldFrame(
            label: 'Urgency',
            child: CruSegmentedControl<ReferralUrgency>(
              semanticLabel: 'Urgency',
              segments: [
                for (final u in ReferralUrgency.values)
                  CruSegment(
                    u,
                    u.label,
                  ),
              ],
              selected: _urgency,
              onChanged: (u) => setState(() => _urgency = u),
            ),
          ),
          const SizedBox(height: CruSpace.s16),

          // Attachments
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attachments (${_attachments.length})',
                style: CruType.callout.w600.tint(c.label),
              ),
              CruCapsuleButton(
                label: 'Add files',
                icon: CruIcons.plus,
                onPressed: _addAttachment,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          if (_attachments.isEmpty)
            Text(
              'No files attached yet (radiographs, photos, lab reports).',
              style: CruType.caption.tint(c.label3),
            )
          else
            for (final path in _attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s6,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    children: [
                      CruIcon(CruIcons.box, size: 16, color: c.label2),
                      const SizedBox(width: CruSpace.s8),
                      Expanded(
                        child: Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.note.tint(c.label),
                        ),
                      ),
                      CruIconButton(
                        icon: CruIcons.arrowUpRight,
                        size: CruSize.squareButton,
                        semanticLabel: 'Open file',
                        tooltip: 'Open file',
                        onPressed: () => launchUrl(Uri.file(path)),
                      ),
                      CruIconButton(
                        icon: CruIcons.close,
                        size: CruSize.squareButton,
                        semanticLabel: 'Remove file',
                        tooltip: 'Remove',
                        onPressed: () => setState(() => _attachments.remove(path)),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: CruSpace.s20),

          // Shared case access placeholder notice
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: BoxDecoration(
              color: c.inset,
              borderRadius: BorderRadius.circular(CruRadius.control),
            ),
            child: Row(
              children: [
                CruIcon(CruIcons.help, size: 16, color: c.label2),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    'Sharing the case with the other doctor inside CruDoc needs the cloud: not connected yet.',
                    style: CruType.caption.tint(c.label2),
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

// ───────────────────────────── Contact Dialogs ─────────────────────────────

/// Dialog to add or edit an external referral contact.
class EditContactDialog extends ConsumerStatefulWidget {
  const EditContactDialog({super.key, this.contact});

  final ReferralContact? contact;

  @override
  ConsumerState<EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends ConsumerState<EditContactDialog> {
  late final TextEditingController _name;
  late final TextEditingController _clinic;
  late final TextEditingController _specialty;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _notes;
  late final TextEditingController _turnaround;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _name = TextEditingController(text: c?.name ?? '');
    _clinic = TextEditingController(text: c?.clinic ?? '');
    _specialty = TextEditingController(text: c?.specialty ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _turnaround = TextEditingController(
      text: c?.turnaroundDays != null ? '${c!.turnaroundDays}' : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _clinic.dispose();
    _specialty.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _notes.dispose();
    _turnaround.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      recToast(context, 'Please enter a contact name');
      return;
    }

    setState(() => _busy = true);
    try {
      final turnaround = int.tryParse(_turnaround.text.trim());
      final contactData = {
        'name': _name.text.trim(),
        'clinic': _clinic.text.trim(),
        'specialty': _specialty.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'city': _city.text.trim(),
        'notes': _notes.text.trim(),
        'turnaroundDays': ?turnaround,
      };

      ReferralContact resultContact;
      if (widget.contact == null) {
        final rec = DentalRecord.create('', RecKind.referralContact, contactData);
        await saveDentalRecord(ref, rec);
        resultContact = ReferralContact.fromRecord(rec);
      } else {
        final oldRecord = (ref.read(clinicRecordsProvider(RecKind.referralContact)).value ?? [])
            .where((r) => r.id == widget.contact!.id)
            .firstOrNull;
        if (oldRecord != null) {
          final updated = oldRecord.copyWith(data: contactData);
          await saveDentalRecord(ref, updated);
          resultContact = ReferralContact.fromRecord(updated);
        } else {
          resultContact = widget.contact!;
        }
      }

      if (mounted) Navigator.of(context).pop(resultContact);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving contact: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: widget.contact == null ? 'Add referral contact' : 'Edit contact',
      width: 480,
      busy: _busy,
      submitLabel: 'Save contact',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(label: 'Doctor / Contact name', controller: _name),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Clinic / Hospital', controller: _clinic),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Specialty', controller: _specialty, hint: 'e.g. Endodontist, Dental lab, OMFS'),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Phone (for WhatsApp)', controller: _phone, keyboardType: TextInputType.phone),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'City', controller: _city),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Standard turnaround (days)', controller: _turnaround, keyboardType: TextInputType.number),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Notes', controller: _notes, maxLines: 4),
        ],
      ),
    );
  }
}

/// Panel dialog displaying the full directory of referral contacts with Labs filter (PR2).
class ContactDirectoryDialog extends ConsumerStatefulWidget {
  const ContactDirectoryDialog({super.key, this.initialLabsOnly = false});

  final bool initialLabsOnly;

  @override
  ConsumerState<ContactDirectoryDialog> createState() => _ContactDirectoryDialogState();
}

class _ContactDirectoryDialogState extends ConsumerState<ContactDirectoryDialog> {
  late bool _labsOnly;

  @override
  void initState() {
    super.initState();
    _labsOnly = widget.initialLabsOnly;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final contacts = ref.watch(referralContactsProvider);
    final labContacts = ref.watch(labPartnersProvider);
    final shown = _labsOnly ? labContacts : contacts;

    return DentalPanelDialog(
      title: 'Referral contacts',
      subtitle: '${contacts.length} contacts · ${labContacts.length} lab partners',
      leading: const CruIconTile(icon: CruIcons.userPlus, tone: CruTileTone.neutral),
      width: 560,
      footer: CruButton(
        label: 'New contact',
        icon: CruIcons.plus,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const EditContactDialog(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruSegmentedControl<bool>(
                semanticLabel: 'Filter contacts',
                segments: [
                  CruSegment(false, 'All (${contacts.length})'),
                  CruSegment(true, 'Labs (${labContacts.length})'),
                ],
                selected: _labsOnly,
                onChanged: (v) => setState(() => _labsOnly = v),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          if (shown.isEmpty)
            DentalEmptyState(
              icon: CruIcons.user,
              title: _labsOnly ? 'No dental labs saved' : 'No contacts saved',
              body: _labsOnly
                  ? 'Add dental lab partners with turnaround times for crown, bridge and denture work.'
                  : 'Add external doctors, specialists, or labs to refer patients to.',
              actions: [
                CruButton(
                  label: _labsOnly ? 'Add dental lab' : 'New contact',
                  icon: CruIcons.plus,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditContactDialog(
                      contact: _labsOnly
                          ? const ReferralContact(id: '', name: '', specialty: 'Dental lab')
                          : null,
                    ),
                  ),
                ),
              ],
            )
          else
            for (final cnt in shown)
              DentalListRow(
                semanticLabel: cnt.name,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => EditContactDialog(contact: cnt),
                ),
                child: Row(
                  children: [
                    CruIconTile(
                      icon: cnt.specialty.toLowerCase().contains('lab')
                          ? CruIcons.box
                          : CruIcons.user,
                      tone: CruTileTone.neutral,
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(cnt.name, style: CruType.callout.w600.tint(c.label)),
                              if (cnt.turnaroundDays != null) ...[
                                const SizedBox(width: CruSpace.s8),
                                CruPill(
                                  text: '${cnt.turnaroundDays}d turnaround',
                                  background: c.inset,
                                  foreground: c.label2,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            [
                              if (cnt.specialty.isNotEmpty) cnt.specialty,
                              if (cnt.clinic.isNotEmpty) cnt.clinic,
                              if (cnt.city.isNotEmpty) cnt.city,
                            ].join(' · '),
                            style: CruType.caption.tint(c.label2),
                          ),
                        ],
                      ),
                    ),
                    if (cnt.phone.isNotEmpty)
                      Text(cnt.phone, style: CruType.caption.tabular.tint(c.label2)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Write Reply Dialog ─────────────────────────────

/// Dialog for writing a treatment summary reply for received referrals.
class WriteReplyDialog extends ConsumerStatefulWidget {
  const WriteReplyDialog({super.key, required this.referral});

  final DentalReferral referral;

  @override
  ConsumerState<WriteReplyDialog> createState() => _WriteReplyDialogState();
}

class _WriteReplyDialogState extends ConsumerState<WriteReplyDialog> {
  late final TextEditingController _reply;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reply = TextEditingController(text: widget.referral.reply);
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _reply.text.trim();
    if (text.isEmpty) {
      recToast(context, 'Please enter treatment summary text');
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final updatedHistory = [
        ...widget.referral.history.map((h) => h.toJson()),
        {
          'status': ReferralStatus.completed.name,
          'at': now.millisecondsSinceEpoch,
          'note': 'Treatment reply documented',
        }
      ];

      final updatedRecord = widget.referral.record.copyWith(
        data: {
          ...widget.referral.record.data,
          'reply': text,
          'status': ReferralStatus.completed.name,
          'history': updatedHistory,
        },
      );
      await saveDentalRecord(ref, updatedRecord);
      if (mounted) recToast(context, 'Treatment summary saved');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving reply: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: 'Write treatment summary',
      subtitle: 'Reply to referring doctor (${widget.referral.contactName})',
      width: 500,
      busy: _busy,
      submitLabel: 'Save & complete',
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Treatment summary & clinical outcome',
            controller: _reply,
            maxLines: 8,
            hint: 'Summary of procedures performed, findings, post-op instructions, recommendations...',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Patient Referrals Dialog ─────────────────────────────

/// Dialog opened from DentalRecordsCard showing referrals for one specific patient.
class PatientReferralsDialog extends ConsumerWidget {
  const PatientReferralsDialog({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final records = ref.watch(patientRecordsProvider((patientId: patient.id, kind: RecKind.referral))).value ??
        const <DentalRecord>[];
    final referrals = records.map(DentalReferral.fromRecord).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    return DentalPanelDialog(
      title: 'Referrals: ${patient.fullName}',
      subtitle: '${referrals.length} referral records',
      leading: const CruIconTile(icon: CruIcons.arrowUpRight, tone: CruTileTone.neutral),
      width: 560,
      footer: CruButton(
        label: 'New referral',
        icon: CruIcons.plus,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => ReferralEditDialog(initialPatient: patient),
        ),
      ),
      body: referrals.isEmpty
          ? DentalEmptyState(
              icon: CruIcons.arrowUpRight,
              title: 'No referrals for this patient',
              body: 'Refer to an external specialist or log an incoming referral.',
              actions: [
                CruButton(
                  label: 'New referral',
                  icon: CruIcons.plus,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ReferralEditDialog(initialPatient: patient),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in referrals)
                  DentalListRow(
                    semanticLabel: r.reason,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => ReferralEditDialog(
                        initialReferral: r,
                        initialPatient: patient,
                      ),
                    ),
                    child: Row(
                      children: [
                        CruIconTile(
                          icon: r.direction == ReferralDirection.out ? CruIcons.arrowUpRight : CruIcons.chevronLeft,
                          tone: CruTileTone.neutral,
                        ),
                        const SizedBox(width: CruSpace.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.reason, style: CruType.callout.w600.tint(c.label)),
                              Text(
                                '${DentalFormat.date(r.recordedAt)} · ${r.direction == ReferralDirection.out ? 'To' : 'From'} ${r.contactName.isNotEmpty ? r.contactName : 'Specialist'}',
                                style: CruType.caption.tint(c.label2),
                              ),
                            ],
                          ),
                        ),
                        CruPill(
                          text: r.status.label,
                          background: r.status == ReferralStatus.completed ? c.greenTint : c.inset,
                          foreground: r.status == ReferralStatus.completed ? c.greenText : c.label2,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────────── Referral Actions Helpers ─────────────────────────────

/// Updates referral status, records history note and saves record.
Future<void> updateReferralStatus(
  WidgetRef ref,
  DentalReferral referral,
  ReferralStatus newStatus, {
  String note = '',
}) async {
  final now = DateTime.now();
  final updatedHistory = [
    ...referral.history.map((h) => h.toJson()),
    {
      'status': newStatus.name,
      'at': now.millisecondsSinceEpoch,
      'note': note.isNotEmpty ? note : 'Status changed to ${newStatus.label}',
    }
  ];

  final updatedRecord = referral.record.copyWith(
    data: {
      ...referral.record.data,
      'status': newStatus.name,
      'history': updatedHistory,
    },
  );
  await saveDentalRecord(ref, updatedRecord);
}

/// Sends referral letter via WhatsApp, sets status to sent, and gives file snackbar.
Future<void> sendReferralWhatsApp(
  BuildContext context,
  WidgetRef ref,
  DentalReferral referral,
  Patient patient,
) async {
  final contacts = ref.read(referralContactsProvider);
  final contact = contacts.where((cnt) => cnt.id == referral.contactId).firstOrNull;
  final phone = contact?.phone ?? '';

  if (phone.isEmpty) {
    recToast(context, 'No phone number saved for ${referral.contactName}');
    return;
  }

  // 1. Generate and save PDF letter
  final pdfPath = await ReferralPdfService.saveLetterToFolder(
    referral: referral,
    patient: patient,
    ref: ref,
    isReply: referral.direction == ReferralDirection.inbound,
  );

  // 2. Open WhatsApp
  final message = referral.direction == ReferralDirection.out
      ? 'Hello Dr. ${referral.contactName}, referring patient ${patient.fullName} (${referral.reason}, Urgency: ${referral.urgency.label}). Referral letter attached.'
      : 'Hello Dr. ${referral.contactName}, here is the treatment summary for ${patient.fullName} (${referral.reason}). Summary letter attached.';

  final uri = WhatsAppTemplateService.buildDirectWhatsAppUrl(
    rawPhone: phone,
    message: message,
  );

  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // 3. Update status to sent if draft
  if (referral.status == ReferralStatus.draft) {
    await updateReferralStatus(ref, referral, ReferralStatus.sent, note: 'Sent via WhatsApp');
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Referral letter saved: ${p.basename(pdfPath)}'),
        action: SnackBarAction(
          label: 'Show in folder',
          onPressed: () {
            launchUrl(Uri.file(p.dirname(pdfPath)));
          },
        ),
      ),
    );
  }
}
