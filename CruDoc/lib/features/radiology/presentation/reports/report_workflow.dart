import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ───────────────────────────── Sign ─────────────────────────────

/// Sign & finalise: confirms the name, qualification and registration
/// number printed under the report (saved to the radiology settings when
/// changed or missing). Returns the settings used, or null if cancelled.
Future<RadSettings?> showRadSignDialog(BuildContext context) =>
    showDialog<RadSettings>(context: context, builder: (_) => const _SignDialog());

class _SignDialog extends ConsumerStatefulWidget {
  const _SignDialog();

  @override
  ConsumerState<_SignDialog> createState() => _SignDialogState();
}

class _SignDialogState extends ConsumerState<_SignDialog> {
  final _form = GlobalKey<FormState>();
  late final RadSettings _settings;
  late final TextEditingController _name;
  late final TextEditingController _qualification;
  late final TextEditingController _regNo;
  bool _busy = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(radSettingsProvider).value ?? const RadSettings();
    final me = ref.read(doctorIdentityProvider).fullName ?? '';
    _name = TextEditingController(
        text: _settings.signatureName.isNotEmpty ? _settings.signatureName : me);
    _qualification = TextEditingController(text: _settings.qualification);
    _regNo = TextEditingController(text: _settings.regNo);
  }

  @override
  void dispose() {
    _name.dispose();
    _qualification.dispose();
    _regNo.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    final next = _settings.copyWith(
      signatureName: _name.text.trim(),
      qualification: _qualification.text.trim(),
      regNo: _regNo.text.trim(),
    );
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (next.signatureName != _settings.signatureName ||
          next.qualification != _settings.qualification ||
          next.regNo != _settings.regNo) {
        await ref.read(radiologyProvider).saveSettings(next);
      }
      if (mounted) Navigator.of(context).pop(next);
    } catch (_) {
      setState(() {
        _busy = false;
        _notice = "Couldn't save your signature details. Try again.";
      });
    }
  }

  String? _required(String? v, String what) => (v ?? '').trim().isEmpty ? what : null;

  @override
  Widget build(BuildContext context) {
    final missing = _settings.signatureName.isEmpty ||
        _settings.qualification.isEmpty ||
        _settings.regNo.isEmpty;
    return CruFormDialog(
      title: 'Sign & finalise',
      subtitle: 'The report is locked once signed',
      leading: const CruIconTile(icon: RadIcons.signature, tone: CruTileTone.accent),
      submitLabel: 'Sign & finalise',
      onSubmit: _sign,
      busy: _busy,
      notice: _notice,
      footerHint: 'Ctrl + Enter to sign',
      width: CruSize.formDialog - 80,
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Signature',
              description: missing
                  ? 'Printed under every signed report. Saved for next time.'
                  : 'Printed under the report. Change it here if needed.',
              children: [
                CruTextField(
                  label: 'Name as printed',
                  controller: _name,
                  hint: 'Dr. Meera Kulkarni',
                  autofocus: _settings.signatureName.isEmpty,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => _required(v, 'Add your name as it should print.'),
                ),
                CruTextField(
                  label: 'Qualification',
                  controller: _qualification,
                  hint: 'MDS (Oral Medicine & Radiology)',
                  validator: (v) => _required(v, 'Add your qualification.'),
                ),
                CruTextField(
                  label: 'Registration number',
                  controller: _regNo,
                  hint: 'Dental council registration',
                  tabular: true,
                  validator: (v) => _required(v, 'Add your registration number.'),
                ),
              ],
            ),
            CruFormSection(
              title: 'After signing',
              children: [
                Text(
                  'The report is locked and a copy is kept in its history. You can '
                  'still add an addendum, print it and send it.',
                  style: CruType.text.tint(context.cru.label2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Addendum ─────────────────────────────

/// Text to add to a signed report. Returns it, or null if cancelled.
Future<String?> showRadAddendumDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _AddendumDialog());

class _AddendumDialog extends StatefulWidget {
  const _AddendumDialog();

  @override
  State<_AddendumDialog> createState() => _AddendumDialogState();
}

class _AddendumDialogState extends State<_AddendumDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _dirty = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: 'Add addendum',
      subtitle: 'Signed reports stay as they are; this is added below',
      leading: const CruIconTile(icon: RadReportIcons.addendum, tone: CruTileTone.accent),
      submitLabel: 'Add addendum',
      dirty: _dirty,
      width: CruSize.formDialog - 80,
      footerHint: 'Ctrl + Enter to add',
      onSubmit: () {
        if (!(_form.currentState?.validate() ?? false)) return;
        Navigator.of(context).pop(_text.text.trim());
      },
      body: Form(
        key: _form,
        child: CruFormSection(
          first: true,
          title: 'Addendum',
          description: 'Dated and signed with your name. Send the report again afterwards.',
          children: [
            CruTextField(
              label: 'What to add',
              controller: _text,
              maxLines: 6,
              autofocus: true,
              hint: 'On review of the sagittal sections, the lesion also…',
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Write the addendum.' : null,
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── History ─────────────────────────────

/// Every saved state of the report, newest first, each readable in full.
Future<void> showRadVersionHistory(BuildContext context, RadReport report) =>
    showDialog<void>(context: context, builder: (_) => _HistoryDialog(report: report));

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.report});

  final RadReport report;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final versions = widget.report.versions.reversed.toList();
    return DentalPanelDialog(
      title: 'Version history',
      subtitle: versions.isEmpty
          ? widget.report.title
          : '${versions.length == 1 ? '1 version' : '${versions.length} versions'} · '
              'a copy is kept at every status change',
      leading: const CruIconTile(icon: RadIcons.history, tone: CruTileTone.neutral),
      width: CruSize.formDialog - 60,
      body: versions.isEmpty
          ? const DentalEmptyState(
              icon: RadIcons.history,
              title: 'No versions yet',
              body: 'A copy of the report is kept each time it is marked preliminary, '
                  'signed, or given an addendum.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < versions.length; i++) ...[
                  if (i > 0) const CruSeparator(indent: CruSpace.s12),
                  DentalListRow(
                    semanticLabel: '${versions[i].status.label}, ${RadFormat.dateTime(versions[i].at)}',
                    onTap: () => setState(() => _open = _open == i ? null : i),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                RadFormat.dateTime(versions[i].at),
                                style: CruType.callout.tabular.tint(c.label),
                              ),
                              if (versions[i].by.isNotEmpty)
                                Text(versions[i].by, style: CruType.subhead.tint(c.label2)),
                            ],
                          ),
                        ),
                        radReportStatusPill(c, versions[i].status),
                        const SizedBox(width: CruSpace.s8),
                        CruIcon(
                          _open == i ? CruIcons.chevronDown : CruIcons.chevronRight,
                          size: 16,
                          color: c.label3,
                        ),
                      ],
                    ),
                  ),
                  if (_open == i)
                    Container(
                      margin: const EdgeInsets.fromLTRB(
                        CruSpace.s12,
                        CruSpace.s4,
                        CruSpace.s12,
                        CruSpace.s12,
                      ),
                      padding: const EdgeInsets.all(CruSpace.s14),
                      decoration: ShapeDecoration(
                        color: c.inset,
                        shape: cruShape(CruRadius.control),
                      ),
                      child: SelectableText(
                        versions[i].snapshot.isEmpty ? '(Empty report)' : versions[i].snapshot,
                        style: CruType.note.tint(c.label),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

// ───────────────────────────── Critical finding ─────────────────────────────

/// Flag a critical finding and tell the referrer now: call, WhatsApp, and
/// a log of who was told when. Red is right here: it's patient safety.
Future<void> showRadCriticalDialog(
  BuildContext context, {
  required String studyId,
  required RadReferrer? referrer,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CriticalDialog(studyId: studyId, referrer: referrer),
    );

class _CriticalDialog extends ConsumerStatefulWidget {
  const _CriticalDialog({required this.studyId, required this.referrer});

  final String studyId;
  final RadReferrer? referrer;

  @override
  ConsumerState<_CriticalDialog> createState() => _CriticalDialogState();
}

class _CriticalDialogState extends ConsumerState<_CriticalDialog> {
  late final _who = TextEditingController(
    text: widget.referrer == null ? '' : '${widget.referrer!.name}, by phone',
  );
  final _note = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _who.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<RadStudy?> _fresh() => ref.read(radStudyProvider(widget.studyId).future);

  Future<void> _update(RadStudy Function(RadStudy) change, String audit, {String detail = ''}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final s = await _fresh();
      if (s == null) return;
      await ref.read(radiologyProvider).saveStudy(change(s), auditAction: audit, detail: detail);
    } catch (_) {
      _message = "Couldn't save. Try again.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launch(Uri uri, String failed) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _message = failed);
  }

  String _alertText(RadStudy s) =>
      'Critical finding on ${s.patientName}\'s ${s.modality.label} '
      '(${RadFormat.date(s.studyDate)}). Please call me as soon as you can. '
      'The report follows.';

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final study = ref.watch(radStudyProvider(widget.studyId)).value;
    if (study == null) {
      return const DentalPanelDialog(title: 'Critical finding', body: SizedBox.shrink());
    }
    final r = widget.referrer;
    final phone = r?.phone.trim() ?? '';
    final wa = WhatsAppTemplateService.normalizePhone(phone);

    if (!study.critical) {
      return DentalPanelDialog(
        title: 'Flag a critical finding',
        subtitle: study.patientName,
        leading: const _RedTile(),
        width: CruSize.formDialog - 160,
        body: Padding(
          padding: const EdgeInsets.all(CruSpace.s8),
          child: Text(
            'For a finding the referrer must act on now: suspected malignancy, a '
            'fracture, spreading infection, a compromised airway. The study and the '
            'report show it in red, and you log who was told and when.',
            style: CruType.text.tint(c.label2),
          ),
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: CruSpace.s10),
            CruButton(
              label: _busy ? 'Saving…' : 'Flag critical',
              icon: RadIcons.flag,
              onPressed: _busy
                  ? null
                  : () => _update(
                        (s) => s.copyWith(critical: true),
                        'Flagged critical finding',
                        detail: study.patientName,
                      ),
            ),
          ],
        ),
      );
    }

    final log = study.criticalLog.reversed.toList();
    return DentalPanelDialog(
      title: 'Critical finding',
      subtitle: log.isEmpty
          ? 'Referrer not told yet'
          : 'Last told ${RadFormat.dateTime(log.first.at)}',
      leading: const _RedTile(),
      width: CruSize.formDialog - 120,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s8, CruSpace.s8, 0),
            child: Text('Tell the referrer now', style: CruType.callout.tint(c.label)),
          ),
          Padding(
            padding: const EdgeInsets.all(CruSpace.s8),
            child: r == null
                ? Text(
                    'No referrer on this study. Add one on the worklist to call them from here.',
                    style: CruType.subhead.tint(c.label2),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        [r.display, if (phone.isNotEmpty) phone].join(' · '),
                        style: CruType.subhead.tabular.tint(c.label2),
                      ),
                      const SizedBox(height: CruSpace.s10),
                      Wrap(
                        spacing: CruSpace.s8,
                        runSpacing: CruSpace.s8,
                        children: [
                          if (phone.isNotEmpty)
                            CruCapsuleButton(
                              label: 'Call',
                              icon: CruIcons.phone,
                              kind: CruCapsuleKind.tinted,
                              onPressed: () => _launch(
                                Uri(scheme: 'tel', path: phone),
                                'No app on this computer places calls. Call $phone from your phone.',
                              ),
                            ),
                          CruCapsuleButton(
                            label: 'WhatsApp',
                            icon: CruIcons.whatsapp,
                            kind: CruCapsuleKind.tinted,
                            onPressed: () => _launch(
                              Uri.parse('https://wa.me/${wa ?? ''}'
                                  '?text=${Uri.encodeComponent(_alertText(study))}'),
                              "Couldn't open WhatsApp.",
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: CruSpace.s8),
          const CruSeparator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s16, CruSpace.s8, CruSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log that you told them', style: CruType.callout.tint(c.label)),
                const SizedBox(height: CruSpace.s12),
                CruFieldRow(
                  flex: const [2, 3],
                  children: [
                    CruTextField(
                      label: 'Who, and how',
                      controller: _who,
                      hint: 'Dr. Shah, by phone',
                    ),
                    CruTextField(
                      label: 'What was said',
                      controller: _note,
                      optional: true,
                      hint: 'Advised urgent biopsy referral',
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruCapsuleButton(
                    label: _busy ? 'Saving…' : 'Add to log',
                    icon: CruIcons.plus,
                    onPressed: _busy
                        ? null
                        : () async {
                            final who = _who.text.trim();
                            if (who.isEmpty) {
                              setState(() => _message = 'Say who was told.');
                              return;
                            }
                            final entry = RadCriticalLog(
                              at: DateTime.now(),
                              contacted: who,
                              note: _note.text.trim(),
                            );
                            await _update(
                              (s) => s.copyWith(criticalLog: [...s.criticalLog, entry]),
                              'Logged critical finding call',
                              detail: who,
                            );
                            _note.clear();
                          },
                  ),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
              child: CruFieldError(_message!),
            ),
          if (log.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            for (final l in log)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        RadFormat.dateTime(l.at),
                        style: CruType.subhead.tabular.tint(c.label2),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        [l.contacted, if (l.note.isNotEmpty) l.note].join(' · '),
                        style: CruType.subhead.tint(c.label),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
      footer: Row(
        children: [
          CruLink(
            label: 'Clear the flag',
            color: c.label2,
            onPressed: _busy
                ? null
                : () async {
                    final ok = await confirmDental(
                      context,
                      title: 'Clear the critical flag?',
                      body: 'The study and report stop showing it in red. The call log is kept.',
                      action: 'Clear flag',
                    );
                    if (ok) {
                      await _update((s) => s.copyWith(critical: false), 'Cleared critical flag');
                    }
                  },
          ),
          const Spacer(),
          CruButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _RedTile extends StatelessWidget {
  const _RedTile();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: CruSize.iconTile,
      height: CruSize.iconTile,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: c.redTint, shape: cruShape(CruRadius.iconTile)),
      child: CruIcon(RadIcons.flag, size: 18, strokeWidth: 1.8, color: c.redText),
    );
  }
}
