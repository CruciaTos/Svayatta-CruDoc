import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/services/rvg_sensor_service.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the Direct RVG Sensor Acquisition dialog.
Future<void> showRvgCaptureDialog(
  BuildContext context, {
  Patient? initialPatient,
  int initialTooth = 36,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RvgCaptureDialog(
    initialPatient: initialPatient,
    initialTooth: initialTooth,
  ),
);

class _RvgCaptureDialog extends ConsumerStatefulWidget {
  const _RvgCaptureDialog({this.initialPatient, this.initialTooth = 36});

  final Patient? initialPatient;
  final int initialTooth;

  @override
  ConsumerState<_RvgCaptureDialog> createState() => _RvgCaptureDialogState();
}

class _RvgCaptureDialogState extends ConsumerState<_RvgCaptureDialog>
    with SingleTickerProviderStateMixin {
  final _service = RvgSensorService.instance;
  StreamSubscription<RvgStatus>? _sub;

  Patient? _patient;
  late int _tooth;
  List<RvgDevice> _devices = [];
  RvgDevice? _selectedDevice;
  bool _loadingDevices = true;

  RvgStatus _status = const RvgStatus(
    state: RvgState.idle,
    message: 'Select tooth and device to arm',
  );
  RvgCaptureResult? _result;
  bool _saving = false;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _patient = widget.initialPatient;
    _tooth = widget.initialTooth;
    _initBridgeAndDevices();

    _sub = _service.statusStream.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);

      if (s.state == RvgState.done && s.hasImage) {
        _onCaptureDone();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sub?.cancel();
    if (_status.state.isCapturing) {
      _service.disarm();
    }
    super.dispose();
  }

  Future<void> _initBridgeAndDevices() async {
    await _service.ensureBridgeRunning();
    final devs = await _service.listDevices();
    if (!mounted) return;
    setState(() {
      _devices = devs;
      _selectedDevice = devs.firstOrNull;
      _loadingDevices = false;
    });
  }

  Future<void> _onCaptureDone() async {
    final res = await _service.fetchLatestImage(
      toothNumber: _tooth,
      deviceName: _selectedDevice?.name ?? 'RVG Sensor',
    );
    if (!mounted) return;
    setState(() {
      _result = res;
    });
  }

  Future<void> _arm() async {
    if (_selectedDevice == null) return;
    setState(() {
      _result = null;
      _status = const RvgStatus(
        state: RvgState.arming,
        message: 'Arming sensor...',
      );
    });

    await _service.armSensor(
      deviceName: _selectedDevice!.name,
      toothNumber: _tooth,
      patientId: _patient?.id ?? '',
      patientName: _patient?.fullName ?? 'Unnamed Patient',
    );
  }

  Future<void> _disarm() async {
    await _service.disarm();
    if (!mounted) return;
    setState(() {
      _status = const RvgStatus(
        state: RvgState.idle,
        message: 'Sensor disarmed.',
      );
    });
  }

  Future<void> _simulateTrigger() async {
    await _service.triggerExposure();
  }

  Future<void> _saveAndOpen() async {
    if (_result == null) return;
    setState(() => _saving = true);

    final ctrl = ref.read(radiologyProvider);
    final studyId = radId('study_');
    final dir = await ctrl.studyDir(studyId);
    final studyDir = dir.path;
    Directory(studyDir).createSync(recursive: true);

    const storedName = 'img_0000.png';
    final filePath = p.join(studyDir, storedName);
    File(filePath).writeAsBytesSync(_result!.imageBytes);

    final imgRef = RadImageRef(
      id: 'img_0',
      path: storedName,
      kind: RadFileKind.raster,
      width: _result!.width,
      height: _result!.height,
      dicomModality: 'IO',
    );

    final now = DateTime.now();
    final patientName = _patient?.fullName ?? 'Direct RVG Patient';
    final patientId = _patient?.id ?? '';

    final study = RadStudy(
      id: studyId,
      patientId: patientId,
      patientName: patientName,
      patientExternalId: _patient?.id ?? '',
      modality: RadModality.iopa,
      studyDate: now,
      receivedAt: now,
      description: 'IOPA Periapical Tooth #$_tooth',
      images: [imgRef],
      bodyPart: 'Mouth / Tooth #$_tooth',
      equipment: _selectedDevice?.name ?? 'RVG Intraoral Sensor',
      extras: {'tooth': _tooth},
      createdAt: now,
      updatedAt: now,
    );

    await ctrl.saveStudy(
      study,
      auditAction: 'RVG direct capture',
      detail: 'Tooth #$_tooth on ${_selectedDevice?.name}',
    );

    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop();

    unawaited(ctrl.openedStudy(study));
    await nav.push(
      radRoute<void>(RadViewerScreen(studyId: study.id, initialStudy: study)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DentalPanelDialog(
      title: 'RVG Sensor Capture',
      subtitle: 'Direct digital X-ray capture from intraoral sensor',
      leading: const CruIconTile(icon: RadIcons.xray, tone: CruTileTone.accent),
      width: CruSize.dialog + 260,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConfigBar(),
              const SizedBox(height: CruSpace.s16),
              _buildToothSelector(),
              const SizedBox(height: CruSpace.s16),
              _buildAcquisitionStage(),
            ],
          ),
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_status.state.isArmed) ...[
            CruButton(
              label: 'Trigger exposure',
              icon: RadIcons.dose,
              kind: CruButtonKind.secondary,
              onPressed: _simulateTrigger,
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(
              label: 'Disarm / Cancel',
              kind: CruButtonKind.secondary,
              onPressed: _disarm,
            ),
          ] else if (_result != null) ...[
            CruButton(
              label: 'Retake',
              kind: CruButtonKind.secondary,
              onPressed: _arm,
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(
              label: _saving ? 'Saving...' : 'Accept & Open in Viewer',
              kind: CruButtonKind.primary,
              onPressed: _saving ? null : _saveAndOpen,
            ),
          ] else ...[
            CruButton(
              label: 'Close',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(
              label: 'Arm Sensor',
              icon: RadIcons.xray,
              kind: CruButtonKind.primary,
              onPressed: _loadingDevices ? null : _arm,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigBar() {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: BoxDecoration(
        color: context.cru.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
        border: Border.all(color: context.cru.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(CruRadius.control),
              onTap: _status.state.isCapturing
                  ? null
                  : () async {
                      final p = await pickRadPatient(context);
                      if (p != null) setState(() => _patient = p);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    CruIcon(
                      RadIcons.referrer,
                      size: 20,
                      color: context.cru.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient',
                            style: CruType.caption.tint(context.cru.label2),
                          ),
                          Text(
                            _patient?.fullName ?? 'Click to select patient',
                            style: CruType.callout.w600.tint(context.cru.label),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 32, width: 1, color: context.cru.hairline),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: _loadingDevices
                ? const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Scanning for sensors...'),
                    ],
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<RvgDevice>(
                      value: _selectedDevice,
                      isExpanded: true,
                      items: _devices.map((d) {
                        return DropdownMenuItem<RvgDevice>(
                          value: d,
                          child: Row(
                            children: [
                              CruIcon(
                                d.isSimulator ? RadIcons.server : RadIcons.xray,
                                size: 18,
                                color: d.isSimulator
                                    ? context.cru.amber
                                    : context.cru.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  d.name,
                                  style: CruType.text.tint(context.cru.label),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _status.state.isCapturing
                          ? null
                          : (dev) {
                              if (dev != null)
                                setState(() => _selectedDevice = dev);
                            },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToothSelector() {
    final teeth = [
      [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28],
      [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Target Tooth (FDI notation)',
              style: CruType.caption.tint(context.cru.label2),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.cru.accentWash,
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
              child: Text(
                'Selected: Tooth #$_tooth',
                style: CruType.caption.tint(context.cru.accentText).w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(CruSpace.s8),
          decoration: BoxDecoration(
            color: context.cru.surface,
            borderRadius: BorderRadius.circular(CruRadius.control),
            border: Border.all(color: context.cru.hairline),
          ),
          child: Column(
            children: teeth.map((row) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((t) {
                    final sel = t == _tooth;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: _status.state.isCapturing
                            ? null
                            : () => setState(() => _tooth = t),
                        child: Container(
                          width: 32,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sel
                                ? context.cru.accent
                                : context.cru.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: sel
                                  ? context.cru.accent
                                  : context.cru.hairline,
                            ),
                          ),
                          child: Text(
                            '$t',
                            style: CruType.caption.w600.tint(
                              sel ? context.cru.onAccent : context.cru.label,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAcquisitionStage() {
    if (_result != null) {
      return Container(
        height: 380,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(CruRadius.card),
          border: Border.all(color: context.cru.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CruRadius.card),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_result!.imageBytes, fit: BoxFit.contain),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(CruRadius.full),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Tooth #$_tooth IOPA · ${_result!.width}x${_result!.height} · ${_selectedDevice?.name}',
                        style: CruType.caption.tint(Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_status.state.isArmed) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final glowAlpha = 0.12 + (_pulseController.value * 0.22);
          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: context.cru.amber.withValues(alpha: glowAlpha),
              borderRadius: BorderRadius.circular(CruRadius.card),
              border: Border.all(color: context.cru.amber, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.cru.amber.withValues(
                          alpha: 0.3 * (1 - _pulseController.value),
                        ),
                      ),
                    ),
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.cru.amber,
                      ),
                      child: Center(
                        child: CruIcon(
                          RadIcons.dose,
                          size: 36,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'SENSOR ARMED · READY FOR EXPOSURE',
                  style: CruType.headline.w600.tint(context.cru.amberText),
                ),
                const SizedBox(height: 6),
                Text(
                  'Position X-ray tube at Tooth #$_tooth and press exposure switch',
                  style: CruType.body.tint(context.cru.label),
                ),
                const SizedBox(height: 12),
                Text(
                  'Listening for radiation... (${_status.elapsed}s)',
                  style: CruType.caption.tint(context.cru.label2),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_status.state == RvgState.exposed ||
        _status.state == RvgState.transferring) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: context.cru.accentWash,
          borderRadius: BorderRadius.circular(CruRadius.card),
          border: Border.all(color: context.cru.accent, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: context.cru.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'RADIATION DETECTED!',
              style: CruType.headline.w600.tint(context.cru.accentText),
            ),
            const SizedBox(height: 6),
            Text(_status.message, style: CruType.body.tint(context.cru.label)),
          ],
        ),
      );
    }

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: context.cru.surface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: context.cru.hairline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.cru.inset,
              border: Border.all(color: context.cru.hairline),
            ),
            child: Center(
              child: CruIcon(
                RadIcons.xray,
                size: 32,
                color: context.cru.accent,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Sensor Standby',
            style: CruType.headline.w600.tint(context.cru.label),
          ),
          const SizedBox(height: 4),
          Text(
            'Tooth #$_tooth selected · Ready to arm ${_selectedDevice?.name ?? 'sensor'}',
            style: CruType.caption.tint(context.cru.label2),
          ),
          const SizedBox(height: 18),
          CruButton(
            label: 'Arm Sensor for Tooth #$_tooth',
            icon: RadIcons.xray,
            kind: CruButtonKind.primary,
            onPressed: _loadingDevices ? null : _arm,
          ),
        ],
      ),
    );
  }
}
