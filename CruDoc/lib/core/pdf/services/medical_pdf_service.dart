import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import '../templates/letterhead_pdf_template.dart';
import '../templates/medical_document_pdf_builder.dart';
import '../templates/pdf_template_theme.dart';
import 'pdf_asset_loader.dart';

class MedicalPdfService {
  const MedicalPdfService({
    this.assetLoader = const PdfAssetLoader(),
    this.baseTheme = const CleanLetterheadPdfTheme(),
  });

  final PdfAssetLoader assetLoader;
  final PdfTemplateTheme baseTheme;

  Future<Uint8List> generate(PdfMedicalDocumentData data) async {
    final logoBytes = await assetLoader.loadRemoteBytes(data.letterheadConfig.logoUrl);
    final theme = baseTheme.forDocument(data.type);
    final letterheadTemplate = LetterheadPdfTemplate(
      config: data.letterheadConfig,
      theme: theme,
      logoBytes: logoBytes,
    );
    final bodyBuilder = MedicalDocumentPdfBuilder(template: letterheadTemplate);
    final document = pw.Document(
      title: data.previewTitle,
      author: data.letterheadConfig.doctorName,
      creator: 'CruDoc Practice Management System',
      subject: data.type.title,
    );

    document.addPage(
      letterheadTemplate.page(
        data: data,
        build: (_) => bodyBuilder.build(data),
      ),
    );

    return document.save();
  }
}