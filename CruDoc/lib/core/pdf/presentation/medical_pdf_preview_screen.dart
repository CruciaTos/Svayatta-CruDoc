import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/pdf_document_models.dart';
import '../services/generated_document_sync.dart';
import '../services/medical_pdf_service.dart';

class MedicalPdfPreviewScreen extends StatefulWidget {
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
  State<MedicalPdfPreviewScreen> createState() =>
      _MedicalPdfPreviewScreenState();
}

class _MedicalPdfPreviewScreenState extends State<MedicalPdfPreviewScreen> {
  /// Built once, so the preview re-laying itself out never uploads twice.
  late final Future<Uint8List> _pdf = _buildPdf();

  Future<Uint8List> _buildPdf() async {
    final bytes = await widget.pdfService.generate(widget.documentData);
    // Copied to the cloud in the background; never holds up the preview.
    unawaited(
      GeneratedDocumentSync.enqueue(data: widget.documentData, bytes: bytes),
    );
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentData.previewTitle),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: PdfPreview(
        build: (_) => _pdf,
        pdfFileName: widget.documentData.fileName,
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
                const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 42,
                  color: Color(0xFFEF4444),
                ),
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
}
