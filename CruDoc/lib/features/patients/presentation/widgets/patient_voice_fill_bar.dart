import 'dart:async';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/services/patient_voice_fill_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Phase { idle, recording, processing, done, error }

/// "Fill by voice" strip shown at the top of the Add Patient form on both
/// mobile and desktop. The doctor taps the mic, says the patient details,
/// taps Done, and [onFill] receives whatever was heard. Nothing is saved —
/// the form still needs the doctor's Save.
class PatientVoiceFillBar extends StatefulWidget {
  const PatientVoiceFillBar({super.key, required this.onFill, this.service});

  final ValueChanged<PatientVoiceFill> onFill;

  /// Injected in tests; a real service is created otherwise.
  final PatientVoiceFillService? service;

  @override
  State<PatientVoiceFillBar> createState() => _PatientVoiceFillBarState();
}

class _PatientVoiceFillBarState extends State<PatientVoiceFillBar> {
  late final PatientVoiceFillService _service =
      widget.service ?? PatientVoiceFillService();

  _Phase _phase = _Phase.idle;
  String _message = '';
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    if (_phase == _Phase.recording) unawaited(_service.cancel());
    if (widget.service == null) unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _service.hasPermission()) {
        _fail(
          'Microphone access is off. Allow it in Settings to fill by voice.',
        );
        return;
      }
      await _service.start();
    } catch (e) {
      _fail('Could not start the microphone.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _phase != _Phase.recording) return;
      setState(() {
        _elapsed += const Duration(milliseconds: 200);
      });
      if (_elapsed >= PatientVoiceFillService.maxDuration) unawaited(_finish());
    });
  }

  Future<void> _finish() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    setState(() => _phase = _Phase.processing);
    try {
      final fill = await _service.stopAndExtract();
      if (!mounted) return;
      widget.onFill(fill);
      setState(() {
        _phase = _Phase.done;
        _message =
            'Filled ${_joinLabels(fill.filledLabels)}. Check before saving.';
      });
    } on PatientVoiceFillException catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await _service.cancel();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _fail(String message) {
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _message = message;
    });
  }

  static String _joinLabels(List<String> labels) {
    if (labels.length <= 1) return labels.join();
    return '${labels.sublist(0, labels.length - 1).join(', ')} and '
        '${labels.last}';
  }

  // Calm Clinical: the strip is an inset well. Ink Blue marks the mic and
  // the "listening now" state, green a filled form; errors stay neutral
  // (red is kept for allergies and patient safety).
  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return AnimatedContainer(
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s10,
        CruSpace.s10,
        CruSpace.s10,
      ),
      decoration: BoxDecoration(
        color: _phase == _Phase.recording ? c.accentWash : c.inset,
        borderRadius: BorderRadius.circular(CruRadius.control),
      ),
      child: Row(
        children: [
          _leading(c),
          const SizedBox(width: CruSpace.s12),
          Expanded(child: _texts(c)),
          const SizedBox(width: CruSpace.s8),
          ..._actions(),
        ],
      ),
    );
  }

  Widget _leading(CruColors c) {
    switch (_phase) {
      case _Phase.processing:
        return SizedBox.square(
          dimension: CruSize.control - CruSpace.s4,
          child: Padding(
            padding: const EdgeInsets.all(CruSpace.s10),
            child: CircularProgressIndicator(strokeWidth: 2.4, color: c.accent),
          ),
        );
      case _Phase.recording:
        return _disc(CruIcons.mic, fill: c.accent, color: c.onAccent);
      case _Phase.done:
        return _disc(CruIcons.check, fill: c.greenTint, color: c.greenText);
      case _Phase.error:
        return _disc(CruIcons.warning, fill: c.track, color: c.label2);
      case _Phase.idle:
        return Material(
          color: c.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _start,
            child: SizedBox.square(
              dimension: CruSize.control - CruSpace.s4,
              child: Center(
                child: CruIcon(CruIcons.mic, color: c.onAccent),
              ),
            ),
          ),
        );
    }
  }

  Widget _disc(
    CruIconData icon, {
    required Color fill,
    required Color color,
  }) => Container(
    width: CruSize.control - CruSpace.s4,
    height: CruSize.control - CruSpace.s4,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: Center(child: CruIcon(icon, color: color)),
  );

  Widget _texts(CruColors c) {
    final (title, subtitle) = switch (_phase) {
      _Phase.idle => (
        'Fill by voice',
        'Tap the mic and say the name, age, sex, mobile and problem.',
      ),
      _Phase.recording => (
        'Listening… ${_format(_elapsed)}',
        'e.g. "Rahul Sharma, 42, male, 98765 43210, low back pain"',
      ),
      _Phase.processing => ('Filling the form…', 'This takes a few seconds.'),
      _Phase.done => ('Form filled', _message),
      _Phase.error => ("Couldn't fill the form", _message),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: CruType.callout.w600.tabular.tint(c.label)),
        const SizedBox(height: CruSpace.s2),
        Text(subtitle, style: CruType.caption.tint(c.label2)),
      ],
    );
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.recording:
        return [
          CruCapsuleButton(label: 'Cancel', onPressed: _cancel),
          const SizedBox(width: CruSpace.s8),
          CruButton(label: 'Done', onPressed: _finish),
        ];
      case _Phase.done:
      case _Phase.error:
        return [
          CruCapsuleButton(
            label: _phase == _Phase.done ? 'Again' : 'Try again',
            icon: CruIcons.mic,
            onPressed: _start,
          ),
        ];
      case _Phase.idle:
      case _Phase.processing:
        return const [];
    }
  }

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
