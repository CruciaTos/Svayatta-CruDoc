import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pdf_document_models.dart';
import '../templates/doc_fields.dart';
import '../templates/doc_template.dart';
import 'doc_body.dart';
import 'doc_context.dart';
import 'pdf_text.dart';
import 'receipt_layout.dart';

class DocRenderer {
  DocRenderer(this.t, this.ctx, this.fonts, {this.forPrint = false});

  final DocTemplate t;
  final DocContext ctx;
  final PdfFonts fonts;

  /// True for the copy sent to the printer: a letterhead background that
  /// is already printed on the paper is left out.
  final bool forPrint;

  static const mm = PdfPageFormat.mm;

  static Future<Uint8List> render(
    DocTemplate t,
    DocContext ctx, {
    bool forPrint = false,
  }) async {
    final fonts = await PdfFonts.load();
    try {
      return await DocRenderer(t, ctx, fonts, forPrint: forPrint)._build();
    } on pw.TooManyPagesException {
      throw StateError('This document is too long to print (over 60 pages).');
    }
  }

  PdfColor color(String ref) => PdfColor.fromInt(t.style.resolve(ref));

  pw.TextStyle style(double pt, {bool bold = false, String color = 'text'}) =>
      pw.TextStyle(
        font: bold ? fonts.bold : fonts.regular,
        fontSize: pt,
        color: this.color(color),
      );

  Future<Uint8List> _build() async {
    final doc = pw.Document(
      title: ctx.data.previewTitle,
      author: ctx.doctor?.name.isNotEmpty == true
          ? ctx.doctor!.name
          : ctx.clinic.name,
      creator: 'CruDoc',
      subject: ctx.data.type.title,
    );
    if (t.paper.isRoll) {
      doc.addPage(ReceiptLayout(this).page());
    } else {
      final m = t.paper.margins;
      doc.addPage(
        pw.MultiPage(
          maxPages: 60,
          pageTheme: pw.PageTheme(
            pageFormat: t.paper.toPdf(),
            margin: pw.EdgeInsets.fromLTRB(
              m.left * mm,
              m.top * mm,
              m.right * mm,
              m.bottom * mm,
            ),
            theme: fonts.theme(),
            buildBackground: _background,
            buildForeground: _watermark,
          ),
          header: (c) => zone(DocZone.header, c.pageNumber, c.pagesCount),
          footer: (c) => zone(DocZone.footer, c.pageNumber, c.pagesCount),
          build: (c) => DocBody(this).build(),
        ),
      );
    }
    return doc.save();
  }

  pw.Widget zone(DocZone z, int page, int pages) {
    final heightMm = t.zoneHeight(z);
    if (heightMm <= 0) return pw.SizedBox();

    final noLogo = ctx.images.logo == null;
    final children = <pw.Widget>[];
    for (final b in t.blocks) {
      if (b.zone != z || b.hidden) continue;
      if (b.onlyWithLogo && noLogo) continue;

      final match = switch (b.showOn) {
        DocShowOn.all => true,
        DocShowOn.first => page == 1,
        DocShowOn.last => page == pages,
        DocShowOn.notFirst => page > 1,
      };
      if (!match) continue;

      final w = block(b, page, pages);
      if (w != null) {
        children.add(
          pw.Positioned(
            left: (b.x + (noLogo ? b.noLogoDx : 0)) * mm,
            top: (b.y + (noLogo ? b.noLogoDy : 0)) * mm,
            child: pw.SizedBox(
              width: b.w * mm,
              height: b.h * mm,
              // Transparency applies to every kind of block.
              child: b.opacity < 1
                  ? pw.Opacity(opacity: b.opacity.clamp(0.0, 1.0), child: w)
                  : w,
            ),
          ),
        );
      }
    }

    return pw.SizedBox(
      width: t.paper.contentWidthMm * mm,
      height: heightMm * mm,
      child: pw.Stack(children: children),
    );
  }

