import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/fmx_series_screen.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Whether [s] is a full-mouth series saved as one study (see
/// [FmxSeriesScreen]). Older single-film FMX studies are not.
bool isFmxSeriesStudy(RadStudy s) {
  final fmx = s.extras['fmx'];
  return fmx is Map && fmx['images'] is List;
}

/// FDI teeth of each image of a saved series, by image id.
Map<String, List<int>> fmxTeethByImage(RadStudy s) {
  final fmx = s.extras['fmx'];
  final out = <String, List<int>>{};
  if (fmx is Map && fmx['images'] is List) {
    for (final m in fmx['images'] as List) {
      if (m is! Map) continue;
      final teeth = m['teeth'];
      out['${m['imageId']}'] = [
        if (teeth is List)
          for (final t in teeth)
            if (t is num) t.toInt(),
      ];
    }
  } else if (fmx is Map && fmx['teeth'] is List) {
    // A single film saved by the first version of the series screen.
    final first = s.images.firstOrNull;
    if (first != null) {
      out[first.id] = [
        for (final t in fmx['teeth'] as List)
          if (t is num) t.toInt(),
      ];
    }
  }
  return out;
}

/// A saved full-mouth series in its mount, read-only. Tap a film to open
/// it in the X-ray viewer.
class FmxSeriesViewScreen extends ConsumerWidget {
  const FmxSeriesViewScreen({super.key, required this.study});
  final RadStudy study;

  FmxTemplate get _template {
    final fmx = study.extras['fmx'];
    final name = fmx is Map ? fmx['template'] : null;
    return fmxTemplates.firstWhere(
      (t) => t.name == name,
      orElse: () => fmxTemplates.first,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final template = _template;
    final slotImage = <String, RadImageRef>{};
    final fmx = study.extras['fmx'];
    if (fmx is Map && fmx['images'] is List) {
      final byId = {for (final i in study.images) i.id: i};
      for (final m in fmx['images'] as List) {
        if (m is! Map) continue;
        final img = byId['${m['imageId']}'];
        if (img != null) slotImage['${m['slot']}'] = img;
      }
    }
    final ctrl = ref.read(radiologyProvider);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(
          study.description,
          style: CruType.headline.w600.tint(c.label),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: FmxMount(
          template: template,
          imageFor: (slot) {
            final img = slotImage[slot.label];
            if (img == null) return null;
            return FutureBuilder<File>(
              future: ctrl.fileOf(study, img.path),
              builder: (_, snap) => snap.hasData
                  ? Image.file(snap.data!, fit: BoxFit.cover)
                  : const SizedBox.expand(),
            );
          },
          onTap: (slot) {
            final img = slotImage[slot.label];
            if (img == null) return;
            Navigator.of(context, rootNavigator: true).push(
              radRoute<void>(
                RadViewerScreen(
                  studyId: study.id,
                  initialStudy: study,
                  initialImageId: img.id,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
