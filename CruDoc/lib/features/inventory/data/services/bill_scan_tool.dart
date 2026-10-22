import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/inventory/domain/bill_import.dart';

/// Scanning isn't set up on this computer. [message] says what to do and
/// is fit to show.
class OcrSetupException implements Exception {
  const OcrSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads a supplier's purchase bill with tool/paddle_ocr_test/bill_scan.py:
/// Sarvam Vision when online, PaddleOCR on this computer when not. Runs
/// in the venv beside the script (tool/paddle_ocr_test/.venv). Desktop
/// only.
abstract final class BillScanTool {
  static const _folder = 'paddle_ocr_test';
  static const _script = 'bill_scan.py';

  /// Sarvam gives up after 60 s; PaddleOCR then takes 15–60 s.
  static const timeout = Duration(minutes: 4);

  static Future<ScannedBill> scan(String imagePath) async {
    final dir = toolDir();
    if (dir == null) {
      throw const OcrSetupException(
        "Bill scanning isn't set up: tool/paddle_ocr_test is missing.",
      );
    }
    final python = Platform.isWindows
        ? p.join(dir, '.venv', 'Scripts', 'python.exe')
        : p.join(dir, '.venv', 'bin', 'python');
    if (!File(python).existsSync()) {
      throw const OcrSetupException(
        "Bill scanning isn't set up: install PaddleOCR in "
        'tool/paddle_ocr_test/.venv.',
      );
    }

    final process = await Process.start(python, [
      _script,
      '--json',
      imagePath,
    ], workingDirectory: dir);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw TimeoutException(
        'Reading the bill took over ${timeout.inMinutes} min',
      );
    }
    final log = (await err).trim();
    final bill = parseOutput(await out);
    if (bill == null) {
      throw Exception(
        'bill_scan.py failed (exit $code): ${log.split('\n').last}',
      );
    }
    debugPrint(
      '[BillScanTool] ${bill.source}: ${bill.items.length} items'
      '${bill.note == null ? '' : ' (${bill.note})'}',
    );
    return bill;
  }

  /// The bill in the script's `--json` reply, or null when there is no
  /// reply. Throws its `error` when it sent one.
  @visibleForTesting
  static ScannedBill? parseOutput(String stdout) {
    final reply = stdout
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.startsWith('{'), orElse: () => '');
    if (reply.isEmpty) return null;
    final json = jsonDecode(reply) as Map<String, dynamic>;
    if (json['error'] case final String error) throw Exception(error);
    return ScannedBill.fromJson(json);
  }

  /// tool/paddle_ocr_test: under the working directory with `flutter
  /// run`, else up from the built app in build/windows/x64/runner.
  static String? toolDir() {
    String? at(Directory d) {
      final c = p.join(d.path, 'tool', _folder);
      return File(p.join(c, _script)).existsSync() ? c : null;
    }

    if (at(Directory.current) case final found?) return found;
    var d = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 7; i++) {
      if (at(d) case final found?) return found;
      d = d.parent;
    }
    return null;
  }
}
