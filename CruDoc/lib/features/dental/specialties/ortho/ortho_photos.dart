import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/ortho/ortho_slider.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The 8 standard orthodontic clinical photo slots.
enum OrthoPhotoSlot {
  frontal('Extraoral Frontal', 'Facial at rest', 'M12 2a7 7 0 0 0-7 7v4a7 7 0 0 0 14 0V9a7 7 0 0 0-7-7z'),
  smile('Extraoral Smile', 'Full smile display', 'M12 2a7 7 0 0 0-7 7v4a7 7 0 0 0 14 0V9a7 7 0 0 0-7-7zM8 13s1.5 2 4 2 4-2 4-2'),
  profile('Extraoral Profile', 'Lateral soft tissue', 'M9 3a6 6 0 0 1 6 6v3a2 2 0 0 1-2 2h-1v2a3 3 0 0 1-3 3'),
  intraFrontal('Intraoral Frontal', 'Centric occlusion', 'M4 8h16v8H4zM4 12h16'),
  intraRight('Intraoral Right', 'Right molar / canine relation', 'M6 8h12v8H6zM14 8v8'),
  intraLeft('Intraoral Left', 'Left molar / canine relation', 'M6 8h12v8H6zM10 8v8'),
  occlusalUpper('Occlusal Upper', 'Maxillary arch & palate', 'M4 16c2-8 14-8 16 0'),
  occlusalLower('Occlusal Lower', 'Mandibular arch alignment', 'M4 8c2 8 14 8 16 0');

  final String title;
  final String subtitle;
  final String svgPath;
  const OrthoPhotoSlot(this.title, this.subtitle, this.svgPath);
}

/// In-memory model for an orthodontic 8-slot photo set.
class OrthoPhotoSet {
  final String id;
  final String patientId;
  final String label;
  final DateTime date;
  final Map<String, String> photos;
  final DentalRecord record;

  const OrthoPhotoSet({
    required this.id,
    required this.patientId,
    required this.label,
    required this.date,
    required this.photos,
    required this.record,
  });

  factory OrthoPhotoSet.fromRecord(DentalRecord r) {
    final d = r.data;
    final photosMap = <String, String>{};
    if (d['photos'] is Map) {
      (d['photos'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          photosMap[k.toString()] = v.toString();
        }
      });
    }

    return OrthoPhotoSet(
      id: r.id,
      patientId: r.patientId,
      label: (d['label'] as String?)?.isNotEmpty == true ? d['label'] as String : 'Series',
      date: r.recordedAt,
      photos: photosMap,
      record: r,
    );
  }

  int get filledCount {
    var count = 0;
    for (final slot in OrthoPhotoSlot.values) {
      final path = photos[slot.name];
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        count++;
      }
    }
    return count;
  }

  String? photoFor(OrthoPhotoSlot slot) {
    final path = photos[slot.name];
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }
}

/// Dialog / View for browsing, capturing, and comparing Orthodontic Photo series.
class OrthoPhotosDialog extends ConsumerStatefulWidget {
  const OrthoPhotosDialog({
    super.key,
    required this.patient,
    this.onCompareRequested,
  });

  final Patient patient;
  final void Function(OrthoPhotoSet before, OrthoPhotoSet after)? onCompareRequested;

  @override
  ConsumerState<OrthoPhotosDialog> createState() => _OrthoPhotosDialogState();
}

class _OrthoPhotosDialogState extends ConsumerState<OrthoPhotosDialog> {
  String? _selectedSetId;

