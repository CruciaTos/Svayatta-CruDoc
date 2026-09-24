import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The study beside the report: referral, key images and measurements to
/// put in the report, the exposure, and the way back to the images.
class RadStudyContextPanel extends StatelessWidget {
  const RadStudyContextPanel({
    super.key,
    required this.study,
    required this.referrer,
    required this.rows,
    required this.keyImageIds,
    required this.measurementIds,
    required this.readOnly,
    required this.onToggleKeyImage,
    required this.onToggleMeasurement,
    required this.onIncludeAllMeasurements,
    required this.onOpenViewer,
  });

  final RadStudy study;
  final RadReferrer? referrer;
  final List<({String id, String label, String value})> rows;
  final List<String> keyImageIds;
  final List<String> measurementIds;
  final bool readOnly;
  final ValueChanged<String> onToggleKeyImage;
  final ValueChanged<String> onToggleMeasurement;
  final VoidCallback onIncludeAllMeasurements;

  /// Opens the viewer, at an image when given.
  final ValueChanged<String?> onOpenViewer;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final now = DateTime.now();
    final patient = RadFormat.patientLine(study, now);
    final dose = study.dose;
    final question = study.clinicalQuestion.trim();
    final notIncluded = rows.where((r) => !measurementIds.contains(r.id)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(CruSpace.s20, CruSpace.s20, CruSpace.s16, CruSpace.s24),
      children: [
        Row(
          children: [
            RadModalityBadge(study.modality),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(
                RadFormat.date(study.studyDate),
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ),
            ?radPriorityPill(c, study.priority),
          ],
        ),
        const SizedBox(height: CruSpace.s10),
        Text(
          study.description.trim().isEmpty ? study.modality.label : study.description.trim(),
          style: CruType.callout.tint(c.label),
        ),
        if (patient.isNotEmpty || study.patientExternalId.isNotEmpty)
          Text(
            [
              if (patient.isNotEmpty) patient,
              if (study.patientExternalId.isNotEmpty) 'ID ${study.patientExternalId}',
            ].join(' · '),
            style: CruType.subhead.tabular.tint(c.label2),
          ),
        if (referrer != null) ...[
          const SizedBox(height: CruSpace.s12),
          _Fact(label: 'Referred by', value: referrer!.display),
        ],
        if (question.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s12),
          _Fact(label: 'Clinical question', value: question),
        ],
        const SizedBox(height: CruSpace.s16),
        CruButton(
          label: 'Open viewer',
          kind: CruButtonKind.inset,
          icon: RadIcons.eye,
          expand: true,
          onPressed: () => onOpenViewer(null),
        ),
        _Heading(
          'Key images',
          trailing: study.keyImages.isEmpty
              ? null
              : '${study.keyImages.where((k) => keyImageIds.contains(k.id)).length} of '
                  '${study.keyImages.length} in report',
        ),
        if (study.keyImages.isEmpty)
          Text(
            'None yet. Mark the views that matter in the viewer (K) and they '
            'appear here and in the report.',
            style: CruType.caption.tint(c.label3),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - CruSpace.s8) / 2;
              return Wrap(
                spacing: CruSpace.s8,
                runSpacing: CruSpace.s12,
                children: [
                  for (final k in study.keyImages)
                    SizedBox(
                      width: w,
                      child: _KeyThumb(
                        study: study,
                        keyImage: k,
                        included: keyImageIds.contains(k.id),
                        readOnly: readOnly,
                        onToggle: () => onToggleKeyImage(k.id),
                        onOpen: () => onOpenViewer(k.imageId),
                      ),
                    ),
                ],
              );
            },
          ),
        _Heading(
          'Measurements',
          trailing: rows.isEmpty ? null : '${rows.length - notIncluded} of ${rows.length} in report',
        ),
        if (rows.isEmpty)
          Text(
            'None yet. Lengths, angles and areas drawn in the viewers are listed here.',
            style: CruType.caption.tint(c.label3),
          )
        else ...[
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
              child: Row(
                children: [
                  RadCheck(
                    value: measurementIds.contains(r.id),
                    semanticLabel: 'Include ${r.label} in the report',
                    onChanged: readOnly ? null : (_) => onToggleMeasurement(r.id),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: Text(
                      r.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.subhead.tint(c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Text(r.value, style: CruType.subhead.w600.tabular.tint(c.label)),
                ],
              ),
            ),
          if (!readOnly && notIncluded > 1) ...[
            const SizedBox(height: CruSpace.s6),
            Align(
              alignment: Alignment.centerLeft,
              child: CruLink(label: 'Include all', onPressed: onIncludeAllMeasurements),
            ),
          ],
        ],
        if (!dose.isEmpty || study.equipment.isNotEmpty) ...[
          const _Heading('Exposure'),
          if (study.equipment.isNotEmpty) _Fact(label: 'Unit', value: study.equipment),
          for (final (label, v, unit) in [
            ('Tube voltage', dose.kvp, 'kVp'),
            ('Tube current', dose.ma, 'mA'),
            ('Exposure time', dose.exposureMs, 'ms'),
            ('Exposure', dose.mas, 'mAs'),
            ('Dose-area product', dose.dap, 'dGy·cm²'),
          ])
            if (v != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: CruType.subhead.tint(c.label2))),
                    Text(
                      '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} $unit',
                      style: CruType.subhead.w500.tabular.tint(c.label),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s24, bottom: CruSpace.s10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: CruType.groupLabel.tint(c.label3))),
          if (trailing != null) Text(trailing!, style: CruType.caption.tabular.tint(c.label3)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CruType.caption.tint(c.label3)),
        const SizedBox(height: CruSpace.s2),
        Text(value, style: CruType.subhead.tint(c.label)),
      ],
    );
  }
}

