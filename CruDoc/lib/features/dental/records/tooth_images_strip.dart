import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/file_thumb.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/fmx_series_view.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const double _tile = 64;

/// The patient's pictures of one tooth: Files linked to it (intraoral
/// camera) and full-mouth series films that cover it. Hidden when there
/// are none.
class ToothImagesStrip extends ConsumerWidget {
  const ToothImagesStrip({super.key, required this.patient, required this.tooth});

  final Patient patient;
  final int tooth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final files = [
      for (final f
          in ref.watch(patientFilesProvider(patient.id)).value ??
              const <PatientFile>[])
        if (f.teeth.contains(tooth) &&
            PatientFileTypes.isViewableImage(f.contentType))
          f,
    ];
    final films = <(RadStudy, RadImageRef)>[];
    for (final s in ref.watch(radStudiesProvider).value ?? const <RadStudy>[]) {
      if (s.patientId != patient.id) continue;
      final teeth = fmxTeethByImage(s);
      for (final i in s.images) {
        if (teeth[i.id]?.contains(tooth) ?? false) films.add((s, i));
      }
    }
    if (files.isEmpty && films.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s16),
      child: CruCard(
        semanticLabel: 'Images of tooth $tooth',
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Images', style: CruType.headline.tint(c.label)),
            ),
            const SizedBox(height: CruSpace.s12),
            Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s8,
              children: [
                for (final (s, i) in films)
                  _FilmTile(study: s, image: i, ref: ref),
                for (final f in files)
                  InkWell(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    onTap: () => FilesActions.open(
                      context,
                      f,
                      patientName: patient.fullName,
                    ),
                    child: FileThumb(
                      file: f,
                      width: _tile,
                      height: _tile,
                      radius: CruRadius.control,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilmTile extends StatelessWidget {
  const _FilmTile({required this.study, required this.image, required this.ref});

  final RadStudy study;
  final RadImageRef image;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final box = BorderRadius.circular(CruRadius.control);
    final icon = CruIcon(RadIcons.xray, size: 24, color: c.label2);
    return InkWell(
      borderRadius: box,
      onTap: () => openRadStudy(context, ref, study, imageId: image.id),
      child: Container(
        width: _tile,
        height: _tile,
        decoration: BoxDecoration(
          color: c.inset,
          borderRadius: box,
          border: Border.all(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<File>(
          future: ref.read(radiologyProvider).fileOf(study, image.path),
          builder: (_, snap) => snap.hasData
              ? Image.file(
                  snap.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(child: icon),
                )
              : Center(child: icon),
        ),
      ),
    );
  }
}
