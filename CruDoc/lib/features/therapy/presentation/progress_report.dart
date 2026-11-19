import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// Builds the progress report from what is saved for [patient] and shares it
/// (share sheet on phones, save/share on PC).
Future<void> shareProgressReport(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  Future<List<DentalRecord>> load(String kind) => ref.read(
    patientRecordsProvider((patientId: patient.id, kind: kind)).future,
  );
  final progress = progressEntries(await load(RecKind.physioProgress));
  final rom = romAssessments(await load(RecKind.physioRom));
  final programs = [
    for (final r in await load(RecKind.physioHep)) HepProgram.fromRecord(r),
  ]..sort((a, b) => b.date.compareTo(a.date));
  final packages = sessionPackages(await load(RecKind.physioPackage));
  final doctor = ref.read(doctorIdentityProvider).fullName;

  final bytes = await buildProgressReportPdf(
    patient: patient,
    progress: progress,
    rom: rom,
    program: programs.firstOrNull,
    package: packages.firstOrNull,
    doctorName: doctor,
  );
  final name = 'Progress report - ${patient.fullName}.pdf';
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      ),
    );
  } else {
    await Printing.sharePdf(bytes: bytes, filename: name);
  }
}

String _pair(int? l, int? r) => '${l ?? '-'} / ${r ?? '-'}';

String _delta(int? a, int? b) {
  if (a == null || b == null) return '-';
  final d = b - a;
  return d > 0 ? '+$d' : '$d';
}

/// Pain, function, ROM, the current home program and session usage: only the
/// sections that have data. No diagnosis, no inferred text.
Future<Uint8List> buildProgressReportPdf({
  required Patient patient,
  required List<ProgressEntry> progress,
  required List<RomAssessment> rom,
  required HepProgram? program,
  required SessionPackage? package,
  String? doctorName,
}) async {
  final doc = pw.Document();
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  const small = pw.TextStyle(fontSize: 10);

  pw.Widget heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget table(List<String> head, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: head,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      );

  final body = <pw.Widget>[];

  // Pain and function.
  if (progress.isNotEmpty) {
    final first = progress.first;
    final last = progress.last;
    String change(String label, int a, int b) =>
        progress.length > 1 && a != b ? '$label $a to $b' : '$label $b';
    body
      ..add(heading('Pain and function'))
      ..add(
        pw.Text(
          '${change('Pain', first.pain, last.pain)}   |   '
          '${change('Function', first.function, last.function)}'
          '   (0 to 10; latest ${DentalFormat.date(last.date)})',
          style: bold,
        ),
      );
    if (progress.length > 1) {
      final shown = progress.length > 10
          ? progress.sublist(progress.length - 10)
          : progress;
      body
        ..add(pw.SizedBox(height: 6))
        ..add(
          table(
            ['Date', 'Pain', 'Worst pain', 'Function'],
            [
              for (final e in shown)
                [
                  DentalFormat.date(e.date),
                  '${e.pain}',
                  '${e.worst}',
                  '${e.function}',
                ],
            ],
          ),
        );
    }
  }

  // ROM by region: first vs latest.
  final byRegion = <String, List<RomAssessment>>{};
  for (final a in rom.reversed) {
    byRegion.putIfAbsent(a.regionId, () => []).add(a); // oldest first
  }
  var romAdded = false;
  for (final r in kRomRegions) {
    final list = byRegion[r.id];
    if (list == null) continue;
    final rows = <List<String>>[];
    for (final m in r.moves) {
      final seen = [
        for (final a in list)
          if (a.row(m.name) case final row? when row.lDeg != null || row.rDeg != null)
            (a, row),
      ];
      if (seen.isEmpty) continue;
      final f = seen.first;
      final l = seen.last;
      final single = seen.length == 1;
      rows.add([
        m.name,
        single ? '-' : _pair(f.$2.lDeg, f.$2.rDeg),
        _pair(l.$2.lDeg, l.$2.rDeg),
        single
            ? '-'
            : '${_delta(f.$2.lDeg, l.$2.lDeg)} / ${_delta(f.$2.rDeg, l.$2.rDeg)}',
      ]);
    }
    if (rows.isEmpty) continue;
    if (!romAdded) {
      body.add(heading('Range of motion (degrees, left / right)'));
      romAdded = true;
    }
    final latest = list.last;
    body
      ..add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
          child: pw.Text(
            '${r.label}  (${list.length > 1 ? '${DentalFormat.date(list.first.date)} to ' : ''}${DentalFormat.date(latest.date)})',
            style: bold,
          ),
        ),
      )
      ..add(table(['Movement', 'First', 'Latest', 'Change'], rows));
  }

  // Current home program.
  if (program != null && program.items.isNotEmpty) {
    body
      ..add(
        heading(
          program.title.isEmpty
              ? 'Home exercise program'
              : 'Home exercise program: ${program.title}',
        ),
      )
      ..add(
        table(
          ['Exercise', 'Dose'],
          [
            for (final i in program.items) [i.name, i.doseText],
          ],
        ),
      );
  }

  // Session package.
  if (package != null) {
    body
      ..add(heading('Sessions'))
      ..add(
        pw.Text(
          '${package.name}: ${package.used.length} of ${package.total} used, '
          '${package.left} left'
          '${package.validUntil != null ? '. Valid until ${DentalFormat.date(package.validUntil!)}' : ''}.',
          style: small,
        ),
      );
  }

  // Blank space for the therapist.
  body
    ..add(heading('Therapist notes'))
    ..add(
      pw.Container(
        height: 90,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
      ),
    );

  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Text(
          'Physiotherapy progress report',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${patient.fullName}  |  Age ${patient.age}  |  '
          '${DentalFormat.date(DateTime.now())}'
          '${doctorName != null && doctorName.trim().isNotEmpty ? '  |  $doctorName' : ''}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        ...body,
      ],
    ),
  );
  return doc.save();
}