/// A key image thumbnail (dark, as radiographs are read), its caption and
/// whether it goes in the report. Clicking the picture opens the viewer.
class _KeyThumb extends ConsumerStatefulWidget {
  const _KeyThumb({
    required this.study,
    required this.keyImage,
    required this.included,
    required this.readOnly,
    required this.onToggle,
    required this.onOpen,
  });

  final RadStudy study;
  final RadKeyImage keyImage;
  final bool included;
  final bool readOnly;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  ConsumerState<_KeyThumb> createState() => _KeyThumbState();
}

class _KeyThumbState extends ConsumerState<_KeyThumb> {
  late Future<File> _file = _resolve();

  Future<File> _resolve() =>
      ref.read(radiologyProvider).fileOf(widget.study, widget.keyImage.pngPath);

  @override
  void didUpdateWidget(_KeyThumb old) {
    super.didUpdateWidget(old);
    if (old.keyImage.pngPath != widget.keyImage.pngPath) _file = _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final caption = widget.keyImage.caption.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            CruPressable(
              onTap: widget.onOpen,
              semanticLabel: 'Open ${caption.isEmpty ? 'key image' : caption} in the viewer',
              tooltip: 'Open in the viewer',
              builder: (context, hovered) => AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                  child: ColoredBox(
                    color: const Color(0xFF000000),
                    child: FutureBuilder<File>(
                      future: _file,
                      builder: (context, snap) {
                        final f = snap.data;
                        if (f == null) return const SizedBox.shrink();
                        return Image.file(
                          f,
                          fit: BoxFit.contain,
                          cacheWidth: 480,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              'Image missing',
                              style: CruType.caption.tint(c.label3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: CruSpace.s6,
              right: CruSpace.s6,
              child: RadCheck(
                value: widget.included,
                semanticLabel: 'Include in the report',
                onChanged: widget.readOnly ? null : (_) => widget.onToggle(),
              ),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s4),
        Text(
          caption.isEmpty ? DentalFormat.shortDate(widget.keyImage.createdAt) : caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: CruType.caption.tint(caption.isEmpty ? c.label3 : c.label2),
        ),
      ],
    );
  }
}
