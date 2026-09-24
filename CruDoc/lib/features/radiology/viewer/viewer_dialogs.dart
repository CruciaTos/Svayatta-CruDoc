import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_icons.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Asks for one line of text (a note, a label, a preset name).
Future<String?> askRadText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? hint,
  String action = 'Save',
  int maxLines = 1,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: title,
        label: label,
        initial: initial,
        hint: hint,
        action: action,
        maxLines: maxLines,
      ),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.hint,
    required this.action,
    required this.maxLines,
  });

  final String title;
  final String label;
  final String initial;
  final String? hint;
  final String action;
  final int maxLines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return DentalPanelDialog(
      title: widget.title,
      width: CruSize.dialog + 60,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s8, CruSpace.s8, CruSpace.s4),
        child: CruTextField(
          label: widget.label,
          controller: _text,
          hint: widget.hint,
          autofocus: true,
          maxLines: widget.maxLines,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
        ),
      ),
      footer: _Footer(action: widget.action, onSubmit: _submit),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.action, required this.onSubmit});

  final String action;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: CruSpace.s10),
          CruButton(label: action, onPressed: onSubmit),
        ],
      );
}

/// Asks for the real length of the line just drawn, in mm.
Future<double?> askRadCalibration(BuildContext context, {required double pixels}) =>
    showDialog<double>(context: context, builder: (_) => _CalibrationDialog(pixels: pixels));

class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog({required this.pixels});

  final double pixels;

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  final _mm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _mm.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_mm.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) {
      setState(() => _error = 'Type the length in millimetres, e.g. 10');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'Calibrate',
      subtitle: 'The line you drew is ${widget.pixels.toStringAsFixed(0)} pixels long',
      leading: const CruIconTile(icon: RadViewerIcons.calibrate, tone: CruTileTone.neutral),
      width: CruSize.dialog + 60,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(CruSpace.s8, CruSpace.s8, CruSpace.s8, CruSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Draw along something of known size (a ruler, an implant, a '
              'calibration ball) and type its real length. Every length and '
              'area on this image then reads in mm.',
              style: CruType.text.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Real length in mm',
              controller: _mm,
              hint: '10',
              autofocus: true,
              tabular: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: CruSpace.s6),
              CruFieldError(_error!),
            ],
          ],
        ),
      ),
      footer: _Footer(action: 'Calibrate', onSubmit: _submit),
    );
  }
}

/// FDI tooth numbers, as the dentist sees them facing the patient:
/// upper right → upper left, lower right → lower left.
const _permanentUpper = ['18', '17', '16', '15', '14', '13', '12', '11', '21', '22', '23', '24', '25', '26', '27', '28'];
const _permanentLower = ['48', '47', '46', '45', '44', '43', '42', '41', '31', '32', '33', '34', '35', '36', '37', '38'];
const _primaryUpper = ['55', '54', '53', '52', '51', '61', '62', '63', '64', '65'];
const _primaryLower = ['85', '84', '83', '82', '81', '71', '72', '73', '74', '75'];

/// Picks an FDI tooth number for a tooth label.
Future<String?> pickRadTooth(BuildContext context, {String initial = ''}) =>
    showDialog<String>(context: context, builder: (_) => _ToothDialog(initial: initial));

class _ToothDialog extends StatefulWidget {
  const _ToothDialog({required this.initial});

  final String initial;

  @override
  State<_ToothDialog> createState() => _ToothDialogState();
}

class _ToothDialogState extends State<_ToothDialog> {
  late bool _primary =
      _primaryUpper.contains(widget.initial) || _primaryLower.contains(widget.initial);

  Widget _row(List<String> teeth) => Wrap(
        spacing: CruSpace.s6,
        runSpacing: CruSpace.s6,
        children: [
          for (var i = 0; i < teeth.length; i++) ...[
            if (i == teeth.length ~/ 2) const SizedBox(width: CruSpace.s12),
            DentalChoiceChip(
              label: teeth[i],
              tabular: true,
              selected: teeth[i] == widget.initial,
              onTap: () => Navigator.of(context).pop(teeth[i]),
            ),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DentalPanelDialog(
      title: 'Tooth number',
      subtitle: 'FDI numbering, as you face the patient',
      leading: const CruIconTile(icon: RadViewerIcons.tooth, tone: CruTileTone.neutral),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CruSegmentedControl<bool>(
              segments: const [CruSegment(false, 'Permanent'), CruSegment(true, 'Primary')],
              selected: _primary,
              onChanged: (v) => setState(() => _primary = v),
            ),
            const SizedBox(height: CruSpace.s16),
            Text('Upper', style: CruType.groupLabel.tint(c.label3)),
            const SizedBox(height: CruSpace.s8),
            _row(_primary ? _primaryUpper : _permanentUpper),
            const SizedBox(height: CruSpace.s16),
            Text('Lower', style: CruType.groupLabel.tint(c.label3)),
            const SizedBox(height: CruSpace.s8),
            _row(_primary ? _primaryLower : _permanentLower),
          ],
        ),
      ),
    );
  }
}
