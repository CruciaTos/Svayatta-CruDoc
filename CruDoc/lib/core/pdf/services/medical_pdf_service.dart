import 'dart:typed_data';

import '../data/doc_repository.dart';
import '../models/pdf_document_models.dart';
import '../render/doc_context.dart';
import '../render/doc_context_builder.dart';
import '../render/doc_renderer.dart';
import '../templates/doc_template.dart';

class RenderedDoc {
  const RenderedDoc({
    required this.bytes,
    required this.template,
    required this.warnings,
  });

  final Uint8List bytes;
  final DocTemplate template;
  final List<DocWarning> warnings;
}

class MedicalPdfService {
  const MedicalPdfService();

  Future<RenderedDoc> render(
    PdfMedicalDocumentData data, {
    DocTemplate? template,
    bool forPrint = false,
    bool sample = false,
  }) async {
    final t =
        template ??
        await DocRepository.instance.resolveTemplate(
          data.kind,
          issuingDoctorUid: data.issuingDoctorUid,
          explicitId: data.templateId,
        );
    final ctx = await buildDocContext(data: data, template: t, sample: sample);
    final bytes = await DocRenderer.render(t, ctx, forPrint: forPrint);
    return RenderedDoc(bytes: bytes, template: t, warnings: ctx.warnings);
  }

  /// Kept for older callers.
  Future<Uint8List> generate(PdfMedicalDocumentData data) async =>
      (await render(data)).bytes;
}
