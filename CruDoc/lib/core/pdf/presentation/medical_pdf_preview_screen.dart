import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/pdf_document_models.dart';
import '../services/medical_pdf_service.dart';

class MedicalPdfPreviewScreen extends StatelessWidget {
  const MedicalPdfPreviewScreen({
    super.key,
    required this.documentData,
    this.pdfService = const MedicalPdfService(),
  });

  final PdfMedicalDocumentData documentData;
  final MedicalPdfService pdfService;

  static Future<void> open(
    BuildContext context, {
    required PdfMedicalDocumentData documentData,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicalPdfPreviewScreen(documentData: documentData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(documentData.previewTitle),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
      ),
      body: PdfPreview(
        build: (_) => _buildPdf(),
        pdfFileName: documentData.fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        useActions: true,
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf_rounded, size: 42, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                const Text(
                  'Unable to generate PDF preview',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildPdf() => pdfService.generate(documentData);
}