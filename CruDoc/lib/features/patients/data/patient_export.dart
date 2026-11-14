import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/patient_import.dart';
import 'package:doctor_management_app/features/patients/data/xlsx_lite.dart';

enum ExportFormat {
  excel('Excel', 'xlsx'),
  csv('CSV', 'csv');

  const ExportFormat(this.label, this.extension);
  final String label;
  final String extension;
}

const exportHeaders = [
  'First name',
  'Last name',
  'Phone',
  'Gender',
  'Date of birth',
  'Email',
  'Diagnosis',
  'Notes',
  'Created on',
];

List<List<String>> patientExportRows(List<Patient> patients) {
  final date = DateFormat('dd/MM/yyyy');
  return [
    exportHeaders,
    for (final p in patients)
      [
        p.firstName,
        p.lastName,
        p.phone,
        p.gender,
        date.format(p.dateOfBirth),
        p.email,
        p.diagnosis.join(', '),
        p.notes,
        date.format(p.createdAt),
      ],
  ];
}

Uint8List encodeRows(List<List<String>> rows, ExportFormat format) =>
    format == ExportFormat.excel
    ? XlsxBook.write(rows, sheet: 'Patients')
    : csvBytes(rows);

String exportFileName(DateTime now, ExportFormat format) =>
    'CruDoc patients ${DateFormat('yyyy-MM-dd').format(now)}.${format.extension}';

bool get _isPhone =>
    !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS);

/// Hands a finished file to the person: the share sheet on a phone, a save
/// dialog on a computer or the web. Returns false when they backed out.
Future<bool> deliverFile(String fileName, Uint8List bytes) async {
  final isCsv = fileName.toLowerCase().endsWith('.csv');
  final mime = isCsv
      ? 'text/csv'
      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (_isPhone) {
    final dir = await getTemporaryDirectory();
    final file = io.File('${dir.path}${io.Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mime, name: fileName)]),
    );
    return true;
  }
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save file',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [isCsv ? 'csv' : 'xlsx'],
    bytes: bytes,
  );
  if (path == null) return false;
  if (!kIsWeb) {
    final f = io.File(path);
    if (!f.existsSync() || f.lengthSync() == 0) await f.writeAsBytes(bytes);
  }
  return true;
}
