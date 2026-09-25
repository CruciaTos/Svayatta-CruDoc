import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_photos_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Screen/dialog displaying an interactive split Before/After comparison slider
/// or Side-by-side view with PNG export functionality for Physiotherapy sessions.
class PhysioBeforeAfterDialog extends ConsumerStatefulWidget {
  const PhysioBeforeAfterDialog({
    super.key,
    required this.patient,
    this.initialBeforeSet,
    this.initialAfterSet,
    this.initialSlot = PhysioPhotoSlot.anterior,
  });

  final Patient patient;
  final PhysioPhotoSet? initialBeforeSet;
  final PhysioPhotoSet? initialAfterSet;
  final PhysioPhotoSlot initialSlot;

  @override
  ConsumerState<PhysioBeforeAfterDialog> createState() =>
      _PhysioBeforeAfterDialogState();
}

class _PhysioBeforeAfterDialogState
    extends ConsumerState<PhysioBeforeAfterDialog> {
  final GlobalKey _exportBoundaryKey = GlobalKey();

  PhysioPhotoSet? _beforeSet;
  PhysioPhotoSet? _afterSet;
  late PhysioPhotoSlot _selectedSlot;

  /// Divider position from 0.0 (all After) to 1.0 (all Before).
  double _dividerFraction = 0.5;
  bool _sideBySide = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _selectedSlot = widget.initialSlot;
    _beforeSet = widget.initialBeforeSet;
    _afterSet = widget.initialAfterSet;
  }

  Future<void> _exportPng() async {
    setState(() => _exporting = true);
    try {
      final boundary = _exportBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        recToast(context, 'Unable to capture comparison view');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) recToast(context, 'Error generating PNG');
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final patientSlug = widget.patient.fullName
          .trim()
          .replaceAll(RegExp(r'[^\w\-]'), '_');
      final dateSlug = DateFormat('yyyyMMdd').format(DateTime.now());
      final defaultName =
          'Physio_${patientSlug}_${_selectedSlot.name}_$dateSlug.png';

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Export Physiotherapy Comparison PNG',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: bytes,
      );

      if (savePath != null) {
        final f = File(savePath);
        if (!await f.exists() || await f.length() == 0) {
          await f.writeAsBytes(bytes, flush: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved comparison: ${p.basename(savePath)}'),
              action: SnackBarAction(
                label: 'Show in folder',
                onPressed: () => launchUrl(Uri.file(p.dirname(savePath))),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) recToast(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
          ..sort((a, b) => a.date.compareTo(b.date));

        if (sets.length < 2) {
          return DentalPanelDialog(
            title: 'Physiotherapy Session Comparison',
            subtitle: widget.patient.fullName,
            body: DentalEmptyState(
              icon: CruIcons.box,
              title: 'Need at least two session photo records',
              body:
                  'Capture photos in at least two sessions to compare postural and biomechanical progress.',
              actions: [
                CruButton(
                  label: 'Close',
                  kind: CruButtonKind.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }

        _beforeSet ??= sets.first;
        _afterSet ??= sets.last;

        final beforePhoto = _beforeSet?.photoFor(_selectedSlot);
        final afterPhoto = _afterSet?.photoFor(_selectedSlot);
        final hasBothPhotos = beforePhoto != null && afterPhoto != null;

        return DentalPanelDialog(
          title: 'Physiotherapy Session Comparison',
          subtitle:
              '${widget.patient.fullName} · ${_sideBySide ? 'Side by side comparison' : 'Drag slider to compare'}',
          width: 960,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top control bar
              Container(
                padding: const EdgeInsets.all(CruSpace.s12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  children: [
                    // Before session selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BASELINE / EARLIER',
                            style: CruType.micro.w600.tint(c.label3),
                          ),
                          const SizedBox(height: CruSpace.s4),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _beforeSet?.id,
                              items: [
                                for (final s in sets)
                                  DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      '${s.label} (${DentalFormat.date(s.date)})',
                                      style: CruType.caption.tint(c.label),
                                    ),
                                  ),
                              ],
                              onChanged: (id) {
                                setState(() {
                                  _beforeSet =
                                      sets.where((s) => s.id == id).firstOrNull;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s16),

                    // View slot selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SLOT VIEW',
                            style: CruType.micro.w600.tint(c.label3),
                          ),
                          const SizedBox(height: CruSpace.s4),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<PhysioPhotoSlot>(
                              isExpanded: true,
                              value: _selectedSlot,
                              items: [
                                for (final slot in PhysioPhotoSlot.values)
                                  DropdownMenuItem(
                                    value: slot,
                                    child: Text(
                                      slot.title,
                                      style: CruType.caption.tint(c.label),
                                    ),
                                  ),
                              ],
                              onChanged: (slot) {
                                if (slot != null) {
                                  setState(() => _selectedSlot = slot);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s16),

                    // After session selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FOLLOW-UP / RECENT',
                            style: CruType.micro.w600.tint(c.label3),
                          ),
                          const SizedBox(height: CruSpace.s4),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _afterSet?.id,
                              items: [
                                for (final s in sets)
                                  DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      '${s.label} (${DentalFormat.date(s.date)})',
                                      style: CruType.caption.tint(c.label),
                                    ),
                                  ),
                              ],
                              onChanged: (id) {
                                setState(() {
                                  _afterSet =
                                      sets.where((s) => s.id == id).firstOrNull;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s16),

                    // Comparison mode toggle (Slider vs Side by side)
                    CruSegmentedControl<bool>(
                      selected: _sideBySide,
                      segments: const [
                        CruSegment(false, 'Slider'),
                        CruSegment(true, 'Side by side'),
                      ],
                      onChanged: (val) => setState(() => _sideBySide = val),
                    ),
                    const SizedBox(width: CruSpace.s12),

                    // Export button
                    CruButton(
                      label: _exporting ? 'Exporting…' : 'Export PNG',
                      icon: CruIcons.download,
                      kind: CruButtonKind.secondary,
                      onPressed: hasBothPhotos && !_exporting ? _exportPng : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s16),

              // Slot selector chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final slot in PhysioPhotoSlot.values) ...[
                      DentalChoiceChip(
                        label: slot.title,
                        selected: _selectedSlot == slot,
                        onTap: () => setState(() => _selectedSlot = slot),
                      ),
                      const SizedBox(width: CruSpace.s6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s16),

              // Main preview boundary (for export)
              RepaintBoundary(
                key: _exportBoundaryKey,
                child: beforePhoto == null || afterPhoto == null
                    ? Container(
                        height: 440,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(CruRadius.control),
                          border: Border.all(color: c.hairline),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CruIcon(
                                CruIcons.box,
                                size: 32,
                                color: c.label3,
                              ),
                              const SizedBox(height: CruSpace.s12),
                              Text(
                                'Missing photo in selected slot',
                                style: CruType.body.w600.tint(c.label),
                              ),
                              const SizedBox(height: CruSpace.s4),
                              Text(
                                '${beforePhoto == null ? _beforeSet?.label : _afterSet?.label} does not have ${_selectedSlot.title} photo.',
                                style: CruType.caption.tint(c.label2),
                              ),
                              const SizedBox(height: CruSpace.s16),
                              CruCapsuleButton(
                                label: 'Try another view',
                                icon: CruIcons.search,
                                onPressed: () {
                                  for (final slot in PhysioPhotoSlot.values) {
                                    if (_beforeSet?.photoFor(slot) != null &&
                                        _afterSet?.photoFor(slot) != null) {
                                      setState(() => _selectedSlot = slot);
                                      break;
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_sideBySide
                        ? Container(
                            height: 480,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius:
                                  BorderRadius.circular(CruRadius.control),
                              border: Border.all(color: c.hairline),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                // Before pane
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        File(beforePhoto),
                                        fit: BoxFit.contain,
                                        alignment: Alignment.center,
                                      ),
                                      Positioned(
                                        top: CruSpace.s12,
                                        left: CruSpace.s12,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: CruSpace.s10,
                                            vertical: CruSpace.s4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.65),
                                            borderRadius: BorderRadius.circular(
                                                CruRadius.control),
                                          ),
                                          child: Text(
                                            'Earlier · ${_beforeSet!.label} (${DentalFormat.date(_beforeSet!.date)})',
                                            style: CruType.caption.w600
                                                .tint(Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 2,
                                  color: Colors.white24,
                                ),
                                // After pane
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        File(afterPhoto),
                                        fit: BoxFit.contain,
                                        alignment: Alignment.center,
                                      ),
                                      Positioned(
                                        top: CruSpace.s12,
                                        right: CruSpace.s12,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: CruSpace.s10,
                                            vertical: CruSpace.s4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.65),
                                            borderRadius: BorderRadius.circular(
                                                CruRadius.control),
                                          ),
                                          child: Text(
                                            'Follow-up · ${_afterSet!.label} (${DentalFormat.date(_afterSet!.date)})',
                                            style: CruType.caption.w600
                                                .tint(Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final boxWidth = constraints.maxWidth;
                              const boxHeight = 480.0;

                              return Container(
                                height: boxHeight,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius:
                                      BorderRadius.circular(CruRadius.control),
                                  border: Border.all(color: c.hairline),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // 1. Bottom layer: AFTER photo
                                    Image.file(
                                      File(afterPhoto),
                                      fit: BoxFit.contain,
                                      alignment: Alignment.center,
                                    ),

                                    // 2. Top layer: BEFORE photo clipped
                                    ClipRect(
                                      clipper: _PhysioSplitClipper(
                                        _dividerFraction,
                                      ),
                                      child: Image.file(
                                        File(beforePhoto),
                                        fit: BoxFit.contain,
                                        alignment: Alignment.center,
                                      ),
                                    ),

                                    // 3. Before label badge
                                    Positioned(
                                      top: CruSpace.s12,
                                      left: CruSpace.s12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: CruSpace.s10,
                                          vertical: CruSpace.s4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(
                                              CruRadius.control),
                                        ),
                                        child: Text(
                                          'Earlier · ${_beforeSet!.label} (${DentalFormat.date(_beforeSet!.date)})',
                                          style: CruType.caption.w600
                                              .tint(Colors.white),
                                        ),
                                      ),
                                    ),

                                    // 4. After label badge
                                    Positioned(
                                      top: CruSpace.s12,
                                      right: CruSpace.s12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: CruSpace.s10,
                                          vertical: CruSpace.s4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(
                                              CruRadius.control),
                                        ),
                                        child: Text(
                                          'Follow-up · ${_afterSet!.label} (${DentalFormat.date(_afterSet!.date)})',
                                          style: CruType.caption.w600
                                              .tint(Colors.white),
                                        ),
                                      ),
                                    ),

                                    // 5. Draggable Divider Line and Handle
                                    Positioned(
                                      left: (boxWidth * _dividerFraction) - 16,
                                      top: 0,
                                      bottom: 0,
                                      width: 32,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (details) {
                                          setState(() {
                                            _dividerFraction =
                                                (_dividerFraction +
                                                        (details.delta.dx /
                                                            boxWidth))
                                                    .clamp(0.02, 0.98);
                                          });
                                        },
                                        child: Center(
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              // Vertical divider line
                                              Container(
                                                width: 2,
                                                color: Colors.white,
                                              ),
                                              // Central circular grab handle
                                              Container(
                                                width: 30,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(alpha: 0.35),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.compare_arrows_rounded,
                                                  color: Colors.black87,
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhysioSplitClipper extends CustomClipper<Rect> {
  const _PhysioSplitClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_PhysioSplitClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
