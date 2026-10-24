import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_block_view.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_body_sections.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const List<int> kDocPalette = [
  0xFF0D9488, // Teal (CruDoc default)
  0xFF2563EB, // Royal Blue
  0xFF0284C7, // Sky Blue
  0xFF059669, // Emerald
  0xFF7C3AED, // Violet
  0xFFE11D48, // Rose
  0xFFD97706, // Amber
  0xFF334155, // Slate
];

// =============================================================================
// 1. ELEMENTS PANEL
// =============================================================================

class EditorElementsPanel extends StatelessWidget {
  const EditorElementsPanel({super.key, required this.controller});

  final TemplateEditorController controller;

  void _addBlock(DocBlock b) {
    controller.add(b);
  }

  Future<void> _uploadCustomImage(BuildContext context) async {
    try {
      Uint8List? raw;
      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        final res = await FilePicker.pickFiles(
          dialogTitle: 'Select image',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          withData: true,
        );
        if (res != null && res.files.isNotEmpty) {
          final f = res.files.first;
          raw =
              f.bytes ??
              (f.path != null ? await File(f.path!).readAsBytes() : null);
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
        if (picked != null) raw = await picked.readAsBytes();
      }
      if (raw == null) return;

      final png = await prepareBrandingImage(raw, maxSide: 2000);
      final sha = sha256Hex(png);
      final tenant = DocRepository.instance.tenantOrNull;
      if (tenant == null) throw StateError('No active clinic');

      final stored = await MedicalStorageService.instance
          .uploadClinicTemplateImage(
            doctorId: tenant,
            templateId: controller.template.id.isNotEmpty
                ? controller.template.id
                : 'new_${DateTime.now().millisecondsSinceEpoch}',
            name: sha,
            png: png,
          );
      await BrandingImageStore.instance.remember(sha, png);

      _addBlock(
        DocBlock(
          id: 'b${DateTime.now().microsecondsSinceEpoch}',
          type: DocBlockType.image,
          imageRole: DocImageRole.custom,
          imagePath: stored.path,
          imageSha: sha,
          w: 30,
          h: 30,
          x: 0,
          y: 0,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = controller.template;
    final blocks = t.blocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with + Add button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Elements (${blocks.length})',
                style: CruType.headline.tint(c.label),
              ),
              PopupMenuButton<String>(
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: c.accentText),
                    const SizedBox(width: 4),
                    Text('Add', style: CruType.subhead.w600.tint(c.accentText)),
                  ],
                ),
                tooltip: 'Add element',
                onSelected: (val) {
                  final cw = t.paper.contentWidthMm;
                  if (val.startsWith('field:')) {
                    final key = val.substring(6);
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.field,
                        field: key,
                        w: 60,
                        h: 6,
                        x: 0,
                        y: 0,
                        fontPt: 10,
                      ),
                    );
                  } else if (val == 'text') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.text,
                        text: 'Sample text {{doc.date}}',
                        w: 80,
                        h: 8,
                        x: 0,
                        y: 0,
                      ),
                    );
                  } else if (val.startsWith('image:')) {
                    final role = switch (val.substring(6)) {
                      'logo' => DocImageRole.logo,
                      'signature' => DocImageRole.signature,
                      'stamp' => DocImageRole.stamp,
                      'clinicStamp' => DocImageRole.clinicStamp,
                      _ => DocImageRole.custom,
                    };
                    final sz = switch (role) {
                      DocImageRole.logo => const Size(22, 22),
                      DocImageRole.signature => const Size(40, 16),
                      DocImageRole.stamp => const Size(24, 24),
                      DocImageRole.clinicStamp => const Size(24, 24),
                      DocImageRole.custom => const Size(30, 30),
                    };
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.image,
                        imageRole: role,
                        w: sz.width,
                        h: sz.height,
                        x: 0,
                        y: 0,
                      ),
                    );
                  } else if (val == 'image_custom') {
                    _uploadCustomImage(context);
                  } else if (val == 'shape_line') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.line,
                        w: cw,
                        h: 1,
                        x: 0,
                        y: 0,
                        strokePt: 1,
                        color: 'border',
                      ),
                    );
                  } else if (val == 'shape_box') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.box,
                        w: 40,
                        h: 20,
                        x: 0,
                        y: 0,
                        strokePt: 1,
                        color: 'border',
                        fill: 'soft',
                      ),
                    );
                  } else if (val == 'qr_upi') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.qr,
                        qr: 'upi',
                        w: 24,
                        h: 24,
                        x: 0,
                        y: 0,
                      ),
                    );
                  } else if (val == 'qr_link') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.qr,
                        qr: 'https://crudoc.com',
                        w: 24,
                        h: 24,
                        x: 0,
                        y: 0,
                      ),
                    );
                  } else if (val == 'doctorList') {
                    _addBlock(
                      DocBlock(
                        id: '',
                        type: DocBlockType.doctorList,
                        w: cw,
                        h: 18,
                        x: 0,
                        y: 0,
                      ),
                    );
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'CLINIC',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.name',
                    child: Text('Clinic name'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.tagline',
                    child: Text('Clinic tagline'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.address',
                    child: Text('Clinic address'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.phone',
                    child: Text('Clinic phone'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.email',
                    child: Text('Clinic email'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.contactLine',
                    child: Text('Contact line'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.regNo',
                    child: Text('Clinic registration no.'),
                  ),
                  const PopupMenuItem(
                    value: 'field:clinic.gstin',
                    child: Text('GSTIN'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'DOCTOR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.name',
                    child: Text('Doctor name'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.qualification',
                    child: Text('Doctor qualification'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.specialty',
                    child: Text('Doctor specialty'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.regNo',
                    child: Text('Doctor reg. no.'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.nameQual',
                    child: Text('Doctor name & qualification'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doctor.specReg',
                    child: Text('Doctor specialty & reg.'),
                  ),
                  const PopupMenuItem(
                    value: 'doctorList',
                    child: Text('All clinic doctors'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'DOCUMENT & PATIENT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'field:doc.title',
                    child: Text('Document title'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doc.numberLine',
                    child: Text('Document number'),
                  ),
                  const PopupMenuItem(
                    value: 'field:doc.dateLine',
                    child: Text('Document date'),
                  ),
                  const PopupMenuItem(
                    value: 'field:patient.name',
                    child: Text('Patient name'),
                  ),
                  const PopupMenuItem(
                    value: 'field:patient.line',
                    child: Text('Patient summary line'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'IMAGES & SHAPES',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'image:logo',
                    child: Text('Clinic logo'),
                  ),
                  const PopupMenuItem(
                    value: 'image:signature',
                    child: Text('Signature'),
                  ),
                  const PopupMenuItem(
                    value: 'image:stamp',
                    child: Text('Personal stamp'),
                  ),
                  const PopupMenuItem(
                    value: 'image:clinicStamp',
                    child: Text('Clinic stamp'),
                  ),
                  const PopupMenuItem(
                    value: 'image_custom',
                    child: Text('Upload picture…'),
                  ),
                  const PopupMenuItem(
                    value: 'shape_line',
                    child: Text('Horizontal line'),
                  ),
                  const PopupMenuItem(
                    value: 'shape_box',
                    child: Text('Rectangle box'),
                  ),
                  const PopupMenuItem(
                    value: 'qr_upi',
                    child: Text('UPI QR Code'),
                  ),
                  const PopupMenuItem(
                    value: 'qr_link',
                    child: Text('Web Link QR'),
                  ),
                  const PopupMenuItem(
                    value: 'text',
                    child: Text('Custom text block'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Block list
        Expanded(
          child: ListView.builder(
            itemCount: blocks.length,
            itemBuilder: (context, i) {
              final b = blocks[i];
              final isSelected = controller.selectedId == b.id;

              final title = switch (b.type) {
                DocBlockType.field => docFieldLabel(b.field),
                DocBlockType.text => b.text.isNotEmpty ? b.text : 'Custom text',
                DocBlockType.image => switch (b.imageRole) {
                  DocImageRole.logo => 'Logo',
                  DocImageRole.signature => 'Signature',
                  DocImageRole.stamp => 'Personal stamp',
                  DocImageRole.clinicStamp => 'Clinic stamp',
                  DocImageRole.custom => 'Picture',
                },
                DocBlockType.line => 'Line (${b.w.toStringAsFixed(0)} mm)',
                DocBlockType.box =>
                  'Box (${b.w.toStringAsFixed(0)} × ${b.h.toStringAsFixed(0)} mm)',
                DocBlockType.qr => b.qr == 'upi' ? 'UPI QR' : 'Link QR',
                DocBlockType.doctorList => 'All doctors',
              };

              final iconData = switch (b.type) {
                DocBlockType.field => Icons.short_text,
                DocBlockType.text => Icons.text_fields,
                DocBlockType.image => Icons.image,
                DocBlockType.line => Icons.horizontal_rule,
                DocBlockType.box => Icons.crop_square,
                DocBlockType.qr => Icons.qr_code,
                DocBlockType.doctorList => Icons.groups,
              };

              return InkWell(
                onTap: () => controller.select(b.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  color: isSelected ? c.accentWash : Colors.transparent,
                  child: Row(
                    children: [
                      Icon(
                        iconData,
                        size: 16,
                        color: isSelected ? c.accent : c.label2,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: CruType.subhead.tint(
                            b.hidden
                                ? c.label3
                                : (isSelected ? c.label : c.label2),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Lock toggle
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: Icon(
                          b.locked ? Icons.lock : Icons.lock_open,
                          color: b.locked ? c.accent : c.label3,
                        ),
                        onPressed: () {
                          controller.updateBlock(
                            b.id,
                            (orig) => orig.copyWith(locked: !orig.locked),
                          );
                        },
                      ),
                      // Eye (hide) toggle
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: Icon(
                          b.hidden ? Icons.visibility_off : Icons.visibility,
                          color: b.hidden ? c.label3 : c.label2,
                        ),
                        onPressed: () {
                          controller.updateBlock(
                            b.id,
                            (orig) => orig.copyWith(hidden: !orig.hidden),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 2. PROPERTIES PANEL
// =============================================================================

class EditorPropertiesPanel extends StatelessWidget {
  const EditorPropertiesPanel({super.key, required this.controller});

  final TemplateEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final b = controller.selected;

    if (b == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s16),
          child: Text(
            'Select an element on the canvas to edit its properties.',
            textAlign: TextAlign.center,
            style: CruType.subhead.tint(c.label2),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title & Actions Bar
          Row(
            children: [
              Expanded(
                child: Text(
                  'Element Properties',
                  style: CruType.headline.tint(c.label),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Duplicate',
                onPressed: controller.duplicateSelected,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: c.redText),
                tooltip: 'Delete',
                onPressed: controller.deleteSelected,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Content editor based on block type
          if (b.type == DocBlockType.field) ...[
            DropdownButtonFormField<String>(
              initialValue: kDocFieldLabels.containsKey(b.field)
                  ? b.field
                  : kDocFieldLabels.keys.first,
              decoration: InputDecoration(
                labelText: 'Data Field',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
              items: [
                for (final e in kDocFieldLabels.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  controller.updateBlock(
                    b.id,
                    (orig) => orig.copyWith(field: v),
                  );
                }
              },
            ),
            const SizedBox(height: CruSpace.s12),
          ] else if (b.type == DocBlockType.text) ...[
            TextFormField(
              initialValue: b.text,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Text Content',
                hintText: 'Enter text or {{placeholders}}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
              onChanged: (v) {
                controller.updateBlock(b.id, (orig) => orig.copyWith(text: v));
              },
            ),
            const SizedBox(height: CruSpace.s6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final ph in [
                  '{{doc.date}}',
                  '{{doc.number}}',
                  '{{patient.name}}',
                  '{{doctor.name}}',
                ])
                  ActionChip(
                    label: Text(ph, style: const TextStyle(fontSize: 10)),
                    onPressed: () {
                      controller.updateBlock(
                        b.id,
                        (orig) => orig.copyWith(text: '${orig.text} $ph'),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
          ] else if (b.type == DocBlockType.qr) ...[
            TextFormField(
              initialValue: b.qr,
              decoration: InputDecoration(
                labelText: 'QR Content ("upi" or URL)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
              onChanged: (v) {
                controller.updateBlock(b.id, (orig) => orig.copyWith(qr: v));
              },
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          // Typography: Font Size, Bold, Alignment
          if (b.type == DocBlockType.field ||
              b.type == DocBlockType.text ||
              b.type == DocBlockType.doctorList) ...[
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('Size', style: CruType.subhead.w500.tint(c.label)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: b.fontPt > 6
                            ? () => controller.updateBlock(
                                b.id,
                                (o) => o.copyWith(fontPt: o.fontPt - 1),
                              )
                            : null,
                      ),
                      Text(
                        '${b.fontPt.toStringAsFixed(0)} pt',
                        style: CruType.body.w600,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: b.fontPt < 28
                            ? () => controller.updateBlock(
                                b.id,
                                (o) => o.copyWith(fontPt: o.fontPt + 1),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_bold,
                    color: b.bold ? c.accent : c.label3,
                  ),
                  onPressed: () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(bold: !o.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),

            // Align
            Row(
              children: [
                Text('Align', style: CruType.subhead.w500.tint(c.label)),
                const SizedBox(width: CruSpace.s12),
                SegmentedButton<DocAlign>(
                  segments: const [
                    ButtonSegment(
                      value: DocAlign.left,
                      icon: Icon(Icons.format_align_left, size: 16),
                    ),
                    ButtonSegment(
                      value: DocAlign.center,
                      icon: Icon(Icons.format_align_center, size: 16),
                    ),
                    ButtonSegment(
                      value: DocAlign.right,
                      icon: Icon(Icons.format_align_right, size: 16),
                    ),
                  ],
                  selected: {b.align},
                  onSelectionChanged: (s) {
                    controller.updateBlock(
                      b.id,
                      (o) => o.copyWith(align: s.first),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          // Color Swatches
          Text('Colour', style: CruType.subhead.w500.tint(c.label)),
          const SizedBox(height: CruSpace.s6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final colorKey in [
                'text',
                'muted',
                'accent',
                'white',
                '#000000',
                '#2563EB',
                '#E11D48',
              ])
                InkWell(
                  onTap: () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(color: colorKey),
                  ),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(controller.template.style.resolve(colorKey)),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: b.color == colorKey ? c.accent : c.hairline,
                        width: b.color == colorKey ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // Show On page option
          DropdownButtonFormField<DocShowOn>(
            initialValue: b.showOn,
            decoration: InputDecoration(
              labelText: 'Show On',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            items: const [
              DropdownMenuItem(value: DocShowOn.all, child: Text('All pages')),
              DropdownMenuItem(
                value: DocShowOn.first,
                child: Text('First page only'),
              ),
              DropdownMenuItem(
                value: DocShowOn.last,
                child: Text('Last page only'),
              ),
              DropdownMenuItem(
                value: DocShowOn.notFirst,
                child: Text('Not on first page'),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                controller.updateBlock(b.id, (o) => o.copyWith(showOn: v));
              }
            },
          ),
          const SizedBox(height: CruSpace.s16),

          // Position & Size (mm)
          Text(
            'Position & Size (mm)',
            style: CruType.subhead.w500.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'X: ${b.x.toStringAsFixed(1)} mm',
                  style: CruType.caption,
                ),
              ),
              Expanded(
                child: Text(
                  'Y: ${b.y.toStringAsFixed(1)} mm',
                  style: CruType.caption,
                ),
              ),
              Expanded(
                child: Text(
                  'W: ${b.w.toStringAsFixed(1)} mm',
                  style: CruType.caption,
                ),
              ),
              Expanded(
                child: Text(
                  'H: ${b.h.toStringAsFixed(1)} mm',
                  style: CruType.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          // PUBG-Style Fine-tune Nudge Pad
          Text(
            'Fine-tune Nudge (0.5 mm)',
            style: CruType.subhead.w500.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s8),
          Center(
            child: SizedBox(
              width: 130,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => controller.nudge(0, -0.5),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => controller.nudge(-0.5, 0),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => controller.nudge(0.5, 0),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => controller.nudge(0, 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 3. PAGE PANEL
// =============================================================================

class EditorPagePanel extends StatelessWidget {
  const EditorPagePanel({super.key, required this.controller});

  final TemplateEditorController controller;

  Future<void> _uploadBackground(BuildContext context) async {
    try {
      Uint8List? raw;
      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        final res = await FilePicker.pickFiles(
          dialogTitle: 'Select letterhead scan or PDF',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
          withData: true,
        );
        if (res != null && res.files.isNotEmpty) {
          final f = res.files.first;
          raw =
              f.bytes ??
              (f.path != null ? await File(f.path!).readAsBytes() : null);
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
        if (picked != null) raw = await picked.readAsBytes();
      }
      if (raw == null) return;

      Uint8List pngBytes;
      // If PDF, rasterize first page at 150 dpi
      if (raw.length > 4 &&
          raw[0] == 0x25 &&
          raw[1] == 0x50 &&
          raw[2] == 0x44 &&
          raw[3] == 0x46) {
        final pages = Printing.raster(raw, pages: [0], dpi: 150);
        pngBytes = await pages.first.then((p) => p.toPng());
      } else {
        pngBytes = raw;
      }

      final processed = await prepareBrandingImage(pngBytes, maxSide: 2480);
      final sha = sha256Hex(processed);
      final tenant = DocRepository.instance.tenantOrNull;
      if (tenant == null) throw StateError('No active clinic');

      final stored = await MedicalStorageService.instance
          .uploadClinicTemplateImage(
            doctorId: tenant,
            templateId: controller.template.id.isNotEmpty
                ? controller.template.id
                : 'new_${DateTime.now().millisecondsSinceEpoch}',
            name: sha,
            png: processed,
          );
      await BrandingImageStore.instance.remember(sha, processed);

      controller.update(
        (t) => t.copyWith(
          background: DocBackground(
            path: stored.path,
            sha: sha,
            printOnPaper: false,
            opacity: 1.0,
          ),
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Letterhead background uploaded.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = controller.template;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Page Settings', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s12),

          // Template Name
          TextFormField(
            initialValue: t.name,
            decoration: InputDecoration(
              labelText: 'Template Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            onChanged: (v) {
              if (v.trim().isNotEmpty) {
                controller.update((orig) => orig.copyWith(name: v.trim()));
              }
            },
          ),
          const SizedBox(height: CruSpace.s12),

          // Applies To Kinds
          Text('Applies to', style: CruType.subhead.w500.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final kind in DocKind.values)
                FilterChip(
                  label: Text(kind.label),
                  selected: t.kinds.contains(kind),
                  onSelected: (selected) {
                    final current = Set<DocKind>.from(t.kinds);
                    if (selected) {
                      current.add(kind);
                    } else {
                      current.remove(kind);
                    }
                    controller.update(
                      (orig) => orig.copyWith(kinds: current.toList()),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),

          // Paper Format
          DropdownButtonFormField<DocPaperFormat>(
            initialValue: t.paper.format,
            decoration: InputDecoration(
              labelText: 'Paper Size',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: DocPaperFormat.a4,
                child: Text('A4 (210 × 297 mm)'),
              ),
              DropdownMenuItem(
                value: DocPaperFormat.a5,
                child: Text('A5 (148 × 210 mm)'),
              ),
              DropdownMenuItem(
                value: DocPaperFormat.letter,
                child: Text('Letter (8.5 × 11 in)'),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                final p = switch (v) {
                  DocPaperFormat.a5 => const DocPaper(
                    format: DocPaperFormat.a5,
                    widthMm: 148,
                    heightMm: 210,
                  ),
                  DocPaperFormat.letter => const DocPaper(
                    format: DocPaperFormat.letter,
                    widthMm: 215.9,
                    heightMm: 279.4,
                  ),
                  _ => const DocPaper(
                    format: DocPaperFormat.a4,
                    widthMm: 210,
                    heightMm: 297,
                  ),
                };
                controller.setPaper(p);
              }
            },
          ),
          const SizedBox(height: CruSpace.s16),

          // Header & Footer Height Fields
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('header_${t.headerMm}'),
                  initialValue: t.headerMm.toStringAsFixed(1),
                  decoration: InputDecoration(
                    labelText: 'Header (mm)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CruRadius.control),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (v) {
                    final mm = double.tryParse(v);
                    if (mm != null) {
                      controller.checkpoint();
                      controller.setZoneHeight(DocZone.header, mm);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('footer_${t.footerMm}'),
                  initialValue: t.footerMm.toStringAsFixed(1),
                  decoration: InputDecoration(
                    labelText: 'Footer (mm)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CruRadius.control),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (v) {
                    final mm = double.tryParse(v);
                    if (mm != null) {
                      controller.checkpoint();
                      controller.setZoneHeight(DocZone.footer, mm);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),

          // Accent Colour Palette
          Text('Accent Colour', style: CruType.subhead.w500.tint(c.label)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final colorVal in kDocPalette)
                InkWell(
                  onTap: () {
                    controller.update(
                      (orig) => orig.copyWith(
                        style: orig.style.copyWith(accent: colorVal),
                      ),
                    );
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(colorVal),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: t.style.accent == colorVal
                            ? c.accent
                            : c.hairline,
                        width: t.style.accent == colorVal ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),

          // Text Size Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Text Scale', style: CruType.subhead.w500.tint(c.label)),
              Text(
                '${(t.style.fontScale * 100).toStringAsFixed(0)} %',
                style: CruType.caption,
              ),
            ],
          ),
          Slider(
            value: t.style.fontScale,
            min: 0.85,
            max: 1.20,
            divisions: 7,
            onChanged: (v) {
              controller.update(
                (orig) =>
                    orig.copyWith(style: orig.style.copyWith(fontScale: v)),
              );
            },
          ),
          const SizedBox(height: CruSpace.s16),

          // Options Toggles
          Text('Options', style: CruType.subhead.w500.tint(c.label)),
          const SizedBox(height: CruSpace.s6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Medicines in capitals'),
            value: t.options.medicinesInCapitals,
            onChanged: (v) {
              controller.update(
                (orig) => orig.copyWith(
                  options: orig.options.copyWith(medicinesInCapitals: v),
                ),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Amount in words'),
            value: t.options.amountInWords,
            onChanged: (v) {
              controller.update(
                (orig) => orig.copyWith(
                  options: orig.options.copyWith(amountInWords: v),
                ),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show UPI QR code'),
            value: t.options.upiQr,
            onChanged: (v) {
              controller.update(
                (orig) =>
                    orig.copyWith(options: orig.options.copyWith(upiQr: v)),
              );
            },
          ),
          const SizedBox(height: CruSpace.s16),

          // Background / Letterhead Paper Section
          Text(
            'Letterhead Paper Background',
            style: CruType.subhead.w500.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Use a photo or scan of your pre-printed stationery behind the document.',
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s8),
          if (t.background == null) ...[
            CruButton(
              label: 'Upload printed letterhead',
              kind: CruButtonKind.secondary,
              onPressed: () => _uploadBackground(context),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Background set',
                    style: CruType.body.w600.tint(c.label),
                  ),
                ),
                CruLink(
                  label: 'Remove',
                  style: CruType.subhead.tint(c.redText),
                  onPressed: () {
                    controller.update(
                      (orig) => orig.copyWith(background: null),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Print background too'),
              subtitle: const Text('Turn off for physical pre-printed paper'),
              value: t.background!.printOnPaper,
              onChanged: (v) {
                controller.update(
                  (orig) => orig.copyWith(
                    background: orig.background!.copyWith(printOnPaper: v),
                  ),
                );
              },
            ),
            const SizedBox(height: CruSpace.s6),
            CruButton(
              label: 'Clear header and footer (pre-printed)',
              kind: CruButtonKind.inset,
              onPressed: () {
                controller.update(
                  (orig) => orig.copyWith(
                    blocks: [
                      for (final b in orig.blocks) b.copyWith(hidden: true),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: CruSpace.s24),

          // Reorderable Body Sections
          Text(
            'Body sections order (${controller.previewKind.label})',
            style: CruType.subhead.w500.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s8),
          _ReorderableBodyList(controller: controller),
          const SizedBox(height: CruSpace.s32),
        ],
      ),
    );
  }
}

class _ReorderableBodyList extends StatelessWidget {
  const _ReorderableBodyList({required this.controller});

  final TemplateEditorController controller;

  @override
  Widget build(BuildContext context) {
    final t = controller.template;
    final sections = t.bodyFor(controller.previewKind);

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final list = List<DocBodySection>.from(sections);
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        controller.update(
          (orig) => orig.withBodySections(controller.previewKind, list),
        );
      },
      children: [
        for (var i = 0; i < sections.length; i++)
          Container(
            key: ValueKey(sections[i].id),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.cru.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: context.cru.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_handle, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DocSection.labels[sections[i].id] ?? sections[i].id,
                    style: CruType.subhead.tint(context.cru.label),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
