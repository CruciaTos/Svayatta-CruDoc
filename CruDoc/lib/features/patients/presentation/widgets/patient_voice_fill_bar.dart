import 'dart:async';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/services/patient_voice_fill_service.dart';

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
  static const _accent = Color(0xFF2563EB);
  static const _accentSoft = Color(0xFFEFF6FF);
  static const _recordRed = Color(0xFFDC2626);
  static const _success = Color(0xFF15803D);
  static const _warning = Color(0xFFB45309);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  late final PatientVoiceFillService _service =
      widget.service ?? PatientVoiceFillService();

  _Phase _phase = _Phase.idle;
  String _message = '';
  Duration _elapsed = Duration.zero;
  double _level = 0;
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
      _level = 0;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final db = await _service.amplitude();
      if (!mounted || _phase != _Phase.recording) return;
      setState(() {
        _elapsed += const Duration(milliseconds: 200);
        // dBFS (-60 quiet .. 0 loud) to 0..1.
        _level = ((db + 60) / 60).clamp(0.0, 1.0);
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

  @override
  Widget build(BuildContext context) {
    final recording = _phase == _Phase.recording;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: recording ? const Color(0xFFFEF2F2) : _accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (recording ? _recordRed : _accent).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          _leading(),
          const SizedBox(width: 12),
          Expanded(child: _texts()),
          const SizedBox(width: 8),
          ..._actions(),
        ],
      ),
    );
  }

  Widget _leading() {
    switch (_phase) {
      case _Phase.processing:
        return const SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _accent),
          ),
        );
      case _Phase.recording:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _recordRed,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _recordRed.withValues(alpha: 0.35),
                blurRadius: 4 + 14 * _level,
                spreadRadius: 1 + 5 * _level,
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
        );
      case _Phase.done:
        return _iconDisc(Icons.check_rounded, _success);
      case _Phase.error:
        return _iconDisc(Icons.error_outline_rounded, _warning);
      case _Phase.idle:
        return Material(
          color: _accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _start,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.mic_rounded, color: Colors.white, size: 22),
            ),
          ),
        );
    }
  }

  Widget _iconDisc(IconData icon, Color color) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 22),
  );

  Widget _texts() {
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12.5, height: 1.35, color: _muted),
        ),
      ],
    );
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.recording:
        return [
          TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _finish,
            style: FilledButton.styleFrom(backgroundColor: _recordRed),
            child: const Text('Done'),
          ),
        ];
      case _Phase.done:
      case _Phase.error:
        return [
          TextButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.mic_rounded, size: 18),
            label: Text(_phase == _Phase.done ? 'Again' : 'Try again'),
            style: TextButton.styleFrom(foregroundColor: _accent),
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
