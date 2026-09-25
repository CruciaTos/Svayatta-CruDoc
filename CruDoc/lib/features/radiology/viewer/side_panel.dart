import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer/measure.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/ai/ai_panels.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum RadPanelTab {
  measure('Measure'),
  keys('Key images'),
  info('Info'),
  adjust('Adjust'),
  ai('AI');

  const RadPanelTab(this.label);
  final String label;

  static RadPanelTab fromName(Object? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => measure);
}

/// What the side panel asks the viewer to do.
abstract interface class RadSidePanelHost {
  void select(String? id);
  void renameAnnotation(RadAnnotation a, String text);
  void deleteAnnotation(RadAnnotation a);
  void recolorAnnotation(RadAnnotation a, Color color);
  void includeInReport(RadAnnotation a, bool include);
  void startCalibration();
  void clearCalibration();

  void markKeyImage();
  void openKeyImage(RadKeyImage k);
  void captionKeyImage(RadKeyImage k, String caption);
  void deleteKeyImage(RadKeyImage k);

  void applyPreset(RadWindowPreset? preset);
  void saveCurrentPreset();
  void deletePreset(RadWindowPreset preset);
  void setFilters(RadFilterSettings f);
  void toggleInvert();
  void resetAdjustments();
}

CruIconData radKindIcon(RadAnnoKind k) => switch (k) {
      RadAnnoKind.length => RadViewerIcons.length,
      RadAnnoKind.angle => RadViewerIcons.angle,
      RadAnnoKind.polygon => RadViewerIcons.polygon,
      RadAnnoKind.ellipse => RadViewerIcons.ellipse,
      RadAnnoKind.rect => RadViewerIcons.rect,
      RadAnnoKind.polyline => RadViewerIcons.polyline,
      RadAnnoKind.arrow => RadViewerIcons.arrow,
      RadAnnoKind.text => RadViewerIcons.text,
      RadAnnoKind.freehand => RadViewerIcons.pen,
      RadAnnoKind.toothLabel => RadViewerIcons.tooth,
    };

/// The collapsible right panel: measurements, key images, image info,
/// adjustments and the AI second read for the active pane's image.
class RadViewerSidePanel extends StatelessWidget {
  const RadViewerSidePanel({
    super.key,
    required this.host,
    required this.width,
    required this.tab,
    required this.onTab,
    required this.study,
    required this.paneStudy,
    required this.pane,
    required this.annotations,
    required this.readOnly,
    required this.selectedId,
    required this.report,
    required this.mmPerPx,
    required this.roi,
    required this.studyDir,
    required this.header,
    required this.presets,
    required this.keyForKeyImage,
  });

  final RadSidePanelHost host;
  final double width;
  final RadPanelTab tab;
  final ValueChanged<RadPanelTab> onTab;

  /// The study being read.
  final RadStudy study;

  /// The study shown in the active pane (an earlier one when comparing).
  final RadStudy paneStudy;
  final RadPane pane;
  final List<RadAnnotation> annotations;
  final bool readOnly;
  final String? selectedId;
  final RadReport? report;
  final double? mmPerPx;
  final RadRoiCache roi;

  /// The study folder (key image PNGs live under it); null until known.
  final String? studyDir;

  /// DICOM header values of the active image; null for pictures.
  final Future<List<(String, String)>>? header;
  final List<RadWindowPreset> presets;

  /// The key bound to "Mark key image" ("K").
  final String keyForKeyImage;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s12, CruSpace.s12, CruSpace.s12, CruSpace.s8),
            child: _Tabs(selected: tab, onChanged: onTab),
          ),
          const CruSeparator(),
          Expanded(
            child: switch (tab) {
              RadPanelTab.measure => _MeasureTab(panel: this),
              RadPanelTab.keys => _KeysTab(panel: this),
              RadPanelTab.info => _InfoTab(panel: this),
              RadPanelTab.adjust => _AdjustTab(panel: this),
              RadPanelTab.ai => pane.imageId.isEmpty
                  ? const _Quiet('Open an image to run the AI second read on it.')
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(CruSpace.s12),
                      child: RadAiSecondReadPanel(
                        study: paneStudy,
                        imageId: pane.imageId,
                        pane: pane,
                      ),
                    ),
            },
          ),
        ],
      ),
    );
  }
}

