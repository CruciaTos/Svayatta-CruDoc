import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class PaddleOcrTreatmentItem {
  final String name;
  final double price;

  PaddleOcrTreatmentItem({required this.name, required this.price});

  factory PaddleOcrTreatmentItem.fromJson(Map<String, dynamic> json) {
    return PaddleOcrTreatmentItem(
      name: json['name'] as String? ?? '',
      price: (json['price'] as num? ?? 0.0).toDouble(),
    );
  }
}

class PaddleOcrMedicineItem {
  final String name;
  final String dosage;
  final double price;

  PaddleOcrMedicineItem({
    required this.name,
    required this.dosage,
    required this.price,
  });

  factory PaddleOcrMedicineItem.fromJson(Map<String, dynamic> json) {
    return PaddleOcrMedicineItem(
      name: json['name'] as String? ?? '',
      dosage: json['dosage'] as String? ?? '',
      price: (json['price'] as num? ?? 0.0).toDouble(),
    );
  }
}

class PaddleOcrResult {
  final String? patientName;
  final List<PaddleOcrTreatmentItem> treatments;
  final List<PaddleOcrMedicineItem> medicines;
  final String? clinicalNotes;
  final String? rawText;

  PaddleOcrResult({
    this.patientName,
    required this.treatments,
    required this.medicines,
    this.clinicalNotes,
    this.rawText,
  });

  factory PaddleOcrResult.fromJson(Map<String, dynamic> json) {
    return PaddleOcrResult(
      patientName: json['patientName'] as String?,
      treatments: (json['treatments'] as List? ?? [])
          .map((t) => PaddleOcrTreatmentItem.fromJson(t as Map<String, dynamic>))
          .toList(),
      medicines: (json['medicines'] as List? ?? [])
          .map((m) => PaddleOcrMedicineItem.fromJson(m as Map<String, dynamic>))
          .toList(),
      clinicalNotes: json['clinicalNotes'] as String?,
      rawText: json['rawText'] as String?,
    );
  }

  bool get isEmpty =>
      (patientName == null || patientName!.isEmpty) &&
      treatments.isEmpty &&
      medicines.isEmpty &&
      (clinicalNotes == null || clinicalNotes!.isEmpty);
}

class PaddleOcrService {
  PaddleOcrService._();
  static final PaddleOcrService instance = PaddleOcrService._();

  static const String serverUrl = 'http://10.0.2.2:5000/ocr';

  Future<PaddleOcrResult> scanInvoice(File imageFile) async {
    final bool isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      return _scanDesktop(imageFile);
    } else {
      return _scanMobile(imageFile);
    }
  }

  Future<PaddleOcrResult> _scanDesktop(File imageFile) async {
    try {
      String projectRoot = Directory.current.path;
      if (p.basename(projectRoot) == 'CruDoc') {
        projectRoot = p.dirname(projectRoot);
      }

      final String pythonPath =
          p.join(projectRoot, '.venv', 'Scripts', 'python.exe');
      final String scriptPath = p.join(projectRoot, 'ocr_backend.py');

      if (!File(pythonPath).existsSync()) {
        throw Exception(
            "Python virtual environment not found at $pythonPath. Please configure the environment.");
      }
      if (!File(scriptPath).existsSync()) {
        throw Exception("OCR backend script not found at $scriptPath.");
      }

      final ProcessResult result = await Process.run(
        pythonPath,
        [scriptPath, imageFile.path],
        workingDirectory: projectRoot,
      );

      if (result.exitCode != 0) {
        throw Exception("Python OCR script failed: ${result.stderr}");
      }

      final String output = result.stdout as String;
      final Map<String, dynamic> jsonMap =
          jsonDecode(output) as Map<String, dynamic>;
      return PaddleOcrResult.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Desktop OCR Error: $e");
      rethrow;
    }
  }

  Future<PaddleOcrResult> _scanMobile(File imageFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));

      final response = await request.send();
      if (response.statusCode != 200) {
        throw Exception("Server returned status code ${response.statusCode}");
      }

      final responseBody = await response.stream.bytesToString();
      final Map<String, dynamic> jsonMap =
          jsonDecode(responseBody) as Map<String, dynamic>;
      return PaddleOcrResult.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Mobile OCR Error: $e");
      rethrow;
    }
  }
}
