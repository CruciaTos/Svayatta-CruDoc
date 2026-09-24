import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Findings a radiograph shows most often, as one-tap chips.
const _quickFindings = [
  'Caries',
  'Periapical radiolucency',
  'Widened PDL space',
  'Root canal treated',
  'Restored',
  'Crown',
  'Implant',
  'Impacted',
  'Retained root',
  'Root resorption',
  'Bone loss',
  'Missing',
];

/// FDI order: quadrant, then tooth.
int _fdiOrder(String a, String b) =>
    (int.tryParse(a) ?? 999).compareTo(int.tryParse(b) ?? 999);

/// Tooth findings: the dental 2D chart (teeth with a finding stand out),
/// click a tooth to write what the scan shows for it, and every finding
/// listed in FDI order.
class RadToothFindings extends StatefulWidget {
  const RadToothFindings({
    super.key,
    required this.findings,
    required this.onChanged,
    required this.readOnly,
    required this.childDefault,
    required this.phrases,
  });

  /// FDI number to finding.
  final Map<String, String> findings;
  final ValueChanged<Map<String, String>> onChanged;
  final bool readOnly;

  /// Start on the milk teeth (a young patient).
  final bool childDefault;
  final List<RadPhrase> phrases;

  @override
  State<RadToothFindings> createState() => _RadToothFindingsState();
}

class _RadToothFindingsState extends State<RadToothFindings> {
  late bool _child = widget.childDefault ||
      (widget.findings.isNotEmpty && widget.findings.keys.every(DentalChart.isPrimary));
  String? _selected;
  final _finding = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _finding.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(String n) {
    setState(() {
      _selected = n;
      _finding.text = widget.findings[n] ?? '';
    });
    if (!widget.readOnly) _focus.requestFocus();
  }

  void _write(String n, String text) {
    final next = {...widget.findings};
    if (text.trim().isEmpty) {
      next.remove(n);
    } else {
      next[n] = text.trim();
    }
    widget.onChanged(next);
  }

  void _remove(String n) {
    final next = {...widget.findings}..remove(n);
    if (_selected == n) _finding.clear();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final numbers = widget.findings.keys.toList()..sort(_fdiOrder);
    final data = ToothChartData({
      for (final n in numbers) n: ToothVisual(number: n, state: ToothState.needsCare),
    });
    final sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.readOnly
                    ? 'Teeth with a finding are shaded.'
                    : 'Click a tooth to write what the scan shows for it.',
                style: CruType.caption.tint(c.label3),
              ),
            ),
            CruSegmentedControl<bool>(
              semanticLabel: 'Dentition',
              segments: const [
                CruSegment(false, 'Permanent'),
                CruSegment(true, 'Milk teeth'),
              ],
              selected: _child,
              onChanged: (v) => setState(() => _child = v),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s8),
        ToothChart2D(
          data: data,
          child: _child,
          mode: ChartMode.findings,
          selected: sel,
          onSelect: _select,
          onOpen: _select,
        ),
        if (sel != null && !widget.readOnly) ...[
          const SizedBox(height: CruSpace.s12),
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(CruRadius.control, side: BorderSide(color: c.separator)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Tooth $sel', style: CruType.callout.tabular.tint(c.label)),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      child: Text(
                        DentalChart.isPrimary(sel) ? 'Milk tooth' : 'Permanent tooth',
                        style: CruType.caption.tint(c.label3),
                      ),
                    ),
                    CruIconButton(
                      icon: CruIcons.close,
                      size: CruSize.rowCapsule,
                      iconSize: 15,
                      semanticLabel: 'Close tooth $sel',
                      tooltip: 'Done',
                      onPressed: () => setState(() => _selected = null),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s8),
                Wrap(
                  spacing: CruSpace.s6,
                  runSpacing: CruSpace.s6,
                  children: [
                    for (final f in _quickFindings)
                      DentalChoiceChip(
                        label: f,
                        selected: radHasTerm(_finding.text, f),
                        onSurface: true,
                        onTap: () {
                          setState(() => _finding.text = radToggleTerm(_finding.text, f));
                          _write(sel, _finding.text);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: CruSpace.s8),
                RadTextArea(
                  controller: _finding,
                  focusNode: _focus,
                  phrases: widget.phrases,
                  minLines: 1,
                  hint: 'What the scan shows for tooth $sel',
                  onChanged: () {
                    setState(() {});
                    _write(sel, _finding.text);
                  },
                ),
              ],
            ),
          ),
        ],
        if (numbers.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s12),
          for (var i = 0; i < numbers.length; i++) ...[
            if (i > 0) const CruSeparator(indent: CruSpace.s12 + CruSize.iconTile + CruSpace.s12),
            DentalListRow(
              semanticLabel: 'Tooth ${numbers[i]}, ${widget.findings[numbers[i]]}',
              minHeight: CruSize.collapsedRow,
              onTap: () => _select(numbers[i]),
              child: Row(
                children: [
                  Container(
                    width: CruSize.iconTile,
                    height: CruSize.pill,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: numbers[i] == sel ? c.label : c.inset,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      numbers[i],
                      style: CruType.caption.w600.tabular
                          .tint(numbers[i] == sel ? c.surface : c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      widget.findings[numbers[i]] ?? '',
                      style: CruType.note.tint(c.label),
                    ),
                  ),
                  if (!widget.readOnly)
                    CruIconButton(
                      icon: CruIcons.close,
                      size: CruSize.rowCapsule,
                      iconSize: 14,
                      semanticLabel: 'Remove finding for ${numbers[i]}',
                      tooltip: 'Remove',
                      onPressed: () => _remove(numbers[i]),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
