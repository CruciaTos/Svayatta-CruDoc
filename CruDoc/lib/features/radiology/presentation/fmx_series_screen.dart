import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_cloud_sync.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/services/rvg_sensor_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One film position in a full-mouth series mount.
class FmxSlot {
  const FmxSlot(this.label, this.teeth, {this.bitewing = false});
  final String label;
  final List<int> teeth;
  final bool bitewing;
}

class FmxTemplate {
  const FmxTemplate(this.name, this.rows);
  final String name;

  /// Upper row, bitewing row, lower row (empty rows are skipped).
  final List<List<FmxSlot>> rows;

  List<FmxSlot> get slots => [for (final r in rows) ...r];
}

const _paUpper = [
  FmxSlot('PA 16-18', [16, 17, 18]),
  FmxSlot('PA 14-15', [14, 15]),
  FmxSlot('PA 13', [13]),
  FmxSlot('PA 11-21', [12, 11, 21, 22]),
  FmxSlot('PA 23', [23]),
  FmxSlot('PA 24-25', [24, 25]),
  FmxSlot('PA 26-28', [26, 27, 28]),
];
const _paLower = [
  FmxSlot('PA 46-48', [46, 47, 48]),
  FmxSlot('PA 44-45', [44, 45]),
  FmxSlot('PA 43', [43]),
  FmxSlot('PA 31-41', [42, 41, 31, 32]),
  FmxSlot('PA 33', [33]),
  FmxSlot('PA 34-35', [34, 35]),
  FmxSlot('PA 36-38', [36, 37, 38]),
];
const _bw = [
  FmxSlot('BW right molar', [16, 17, 46, 47], bitewing: true),
  FmxSlot('BW right premolar', [14, 15, 44, 45], bitewing: true),
  FmxSlot('BW left premolar', [24, 25, 34, 35], bitewing: true),
  FmxSlot('BW left molar', [26, 27, 36, 37], bitewing: true),
];

const fmxTemplates = <FmxTemplate>[
  FmxTemplate('FMX 18', [_paUpper, _bw, _paLower]),
  FmxTemplate('FMX 14', [_paUpper, _paLower]),
  FmxTemplate('4 bitewings', [_bw]),
];

class _Shot {
  _Shot(this.bytes, this.at, this.studyId);
  Uint8List bytes;
  DateTime at;
  final String studyId;
}

/// Full-mouth X-ray series: the mount fills in as each film is captured.
class FmxSeriesScreen extends ConsumerStatefulWidget {
  const FmxSeriesScreen({super.key, this.patient});
  final Patient? patient;

  @override
  ConsumerState<FmxSeriesScreen> createState() => _FmxSeriesScreenState();
}

class _FmxSeriesScreenState extends ConsumerState<FmxSeriesScreen> {
  final _service = RvgSensorService.instance;
  final _seriesId = radId('fmx_');

  Patient? _patient;
  FmxTemplate _template = fmxTemplates.first;
  final Map<String, _Shot> _shots = {};
  final List<_Shot> _log = [];
  final List<String> _logLabels = [];
  int _current = 0;
  bool _busy = false;
  String _message = '';
  List<RvgDevice> _devices = [];
  RvgDevice? _device;
  bool _loading = true;
  Completer<bool>? _wait;
  StreamSubscription<RvgStatus>? _sub;

