import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/messaging/data/services/whatsapp_template_service.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_pdf.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Radiology report - Asha Patil - 2026-09-24.pdf" (safe on Windows).
String radReportFileName(RadStudy s) {
  final d = s.studyDate;
  final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final name = s.patientName.trim().isEmpty ? 'Patient' : s.patientName.trim();
  return 'Radiology report - $name - $date.pdf'.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-');
}

/// Gathers what the PDF prints: letterhead, the chosen measurements and
/// the chosen key images (PNG files in the study folder).
Future<RadReportPdfData> radCollectPdf(WidgetRef ref, RadStudy study, RadReport report) async {
  final settings = await ref.read(radSettingsProvider.future);
  final identity = ref.read(doctorIdentityProvider);
  final rad = ref.read(radiologyProvider);
  final keys = <({String caption, Uint8List png})>[];
  for (final id in report.keyImageIds) {
    final k = study.keyImages.where((k) => k.id == id).firstOrNull;
    if (k == null) continue;
    try {
      final f = await rad.fileOf(study, k.pngPath);
      if (await f.exists()) keys.add((caption: k.caption, png: await f.readAsBytes()));
    } catch (_) {
      // A missing picture is left out of the PDF, not a reason to fail.
    }
  }
  return RadReportPdfData(
    study: study,
    report: report,
    referrer: ref.read(radReferrerByIdProvider)[study.referrerId],
    letterhead: RadLetterhead.from(
      clinicName: identity.clinicName,
      doctorName: identity.fullName,
      settings: settings,
      profile: ref.read(doctorProfileProvider).value,
    ),
    measurements: [
      for (final m in radMeasurementRows(study))
        if (report.measurementIds.contains(m.id)) (label: m.label, value: m.value),
    ],
    keyImages: keys,
    ceph: radCephTables(study),
  );
}

Future<Uint8List> radReportPdfBytes(WidgetRef ref, RadStudy study, RadReport report) async =>
    buildRadReportPdf(await radCollectPdf(ref, study, report));

/// Asks where to save the PDF and saves it. Returns the path, or null if
/// the doctor cancelled.
Future<String?> radSavePdfAs(WidgetRef ref, RadStudy study, RadReport report) async {
  final bytes = await radReportPdfBytes(ref, study, report);
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save report as PDF',
    fileName: radReportFileName(study),
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
  if (path == null) return null;
  final f = File(path);
  if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(bytes, flush: true);
  await ref.read(radiologyProvider).log('Exported PDF',
      targetKind: 'report', targetId: report.id, detail: study.patientName);
  return path;
}

/// Saves the PDF in the study's folder (reports/), for attaching to a
/// WhatsApp message or an email.
Future<File> _saveInStudy(WidgetRef ref, RadStudy study, Uint8List bytes) async {
  final dir = await ref.read(radiologyProvider).studyDir(study.id);
  final out = Directory(p.join(dir.path, 'reports'));
  await out.create(recursive: true);
  final f = File(p.join(out.path, radReportFileName(study)));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// Opens the file manager with [path] selected.
Future<void> radShowInFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
      return;
    }
  } catch (_) {
    // Fall back to opening the folder.
  }
  await launchUrl(Uri.directory(p.dirname(path)));
}

/// The short message that goes with the PDF.
String radShareSummary(RadStudy s, RadReport r, {required String signer}) {
  final b = StringBuffer();
  final who = [s.patientName.trim(), RadFormat.patientLine(s, DateTime.now())]
      .where((e) => e.isNotEmpty)
      .join(', ');
  b.writeln('Radiology report: $who');
  b.writeln('${s.modality.label} · ${RadFormat.date(s.studyDate)}');
  if (r.status == RadReportStatus.preliminary) {
    b.writeln('Preliminary report; the final signed report will follow.');
  }
  if (s.critical) b.writeln('Critical finding: please look at this report now.');
  final imp = r.impression.trim();
  if (imp.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Impression: ${imp.length > 600 ? '${imp.substring(0, 600)}…' : imp}');
  }
  b
    ..writeln()
    ..writeln('The full report is attached as a PDF.');
  if (signer.isNotEmpty) b.writeln('— $signer');
  return b.toString().trim();
}

