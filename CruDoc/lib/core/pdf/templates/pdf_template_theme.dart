import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';

class PdfTemplateTheme {
  const PdfTemplateTheme({
    required this.name,
    required this.accentColor,
    required this.secondaryAccentColor,
    this.darkTextColor = const PdfColor.fromInt(0xFF0F172A),
    this.bodyTextColor = const PdfColor.fromInt(0xFF334155),
    this.mutedTextColor = const PdfColor.fromInt(0xFF64748B),
    this.borderColor = const PdfColor.fromInt(0xFFE2E8F0),
    this.softBackgroundColor = const PdfColor.fromInt(0xFFF8FAFC),
  });

  final String name;
  final PdfColor accentColor;
  final PdfColor secondaryAccentColor;
  final PdfColor darkTextColor;
  final PdfColor bodyTextColor;
  final PdfColor mutedTextColor;
  final PdfColor borderColor;
  final PdfColor softBackgroundColor;

  pw.TextStyle get titleStyle => pw.TextStyle(
        color: darkTextColor,
        fontSize: 17,
        fontWeight: pw.FontWeight.bold,
      );

  pw.TextStyle get sectionTitleStyle => pw.TextStyle(
        color: darkTextColor,
        fontSize: 11.5,
        fontWeight: pw.FontWeight.bold,
      );

  pw.TextStyle get bodyStyle => pw.TextStyle(
        color: bodyTextColor,
        fontSize: 9.5,
      );

  pw.TextStyle get mutedStyle => pw.TextStyle(
        color: mutedTextColor,
        fontSize: 8.5,
      );

  PdfTemplateTheme forDocument(PdfMedicalDocumentType type) {
    return switch (type) {
      PdfMedicalDocumentType.invoice => const PdfTemplateTheme(
          name: 'Clean Letterhead - Invoice',
          accentColor: PdfColor.fromInt(0xFF0D9488),
          secondaryAccentColor: PdfColor.fromInt(0xFF1E78FF),
        ),
      PdfMedicalDocumentType.prescription => const PdfTemplateTheme(
          name: 'Clean Letterhead - Prescription',
          accentColor: PdfColor.fromInt(0xFF8B5CF6),
          secondaryAccentColor: PdfColor.fromInt(0xFF1E78FF),
        ),
      PdfMedicalDocumentType.report => const PdfTemplateTheme(
          name: 'Clean Letterhead - Report',
          accentColor: PdfColor.fromInt(0xFF1E78FF),
          secondaryAccentColor: PdfColor.fromInt(0xFF475569),
        ),
    };
  }
}

class CleanLetterheadPdfTheme extends PdfTemplateTheme {
  const CleanLetterheadPdfTheme({
    super.name = 'Clean Letterhead',
    super.accentColor = const PdfColor.fromInt(0xFF1E78FF),
    super.secondaryAccentColor = const PdfColor.fromInt(0xFF0D9488),
  });
}