/// Segmented tabs that share the panel's width.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onChanged});

  final RadPanelTab selected;
  final ValueChanged<RadPanelTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      height: CruSize.segmentHeight,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(color: c.inset, shape: cruShape(CruRadius.segmentOuter)),
      child: Row(
        children: [
          for (final t in RadPanelTab.values)
            Expanded(
              child: Semantics(
                selected: t == selected,
                child: CruPressable(
                  onTap: () => onChanged(t),
                  semanticLabel: t.label,
                  scaleOnPress: false,
                  builder: (context, hovered) => AnimatedContainer(
                    duration: CruMotion.of(context, CruMotion.fast),
                    curve: CruMotion.curve,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: t == selected ? c.segmentSelected : c.segmentSelected.withValues(alpha: 0),
                      shape: cruShape(CruRadius.segmentInner),
                      shadows: t == selected ? c.segmentShadow : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (t == RadPanelTab.ai) ...[
                          CruIcon(CruIcons.sparkleSingle, size: 12, strokeWidth: 2, color: c.ai),
                          const SizedBox(width: CruSpace.s2),
                        ],
                        Flexible(
                          child: Text(
                            t == RadPanelTab.keys ? 'Keys' : t.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: CruType.caption.copyWith(
                              fontWeight: t == selected ? FontWeight.w600 : FontWeight.w500,
                              color: t == selected || hovered ? c.label : c.label2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(CruSpace.s20),
        child: Text(text, style: CruType.text.tint(context.cru.label2)),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CruSpace.s4, CruSpace.s16, CruSpace.s4, CruSpace.s8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: CruType.groupLabel.tint(c.label3))),
          if (trailing != null) Text(trailing!, style: CruType.caption.tabular.tint(c.label2)),
        ],
      ),
    );
  }
}

// ───────────────────────────── Measure ─────────────────────────────

class _MeasureTab extends StatelessWidget {
  const _MeasureTab({required this.panel});

  final RadViewerSidePanel panel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final pane = panel.pane;
    if (pane.imageId.isEmpty) return const _Quiet('Open an image to measure it.');
    final ruler = panel.paneStudy.calibration[pane.imageId];
    final fileSpacing = panel.paneStudy.images
        .where((i) => i.id == pane.imageId)
        .map((i) => i.pixelSpacingMm)
        .firstOrNull;
    final report = panel.report;
    final signed = report?.isSigned ?? false;

    final (String calTitle, String calBody) = ruler != null
        ? ('Calibrated with the ruler', '${ruler.toStringAsFixed(4)} mm per pixel')
        : fileSpacing != null
            ? ('Calibrated from the file', '${fileSpacing.toStringAsFixed(4)} mm per pixel')
            : ('Not calibrated', 'Lengths and areas read in pixels');

    return ListView(
      padding: const EdgeInsets.all(CruSpace.s12),
      children: [
        Container(
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(color: c.inset, shape: cruShape(CruRadius.control)),
          child: Row(
            children: [
              CruIcon(RadViewerIcons.calibrate, size: 18, strokeWidth: 1.8, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(calTitle, style: CruType.callout.tint(c.label)),
                    Text(calBody, style: CruType.caption.tabular.tint(c.label2)),
                  ],
                ),
              ),
              if (!panel.readOnly) ...[
                if (ruler != null) ...[
                  CruCapsuleButton(
                    label: 'Clear',
                    kind: CruCapsuleKind.surface,
                    onPressed: panel.host.clearCalibration,
                  ),
                  const SizedBox(width: CruSpace.s6),
                ],
                CruCapsuleButton(
                  label: ruler != null ? 'Redo' : 'Calibrate',
                  kind: CruCapsuleKind.surface,
                  onPressed: panel.host.startCalibration,
                ),
              ],
            ],
          ),
        ),
        if (panel.readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(CruSpace.s4, CruSpace.s12, CruSpace.s4, 0),
            child: Text(
              'An earlier study, shown for comparison. Its marks are read only.',
              style: CruType.caption.tint(c.label2),
            ),
          ),
        _SectionLabel(
          'On this image',
          trailing: panel.annotations.isEmpty ? null : '${panel.annotations.length}',
        ),
        if (panel.annotations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            child: Text(
              panel.readOnly
                  ? 'No marks on this image.'
                  : 'No marks yet. Pick a tool in the toolbar (L for length, A for angle) and draw on the image.',
              style: CruType.text.tint(c.label2),
            ),
          ),
        for (final a in panel.annotations.reversed)
          _AnnotationRow(
            key: ValueKey(a.id),
            annotation: a,
            panel: panel,
            selected: a.id == panel.selectedId,
            included: report?.measurementIds.contains(a.id) ?? false,
            showInclude: report != null && a.kind.isMeasurement && !panel.readOnly,
            includeLocked: signed,
          ),
      ],
    );
  }
}