  pw.Widget? block(DocBlock b, int page, int pages) {
    return switch (b.type) {
      DocBlockType.field => () {
        final text = ctx.field(b.field, page: page, pages: pages);
        if (text.isEmpty) return null;
        return textBox(
          b,
          text,
          multiline: docFieldDef(b.field)?.multiline ?? false,
        );
      }(),
      DocBlockType.text => () {
        final text = ctx.fill(b.text, page: page, pages: pages);
        if (text.trim().isEmpty) return null;
        return textBox(b, text, multiline: true);
      }(),
      DocBlockType.image => () {
        final bytes = ctx.images.forBlock(b);
        if (bytes == null) return null;
        return pw.Image(
          pw.MemoryImage(bytes),
          fit: pw.BoxFit.contain,
          alignment: align(b),
        );
      }(),
      DocBlockType.line => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Container(
          width: b.w * mm,
          height: math.max(b.strokePt, 0.3),
          color: color(b.color),
        ),
      ),
      DocBlockType.box => pw.Container(
        decoration: pw.BoxDecoration(
          color: b.fill == 'none' ? null : color(b.fill),
          border: b.strokePt > 0
              ? pw.Border.all(color: color(b.color), width: b.strokePt)
              : null,
          borderRadius: b.radiusMm > 0
              ? pw.BorderRadius.circular(b.radiusMm * mm)
              : null,
        ),
      ),
      DocBlockType.qr => () {
        final data = b.qr == 'upi'
            ? ctx.upiUri()
            : ctx.fill(b.qr, page: page, pages: pages);
        if (data == null || data.trim().isEmpty) return null;
        return pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: data,
          drawText: false,
          color: color(b.color),
        );
      }(),
      DocBlockType.doctorList => () {
        // A solo practice has no member list: show the issuing doctor.
        final list = ctx.doctors.isNotEmpty ? ctx.doctors : [?ctx.doctor];
        if (list.isEmpty) return null;
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final doc in list.take(4))
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: switch (b.align) {
                    DocAlign.left => pw.CrossAxisAlignment.start,
                    DocAlign.center => pw.CrossAxisAlignment.center,
                    DocAlign.right => pw.CrossAxisAlignment.end,
                  },
                  children: [
                    if (doc.name.isNotEmpty)
                      pw.Text(
                        pdfSafe(doc.name),
                        style: style(b.fontPt, bold: true, color: b.color),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    if (doc.qualification.isNotEmpty)
                      pw.Text(
                        pdfSafe(doc.qualification),
                        style: style(b.fontPt - 1, color: 'muted'),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    if (doc.regNo.isNotEmpty)
                      pw.Text(
                        'Reg. No. ${pdfSafe(doc.regNo)}',
                        style: style(b.fontPt - 1.5, color: 'muted'),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                  ],
                ),
              ),
          ],
        );
      }(),
    };
  }

  pw.Widget textBox(DocBlock b, String text, {required bool multiline}) {
    final scriptImg = ctx.scriptImages[text.trim()];
    if (scriptImg != null) {
      final w = scriptImg.widthPt * (b.fontPt / 10);
      final h = scriptImg.heightPt * (b.fontPt / 10);
      return pw.Align(
        alignment: align(b),
        child: pw.FittedBox(
          fit: pw.BoxFit.contain,
          alignment: align(b),
          child: pw.Image(pw.MemoryImage(scriptImg.png), width: w, height: h),
        ),
      );
    }
    final st = style(b.fontPt, bold: b.bold, color: b.color);
    final lineMm = b.fontPt * 0.3528 * 1.3;
    final maxLines = (b.h / lineMm).floor();
    if (!multiline || maxLines <= 1) {
      return pw.Align(
        alignment: align(b),
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: align(b),
          child: pw.Text(text.replaceAll('\n', ', '), style: st, maxLines: 1),
        ),
      );
    }
    return pw.Align(
      alignment: align(b),
      child: pw.Text(
        text,
        style: st,
        textAlign: textAlign(b),
        maxLines: maxLines,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Alignment align(DocBlock b) => switch (b.align) {
    DocAlign.left => pw.Alignment.topLeft,
    DocAlign.center => pw.Alignment.topCenter,
    DocAlign.right => pw.Alignment.topRight,
  };

  pw.TextAlign textAlign(DocBlock b) => switch (b.align) {
    DocAlign.left => pw.TextAlign.left,
    DocAlign.center => pw.TextAlign.center,
    DocAlign.right => pw.TextAlign.right,
  };

  pw.Widget _background(pw.Context c) {
    final bytes = ctx.images.background;
    final bg = t.background;
    if (bytes == null || bg == null || (forPrint && !bg.printOnPaper)) {
      return pw.SizedBox();
    }
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Opacity(
        opacity: bg.opacity,
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
      ),
    );
  }

  pw.Widget _watermark(pw.Context c) {
    final isCancelled =
        ctx.data is PdfInvoiceDocumentData &&
        (ctx.data as PdfInvoiceDocumentData).cancelled;
    final word = ctx.sample ? 'SAMPLE' : (isCancelled ? 'CANCELLED' : null);
    if (word == null) return pw.SizedBox();

    // The PDF library ignores a colour's alpha for text; Opacity makes it faint.
    final wmColor = ctx.sample
        ? const PdfColor(0.4, 0.4, 0.4)
        : const PdfColor(0.85, 0.1, 0.1);

    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Center(
        child: pw.Opacity(
          opacity: ctx.sample ? 0.12 : 0.18,
          child: pw.Transform.rotate(
            angle: 0.6,
            child: pw.Text(
              word,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 78,
                color: wmColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
