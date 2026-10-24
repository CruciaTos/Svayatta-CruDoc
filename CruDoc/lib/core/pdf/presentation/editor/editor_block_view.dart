import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';

const Map<String, String> kDocFieldLabels = {
  'clinic.name': 'Clinic name',
  'clinic.tagline': 'Tagline',
  'clinic.address': 'Clinic address',
  'clinic.phone': 'Clinic phone',
  'clinic.email': 'Clinic email',
  'clinic.website': 'Clinic website',
  'clinic.timings': 'Clinic timings',
  'clinic.regNo': 'Clinic reg. no.',
  'clinic.gstin': 'GSTIN',
  'clinic.contactLine': 'Contact line',
  'clinic.addressContact': 'Address & contact',
  'doctor.name': 'Doctor name',
  'doctor.qualification': 'Doctor qualification',
  'doctor.specialty': 'Doctor specialty',
  'doctor.regNo': 'Doctor reg. no.',
  'doctor.nameQual': 'Doctor name & qualification',
  'doctor.specReg': 'Doctor specialty & reg.',
  'doctor.phone': 'Doctor phone',
  'doctor.email': 'Doctor email',
  'doc.title': 'Document title',
  'doc.number': 'Document number',
  'doc.numberLine': 'Document number line',
  'doc.date': 'Document date',
  'doc.dateLine': 'Document date line',
  'doc.status': 'Payment status',
  'patient.name': 'Patient name',
  'patient.ageSex': 'Patient age & gender',
  'patient.phone': 'Patient phone',
  'patient.line': 'Patient summary line',
  'page.number': 'Page number',
  'footer.text': 'Footer note',
};

String docFieldLabel(String key) => kDocFieldLabels[key] ?? key;

class EditorBlockView extends StatelessWidget {
  const EditorBlockView({
    super.key,
    required this.block,
    required this.template,
    required this.previewCtx,
    required this.pxPerMm,
  });

  final DocBlock block;
  final DocTemplate template;
  final DocContext previewCtx;
  final double pxPerMm;

  TextAlign get _textAlign => switch (block.align) {
    DocAlign.left => TextAlign.left,
    DocAlign.center => TextAlign.center,
    DocAlign.right => TextAlign.right,
  };

  Alignment get _alignment => switch (block.align) {
    DocAlign.left => Alignment.centerLeft,
    DocAlign.center => Alignment.center,
    DocAlign.right => Alignment.centerRight,
  };

  @override
  Widget build(BuildContext context) {
    final style = template.style;
    final textColor = Color(style.resolve(block.color));
    final fontSize = block.fontPt * 0.3528 * pxPerMm;

    final textStyle = TextStyle(
      fontFamily: 'Geist',
      fontSize: fontSize,
      fontWeight: block.bold ? FontWeight.bold : FontWeight.normal,
      color: textColor,
      height: 1.25,
    );

    return switch (block.type) {
      DocBlockType.field => _buildField(textStyle),
      DocBlockType.text => _buildText(textStyle),
      DocBlockType.image => _buildImage(),
      DocBlockType.line => _buildLine(),
      DocBlockType.box => _buildBox(),
      DocBlockType.qr => _buildQr(),
      DocBlockType.doctorList => _buildDoctorList(textStyle),
    };
  }

  Widget _buildField(TextStyle style) {
    final val = previewCtx.field(block.field);
    final hasVal = val.trim().isNotEmpty;
    final text = hasVal ? val : '[${docFieldLabel(block.field)}]';
    final effectiveStyle = hasVal
        ? style
        : style.copyWith(
            color: const Color(0xFF94A3B8),
            fontStyle: FontStyle.italic,
          );

    final isMultiLine =
        block.field == 'clinic.address' ||
        block.field == 'clinic.timings' ||
        block.field == 'footer.text' ||
        block.h > 12;

    if (isMultiLine) {
      return Align(
        alignment: _alignment,
        child: Text(
          text,
          textAlign: _textAlign,
          style: effectiveStyle,
          maxLines: math.max(1, (block.h / 4).floor()),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Align(
      alignment: _alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: _alignment,
        child: Text(
          text,
          textAlign: _textAlign,
          style: effectiveStyle,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _buildText(TextStyle style) {
    final filled = previewCtx.fill(block.text);
    final text = filled.trim().isNotEmpty
        ? filled
        : (block.text.isNotEmpty ? block.text : '[Text block]');
    final isPlaceholder = filled.trim().isEmpty;
    final effectiveStyle = isPlaceholder
        ? style.copyWith(
            color: const Color(0xFF94A3B8),
            fontStyle: FontStyle.italic,
          )
        : style;

    return Align(
      alignment: _alignment,
      child: Text(
        text,
        textAlign: _textAlign,
        style: effectiveStyle,
        maxLines: math.max(1, (block.h / 3.5).floor()),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildImage() {
    final bytes = previewCtx.images.forBlock(block);
    if (bytes != null && bytes.isNotEmpty) {
      return Opacity(
        opacity: block.opacity.clamp(0.0, 1.0),
        child: Image.memory(bytes, fit: BoxFit.contain, alignment: _alignment),
      );
    }

    final roleLabel = switch (block.imageRole) {
      DocImageRole.logo => 'Logo',
      DocImageRole.signature => 'Signature',
      DocImageRole.stamp => 'Personal Stamp',
      DocImageRole.clinicStamp => 'Clinic Stamp',
      DocImageRole.custom => 'Picture',
    };

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        roleLabel,
        style: TextStyle(
          fontSize: math.max(8.0, 8.0 * (pxPerMm / 3.0)),
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLine() {
    final color = Color(template.style.resolve(block.color));
    final thickness = math.max(1.0, block.strokePt * 0.3528 * pxPerMm);
    return Align(
      alignment: Alignment.center,
      child: Container(height: thickness, color: color),
    );
  }

  Widget _buildBox() {
    final fillColor = Color(template.style.resolve(block.fill));
    final borderColor = Color(template.style.resolve(block.color));
    final strokeWidth = block.strokePt * 0.3528 * pxPerMm;
    final radius = block.radiusMm * pxPerMm;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
        border: strokeWidth > 0
            ? Border.all(color: borderColor, width: strokeWidth)
            : null,
      ),
    );
  }

  Widget _buildQr() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Center(
        child: Icon(Icons.qr_code_2, color: Color(0xFF0F172A), size: 24),
      ),
    );
  }

  Widget _buildDoctorList(TextStyle style) {
    final docs = previewCtx.doctors;
    if (docs.isEmpty) {
      return Align(
        alignment: _alignment,
        child: Text(
          '[All clinic doctors list]',
          style: style.copyWith(
            color: const Color(0xFF94A3B8),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final cols = math.min(4, math.max(1, docs.length));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i < docs.length) ...[
                  Text(
                    docs[i].name,
                    style: style.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (docs[i].qualification.isNotEmpty)
                    Text(
                      docs[i].qualification,
                      style: style.copyWith(
                        fontSize: math.max(6.0, style.fontSize! * 0.85),
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (docs[i].regNo.isNotEmpty)
                    Text(
                      'Reg. No. ${docs[i].regNo}',
                      style: style.copyWith(
                        fontSize: math.max(6.0, style.fontSize! * 0.8),
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