class _AnnotationRow extends StatelessWidget {
  const _AnnotationRow({
    super.key,
    required this.annotation,
    required this.panel,
    required this.selected,
    required this.included,
    required this.showInclude,
    required this.includeLocked,
  });

  final RadAnnotation annotation;
  final RadViewerSidePanel panel;
  final bool selected;
  final bool included;
  final bool showInclude;
  final bool includeLocked;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final a = annotation;
    final value = RadMeasure.valueText(a, panel.mmPerPx);
    final roi = panel.roi.text(a, panel.pane.px);
    final title = a.text.isNotEmpty ? a.text : RadMeasure.kindLabel(a.kind);
    final sub = [
      if (a.text.isNotEmpty) RadMeasure.kindLabel(a.kind),
      ?value,
      ?roi,
    ].join(' · ');
    return AnimatedContainer(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      margin: const EdgeInsets.only(bottom: CruSpace.s2),
      decoration: ShapeDecoration(
        color: selected ? c.inset : c.inset.withValues(alpha: 0),
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalListRow(
            minHeight: 52,
            semanticLabel: title,
            onTap: () => panel.host.select(selected ? null : a.id),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: selected ? c.surface : c.inset,
                    shape: cruShape(CruRadius.iconTile),
                  ),
                  child: CruIcon(radKindIcon(a.kind), size: 16, strokeWidth: 1.8, color: c.label2),
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: CruType.callout.tint(c.label)),
                      if (sub.isNotEmpty)
                        Text(sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.caption.tabular.tint(c.label2)),
                    ],
                  ),
                ),
                if (showInclude)
                  _Check(
                    value: included,
                    tooltip: includeLocked
                        ? 'The report is signed'
                        : included
                            ? 'In the report'
                            : 'Add to the report',
                    onChanged: includeLocked ? null : (v) => panel.host.includeInReport(a, v),
                  ),
                if (!panel.readOnly)
                  CruIconButton(
                    icon: RadIcons.trash,
                    size: 32,
                    iconSize: 16,
                    semanticLabel: 'Delete',
                    tooltip: 'Delete (Del)',
                    onPressed: () => panel.host.deleteAnnotation(a),
                  ),
              ],
            ),
          ),
          if (selected && !panel.readOnly) _AnnotationEditor(annotation: a, panel: panel),
        ],
      ),
    );
  }
}

/// A small checkbox for "include in report".
class _Check extends StatelessWidget {
  const _Check({required this.value, required this.onChanged, required this.tooltip});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = onChanged != null;
    return CruPressable(
      onTap: enabled ? () => onChanged!(!value) : null,
      semanticLabel: 'Include in report',
      tooltip: tooltip,
      builder: (context, hovered) => SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: value ? (enabled ? c.label : c.label3) : c.surface,
              shape: cruShape(
                CruRadius.keycap,
                side: value ? BorderSide.none : BorderSide(color: hovered ? c.label2 : c.label3),
              ),
            ),
            child: value ? CruIcon(CruIcons.check, size: 13, strokeWidth: 2.6, color: c.surface) : null,
          ),
        ),
      ),
    );
  }
}

/// Label and colour of the selected annotation.
class _AnnotationEditor extends StatefulWidget {
  const _AnnotationEditor({required this.annotation, required this.panel});

