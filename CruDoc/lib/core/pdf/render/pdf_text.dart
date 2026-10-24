import 'dart:io' as io;

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

/// Geist, the app font, embedded in every PDF. It has the ₹ sign; the
/// PDF library's built-in Helvetica does not.
class PdfFonts {
  PdfFonts._(this.regular, this.medium, this.bold);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;

  static PdfFonts? _cached;

  static Future<PdfFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    Future<pw.Font> font(String file) async {
      try {
        return pw.Font.ttf(await rootBundle.load('assets/fonts/Geist/$file'));
      } catch (_) {
        final f = io.File('assets/fonts/Geist/$file');
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          return pw.Font.ttf(bytes.buffer.asByteData());
        }
        rethrow;
      }
    }

    return _cached = PdfFonts._(
      await font('Geist-Regular.ttf'),
      await font('Geist-Medium.ttf'),
      await font('Geist-Bold.ttf'),
    );
  }

  pw.ThemeData theme() => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );
}

final _undrawable = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FE0F}\u{200D}]',
  unicode: true,
);

/// Text the PDF font can draw: emoji and joiners removed, tabs as spaces.
String pdfSafe(String? s) =>
    (s ?? '').replaceAll(_undrawable, '').replaceAll('\t', ' ').trim();

/// True when [s] has letters of scripts Geist cannot draw (Hebrew/Arabic
/// to Sinhala, which covers Devanagari, Gujarati, Tamil, Telugu, Kannada…).
bool needsScriptFallback(String s) =>
    s.runes.any((r) => r >= 0x0590 && r <= 0x0DFF);

/// Rupees → whole paise.
int toPaise(num rupees) => (rupees * 100).round();

final _inr2 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _inr0 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// "₹1,25,000" for whole rupees, "₹1,250.50" otherwise.
String formatPaise(int paise) =>
    paise % 100 == 0 ? _inr0.format(paise ~/ 100) : _inr2.format(paise / 100);

/// "24 Oct 2026".
String formatDocDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

/// Indian financial year of [d]: April 2026 – March 2027 → "26-27".
String financialYear(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  String two(int y) => (y % 100).toString().padLeft(2, '0');
  return '${two(start)}-${two(start + 1)}';
}

const _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];
const _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _below100(int n) => n < 20
    ? _ones[n]
    : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';

String _below1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _below100(r)].join(' ');
}

/// Indian system: 1,23,45,678 → "One Crore Twenty Three Lakh Forty Five
/// Thousand Six Hundred Seventy Eight".
String _indianWords(int n) {
  if (n == 0) return 'Zero';
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final rest = n % 1000;
  return [
    if (crore > 0) '${_indianWords(crore)} Crore',
    if (lakh > 0) '${_below100(lakh)} Lakh',
    if (thousand > 0) '${_below100(thousand)} Thousand',
    if (rest > 0) _below1000(rest),
  ].join(' ');
}

/// "Rupees One Thousand Two Hundred Fifty and Fifty Paise Only".
String rupeesInWords(int paise) {
  final p = paise.abs();
  final words = StringBuffer(paise < 0 ? 'Minus ' : '')
    ..write('Rupees ${_indianWords(p ~/ 100)}');
  if (p % 100 > 0) words.write(' and ${_below100(p % 100)} Paise');
  words.write(' Only');
  return words.toString();
}
