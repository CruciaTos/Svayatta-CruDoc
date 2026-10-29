import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_block_view.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_touch_ui.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_body_sections.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Accent colours for the printed document (not the app's colours).
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

const _paletteNames = [
  'Teal',
  'Royal blue',
  'Sky blue',
  'Emerald',
  'Violet',
  'Rose',
  'Amber',
  'Slate',
];

/// Text and line colours a block can use (tokens resolve per template).
const _blockColours = [
  ('text', 'Text'),
  ('muted', 'Grey'),
  ('accent', 'Accent'),
  ('white', 'White'),
  ('#000000', 'Black'),
  ('#2563EB', 'Blue'),
  ('#E11D48', 'Rose'),
];

Future<Uint8List?> _pickImage({bool allowPdf = false}) async {
  if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final res = await FilePicker.pickFiles(
      dialogTitle: allowPdf ? 'Select letterhead scan or PDF' : 'Select image',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', if (allowPdf) 'pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    return f.bytes ??
        (f.path != null ? await File(f.path!).readAsBytes() : null);
  }
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  return picked?.readAsBytes();
}

void _toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// =============================================================================
// 1. ELEMENTS PANEL
// =============================================================================

/// Every element on the page, with hide and lock; "Add" swaps the list
/// for a picker of what can be added.
class EditorElementsPanel extends StatefulWidget {
  const EditorElementsPanel({
    super.key,
    required this.controller,
    this.onPicked,
  });

  final TemplateEditorController controller;

  /// After choosing or adding an element (the phone closes its sheet).
  final VoidCallback? onPicked;

  @override
  State<EditorElementsPanel> createState() => _EditorElementsPanelState();
}

class _EditorElementsPanelState extends State<EditorElementsPanel> {
  bool _adding = false;

  TemplateEditorController get _ctrl => widget.controller;

  static const _groups = <(String, List<(String, String)>)>[
    (
      'Clinic',
      [
        ('Clinic name', 'field:clinic.name'),
        ('Tagline', 'field:clinic.tagline'),
        ('Address', 'field:clinic.address'),
        ('Phone', 'field:clinic.phone'),
        ('Email', 'field:clinic.email'),
        ('Contact line', 'field:clinic.contactLine'),
        ('Registration number', 'field:clinic.regNo'),
        ('GSTIN', 'field:clinic.gstin'),
      ],
    ),
    (
      'Doctor',
      [
        ('Doctor name', 'field:doctor.name'),
        ('Qualification', 'field:doctor.qualification'),
        ('Specialty', 'field:doctor.specialty'),
        ('Registration number', 'field:doctor.regNo'),
        ('Name and qualification', 'field:doctor.nameQual'),
        ('Specialty and registration', 'field:doctor.specReg'),
        ('All clinic doctors', 'doctorList'),
      ],
    ),
    (
      'Document and patient',
      [
        ('Document title', 'field:doc.title'),
        ('Document number', 'field:doc.numberLine'),
        ('Date', 'field:doc.dateLine'),
        ('Patient name', 'field:patient.name'),
        ('Patient summary', 'field:patient.line'),
      ],
    ),
    (
      'Pictures',
      [
        ('Clinic logo', 'image:logo'),
        ('Signature', 'image:signature'),
        ('Personal stamp', 'image:stamp'),
        ('Clinic stamp', 'image:clinicStamp'),
        ('Upload a picture…', 'image_custom'),
      ],
    ),
    (
      'Lines, boxes and codes',
      [
        ('Line', 'shape_line'),
        ('Box', 'shape_box'),
        ('UPI pay QR code', 'qr_upi'),
        ('Link QR code', 'qr_link'),
        ('Your own text', 'text'),
      ],
    ),
  ];

  static CruIconData _iconForKey(String key) {
    if (key.startsWith('image')) return EditorIcons.image;
    if (key == 'shape_line') return EditorIcons.line;
    if (key == 'shape_box') return EditorIcons.box;
    if (key.startsWith('qr')) return EditorIcons.qr;
    if (key == 'doctorList') return CruIcons.patients;
    return EditorIcons.text;
  }

  DocBlock? _blockFor(String key) {
    final cw = _ctrl.template.paper.contentWidthMm;
    if (key.startsWith('field:')) {
      return DocBlock(
        id: '',
        type: DocBlockType.field,
        field: key.substring(6),
        w: 60,
        h: 6,
        x: 0,
        y: 0,
      );
    }
    if (key.startsWith('image:')) {
      final role = switch (key.substring(6)) {
        'logo' => DocImageRole.logo,
        'signature' => DocImageRole.signature,
        'stamp' => DocImageRole.stamp,
        _ => DocImageRole.clinicStamp,
      };
      final sz = switch (role) {
        DocImageRole.logo => const Size(22, 22),
        DocImageRole.signature => const Size(40, 16),
        _ => const Size(24, 24),
      };
      return DocBlock(
        id: '',
        type: DocBlockType.image,
        imageRole: role,
        w: sz.width,
        h: sz.height,
        x: 0,
        y: 0,
      );
    }
    return switch (key) {
      'text' => const DocBlock(
        id: '',
        type: DocBlockType.text,
        text: 'Your text',
        w: 80,
        h: 8,
        x: 0,
        y: 0,
      ),
      'shape_line' => DocBlock(
        id: '',
        type: DocBlockType.line,
        w: cw,
        h: 1,
        x: 0,
        y: 0,
        strokePt: 1,
        color: 'border',
      ),
      'shape_box' => const DocBlock(
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
      'qr_upi' => const DocBlock(
        id: '',
        type: DocBlockType.qr,
        qr: 'upi',
        w: 24,
        h: 24,
        x: 0,
        y: 0,
      ),
      'qr_link' => const DocBlock(
        id: '',
        type: DocBlockType.qr,
        w: 24,
        h: 24,
        x: 0,
        y: 0,
      ),
      'doctorList' => DocBlock(
        id: '',
        type: DocBlockType.doctorList,
        w: cw,
        h: 18,
        x: 0,
        y: 0,
      ),
      _ => null,
    };
  }

  Future<void> _add(String key) async {
    if (key == 'image_custom') {
      await _uploadCustomImage();
      return;
    }
    final b = _blockFor(key);
    if (b == null) return;
    _placed(_ctrl.add(b));
  }

  void _placed(bool ok) {
    if (!ok) {
      _toast(
        context,
        'Open a header or footer first (Page), or remove an element.',
      );
      return;
    }
    setState(() => _adding = false);
    widget.onPicked?.call();
  }

  Future<void> _uploadCustomImage() async {
    try {
      final raw = await _pickImage();
      if (raw == null) return;
      final png = await prepareBrandingImage(raw, maxSide: 2000);
      final sha = sha256Hex(png);
      final tenant = DocRepository.instance.tenantOrNull;
      if (tenant == null) throw StateError('No active clinic');
      final t = _ctrl.template;
      final stored = await MedicalStorageService.instance
          .uploadClinicTemplateImage(
            doctorId: tenant,
            templateId: t.id.isNotEmpty
                ? t.id
                : 'new_${DateTime.now().millisecondsSinceEpoch}',
            name: sha,
            png: png,
          );
      await BrandingImageStore.instance.remember(sha, png);
      if (!mounted) return;
      _placed(
        _ctrl.add(
          DocBlock(
            id: '',
            type: DocBlockType.image,
            imageRole: DocImageRole.custom,
            imagePath: stored.path,
            imageSha: sha,
            w: 30,
            h: 30,
            x: 0,
            y: 0,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast(context, 'Could not add the picture: $e');
    }
  }

  void _toggleHidden(DocBlock b) {
    _ctrl.updateBlock(b.id, (o) => o.copyWith(hidden: !o.hidden));
    if (!b.hidden && _ctrl.selectedId == b.id) _ctrl.select(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = _ctrl.template;
    final blocks = t.blocks;
    final hidden = blocks.where((b) => b.hidden).length;
    final canAdd = t.headerMm > 0 || t.footerMm > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            CruSpace.s12,
            CruSpace.s12,
            CruSpace.s12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        _adding ? 'Add to the page' : 'Elements',
                        style: CruType.headline.tint(c.label),
                      ),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      _adding
                          ? 'It goes in the middle of the header.'
                          : [
                              '${blocks.length - hidden} on the page',
                              if (hidden > 0) '$hidden hidden',
                            ].join(' · '),
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              if (canAdd)
                CruCapsuleButton(
                  label: _adding ? 'Back' : 'Add',
                  icon: _adding ? CruIcons.chevronLeft : CruIcons.plus,
                  onPressed: () => setState(() => _adding = !_adding),
                ),
            ],
          ),
        ),
        const CruSeparator(),
        Expanded(
          child: _adding
              ? _buildAddList(context)
              : blocks.isEmpty
              ? _buildEmpty(context, canAdd)
              : _buildBlockList(context, blocks),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, bool canAdd) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Text(
        canAdd
            ? 'Nothing on the page yet. Tap Add to put the clinic name, a '
                  'logo or a line in the header.'
            : 'This template prints with a fixed layout, so there is '
                  'nothing to move. Change its name and colour from Page.',
        textAlign: TextAlign.center,
        style: CruType.subhead.tint(c.label2),
      ),
    );
  }

  Widget _buildBlockList(BuildContext context, List<DocBlock> blocks) {
    final c = context.cru;
    return ListView.builder(
      padding: const EdgeInsets.all(CruSpace.s8),
      itemCount: blocks.length,
      itemBuilder: (context, i) {
        final b = blocks[i];
        final selected = _ctrl.selectedId == b.id;
        final title = editorBlockTitle(b);
        final state = [if (b.hidden) 'Hidden', if (b.locked) 'Locked'];
        return CruPressable(
          scaleOnPress: false,
          semanticLabel: title,
          onTap: () {
            // Picking a hidden element brings it back.
            if (b.hidden) {
              _ctrl.updateBlock(b.id, (o) => o.copyWith(hidden: false));
            }
            _ctrl.select(b.id);
            widget.onPicked?.call();
          },
          builder: (context, hovered) => AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            constraints: const BoxConstraints(minHeight: CruSize.collapsedRow),
            padding: const EdgeInsets.only(
              left: CruSpace.s12,
              right: CruSpace.s4,
            ),
            decoration: ShapeDecoration(
              color: selected
                  ? c.accentWash
                  : (hovered ? c.hoverFill : c.surface.withValues(alpha: 0)),
              shape: cruShape(CruRadius.control),
            ),
            child: Row(
              children: [
                CruIcon(
                  editorBlockIcon(b),
                  size: 18,
                  strokeWidth: 1.8,
                  color: b.hidden ? c.label3 : c.label2,
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (selected
                                    ? CruType.subhead.w600
                                    : CruType.subhead.w500)
                                .tint(b.hidden ? c.label3 : c.label),
                      ),
                      if (state.isNotEmpty)
                        Text(
                          state.join(' · '),
                          style: CruType.caption.tint(c.label3),
                        ),
                    ],
                  ),
                ),
                CruIconButton(
                  icon: b.hidden ? EditorIcons.eyeOff : EditorIcons.eye,
                  size: CruSize.squareButton,
                  iconSize: 17,
                  semanticLabel: b.hidden ? 'Show $title' : 'Hide $title',
                  tooltip: b.hidden ? 'Show' : 'Hide',
                  onPressed: () => _toggleHidden(b),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddList(BuildContext context) {
    final c = context.cru;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s8,
        CruSpace.s16,
        CruSpace.s8,
        CruSpace.s16,
      ),
      children: [
        for (final (group, items) in _groups) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
            child: EditorSectionLabel(group),
          ),
          for (final (label, key) in items)
            CruPressable(
              scaleOnPress: false,
              semanticLabel: 'Add $label',
              onTap: () => _add(key),
              builder: (context, hovered) => AnimatedContainer(
                duration: CruMotion.of(context, CruMotion.fast),
                height: CruSize.actionButton,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                decoration: ShapeDecoration(
                  color: hovered ? c.hoverFill : c.surface.withValues(alpha: 0),
                  shape: cruShape(CruRadius.control),
                ),
                child: Row(
                  children: [
                    CruIcon(
                      _iconForKey(key),
                      size: 18,
                      strokeWidth: 1.8,
                      color: c.label2,
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Text(
                        label,
                        style: CruType.subhead.w500.tint(c.label),
                      ),
                    ),
                    CruIcon(
                      CruIcons.plus,
                      size: 16,
                      strokeWidth: 2,
                      color: c.label3,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: CruSpace.s16),
        ],
      ],
    );
  }
}

// =============================================================================
// 2. PROPERTIES PANEL
// =============================================================================

/// Everything about the selected element. [showTune] adds the Size and
/// Transparency sliders and quick actions (the phone has them in its own
/// panel already).
class EditorPropertiesPanel extends StatelessWidget {
  const EditorPropertiesPanel({
    super.key,
    required this.controller,
    this.showTune = true,
  });

  final TemplateEditorController controller;
  final bool showTune;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final b = controller.selected;

    if (b == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Text(
            'Tap an element on the page to move or change it.',
            textAlign: TextAlign.center,
            style: CruType.subhead.tint(c.label2),
          ),
        ),
      );
    }

    final locked = b.locked;
    final isText =
        b.type == DocBlockType.field ||
        b.type == DocBlockType.text ||
        b.type == DocBlockType.doctorList;
    final removes =
        !b.id.startsWith('builtin.') && !controller.template.isBuiltin;
    const gap = SizedBox(height: CruSpace.s24);

    return ListView(
      padding: const EdgeInsets.all(CruSpace.s16),
      children: [
        // Which element, with duplicate and remove
        Row(
          children: [
            CruIconTile(icon: editorBlockIcon(b), tone: CruTileTone.neutral),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    editorBlockTitle(b),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.callout.tint(c.label),
                  ),
                  Text(
                    b.zone == DocZone.header
                        ? 'In the header'
                        : 'In the footer',
                    style: CruType.caption.tint(c.label2),
                  ),
                ],
              ),
            ),
            // On a phone these live in the element's actions sheet.
            if (showTune) ...[
              CruIconButton(
                icon: EditorIcons.copy,
                size: CruSize.squareButton + CruSpace.s4,
                iconSize: 18,
                semanticLabel: 'Duplicate',
                tooltip: 'Duplicate',
                onPressed: controller.duplicateSelected,
              ),
              CruIconButton(
                icon: removes ? EditorIcons.trash : EditorIcons.eyeOff,
                size: CruSize.squareButton + CruSpace.s4,
                iconSize: 18,
                semanticLabel: removes ? 'Delete' : 'Hide',
                tooltip: removes ? 'Delete' : 'Hide',
                onPressed: controller.deleteSelected,
              ),
            ],
          ],
        ),
        if (locked) ...[
          const SizedBox(height: CruSpace.s16),
          _Note(
            text: 'Locked, so it can\'t move by accident.',
            action: 'Unlock',
            onAction: () =>
                controller.updateBlock(b.id, (o) => o.copyWith(locked: false)),
          ),
        ],
        if (showTune) ...[
          gap,
          const EditorSectionLabel('Size and transparency'),
          EditorSlider(
            label: 'Size',
            value: controller.scaleOf(b),
            min: 0.3,
            max: controller.maxScaleOf(b).clamp(0.5, 2.5).toDouble(),
            valueText: '${(controller.scaleOf(b) * 100).round()}%',
            enabled: !locked,
            onStart: controller.beginLive,
            onChanged: (v) => controller.setScaleLive(b.id, v),
            onEnd: controller.endLive,
          ),
          EditorSlider(
            label: 'Transparency',
            value: (1 - b.opacity).clamp(0.0, 0.8).toDouble(),
            min: 0,
            max: 0.8,
            valueText: '${((1 - b.opacity) * 100).round()}%',
            enabled: !locked,
            onStart: controller.beginLive,
            onChanged: (v) => controller.setTransparencyLive(b.id, v),
            onEnd: controller.endLive,
          ),
          const SizedBox(height: CruSpace.s8),
          Row(
            children: [
              CruCapsuleButton(
                label: locked ? 'Unlock' : 'Lock',
                icon: locked ? EditorIcons.unlock : EditorIcons.lock,
                onPressed: () => controller.updateBlock(
                  b.id,
                  (o) => o.copyWith(locked: !o.locked),
                ),
              ),
              if (!locked && controller.isChanged(b)) ...[
                const SizedBox(width: CruSpace.s8),
                CruCapsuleButton(
                  label: 'Reset',
                  icon: EditorIcons.reset,
                  onPressed: () => controller.resetBlock(b.id),
                ),
              ],
            ],
          ),
        ],

        // What it shows
        if (b.type == DocBlockType.field) ...[
          gap,
          CruDropdownField<String>(
            label: 'Shows',
            value: kDocFieldLabels.containsKey(b.field) ? b.field : null,
            items: kDocFieldLabels.keys.toList(),
            itemLabel: (k) => kDocFieldLabels[k] ?? k,
            onChanged: (v) =>
                controller.updateBlock(b.id, (o) => o.copyWith(field: v)),
          ),
        ] else if (b.type == DocBlockType.text) ...[
          gap,
          const EditorSectionLabel('Text'),
          _BoundTextField(
            id: b.id,
            label: 'Words',
            value: b.text,
            maxLines: 3,
            help: 'Tap a detail below to add it; it fills in on each document.',
            onBegin: controller.checkpoint,
            onChanged: (v) =>
                controller.updateBlockLive(b.id, (o) => o.copyWith(text: v)),
          ),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s6,
            children: [
              for (final (label, ph) in const [
                ('Date', '{{doc.date}}'),
                ('Number', '{{doc.number}}'),
                ('Patient', '{{patient.name}}'),
                ('Doctor', '{{doctor.name}}'),
              ])
                IntrinsicWidth(
                  child: CruCapsuleButton(
                    label: label,
                    icon: CruIcons.plus,
                    onPressed: () => controller.updateBlock(
                      b.id,
                      (o) => o.copyWith(
                        text: o.text.trim().isEmpty ? ph : '${o.text} $ph',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ] else if (b.type == DocBlockType.qr) ...[
          gap,
          const EditorSectionLabel('QR code'),
          CruSegmentedControl<bool>(
            semanticLabel: 'QR code content',
            segments: const [
              CruSegment(true, 'Pay by UPI'),
              CruSegment(false, 'A link'),
            ],
            selected: b.qr == 'upi',
            onChanged: (upi) => controller.updateBlock(
              b.id,
              (o) => o.copyWith(qr: upi ? 'upi' : ''),
            ),
          ),
          if (b.qr != 'upi') ...[
            const SizedBox(height: CruSpace.s12),
            _BoundTextField(
              id: b.id,
              label: 'Link',
              value: b.qr,
              hint: 'yourclinic.in/book',
              keyboardType: TextInputType.url,
              onBegin: controller.checkpoint,
              onChanged: (v) =>
                  controller.updateBlockLive(b.id, (o) => o.copyWith(qr: v)),
            ),
          ],
        ],

        // How text looks
        if (isText) ...[
          gap,
          const EditorSectionLabel('Text style'),
          EditorStepper(
            label: 'Text size',
            valueText:
                '${b.fontPt.toStringAsFixed(b.fontPt % 1 == 0 ? 0 : 1)} pt',
            onMinus: b.fontPt > 5
                ? () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(fontPt: (o.fontPt - 1).clamp(5.0, 40.0)),
                  )
                : null,
            onPlus: b.fontPt < 40
                ? () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(fontPt: (o.fontPt + 1).clamp(5.0, 40.0)),
                  )
                : null,
          ),
          const SizedBox(height: CruSpace.s12),
          CruSwitchRow(
            title: 'Bold',
            value: b.bold,
            onChanged: (v) =>
                controller.updateBlock(b.id, (o) => o.copyWith(bold: v)),
          ),
          const SizedBox(height: CruSpace.s12),
          CruSegmentedControl<DocAlign>(
            semanticLabel: 'Line up',
            segments: const [
              CruSegment(DocAlign.left, 'Left'),
              CruSegment(DocAlign.center, 'Centre'),
              CruSegment(DocAlign.right, 'Right'),
            ],
            selected: b.align,
            onChanged: (v) =>
                controller.updateBlock(b.id, (o) => o.copyWith(align: v)),
          ),
        ],

        // Colour
        if (b.type != DocBlockType.image && b.type != DocBlockType.qr) ...[
          gap,
          EditorSectionLabel(
            b.type == DocBlockType.box ? 'Border colour' : 'Colour',
          ),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final (key, name) in _blockColours)
                EditorSwatch(
                  color: Color(controller.template.style.resolve(key)),
                  selected: b.color == key,
                  semanticLabel: name,
                  onTap: () => controller.updateBlock(
                    b.id,
                    (o) => o.copyWith(color: key),
                  ),
                ),
            ],
          ),
        ],

        // Where and when
        gap,
        CruDropdownField<DocShowOn>(
          label: 'Prints on',
          value: b.showOn,
          items: DocShowOn.values,
          itemLabel: (v) => switch (v) {
            DocShowOn.all => 'Every page',
            DocShowOn.first => 'First page only',
            DocShowOn.last => 'Last page only',
            DocShowOn.notFirst => 'Every page but the first',
          },
          onChanged: (v) =>
              controller.updateBlock(b.id, (o) => o.copyWith(showOn: v)),
        ),
        gap,
        _NudgePad(controller: controller, enabled: !locked),
        const SizedBox(height: CruSpace.s16),
      ],
    );
  }
}