  final RadAnnotation annotation;
  final RadViewerSidePanel panel;

  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  late final _text = TextEditingController(text: widget.annotation.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_AnnotationEditor old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.annotation.text != _text.text) {
      _text.text = widget.annotation.text;
    }
  }

  void _commit() {
    final v = _text.text.trim();
    if (v != widget.annotation.text) widget.panel.host.renameAnnotation(widget.annotation, v);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.annotation;
    final current = RadInk.of(a);
    return Padding(
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, 0, CruSpace.s12, CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruTextField(
            label: a.kind == RadAnnoKind.toothLabel
                ? 'Tooth'
                : a.kind == RadAnnoKind.text
                    ? 'Note'
                    : 'Label',
            controller: _text,
            focusNode: _focus,
            hint: RadMeasure.kindLabel(a.kind),
            onSubmitted: (_) => _commit(),
          ),
          const SizedBox(height: CruSpace.s10),
          Row(
            children: [
              for (final s in RadInk.swatches)
                Padding(
                  padding: const EdgeInsets.only(right: CruSpace.s8),
                  child: CruPressable(
                    onTap: () => widget.panel.host.recolorAnnotation(a, s),
                    semanticLabel: 'Colour',
                    builder: (context, hovered) => Container(
                      width: 22,
                      height: 22,
                      decoration: ShapeDecoration(
                        color: s,
                        shape: CircleBorder(
                          side: BorderSide(
                            color: s.toARGB32() == current.toARGB32()
                                ? context.cru.label
                                : context.cru.separator,
                            width: s.toARGB32() == current.toARGB32() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Key images ─────────────────────────────

class _KeysTab extends StatelessWidget {
  const _KeysTab({required this.panel});

  final RadViewerSidePanel panel;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final keys = panel.study.keyImages.reversed.toList();
    final canMark = panel.pane.hasImage;
    return ListView(
      padding: const EdgeInsets.all(CruSpace.s12),
      children: [
        CruButton(
          label: 'Mark key image',
          icon: RadViewerIcons.keyImage,
          kind: CruButtonKind.inset,
          expand: true,
          onPressed: canMark ? panel.host.markKeyImage : null,
        ),
        const SizedBox(height: CruSpace.s6),
        Text(
          panel.keyForKeyImage.isEmpty
              ? 'Saves the pane as you see it, marks included, for the report.'
              : 'Or press ${panel.keyForKeyImage}. Saves the pane as you see it, marks included, for the report.',
          style: CruType.caption.tint(c.label2),
        ),
        _SectionLabel('Key images', trailing: keys.isEmpty ? null : '${keys.length}'),
        if (keys.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            child: Text('None yet.', style: CruType.text.tint(c.label2)),
          ),
        for (final k in keys) _KeyCard(key: ValueKey(k.id), keyImage: k, panel: panel),
      ],
    );
  }
}

class _KeyCard extends StatefulWidget {
  const _KeyCard({super.key, required this.keyImage, required this.panel});

  final RadKeyImage keyImage;
  final RadViewerSidePanel panel;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  late final _caption = TextEditingController(text: widget.keyImage.caption);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    final v = _caption.text.trim();
    if (v != widget.keyImage.caption) widget.panel.host.captionKeyImage(widget.keyImage, v);
  }

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final k = widget.keyImage;
    final dir = widget.panel.studyDir;
    final index = widget.panel.study.images.indexWhere((i) => i.id == k.imageId);
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(color: RadInk.viewport, shape: cruShape(CruRadius.control)),
            child: dir == null
                ? null
                : Image.file(
                    File(p.join(dir, k.pngPath)),
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => Center(
                      child: Text('Picture missing', style: CruType.caption.tint(RadInk.overlayQuiet)),
                    ),
                  ),
          ),
          const SizedBox(height: CruSpace.s8),
          TextField(
            controller: _caption,
            focusNode: _focus,
            style: CruType.text.tint(c.label),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _commit(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a caption',
              hintStyle: CruType.text.tint(c.label3),
              filled: true,
              fillColor: c.inset,
              contentPadding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s6),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (index >= 0) 'Image ${index + 1}',
                    RadFormat.dateTime(k.createdAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ),
              if (index >= 0)
                CruCapsuleButton(
                  label: 'Show',
                  height: CruSize.rowCapsule,
                  onPressed: () => widget.panel.host.openKeyImage(k),
                ),
              CruIconButton(
                icon: RadIcons.trash,
                size: 32,
                iconSize: 16,
                semanticLabel: 'Remove key image',
                tooltip: 'Remove',
                onPressed: () => widget.panel.host.deleteKeyImage(k),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Info ─────────────────────────────

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.panel});

  final RadViewerSidePanel panel;

  String _num(double v, [int digits = 1]) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final s = panel.paneStudy;
    final pane = panel.pane;
    final image = s.images.where((i) => i.id == pane.imageId).firstOrNull;
    final px = pane.px;
    final dose = s.dose;
    final ruler = s.calibration[pane.imageId];
    return ListView(
      padding: const EdgeInsets.fromLTRB(CruSpace.s12, 0, CruSpace.s12, CruSpace.s16),
      children: [
        if (image != null) ...[
          const _SectionLabel('Image'),
          _KV('Kind', image.kind == RadFileKind.dicom ? 'DICOM' : 'Picture'),
          if (px != null || image.width > 0)
            _KV('Size', '${px?.width ?? image.width} × ${px?.height ?? image.height} px'),
          if (image.frames > 1) _KV('Frames', '${image.frames}'),
          if (image.pixelSpacingMm != null)
            _KV('Pixel spacing', '${image.pixelSpacingMm!.toStringAsFixed(4)} mm'),
          if (ruler != null) _KV('Ruler calibration', '${ruler.toStringAsFixed(4)} mm per px'),
          if (image.seriesDescription.isNotEmpty) _KV('Series', image.seriesDescription),
          if (image.instanceNumber > 0) _KV('Instance', '${image.instanceNumber}'),
          if (image.compressed) _KV('Status', 'Compressed — not supported yet'),
          if (px != null) _KV('Values', '${_num(px.minValue)} to ${_num(px.maxValue)}'),
        ],
        const _SectionLabel('Study'),
        _KV('Type', s.modality.label),
        _KV('Taken', RadFormat.date(s.studyDate)),
        _KV('Received', RadFormat.dateTime(s.receivedAt)),
        if (s.description.isNotEmpty) _KV('Description', s.description),
        if (s.equipment.isNotEmpty) _KV('Equipment', s.equipment),
        if (s.institution.isNotEmpty) _KV('Institution', s.institution),
        if (s.bodyPart.isNotEmpty) _KV('Body part', s.bodyPart),
        if (s.accession.isNotEmpty) _KV('Accession', s.accession),
        if (s.patientExternalId.isNotEmpty) _KV('Scanner patient ID', s.patientExternalId),
        if (!dose.isEmpty) ...[
          const _SectionLabel('Dose'),
          if (dose.kvp != null) _KV('Tube voltage', '${_num(dose.kvp!)} kVp'),
          if (dose.ma != null) _KV('Tube current', '${_num(dose.ma!)} mA'),
          if (dose.exposureMs != null) _KV('Exposure time', '${_num(dose.exposureMs!)} ms'),
          if (dose.mas != null) _KV('Exposure', '${_num(dose.mas!)} mAs'),
          if (dose.dap != null) _KV('Dose-area product', _num(dose.dap!, 2)),
        ],
        if (panel.header != null)
          FutureBuilder<List<(String, String)>>(
            future: panel.header,
            builder: (context, snap) {
              final rows = snap.data;
              if (snap.hasError) {
                return const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_SectionLabel('DICOM header'), _KV('Header', "Couldn't be read")],
                );
              }
              if (rows == null) {
                return const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_SectionLabel('DICOM header'), _KV('Header', 'Reading…')],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('DICOM header'),
                  for (final (k, v) in rows) _KV(k, v),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4, vertical: CruSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 128, child: Text(label, style: CruType.caption.tint(c.label2))),
          Expanded(
            child: SelectableText(value, style: CruType.caption.tabular.tint(c.label)),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Adjust ─────────────────────────────

class _AdjustTab extends StatelessWidget {
  const _AdjustTab({required this.panel});

  final RadViewerSidePanel panel;

  static bool _matches(RadPane pane, double c, double w) {
    final px = pane.px;
    if (px == null) return false;
    final tol = ((px.highPct - px.lowPct).abs() * 0.01).clamp(1e-6, double.infinity);
    return (pane.center - c).abs() <= tol && (pane.width - w).abs() <= tol;
  }

  @override
  Widget build(BuildContext context) {
    final host = panel.host;
    return ListenableBuilder(
      listenable: panel.pane,
      builder: (context, _) {
        final c = context.cru;
        final pane = panel.pane;
        final px = pane.px;
        if (px == null) return const _Quiet('Open an image to adjust it.');
        final f = pane.filters;
        final (dc, dw) = px.defaultWindow;
        final range = (px.maxValue - px.minValue).abs();
        String n(double v) => range < 20 ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
        return ListView(
          padding: const EdgeInsets.fromLTRB(CruSpace.s12, 0, CruSpace.s12, CruSpace.s16),
          children: [
            _SectionLabel('Window', trailing: 'W ${n(pane.width)} · L ${n(pane.center)}'),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                DentalChoiceChip(
                  label: 'Default',
                  selected: _matches(pane, dc, dw),
                  onTap: () => host.applyPreset(null),
                ),
                for (final pr in [...radBuiltInPresets, ...panel.presets])
                  _PresetChip(
                    preset: pr,
                    selected: () {
                      final (pc, pw) = pr.resolve(px);
                      return _matches(pane, pc, pw);
                    }(),
                    onTap: () => host.applyPreset(pr),
                    onDelete: pr.custom ? () => host.deletePreset(pr) : null,
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s10),
            Align(
              alignment: Alignment.centerLeft,
              child: CruCapsuleButton(
                label: 'Save as preset',
                icon: CruIcons.plus,
                onPressed: host.saveCurrentPreset,
              ),
            ),
            const SizedBox(height: CruSpace.s6),
            Text(
              'Drag with the right mouse button on the image: sideways for contrast, up and down for brightness.',
              style: CruType.caption.tint(c.label2),
            ),
            const _SectionLabel('Display'),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                DentalChoiceChip(label: 'Invert', selected: pane.userInvert, onTap: host.toggleInvert),
                DentalChoiceChip(
                  label: 'Local contrast (CLAHE)',
                  selected: f.clahe,
                  onTap: () => host.setFilters(f.copyWith(clahe: !f.clahe)),
                ),
              ],
            ),
            _SliderRow(
              label: 'Gamma',
              value: f.gamma,
              min: 0.3,
              max: 3,
              format: (v) => v.toStringAsFixed(2),
              onChanged: (v) => host.setFilters(f.copyWith(gamma: v)),
            ),
            _SliderRow(
              label: 'Sharpen',
              value: f.sharpen,
              min: 0,
              max: 1,
              format: (v) => v == 0 ? 'Off' : '${(v * 100).round()}%',
              onChanged: (v) => host.setFilters(f.copyWith(sharpen: v)),
            ),
            if (!px.isColor) ...[
              const _SectionLabel('Colour map'),
              Wrap(
                spacing: CruSpace.s6,
                runSpacing: CruSpace.s6,
                children: [
                  for (final m in radColormaps)
                    DentalChoiceChip(
                      label: m == 'gray' ? 'Grey' : '${m[0].toUpperCase()}${m.substring(1)}',
                      selected: f.colormap == m,
                      onTap: () => host.setFilters(f.copyWith(colormap: m)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: CruSpace.s20),
            Align(
              alignment: Alignment.centerLeft,
              child: CruCapsuleButton(
                label: 'Reset adjustments',
                onPressed: host.resetAdjustments,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final RadWindowPreset preset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final chip = DentalChoiceChip(label: preset.name, selected: selected, onTap: onTap);
    final delete = onDelete;
    if (delete == null) return chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        CruPressable(
          onTap: delete,
          semanticLabel: 'Remove preset ${preset.name}',
          tooltip: 'Remove preset',
          builder: (context, hovered) => SizedBox(
            width: 22,
            height: CruSize.chip,
            child: Center(
              child: CruIcon(CruIcons.close, size: 12, strokeWidth: 2.2, color: hovered ? c.label : c.label3),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled slider that applies when the drag ends (sharpening runs
/// over the whole image).
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            child: Row(
              children: [
                Expanded(child: Text(widget.label, style: CruType.text.tint(c.label))),
                Text(widget.format(v), style: CruType.caption.tabular.tint(c.label2)),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: c.label2,
              inactiveTrackColor: c.track,
              thumbColor: c.surface,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2),
            ),
            child: Slider(
              value: v,
              min: widget.min,
              max: widget.max,
              onChanged: (x) => setState(() => _dragging = x),
              onChangeEnd: (x) {
                setState(() => _dragging = null);
                widget.onChanged(x);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The DICOM header future is cached per file so switching tabs doesn't
/// read the file again.
class RadHeaderCache {
  final _cache = <String, Future<List<(String, String)>>>{};

  Future<List<(String, String)>> get(String key, Future<List<(String, String)>> Function() load) =>
      _cache.putIfAbsent(key, load);
}
