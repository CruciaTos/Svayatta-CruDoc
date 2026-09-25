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
import 'package:doctor_management_app/features/dental/specialties/ortho/ortho_photos.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Screen/dialog displaying an interactive split Before/After comparison slider
/// with PNG export functionality for clinical documentation or patient sharing.
class OrthoBeforeAfterDialog extends ConsumerStatefulWidget {
  const OrthoBeforeAfterDialog({
    super.key,
    required this.patient,
    this.initialBeforeSet,
    this.initialAfterSet,
    this.initialSlot = OrthoPhotoSlot.smile,
  });

  final Patient patient;
  final OrthoPhotoSet? initialBeforeSet;
  final OrthoPhotoSet? initialAfterSet;
  final OrthoPhotoSlot initialSlot;

  @override
  ConsumerState<OrthoBeforeAfterDialog> createState() => _OrthoBeforeAfterDialogState();
}

class _OrthoBeforeAfterDialogState extends ConsumerState<OrthoBeforeAfterDialog> {
  final GlobalKey _exportBoundaryKey = GlobalKey();

  OrthoPhotoSet? _beforeSet;
  OrthoPhotoSet? _afterSet;
  late OrthoPhotoSlot _selectedSlot;

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
      final patientSlug = widget.patient.fullName.trim().replaceAll(RegExp(r'[^\w\-]'), '_');
      final dateSlug = DateFormat('yyyyMMdd').format(DateTime.now());
      final defaultName = 'BeforeAfter_${patientSlug}_${_selectedSlot.name}_$dateSlug.png';

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Export Before/After PNG',
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
          ..sort((a, b) => a.date.compareTo(b.date));

        if (sets.length < 2) {
          return DentalPanelDialog(
            title: 'Before & After Comparison',
            subtitle: widget.patient.fullName,
            body: DentalEmptyState(
              icon: CruIcons.box,
              title: 'Need at least two photo series',
              body: 'Capture a "Start" and a "Progress" or "Debond" series to compare clinical changes.',
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
          title: 'Before & After Comparison',
          subtitle: '${widget.patient.fullName} · ${_sideBySide ? 'Side by side comparison' : 'Drag slider to compare'}',
          width: 960,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Controls bar
              Container(
                padding: const EdgeInsets.all(CruSpace.s12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  children: [
                    // Before set selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BEFORE', style: CruType.micro.w600.tint(c.label3)),
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
                                  _beforeSet = sets.where((s) => s.id == id).firstOrNull;
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
                          Text('VIEW', style: CruType.micro.w600.tint(c.label3)),
                          const SizedBox(height: CruSpace.s4),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<OrthoPhotoSlot>(
                              isExpanded: true,
                              value: _selectedSlot,
                              items: [
                                for (final slot in OrthoPhotoSlot.values)
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

                    // After set selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AFTER', style: CruType.micro.w600.tint(c.label3)),
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
                                  _afterSet = sets.where((s) => s.id == id).firstOrNull;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s16),

                    // Comparison mode toggle
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
                      kind: CruButtonKind.primary,
                      onPressed: (!hasBothPhotos || _exporting) ? null : _exportPng,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s16),

              // Interactive Slider Area or Missing message
              if (!hasBothPhotos)
                Container(
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
                        CruIcon(CruIcons.box, size: 36, color: c.label3),
                        const SizedBox(height: CruSpace.s12),
                        Text(
                          'Missing "${_selectedSlot.title}" in one or both series',
                          style: CruType.callout.w600.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s4),
                        Text(
                          'Before: ${beforePhoto != null ? 'Present' : 'Not recorded'} · After: ${afterPhoto != null ? 'Present' : 'Not recorded'}',
                          style: CruType.caption.tint(c.label2),
                        ),
                        const SizedBox(height: CruSpace.s16),
                        CruCapsuleButton(
                          label: 'Try another view',
                          icon: CruIcons.search,
                          onPressed: () {
                            // Find first view present in both
                            for (final slot in OrthoPhotoSlot.values) {
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
              else if (_sideBySide)
                Container(
                  height: 480,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(CruRadius.control),
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
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(CruRadius.control),
                                ),
                                child: Text(
                                  'Before · ${DentalFormat.date(_beforeSet!.date)}',
                                  style: CruType.caption.w600.tint(Colors.white),
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
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(CruRadius.control),
                                ),
                                child: Text(
                                  'After · ${DentalFormat.date(_afterSet!.date)}',
                                  style: CruType.caption.w600.tint(Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final boxWidth = constraints.maxWidth;
                    const boxHeight = 480.0;

                    return Container(
                      height: boxHeight,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(CruRadius.control),
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

                          // 2. Top layer: BEFORE photo clipped by horizontal widthFactor
                          ClipRect(
                            clipper: _HorizontalSplitClipper(_dividerFraction),
                            child: Image.file(
                              File(beforePhoto),
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            ),
                          ),

                          // 3. Before label pill (top-left)
                          Positioned(
                            top: CruSpace.s12,
                            left: CruSpace.s12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CruSpace.s10,
                                vertical: CruSpace.s4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(CruRadius.control),
                              ),
                              child: Text(
                                'Before · ${DentalFormat.date(_beforeSet!.date)}',
                                style: CruType.caption.w600.tint(Colors.white),
                              ),
                            ),
                          ),

                          // 4. After label pill (top-right)
                          Positioned(
                            top: CruSpace.s12,
                            right: CruSpace.s12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CruSpace.s10,
                                vertical: CruSpace.s4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(CruRadius.control),
                              ),
                              child: Text(
                                'After · ${DentalFormat.date(_afterSet!.date)}',
                                style: CruType.caption.w600.tint(Colors.white),
                              ),
                            ),
                          ),

                          // 5. Draggable Divider Line and Knob
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: (boxWidth * _dividerFraction) - 1.5,
                            child: Container(
                              width: 3,
                              color: Colors.white,
                            ),
                          ),

                          Positioned(
                            top: (boxHeight / 2) - 20,
                            left: (boxWidth * _dividerFraction) - 20,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: CruIcon(
                                  CruIcons.importExport,
                                  size: 20,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          ),

                          // 6. Transparent gesture detector across whole area
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _dividerFraction = (_dividerFraction + (details.delta.dx / boxWidth))
                                    .clamp(0.02, 0.98);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // Offstage RepaintBoundary for high-res side-by-side PNG export
              if (hasBothPhotos)
                Offstage(
                  offstage: true,
                  child: RepaintBoundary(
                    key: _exportBoundaryKey,
                    child: Container(
                      width: 1200,
                      height: 700,
                      color: Colors.white,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.patient.fullName} — ${_selectedSlot.title}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Orthodontic Treatment Progress Comparison',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'CruDoc Dental',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // Side by side images
                          Expanded(
                            child: Row(
                              children: [
                                // Before pane
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        color: Colors.grey.shade100,
                                        child: Text(
                                          'BEFORE: ${_beforeSet!.label} (${DentalFormat.date(_beforeSet!.date)})',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: Image.file(
                                          File(beforePhoto),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),

                                // After pane
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        color: Colors.grey.shade100,
                                        child: Text(
                                          'AFTER: ${_afterSet!.label} (${DentalFormat.date(_afterSet!.date)})',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: Image.file(
                                          File(afterPhoto),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
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
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  const _HorizontalSplitClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) => oldClipper.fraction != fraction;
}