/// Send the report: WhatsApp or email to the referrer (the PDF is saved
/// first so it can be attached), print, save a PDF, or a secure link once
/// the cloud is connected. [onShared] records how it went out.
Future<void> showRadShareDialog(
  BuildContext context, {
  required RadStudy study,
  required RadReport report,
  required RadReferrer? referrer,
  required Future<void> Function(String via) onShared,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareDialog(
        study: study,
        report: report,
        referrer: referrer,
        onShared: onShared,
      ),
    );

enum _Action { whatsApp, email, print, save }

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({
    required this.study,
    required this.report,
    required this.referrer,
    required this.onShared,
  });

  final RadStudy study;
  final RadReport report;
  final RadReferrer? referrer;
  final Future<void> Function(String via) onShared;

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  _Action? _busy;
  String? _savedPath;
  String? _message;
  bool _warn = false;

  bool get _sendable => widget.report.status != RadReportStatus.draft;

  void _say(String text, {bool warn = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _warn = warn;
    });
  }

  Future<void> _run(_Action a) async {
    setState(() {
      _busy = a;
      _message = null;
    });
    try {
      switch (a) {
        case _Action.whatsApp:
        case _Action.email:
          await _send(a);
        case _Action.print:
          final bytes = await radReportPdfBytes(ref, widget.study, widget.report);
          final done = await Printing.layoutPdf(
            name: radReportFileName(widget.study),
            onLayout: (_) async => bytes,
          );
          if (done && _sendable) await widget.onShared('Print');
          if (done) _say(_sendable ? 'Printed. Recorded as handed over on paper.' : 'Printed.');
        case _Action.save:
          final path = await radSavePdfAs(ref, widget.study, widget.report);
          if (path != null) {
            setState(() => _savedPath = path);
            _say('Saved ${p.basename(path)}.');
          }
      }
    } catch (_) {
      _say("Couldn't make the PDF. Try again.", warn: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _send(_Action a) async {
    final r = widget.referrer;
    final bytes = await radReportPdfBytes(ref, widget.study, widget.report);
    final file = await _saveInStudy(ref, widget.study, bytes);
    if (!mounted) return;
    setState(() => _savedPath = file.path);
    final settings = await ref.read(radSettingsProvider.future);
    final signer = settings.signatureName.trim().isNotEmpty
        ? settings.signatureName.trim()
        : (ref.read(doctorIdentityProvider).fullName ?? '');
    final text = radShareSummary(widget.study, widget.report, signer: signer);
    final Uri uri;
    final String via;
    if (a == _Action.whatsApp) {
      final phone = WhatsAppTemplateService.normalizePhone(r?.phone);
      uri = Uri.parse(
          'https://wa.me/${phone ?? ''}?text=${Uri.encodeComponent(text)}');
      via = 'WhatsApp';
    } else {
      final subject = 'Radiology report: ${widget.study.patientName} '
          '(${widget.study.modality.short}, ${RadFormat.date(widget.study.studyDate)})';
      uri = Uri.parse('mailto:${r?.email.trim() ?? ''}'
          '?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}');
      via = 'Email';
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _say(
        a == _Action.whatsApp
            ? "Couldn't open WhatsApp. The PDF is saved; send it another way."
            : "Couldn't open your email app. The PDF is saved; send it another way.",
        warn: true,
      );
      return;
    }
    await widget.onShared(via);
    _say('$via opened with a short summary. Attach ${p.basename(file.path)} '
        '(Show in folder), then send.');
  }

  Widget _row({
    required CruIconData icon,
    required String title,
    required String body,
    Widget? note,
    Widget? action,
  }) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8, vertical: CruSpace.s12),
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.neutral),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(body, style: CruType.subhead.tint(c.label2)),
                if (note != null) ...[const SizedBox(height: CruSpace.s6), note],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: CruSpace.s12), action],
        ],
      ),
    );
  }

  Widget _capsule(String label, _Action a, {bool enabled = true}) {
    final busy = _busy == a;
    final on = enabled && _busy == null;
    return Opacity(
      opacity: on || busy ? 1 : 0.5,
      child: CruCapsuleButton(
        label: busy ? 'Preparing…' : label,
        onPressed: on ? () => _run(a) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final r = widget.referrer;
    final phone = r?.phone.trim() ?? '';
    final email = r?.email.trim() ?? '';
    final notYet = _sendable ? null : 'Mark it preliminary or sign it first.';
    return DentalPanelDialog(
      title: 'Send report',
      subtitle: [
        widget.study.patientName,
        widget.report.status.label,
        if (widget.report.sharedAt != null)
          'Last sent ${RadFormat.dateTime(widget.report.sharedAt!)} by ${widget.report.sharedVia}',
      ].join(' · '),
      leading: const CruIconTile(icon: RadIcons.share, tone: CruTileTone.accent),
      width: CruSize.formDialog - 120,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            icon: CruIcons.whatsapp,
            title: 'WhatsApp',
            body: notYet ??
                (phone.isNotEmpty
                    ? 'To ${r!.name} on $phone with a short summary. The PDF is saved first '
                        'so you can attach it.'
                    : 'Opens WhatsApp with a short summary to pick the contact. The PDF is '
                        'saved first so you can attach it.'),
            action: _capsule('Send', _Action.whatsApp, enabled: _sendable),
          ),
          const CruSeparator(indent: CruSpace.s8 + CruSize.iconTile + CruSpace.s12),
          _row(
            icon: RadIcons.mail,
            title: 'Email',
            body: notYet ??
                (email.isNotEmpty
                    ? 'To $email from your email app, with the summary. Attach the saved PDF.'
                    : 'Opens your email app with the summary. Attach the saved PDF.'),
            action: _capsule('Write', _Action.email, enabled: _sendable),
          ),
          const CruSeparator(indent: CruSpace.s8 + CruSize.iconTile + CruSpace.s12),
          _row(
            icon: RadIcons.print,
            title: 'Print',
            body: _sendable
                ? 'On the letterhead, with key images and your signature block.'
                : 'A proof copy marked Draft.',
            action: _capsule('Print', _Action.print),
          ),
          const CruSeparator(indent: CruSpace.s8 + CruSize.iconTile + CruSpace.s12),
          _row(
            icon: CruIcons.download,
            title: 'Save PDF',
            body: 'Choose where to keep a copy.',
            action: _capsule('Save', _Action.save),
          ),
          const CruSeparator(indent: CruSpace.s8 + CruSize.iconTile + CruSpace.s12),
          _row(
            icon: RadIcons.cloud,
            title: 'Secure link',
            body: 'A private link the referrer opens in a browser, with the images.',
            note: const RadNotConnected(
              compact: true,
              title: 'Cloud not connected yet',
              body: '',
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: CruSpace.s8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CruSpace.s12,
                vertical: CruSpace.s10,
              ),
              decoration: ShapeDecoration(
                color: _warn ? c.amberTint : c.inset,
                shape: cruShape(CruRadius.control),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _message!,
                      style: CruType.subhead.tint(_warn ? c.amberText : c.label),
                    ),
                  ),
                  if (_savedPath != null) ...[
                    const SizedBox(width: CruSpace.s12),
                    CruCapsuleButton(
                      label: 'Show in folder',
                      icon: RadReportIcons.folderOpen,
                      kind: CruCapsuleKind.surface,
                      onPressed: () => radShowInFolder(_savedPath!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