  List<FmxSlot> get _slots => _template.slots;
  bool get _complete => _slots.every((s) => _shots.containsKey(s.label));
  bool get _canCapture =>
      !_loading && (Platform.isWindows || (_device?.isSimulator ?? false));

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _sub = _service.statusStream.listen((s) {
      if (!mounted || !_busy) return;
      setState(() => _message = s.message);
      final w = _wait;
      if (w == null || w.isCompleted) return;
      if (s.state == RvgState.done && s.hasImage) w.complete(true);
      if (s.state == RvgState.error) w.complete(false);
    });
    _init();
  }

  Future<void> _init() async {
    await _service.ensureBridgeRunning();
    final devs = await _service.listDevices();
    if (!mounted) return;
    setState(() {
      _devices = devs;
      _device = devs.firstOrNull;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_busy) _service.disarm();
    super.dispose();
  }

  void _setTemplate(FmxTemplate t) {
    if (_busy || t == _template) return;
    setState(() {
      _template = t;
      _current = _firstEmpty(0);
    });
  }

  int _firstEmpty(int from) {
    final n = _slots.length;
    for (var i = 0; i < n; i++) {
      final idx = (from + i) % n;
      if (!_shots.containsKey(_slots[idx].label)) return idx;
    }
    return from.clamp(0, n - 1);
  }

  Future<bool> _confirm(String title, String yes) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Dose log lines: slot, time, exposure (kVp/mA/s are not exposed by the
  /// sensor service, so they are recorded as unknown).
  String _logText() {
    final lines = <String>[];
    for (var i = 0; i < _log.length; i++) {
      lines.add('${_logLabels[i]} ${_hhmm(_log[i].at)} exposure n/a');
    }
    return 'Dose log (${_log.length} exposures): ${lines.join('; ')}';
  }

  Future<void> _capture() async {
    if (_busy || !_canCapture) return;
    final slot = _slots[_current];
    if (_shots.containsKey(slot.label) &&
        !await _confirm('Replace the image for ${slot.label}?', 'Retake')) {
      return;
    }
    if (!mounted) return;
    if (_patient == null) {
      final picked = await pickRadPatient(context);
      if (picked == null || !mounted) return;
      _patient = picked;
    }
    final device = _device?.name ?? 'RVG Sensor';
    final wait = Completer<bool>();
    setState(() {
      _busy = true;
      _wait = wait;
      _message = 'Arming sensor...';
    });
    try {
      await _service.armSensor(
        deviceName: device,
        toothNumber: slot.teeth.first,
        patientId: _patient!.id,
        patientName: _patient!.fullName,
      );
      final ok = await wait.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => false,
      );
      if (!ok) {
        await _service.disarm();
        if (mounted) setState(() => _message = 'Capture cancelled.');
        return;
      }
      final res = await _service.fetchLatestImage(
        toothNumber: slot.teeth.first,
        deviceName: device,
      );
      if (res == null || !mounted) return;
      await _store(slot, res, device);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final w = _wait;
    if (w != null && !w.isCompleted) w.complete(false);
  }

  Future<void> _store(FmxSlot slot, RvgCaptureResult res, String device) async {
    final old = _shots[slot.label];
    final shot = _Shot(
      res.imageBytes,
      res.capturedAt,
      old?.studyId ?? radId('study_'),
    );
    // Retake keeps the same study id so the saved study is replaced.
    _log.add(shot);
    _logLabels.add(slot.label);

    final ctrl = ref.read(radiologyProvider);
    final dir = await ctrl.studyDir(shot.studyId);
    Directory(dir.path).createSync(recursive: true);
    const storedName = 'img_0000.png';
    File(p.join(dir.path, storedName)).writeAsBytesSync(res.imageBytes);

    final teeth = slot.teeth.join(',');
    final tag = 'FMX · ${slot.label} · teeth $teeth';
    final now = DateTime.now();
    final study = RadStudy(
      id: shot.studyId,
      patientId: _patient!.id,
      patientName: _patient!.fullName,
      patientExternalId: _patient!.id,
      modality: slot.bitewing ? RadModality.bitewing : RadModality.iopa,
      studyDate: now,
      receivedAt: now,
      description: tag,
      clinicalQuestion:
          '$tag · series $_seriesId · exposed ${res.capturedAt.toIso8601String()} · ${_logText()}',
      images: [
        RadImageRef(
          id: 'img_0',
          path: storedName,
          kind: RadFileKind.raster,
          width: res.width,
          height: res.height,
          dicomModality: 'IO',
        ),
      ],
      bodyPart: 'Mouth / teeth $teeth',
      equipment: device,
      extras: {
        'tooth': slot.teeth.first,
        'fmx': {
          'seriesId': _seriesId,
          'template': _template.name,
          'slot': slot.label,
          'teeth': slot.teeth,
          'exposedAt': res.capturedAt.toIso8601String(),
          'kvp': null,
          'ma': null,
          'exposureSeconds': null,
        },
      },
      createdAt: now,
      updatedAt: now,
    );
    await ctrl.saveStudy(
      study,
      auditAction: 'RVG FMX capture',
      detail: tag,
    );
    unawaited(
      RadiologyCloudSync.enqueueStudyImages(
        ctrl: ctrl,
        study: study,
        studyDir: dir.path,
      ),
    );
    if (!mounted) return;
    setState(() {
      _shots[slot.label] = shot;
      _current = _firstEmpty(_current + 1);
      _message = _complete ? 'Series complete.' : '';
    });
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_complete || _shots.isEmpty && _log.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (await _confirm('Series not finished. Leave anyway?', 'Leave') &&
        mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          title: Text(
            'Full-mouth series · ${_shots.length}/${_slots.length}',
            style: CruType.headline.w600.tint(c.label),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(CruSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: CruSpace.s12),
              Expanded(child: narrow ? _list() : _grid()),
              const SizedBox(height: CruSpace.s12),
              _controls(),
              const SizedBox(height: CruSpace.s12),
              _doseLog(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.cru;
    return Wrap(
      spacing: CruSpace.s8,
      runSpacing: CruSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final t in fmxTemplates)
          ChoiceChip(
            label: Text(t.name),
            selected: t == _template,
            onSelected: _busy ? null : (_) => _setTemplate(t),
          ),
        Text(
          _patient?.fullName ?? 'Patient chosen at first capture',
          style: CruType.caption.tint(c.label2),
        ),
        if (_devices.length > 1)
          DropdownButton<RvgDevice>(
            value: _device,
            items: [
              for (final d in _devices)
                DropdownMenuItem(value: d, child: Text(d.name)),
            ],
            onChanged: _busy ? null : (d) => setState(() => _device = d),
          ),
      ],
    );
  }

  Widget _grid() {
    return Column(
      children: [
        for (var r = 0; r < _template.rows.length; r++) ...[
          if (r > 0) const SizedBox(height: CruSpace.s8),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < _template.rows[r].length; i++) ...[
                  if (i > 0) const SizedBox(width: CruSpace.s8),
                  Expanded(child: _tile(_template.rows[r][i])),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _list() {
    return ListView.separated(
      itemCount: _slots.length,
      separatorBuilder: (_, _) => const SizedBox(height: CruSpace.s8),
      itemBuilder: (_, i) => SizedBox(height: 120, child: _tile(_slots[i])),
    );
  }

  Widget _tile(FmxSlot slot) {
    final c = context.cru;
    final idx = _slots.indexOf(slot);
    final cur = idx == _current;
    final shot = _shots[slot.label];
    return InkWell(
      borderRadius: BorderRadius.circular(CruRadius.control),
      onTap: _busy ? null : () => setState(() => _current = idx),
      child: Container(
        decoration: BoxDecoration(
          color: c.inset,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(
            color: cur ? c.accent : c.hairline,
            width: cur ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CruRadius.control),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shot != null)
                Image.memory(shot.bytes, fit: BoxFit.cover, gaplessPlayback: true),
              Positioned(
                left: CruSpace.s8,
                right: CruSpace.s8,
                bottom: CruSpace.s8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(CruRadius.full),
                  ),
                  child: Text(
                    slot.label,
                    style: CruType.caption.w600.tint(c.label),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (shot != null)
                Positioned(
                  top: CruSpace.s8,
                  right: CruSpace.s8,
                  child: Icon(Icons.check_circle, size: 18, color: c.green),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final c = context.cru;
    final slot = _slots[_current];
    final filled = _shots.containsKey(slot.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _message.isNotEmpty
                    ? _message
                    : _canCapture
                    ? '${slot.label} · teeth ${slot.teeth.join(', ')}'
                    : 'Capture needs a Windows PC with a sensor, or the simulator.',
                style: CruType.caption.tint(c.label2),
              ),
            ),
            if (_busy) ...[
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: 'Cancel',
                kind: CruButtonKind.secondary,
                onPressed: _cancel,
              ),
            ] else ...[
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: filled ? 'Retake ${slot.label}' : 'Capture',
                icon: RadIcons.xray,
                kind: CruButtonKind.primary,
                onPressed: _canCapture ? _capture : null,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _doseLog() {
    final c = context.cru;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 96),
      child: Container(
        padding: const EdgeInsets.all(CruSpace.s8),
        decoration: BoxDecoration(
          color: c.inset,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: c.hairline),
        ),
        child: _log.isEmpty
            ? Text('Dose log · no exposures yet',
                style: CruType.caption.tint(c.label2))
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Dose log · ${_log.length} exposures',
                    style: CruType.caption.w600.tint(c.label),
                  ),
                  for (var i = 0; i < _log.length; i++)
                    Text(
                      '${_logLabels[i]} · ${_hhmm(_log[i].at)} · exposure n/a',
                      style: CruType.caption.tint(c.label2),
                    ),
                ],
              ),
      ),
    );
  }
}