/// Moves the element half a millimetre at a time.
class _NudgePad extends StatelessWidget {
  const _NudgePad({required this.controller, required this.enabled});

  final TemplateEditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget arrow(CruIconData icon, String label, double dx, double dy) =>
        AnimatedOpacity(
          duration: CruMotion.of(context, CruMotion.fast),
          opacity: enabled ? 1 : 0.35,
          child: CruSquareButton(
            icon: icon,
            semanticLabel: 'Move $label',
            tooltip: 'Move $label',
            onPressed: enabled ? () => controller.nudge(dx, dy) : null,
          ),
        );
    return Row(
      children: [
        Expanded(
          child: Text(
            'Fine move, 0.5 mm',
            style: CruType.subhead.w500.tint(c.label2),
          ),
        ),
        arrow(CruIcons.chevronLeft, 'left', -0.5, 0),
        const SizedBox(width: CruSpace.s6),
        arrow(EditorIcons.chevronUp, 'up', 0, -0.5),
        const SizedBox(width: CruSpace.s6),
        arrow(CruIcons.chevronDown, 'down', 0, 0.5),
        const SizedBox(width: CruSpace.s6),
        arrow(CruIcons.chevronRight, 'right', 0.5, 0),
      ],
    );
  }
}

/// A quiet inset note, with an optional capsule action.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s14,
        CruSpace.s10,
        CruSpace.s10,
        CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: CruType.subhead.w500.tint(c.label2)),
          ),
          if (action != null) ...[
            const SizedBox(width: CruSpace.s8),
            CruCapsuleButton(
              label: action!,
              kind: CruCapsuleKind.surface,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// A text field kept in step with a value that can also change elsewhere
/// (undo, another element). One undo step per edit: [onBegin] runs on the
/// first change after the field is focused.
class _BoundTextField extends StatefulWidget {
  const _BoundTextField({
    required this.id,
    required this.label,
    required this.value,
    required this.onBegin,
    required this.onChanged,
    this.maxLines = 1,
    this.hint,
    this.help,
    this.keyboardType,
  });

  /// What is being edited; a new id starts afresh.
  final String id;
  final String label;
  final String value;
  final VoidCallback onBegin;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final String? hint;
  final String? help;
  final TextInputType? keyboardType;

  @override
  State<_BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<_BoundTextField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _begun = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _begun = false;
    });
  }

  @override
  void didUpdateWidget(_BoundTextField old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        (!_focus.hasFocus && widget.value != _text.text)) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CruTextField(
      label: widget.label,
      controller: _text,
      focusNode: _focus,
      maxLines: widget.maxLines,
      hint: widget.hint,
      help: widget.help,
      keyboardType: widget.keyboardType,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (v) {
        if (!_begun) {
          _begun = true;
          widget.onBegin();
        }
        widget.onChanged(v);
      },
    );
  }
}

