import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the CBCT 3D viewer will do (approved; not built yet).
const _planned = <(String, String)>[
  ('Axial, coronal and sagittal', 'Linked crosshairs, tilted planes, thick slab (MIP / average)'),
  ('Panoramic from CBCT', 'Draw or auto-detect the arch; numbered cross-sections along it'),
  ('Nerve canal', 'Trace the mandibular canal; distance to canal on every measurement'),
  ('3D rendering', 'Bone, teeth, soft tissue and X-ray presets in ivory, with clipping and cut tools'),
  ('Measurements in 3D', 'Distances, angles and lesion volume'),
  ('Airway', 'Volume and the narrowest cross-section'),
  ('Sinus and TMJ views', 'Both condyles side by side'),
  ('Implant planning', 'Implant library, bone density along the implant, canal warning'),
  ('Export', 'STL for 3D printing and a rotating GIF'),
];

/// The CBCT 3D viewer's place in the app. The 3D work is planned but not
/// built yet, so this page says so and lists what's coming; the slices
/// can be read now in the 2D viewer.
class CbctViewerScreen extends ConsumerWidget {
  const CbctViewerScreen({super.key, required this.studyId});

  final String studyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final study = ref.watch(radStudyProvider(studyId)).value;
    final slices = study?.images.fold<int>(0, (n, i) => n + i.frames) ?? 0;

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Padding(
          padding: CruSpace.mainPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CruIconButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('3D viewer', style: CruType.largeTitle.tint(c.label)),
                        if (study != null)
                          Text(
                            '${study.patientName} · ${study.modality.label} · '
                            '${RadFormat.date(study.studyDate)} · $slices slices',
                            style: CruType.text.tabular.tint(c.label2),
                          ),
                      ],
                    ),
                  ),
                  CruButton(
                    label: 'Read slices in 2D',
                    icon: RadIcons.xray,
                    onPressed: study == null
                        ? null
                        : () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                              builder: (_) => Theme(
                                data: Theme.of(context),
                                child: RadViewerScreen(studyId: studyId),
                              ),
                            )),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.cardGap),
              const RadNotConnected(
                icon: RadIcons.cube,
                title: 'The 3D viewer isn\'t built yet',
                body: 'It\'s planned and will open here for CBCT studies. Until then, page '
                    'through the slices in the 2D viewer: measurements, key images and the '
                    'report all work there.',
              ),
              const SizedBox(height: CruSpace.cardGap),
              Expanded(
                child: CruCard(
                  semanticLabel: 'Coming in the 3D viewer',
                  child: ListView(
                    children: [
                      Text('Coming in the 3D viewer', style: CruType.headline.tint(c.label)),
                      const SizedBox(height: CruSpace.s12),
                      for (final (title, body) in _planned)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CruIconTile(icon: RadIcons.cube, tone: CruTileTone.neutral),
                              const SizedBox(width: CruSpace.s12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: CruType.callout.tint(c.label)),
                                    Text(body, style: CruType.subhead.tint(c.label2)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A CBCT volume: several slices, or one multi-frame file.
bool radIsVolume(RadStudy s) {
  if (!s.modality.isVolume) return false;
  final readable = s.images.where((i) => !i.compressed).toList();
  return readable.length > 1 || (readable.length == 1 && readable.first.frames > 1);
}
