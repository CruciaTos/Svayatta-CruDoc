import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_photos_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_comparison_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dialog for browsing, capturing, managing, and comparing per-session Physiotherapy photo records.
class PhysioPhotosDialog extends ConsumerStatefulWidget {
  const PhysioPhotosDialog({
    super.key,
    required this.patient,
    this.initialVisitId,
    this.initialSessionNumber,
  });

  final Patient patient;
  final String? initialVisitId;
  final int? initialSessionNumber;

  @override
  ConsumerState<PhysioPhotosDialog> createState() => _PhysioPhotosDialogState();
}

class _PhysioPhotosDialogState extends ConsumerState<PhysioPhotosDialog> {
  String? _selectedSetId;

  Future<void> _createSession(int nextSessionNumber) async {
    final labelCtrl = TextEditingController(text: 'Session $nextSessionNumber');
    final notesCtrl = TextEditingController();
    int sessionNum = nextSessionNumber;

    final chosen = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => CruFormDialog(
          title: 'New physiotherapy session photo series',
          subtitle: '${widget.patient.fullName} · Session $sessionNum',
          width: 480,
          submitLabel: 'Create session',
          onSubmit: () => Navigator.of(ctx).pop(true),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PRESETS',
                style: CruType.micro.w600.tint(ctx.cru.label2),
              ),
              const SizedBox(height: CruSpace.s6),
              Wrap(
                spacing: CruSpace.s8,
                runSpacing: CruSpace.s8,
                children: [
                  for (final preset in [
                    'Initial Assessment',
                    'Progress Evaluation',
                    'Mid-treatment Review',
                    'Discharge / Final',
                  ])
                    DentalChoiceChip(
                      label: preset,
                      selected: labelCtrl.text.contains(preset),
                      onTap: () {
                        setDialogState(() {
                          labelCtrl.text = 'Session $sessionNum - $preset';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Session label',
                controller: labelCtrl,
              ),
              const SizedBox(height: CruSpace.s12),
              CruTextField(
                label: 'Session notes / clinical focus (optional)',
                controller: notesCtrl,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == true && mounted) {
      final now = DateTime.now();
      final record = DentalRecord.create(
        widget.patient.id,
        RecKind.physioPhotoSet,
        {
          'sessionNumber': sessionNum,
          'visitId': widget.initialVisitId,
          'label': labelCtrl.text.trim().isNotEmpty
              ? labelCtrl.text.trim()
              : 'Session $sessionNum',
          'notes': notesCtrl.text.trim(),
          'photos': <String, String>{},
        },
        at: now,
      );
      await saveDentalRecord(ref, record);
      if (mounted) {
        setState(() => _selectedSetId = record.id);
        recToast(context, 'Session record created');
      }
    }
  }

  Future<void> _pickPhoto(PhysioPhotoSet set, PhysioPhotoSlot slot) async {
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
        p.join(appSupport.path, 'therapy', 'photos', widget.patient.id, set.id),
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

  Future<void> _deletePhoto(PhysioPhotoSet set, PhysioPhotoSlot slot) async {
    final ok = await confirmDental(
      context,
      title: 'Remove photo?',
      body: 'Remove ${slot.title} from ${set.label}?',
      action: 'Remove',
    );
    if (!ok || !mounted) return;

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
      recToast(context, '${slot.title} removed');
    }
  }

  Future<void> _deleteSession(PhysioPhotoSet set) async {
    final ok = await confirmDental(
      context,
      title: 'Delete session photos?',
      body: 'Delete "${set.label}" and all ${set.filledCount} associated clinical photos?',
      action: 'Delete session',
    );
    if (!ok || !mounted) return;

    for (final path in set.photos.values) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }

    await deleteDentalRecord(ref, set.record);
    if (mounted) {
      setState(() => _selectedSetId = null);
      recToast(context, 'Session photos deleted');
    }
  }

  void _openFullScreenViewer(String imagePath, String title, String subtitle) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(CruSpace.s24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CruType.title2.w600.tint(Colors.white),
                    ),
                    Text(
                      subtitle,
                      style: CruType.caption.tint(Colors.white70),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CruRadius.control),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recordsAsync = ref.watch(
      patientRecordsProvider(
        (patientId: widget.patient.id, kind: RecKind.physioPhotoSet),
      ),
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
        final sets = records.map(PhysioPhotoSet.fromRecord).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (sets.isNotEmpty &&
            (_selectedSetId == null ||
                !sets.any((s) => s.id == _selectedSetId))) {
          _selectedSetId = sets.first.id;
        }

        final selectedSet = sets.isEmpty
            ? null
            : sets.firstWhere(
                (s) => s.id == _selectedSetId,
                orElse: () => sets.first,
              );

        final nextNum = sets.isEmpty
            ? 1
            : sets.map((s) => s.sessionNumber).fold<int>(0, (m, v) => v > m ? v : m) + 1;

        return DentalPanelDialog(
          title: 'Physiotherapy Session Photos',
          subtitle:
              '${widget.patient.fullName} · Posture, alignment & movement records',
          width: 1040,
          body: SizedBox(
            height: 600,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sessions list sidebar
                SizedBox(
                  width: 260,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(CruRadius.control),
                      border: Border.all(color: c.hairline),
                    ),
                    padding: const EdgeInsets.all(CruSpace.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SESSIONS (${sets.length})',
                              style: CruType.micro.w600.tint(c.label2),
                            ),
                            CruCapsuleButton(
                              label: '+ Session',
                              icon: CruIcons.plus,
                              onPressed: () => _createSession(nextNum),
                            ),
                          ],
                        ),
                        const SizedBox(height: CruSpace.s12),
                        if (sets.isEmpty)
                          Expanded(
                            child: Center(
                              child: Text(
                                'No sessions recorded yet.\nClick "+ Session" above.',
                                textAlign: TextAlign.center,
                                style: CruType.caption.tint(c.label3),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: sets.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: CruSpace.s8),
                              itemBuilder: (ctx, i) {
                                final s = sets[i];
                                final isSelected = s.id == _selectedSetId;
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedSetId = s.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(CruSpace.s10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? c.canvas : c.surface,
                                      borderRadius: BorderRadius.circular(CruRadius.control),
                                      border: Border.all(
                                        color: isSelected ? c.accent : c.hairline,
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: CruSpace.s6,
                                                vertical: CruSpace.s2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? c.accent.withValues(alpha: 0.15)
                                                    : c.hairline,
                                                borderRadius: BorderRadius.circular(CruRadius.full),
                                              ),
                                              child: Text(
                                                'S${s.sessionNumber}',
                                                style: CruType.micro.w600.tint(
                                                  isSelected ? c.accent : c.label2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: CruSpace.s8),
                                            Expanded(
                                              child: Text(
                                                s.label,
                                                style: CruType.body.w600.tint(c.label),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: CruSpace.s4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              DentalFormat.date(s.date),
                                              style: CruType.caption.tint(c.label2),
                                            ),
                                            Text(
                                              '${s.filledCount}/8 photos',
                                              style: CruType.micro.w600.tint(
                                                s.filledCount > 0 ? c.accent : c.label3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: CruSpace.s16),

                // Main session content & 8 photo slots
                Expanded(
                  child: selectedSet == null
                      ? DentalEmptyState(
                          icon: CruIcons.box,
                          title: 'No session selected',
                          body: 'Create a session or select one on the left to add posture and movement photos.',
                          actions: [
                            CruButton(
                              label: 'Create first session',
                              icon: CruIcons.plus,
                              onPressed: () => _createSession(1),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Session header banner
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CruSpace.s16,
                                vertical: CruSpace.s12,
                              ),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(CruRadius.control),
                                border: Border.all(color: c.hairline),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              selectedSet.label,
                                              style: CruType.title2.w600.tint(c.label),
                                            ),
                                            const SizedBox(width: CruSpace.s10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: CruSpace.s8,
                                                vertical: CruSpace.s2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: c.accent.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(CruRadius.full),
                                              ),
                                              child: Text(
                                                '${selectedSet.filledCount}/8 photos',
                                                style: CruType.caption.w600.tint(c.accent),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: CruSpace.s4),
                                        Text(
                                          'Recorded on ${DentalFormat.date(selectedSet.date)}${selectedSet.notes.isNotEmpty ? ' · "${selectedSet.notes}"' : ''}',
                                          style: CruType.caption.tint(c.label2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Compare sessions button
                                  CruButton(
                                    label: 'Compare',
                                    icon: CruIcons.search,
                                    kind: CruButtonKind.secondary,
                                    onPressed: sets.length >= 2
                                        ? () {
                                            showDialog<void>(
                                              context: context,
                                              builder: (_) => PhysioBeforeAfterDialog(
                                                patient: widget.patient,
                                                initialBeforeSet: sets.last,
                                                initialAfterSet: selectedSet,
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                  const SizedBox(width: CruSpace.s8),
                                  IconButton(
                                    tooltip: 'Delete session',
                                    icon: Icon(Icons.delete_outline, color: c.label2, size: 20),
                                    onPressed: () => _deleteSession(selectedSet),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: CruSpace.s12),

                            // 8 Photo Slots Grid (4 x 2)
                            Expanded(
                              child: GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: CruSpace.s10,
                                  mainAxisSpacing: CruSpace.s10,
                                ),
                                itemCount: PhysioPhotoSlot.values.length,
                                itemBuilder: (ctx, idx) {
                                  final slot = PhysioPhotoSlot.values[idx];
                                  final photoPath = selectedSet.photoFor(slot);
                                  final hasPhoto = photoPath != null;

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: c.surface,
                                      borderRadius: BorderRadius.circular(CruRadius.control),
                                      border: Border.all(
                                        color: hasPhoto ? c.accent.withValues(alpha: 0.5) : c.hairline,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (hasPhoto) ...[
                                          // Photo preview
                                          GestureDetector(
                                            onTap: () => _openFullScreenViewer(
                                              photoPath,
                                              slot.title,
                                              '${selectedSet.label} · ${DentalFormat.date(selectedSet.date)}',
                                            ),
                                            child: Image.file(
                                              File(photoPath),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          // Bottom gradient overlay with title
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: CruSpace.s8,
                                                vertical: CruSpace.s6,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [
                                                    Colors.black87,
                                                    Colors.black.withValues(alpha: 0.0),
                                                  ],
                                                ),
                                              ),
                                              child: Text(
                                                slot.title,
                                                style: CruType.caption.w600.tint(Colors.white),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          // Top action icons (Zoom, Replace, Delete)
                                          Positioned(
                                            top: CruSpace.s4,
                                            right: CruSpace.s4,
                                            child: Container(
                                              padding: const EdgeInsets.all(CruSpace.s2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(CruRadius.control),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Retake / replace',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(
                                                      minWidth: 26,
                                                      minHeight: 26,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.refresh,
                                                      size: 16,
                                                      color: Colors.white,
                                                    ),
                                                    onPressed: () => _pickPhoto(selectedSet, slot),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Delete',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(
                                                      minWidth: 26,
                                                      minHeight: 26,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 16,
                                                      color: Colors.white,
                                                    ),
                                                    onPressed: () => _deletePhoto(selectedSet, slot),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          // Empty slot placeholder
                                          InkWell(
                                            onTap: () => _pickPhoto(selectedSet, slot),
                                            child: Padding(
                                              padding: const EdgeInsets.all(CruSpace.s10),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.camera_alt_outlined,
                                                    size: 28,
                                                    color: c.label3,
                                                  ),
                                                  const SizedBox(height: CruSpace.s8),
                                                  Text(
                                                    slot.title,
                                                    textAlign: TextAlign.center,
                                                    style: CruType.body.w600.tint(c.label),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: CruSpace.s4),
                                                  Text(
                                                    slot.subtitle,
                                                    textAlign: TextAlign.center,
                                                    style: CruType.micro.tint(c.label3),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: CruSpace.s8),
                                                  CruCapsuleButton(
                                                    label: 'Upload',
                                                    icon: CruIcons.plus,
                                                    onPressed: () => _pickPhoto(selectedSet, slot),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