  Future<void> _createSeries([String defaultLabel = 'Progress']) async {
    final labelCtrl = TextEditingController(text: defaultLabel);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'New orthodontic photo series',
        subtitle: widget.patient.fullName,
        width: 440,
        submitLabel: 'Create series',
        onSubmit: () => Navigator.of(ctx).pop(labelCtrl.text.trim()),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: CruSpace.s8,
              children: [
                for (final preset in ['Start', 'Progress', 'Debond', 'Retention'])
                  DentalChoiceChip(
                    label: preset,
                    selected: labelCtrl.text == preset,
                    onTap: () {
                      labelCtrl.text = preset;
                      (ctx as Element).markNeedsBuild();
                    },
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            CruTextField(
              label: 'Series label',
              controller: labelCtrl,
            ),
          ],
        ),
      ),
    );

    if (chosen != null && chosen.isNotEmpty) {
      final now = DateTime.now();
      final record = DentalRecord.create(
        widget.patient.id,
        RecKind.photoSet,
        {
          'label': chosen,
          'photos': <String, String>{},
        },
        at: now,
      );
      await saveDentalRecord(ref, record);
      if (mounted) {
        setState(() => _selectedSetId = record.id);
        recToast(context, 'Series "$chosen" created');
      }
    }
  }

  Future<void> _pickPhoto(OrthoPhotoSet set, OrthoPhotoSlot slot) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      dialogTitle: 'Select ${slot.title} photo',
    );

    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    try {
      final appSupport = await getApplicationSupportDirectory();
      final targetDir = Directory(
        p.join(appSupport.path, 'dental', 'ortho', widget.patient.id, set.id),
      );
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final ext = p.extension(sourcePath);
      final destPath = p.join(targetDir.path, '${slot.name}$ext');
      await File(sourcePath).copy(destPath);

      final nextPhotos = Map<String, String>.from(set.photos);
      nextPhotos[slot.name] = destPath;

      final updated = set.record.copyWith(
        data: {
          ...set.record.data,
          'photos': nextPhotos,
        },
      );
      await saveDentalRecord(ref, updated);
      if (mounted) {
        setState(() {});
        recToast(context, '${slot.title} photo saved');
      }
    } catch (e) {
      if (mounted) recToast(context, 'Failed to save photo: $e');
    }
  }

  Future<void> _removePhoto(OrthoPhotoSet set, OrthoPhotoSlot slot) async {
    final ok = await confirmDental(
      context,
      title: 'Remove photo?',
      body: 'Remove ${slot.title} from this series?',
      action: 'Remove',
    );
    if (!ok) return;

    final existingPath = set.photos[slot.name];
    if (existingPath != null) {
      final file = File(existingPath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }

    final nextPhotos = Map<String, String>.from(set.photos)..remove(slot.name);
    final updated = set.record.copyWith(
      data: {
        ...set.record.data,
        'photos': nextPhotos,
      },
    );
    await saveDentalRecord(ref, updated);
    if (mounted) {
      setState(() {});
      recToast(context, 'Photo removed');
    }
  }

  void _viewFullPhoto(String path, String title, OrthoPhotoSet set, OrthoPhotoSlot slot) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.cru;
        return Dialog(
          backgroundColor: c.surface,
          insetPadding: const EdgeInsets.all(CruSpace.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s16,
                    vertical: CruSpace.s12,
                  ),
                  child: Row(
                    children: [
                      Text(title, style: CruType.callout.w600.tint(c.label)),
                      const Spacer(),
                      CruCapsuleButton(
                        label: 'Replace',
                        icon: CruIcons.pen,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _pickPhoto(set, slot);
                        },
                      ),
                      const SizedBox(width: CruSpace.s8),
                      CruCapsuleButton(
                        label: 'Remove',
                        icon: CruIcons.close,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _removePhoto(set, slot);
                        },
                      ),
                      const SizedBox(width: CruSpace.s8),
                      CruIconButton(
                        icon: CruIcons.close,
                        semanticLabel: 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const CruSeparator(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(CruSpace.s16),
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recordsAsync = ref.watch(
      patientRecordsProvider((patientId: widget.patient.id, kind: RecKind.photoSet)),
    );

    return recordsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(CruSpace.s24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (records) {
        final sets = records.map(OrthoPhotoSet.fromRecord).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (sets.isEmpty) {
          return DentalPanelDialog(
            title: 'Orthodontic Photo Series',
            subtitle: widget.patient.fullName,
            body: DentalEmptyState(
              icon: CruIcons.box,
              title: 'No photo series captured yet',
              body: 'Record standard 8-view orthodontic photo sets for start, progress, and debond.',
              actions: [
                CruButton(
                  label: 'Start photo series',
                  icon: CruIcons.plus,
                  onPressed: () => _createSeries('Start'),
                ),
              ],
            ),
          );
        }

        final activeSet = sets.where((s) => s.id == _selectedSetId).firstOrNull ?? sets.first;

        return DentalPanelDialog(
          title: 'Orthodontic Photo Series',
          subtitle: '${widget.patient.fullName} · 8-view clinical records',
          width: 960,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top actions bar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (sets.length >= 2) ...[
                    CruButton(
                      label: 'Compare before & after',
                      icon: CruIcons.importExport,
                      kind: CruButtonKind.secondary,
                      onPressed: () {
                        final sortedOldestFirst = [...sets]..sort((a, b) => a.date.compareTo(b.date));
                        if (widget.onCompareRequested != null) {
                          widget.onCompareRequested!(
                            sortedOldestFirst.first,
                            sortedOldestFirst.last,
                          );
                        } else {
                          showDialog<void>(
                            context: context,
                            builder: (_) => OrthoBeforeAfterDialog(
                              patient: widget.patient,
                              initialBeforeSet: sortedOldestFirst.first,
                              initialAfterSet: sortedOldestFirst.last,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  CruButton(
                    label: 'New series',
                    icon: CruIcons.plus,
                    kind: CruButtonKind.primary,
                    onPressed: () => _createSeries('Progress'),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              // Series selection bar
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in sets) ...[
                            DentalChoiceChip(
                              label: '${s.label} (${DentalFormat.date(s.date)})',
                              selected: s.id == activeSet.id,
                              onTap: () => setState(() => _selectedSetId = s.id),
                            ),
                            const SizedBox(width: CruSpace.s6),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  CruPill(
                    text: '${activeSet.filledCount} of 8',
                    background: activeSet.filledCount == 8 ? c.greenTint : c.inset,
                    foreground: activeSet.filledCount == 8 ? c.greenText : c.label2,
                  ),
                  const SizedBox(width: CruSpace.s8),
                  PopupMenuButton<String>(
                    tooltip: 'Series actions',
                    icon: CruIcon(CruIcons.more, size: 18, color: c.label2),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'delete', child: Text('Delete series')),
                    ],
                    onSelected: (action) async {
                      if (action == 'delete') {
                        final ok = await confirmDental(
                          context,
                          title: 'Delete series?',
                          body: 'Delete "${activeSet.label}" and all attached photos?',
                          action: 'Delete',
                        );
                        if (ok) {
                          await deleteDentalRecord(ref, activeSet.record);
                          if (mounted) {
                            setState(() => _selectedSetId = null);
                          }
                          if (context.mounted) {
                            recToast(context, 'Series deleted');
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),

              // 8-slot Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 4;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: CruSpace.s12,
                      mainAxisSpacing: CruSpace.s12,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: OrthoPhotoSlot.values.length,
                    itemBuilder: (context, index) {
                      final slot = OrthoPhotoSlot.values[index];
                      final photoPath = activeSet.photoFor(slot);
                      return _PhotoSlotTile(
                        slot: slot,
                        photoPath: photoPath,
                        onTap: () {
                          if (photoPath != null) {
                            _viewFullPhoto(photoPath, slot.title, activeSet, slot);
                          } else {
                            _pickPhoto(activeSet, slot);
                          }
                        },
                        onAdd: () => _pickPhoto(activeSet, slot),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoSlotTile extends StatelessWidget {
  const _PhotoSlotTile({
    required this.slot,
    required this.photoPath,
    required this.onTap,
    required this.onAdd,
  });

  final OrthoPhotoSlot slot;
  final String? photoPath;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hasPhoto = photoPath != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CruRadius.control),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: hasPhoto ? c.hairline : c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
              )
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.inset,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CruIcon(CruIcons.box, size: 18, color: c.label3),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s8),
                  Text(
                    slot.title,
                    textAlign: TextAlign.center,
                    style: CruType.caption.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
                    child: Text(
                      slot.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.micro.tint(c.label3),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s6),
                  CruCapsuleButton(
                    label: 'Add photo',
                    icon: CruIcons.plus,
                    onPressed: onAdd,
                  ),
                ],
              ),

            // Top caption overlay when photo is present
            if (hasPhoto)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                    vertical: CruSpace.s4,
                  ),
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          slot.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.micro.w600.tint(Colors.white),
                        ),
                      ),
                      const CruIcon(CruIcons.check, size: 14, color: Colors.white),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