// =============================================================================
// 3. PAGE PANEL
// =============================================================================

/// The template as a whole: name, what it's for, paper, header and footer,
/// colour, text size, print options, letterhead paper and body order.
class EditorPagePanel extends StatelessWidget {
  const EditorPagePanel({
    super.key,
    required this.controller,
    this.onResetLayout,
  });

  final TemplateEditorController controller;

  /// Puts every element back as in the ready-made design (asks first).
  final VoidCallback? onResetLayout;

  Future<void> _uploadBackground(BuildContext context) async {
    try {
      final raw = await _pickImage(allowPdf: true);
      if (raw == null) return;

      // A PDF: use its first page at 150 dpi.
      var pngBytes = raw;
      if (raw.length > 4 &&
          raw[0] == 0x25 &&
          raw[1] == 0x50 &&
          raw[2] == 0x44 &&
          raw[3] == 0x46) {
        final pages = Printing.raster(raw, pages: [0], dpi: 150);
        pngBytes = await pages.first.then((p) => p.toPng());
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
      if (context.mounted) _toast(context, 'Letterhead paper added.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not add it: $e');
    }
  }

  void _toggleKind(DocTemplate t, DocKind kind) {
    // No ticks stored means "every kind".
    final current = t.kinds.isEmpty
        ? DocKind.values.toSet()
        : Set<DocKind>.from(t.kinds);
    if (current.contains(kind)) {
      if (current.length == 1) return; // keep at least one
      current.remove(kind);
    } else {
      current.add(kind);
    }
    final all = current.length == DocKind.values.length;
    controller.update(
      (o) => o.copyWith(
        kinds: all
            ? const []
            : [
                for (final k in DocKind.values)
                  if (current.contains(k)) k,
              ],
      ),
    );
  }

  void _setZone(DocZone z, double mm) {
    controller.checkpoint();
    controller.setZoneHeight(z, mm);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = controller.template;
    final roll = t.paper.isRoll;
    const gap = SizedBox(height: CruSpace.s24);

    String mm(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)} mm';

    return ListView(
      padding: const EdgeInsets.all(CruSpace.s16),
      children: [
        const EditorSectionLabel('Template'),
        _BoundTextField(
          id: 'template-name',
          label: 'Name',
          value: t.name,
          onBegin: controller.checkpoint,
          onChanged: (v) {
            if (v.trim().isNotEmpty) {
              controller.updateLive((o) => o.copyWith(name: v.trim()));
            }
          },
        ),
        if (!roll) ...[
          const SizedBox(height: CruSpace.s16),
          Text('Used for', style: CruType.subhead.w500.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final kind in DocKind.values)
                EditorChoiceChip(
                  label: kind.label,
                  selected: t.appliesTo(kind),
                  onTap: () => _toggleKind(t, kind),
                ),
            ],
          ),
        ],

        gap,
        const EditorSectionLabel('Paper'),
        if (roll)
          const _Note(
            text:
                'Receipt roll, 80 mm wide. Receipts print with a fixed '
                'layout; only the name and colour change.',
          )
        else ...[
          CruDropdownField<DocPaperFormat>(
            label: 'Size',
            value: t.paper.format == DocPaperFormat.custom
                ? null
                : t.paper.format,
            items: const [
              DocPaperFormat.a4,
              DocPaperFormat.a5,
              DocPaperFormat.letter,
            ],
            itemLabel: (f) => switch (f) {
              DocPaperFormat.a5 => 'A5 · 148 × 210 mm',
              DocPaperFormat.letter => 'Letter · 8.5 × 11 in',
              _ => 'A4 · 210 × 297 mm',
            },
            tabular: true,
            onChanged: (v) => controller.setPaper(switch (v) {
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
            }),
          ),
          const SizedBox(height: CruSpace.s16),
          EditorStepper(
            label: 'Header height',
            valueText: mm(t.headerMm),
            onMinus: t.headerMm > 0
                ? () => _setZone(DocZone.header, t.headerMm - 2)
                : null,
            onPlus: () => _setZone(DocZone.header, t.headerMm + 2),
          ),
          const SizedBox(height: CruSpace.s8),
          EditorStepper(
            label: 'Footer height',
            valueText: mm(t.footerMm),
            onMinus: t.footerMm > 0
                ? () => _setZone(DocZone.footer, t.footerMm - 2)
                : null,
            onPlus: () => _setZone(DocZone.footer, t.footerMm + 2),
          ),
        ],

        gap,
        const EditorSectionLabel('Colour'),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            for (var i = 0; i < kDocPalette.length; i++)
              EditorSwatch(
                color: Color(kDocPalette[i]),
                selected: t.style.accent == kDocPalette[i],
                semanticLabel: _paletteNames[i],
                onTap: () => controller.update(
                  (o) => o.copyWith(
                    style: o.style.copyWith(accent: kDocPalette[i]),
                  ),
                ),
              ),
          ],
        ),

        if (!roll) ...[
          gap,
          const EditorSectionLabel('Body text'),
          EditorSlider(
            label: 'Text size',
            value: t.style.fontScale.clamp(0.85, 1.2).toDouble(),
            min: 0.85,
            max: 1.2,
            valueText: '${(t.style.fontScale * 100).round()}%',
            enabled: true,
            onStart: controller.beginLive,
            onChanged: (v) {
              final stepped = (v * 20).roundToDouble() / 20;
              controller.updateLive(
                (o) => o.copyWith(style: o.style.copyWith(fontScale: stepped)),
              );
            },
            onEnd: controller.endLive,
          ),

          gap,
          const EditorSectionLabel('Print options'),
          CruSwitchRow(
            title: 'Medicines in capitals',
            value: t.options.medicinesInCapitals,
            onChanged: (v) => controller.update(
              (o) => o.copyWith(
                options: o.options.copyWith(medicinesInCapitals: v),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          CruSwitchRow(
            title: 'Amount in words',
            value: t.options.amountInWords,
            onChanged: (v) => controller.update(
              (o) => o.copyWith(options: o.options.copyWith(amountInWords: v)),
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          CruSwitchRow(
            title: 'UPI pay QR code on bills',
            value: t.options.upiQr,
            onChanged: (v) => controller.update(
              (o) => o.copyWith(options: o.options.copyWith(upiQr: v)),
            ),
          ),

          gap,
          const EditorSectionLabel('Letterhead paper'),
          Text(
            'Use a photo or scan of your printed stationery behind the '
            'document.',
            style: CruType.subhead.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          if (t.background == null)
            Align(
              alignment: Alignment.centerLeft,
              child: CruButton(
                label: 'Add letterhead paper',
                kind: CruButtonKind.inset,
                onPressed: () => _uploadBackground(context),
              ),
            )
          else ...[
            _Note(
              text: 'Letterhead paper added.',
              action: 'Remove',
              onAction: () =>
                  controller.update((o) => o.copyWith(clearBackground: true)),
            ),
            const SizedBox(height: CruSpace.s12),
            CruSwitchRow(
              title: 'Print the paper too',
              subtitle:
                  'Turn off when you print on paper that\'s already '
                  'printed.',
              value: t.background!.printOnPaper,
              onChanged: (v) => controller.update(
                (o) => o.copyWith(
                  background: o.background!.copyWith(printOnPaper: v),
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s12),
            Align(
              alignment: Alignment.centerLeft,
              child: CruButton(
                label: 'Hide header and footer elements',
                kind: CruButtonKind.inset,
                onPressed: () => controller.update(
                  (o) => o.copyWith(
                    blocks: [
                      for (final b in o.blocks) b.copyWith(hidden: true),
                    ],
                  ),
                ),
              ),
            ),
          ],

          gap,
          EditorSectionLabel('Body sections · ${controller.previewKind.label}'),
          Text(
            'Drag to change the order. Hide what you don\'t print.',
            style: CruType.subhead.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          _BodySections(controller: controller),
        ],
        if (onResetLayout != null) ...[
          gap,
          const EditorSectionLabel('Start over'),
          Text(
            'Put every element back where the ready-made design has it.',
            style: CruType.subhead.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: CruButton(
              label: 'Reset layout',
              icon: EditorIcons.reset,
              kind: CruButtonKind.inset,
              onPressed: onResetLayout,
            ),
          ),
        ],
        const SizedBox(height: CruSpace.s16),
      ],
    );
  }
}

class _BodySections extends StatelessWidget {
  const _BodySections({required this.controller});

  final TemplateEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final kind = controller.previewKind;
    final sections = controller.template.bodyFor(kind);

    void save(List<DocBodySection> list) =>
        controller.update((o) => o.withBodySections(kind, list));

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: sections.length,
      onReorderItem: (oldIndex, newIndex) {
        final list = List<DocBodySection>.from(sections);
        list.insert(newIndex, list.removeAt(oldIndex));
        save(list);
      },
      proxyDecorator: (child, _, _) =>
          Material(color: c.surface.withValues(alpha: 0), child: child),
      itemBuilder: (context, i) {
        final sec = sections[i];
        final label = DocSection.labels[sec.id] ?? sec.id;
        return Padding(
          key: ValueKey(sec.id),
          padding: const EdgeInsets.only(bottom: CruSpace.s6),
          child: Container(
            height: CruSize.collapsedRow,
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Semantics(
                    label: 'Drag to move $label',
                    child: SizedBox(
                      width: CruSize.actionButton,
                      height: CruSize.collapsedRow,
                      child: Center(
                        child: CruIcon(
                          EditorIcons.grip,
                          size: 18,
                          color: c.label3,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.w500.tint(
                      sec.visible ? c.label : c.label3,
                    ),
                  ),
                ),
                CruIconButton(
                  icon: sec.visible ? EditorIcons.eye : EditorIcons.eyeOff,
                  size: CruSize.squareButton + CruSpace.s4,
                  iconSize: 17,
                  semanticLabel: sec.visible ? 'Hide $label' : 'Show $label',
                  tooltip: sec.visible ? 'Hide' : 'Show',
                  onPressed: () => save([
                    for (final s in sections)
                      s.id == sec.id ? s.copyWith(visible: !s.visible) : s,
                  ]),
                ),
                const SizedBox(width: CruSpace.s4),
              ],
            ),
          ),
        );
      },
    );
  }
}
