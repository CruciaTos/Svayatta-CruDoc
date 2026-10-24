import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doctor_management_app/core/pdf/models/pdf_document_models.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/render/doc_renderer.dart';
import 'package:doctor_management_app/core/pdf/render/doc_samples.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocRenderer sample PDFs and edge cases', () {
    final outDir = Directory('build/doc_samples');

    setUpAll(() {
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
    });

    test('renders all builtin templates across all applicable kinds', () async {
      for (final t in builtinTemplates) {
        for (final kind in DocKind.values) {
          if (!t.appliesTo(kind)) continue;

          final data = docSampleData(kind);
          final ctx = docSampleContext(data);
          final bytes = await DocRenderer.render(t, ctx);

          expect(bytes, isNotEmpty);
          expect(String.fromCharCodes(bytes.take(4)), '%PDF');

          final safeId = t.id.replaceAll('.', '_');
          final file = File('${outDir.path}/${safeId}_${kind.name}.pdf');
          file.writeAsBytesSync(bytes);
        }
      }
    });

    test(
      'edge case: edge_60_items.pdf (60 bill lines + 3000 char notes -> 2+ pages)',
      () async {
        final classic = builtinById('builtin.classic');
        final sixtyItems = List.generate(
          60,
          (i) => PdfInvoiceLineItem(
            description: 'Medical Procedure Item #${i + 1}',
            quantity: 1,
            unitPrice: 100.0,
          ),
        );
        final longNotes = 'Clinical Note Paragraph ${'A' * 2900}';
        final sixtyData = PdfInvoiceDocumentData(
          patient: const PdfPatientSnapshot(fullName: 'Multi-Page Patient'),
          documentNumber: 'INV-26-27/0060',
          documentDate: DateTime(2026, 10, 24),
          items: sixtyItems,
          totals: const PdfMoneyTotals(
            subtotal: 6000.0,
            discountAmount: 0.0,
            taxPercent: 0.0,
            taxAmount: 0.0,
            grandTotal: 6000.0,
            paidAmount: 6000.0,
            balanceDue: 0.0,
            paymentMode: 'Card',
          ),
          notes: longNotes,
        );

        final bytes = await DocRenderer.render(
          classic,
          docSampleContext(sixtyData),
        );

        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');

        final pdfStr = String.fromCharCodes(bytes);
        final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr).length;
        expect(pageCount, greaterThanOrEqualTo(2));

        File('${outDir.path}/edge_60_items.pdf').writeAsBytesSync(bytes);
      },
    );

    test('edge case: edge_empty_clinic.pdf (empty clinic/doctor)', () async {
      final classic = builtinById('builtin.classic');
      final emptyCtx = DocContext(
        data: docSampleData(DocKind.invoice),
        clinic: const DocClinicInfo(),
        doctor: const DocDoctorInfo(uid: ''),
        sample: false,
      );

      final bytes = await DocRenderer.render(classic, emptyCtx);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      File('${outDir.path}/edge_empty_clinic.pdf').writeAsBytesSync(bytes);
    });

    test(
      'edge case: edge_cancelled.pdf (cancelled invoice watermark)',
      () async {
        final classic = builtinById('builtin.classic');
        final cancelledData = PdfInvoiceDocumentData(
          patient: const PdfPatientSnapshot(fullName: 'Cancelled Patient'),
          documentNumber: 'INV-26-27/9999',
          documentDate: DateTime(2026, 10, 24),
          items: const [
            PdfInvoiceLineItem(
              description: 'Cancelled Dental Procedure',
              quantity: 1,
              unitPrice: 1000.0,
            ),
          ],
          totals: const PdfMoneyTotals(
            subtotal: 1000.0,
            discountAmount: 0.0,
            taxPercent: 0.0,
            taxAmount: 0.0,
            grandTotal: 1000.0,
            paidAmount: 0.0,
            balanceDue: 1000.0,
            paymentMode: '',
          ),
          cancelled: true,
        );

        final bytes = await DocRenderer.render(
          classic,
          DocContext(
            data: cancelledData,
            clinic: const DocClinicInfo(name: 'Demo Clinic'),
            sample: false,
          ),
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        File('${outDir.path}/edge_cancelled.pdf').writeAsBytesSync(bytes);
      },
    );

    test('edge case: edge_gst.pdf (gstEnabled and multi-tier tax)', () async {
      final classic = builtinById('builtin.classic');
      final gstData = PdfInvoiceDocumentData(
        patient: const PdfPatientSnapshot(fullName: 'GST Patient'),
        documentNumber: 'INV-26-27/0055',
        documentDate: DateTime(2026, 10, 24),
        items: const [
          PdfInvoiceLineItem(
            description: 'Medicines (5% GST)',
            quantity: 2,
            unitPrice: 500.0,
            taxPercent: 5.0,
          ),
          PdfInvoiceLineItem(
            description: 'Cosmetic Procedure (18% GST)',
            quantity: 1,
            unitPrice: 2000.0,
            taxPercent: 18.0,
          ),
        ],
        totals: const PdfMoneyTotals(
          subtotal: 3000.0,
          discountAmount: 0.0,
          taxPercent: 0.0,
          taxAmount: 410.0,
          grandTotal: 3410.0,
          paidAmount: 3410.0,
          balanceDue: 0.0,
          paymentMode: 'Net Banking',
        ),
      );

      final gstClinic = const DocClinicInfo(
        name: 'CruDoc Advanced Healthcare',
        gstEnabled: true,
        gstin: '27AAAAA0000A1Z5',
      );

      final bytes = await DocRenderer.render(
        classic,
        DocContext(data: gstData, clinic: gstClinic, sample: false),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      File('${outDir.path}/edge_gst.pdf').writeAsBytesSync(bytes);
    });

    test('edge case: edge_long_names.pdf (long names & multiline address)', () async {
      final classic = builtinById('builtin.classic');
      final longClinic = const DocClinicInfo(
        name:
            'Super Speciality International Healthcare And Dental Research Institute Mumbai',
        address:
            'Tower A, Floor 14, Plot 99, North Central Medical Park\nOpposite Central Railway Junction, Near Metro Pillar 104\nAndheri East, Western Express Highway\nMumbai, Maharashtra 400069, India',
        tagline:
            'Delivering World-Class Excellence In Modern Clinical Diagnostic And Therapeutic Healthcare',
      );

      final bytes = await DocRenderer.render(
        classic,
        DocContext(
          data: docSampleData(DocKind.invoice),
          clinic: longClinic,
          sample: false,
        ),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      File('${outDir.path}/edge_long_names.pdf').writeAsBytesSync(bytes);
    });

    test(
      'edge case: edge_upi.pdf (upiId set, balance due -> QR shown)',
      () async {
        final classic = builtinById('builtin.classic');
        final upiData = PdfInvoiceDocumentData(
          patient: const PdfPatientSnapshot(fullName: 'UPI Patient'),
          documentNumber: 'INV-26-27/0077',
          documentDate: DateTime(2026, 10, 24),
          items: const [
            PdfInvoiceLineItem(
              description: 'Specialist Consultation',
              quantity: 1,
              unitPrice: 1500.0,
            ),
          ],
          totals: const PdfMoneyTotals(
            subtotal: 1500.0,
            discountAmount: 0.0,
            taxPercent: 0.0,
            taxAmount: 0.0,
            grandTotal: 1500.0,
            paidAmount: 500.0,
            balanceDue: 1000.0,
            paymentMode: 'Cash',
          ),
        );

        final upiClinic = const DocClinicInfo(
          name: 'CruDoc Polyclinic',
          upiId: 'crudoc@okaxis',
          upiName: 'CruDoc Healthcare',
        );

        final bytes = await DocRenderer.render(
          classic,
          DocContext(data: upiData, clinic: upiClinic, sample: false),
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        File('${outDir.path}/edge_upi.pdf').writeAsBytesSync(bytes);
      },
    );

    test(
      'edge case: edge_print_variant.pdf (background excluded when forPrint: true)',
      () async {
        final classic = builtinById('builtin.classic');
        final img1x1 = img.Image(width: 10, height: 10);
        img.fill(img1x1, color: img.ColorRgb8(200, 200, 200));
        final bgBytes = Uint8List.fromList(img.encodePng(img1x1));

        final bgTemplate = classic.copyWith(
          background: const DocBackground(
            path: 'templates/t1/bg.png',
            sha: 'dummy-sha',
            printOnPaper: false,
            opacity: 0.5,
          ),
        );

        final bgCtx = DocContext(
          data: docSampleData(DocKind.invoice),
          clinic: const DocClinicInfo(name: 'Background Clinic'),
          images: DocImages(background: bgBytes),
          sample: false,
        );

        final bytes = await DocRenderer.render(
          bgTemplate,
          bgCtx,
          forPrint: true,
        );
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        File('${outDir.path}/edge_print_variant.pdf').writeAsBytesSync(bytes);
      },
    );
  });
}
