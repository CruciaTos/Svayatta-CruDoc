import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The radiologist's lesion checklist with the usual descriptors as chips
/// (tap to add or take out; the text stays editable).
abstract final class RadLesionTerms {
  static const shape = ['Round', 'Oval', 'Scalloped', 'Lobulated', 'Irregular'];
  static const borders = [
    'Well-defined',
    'Ill-defined',
    'Corticated',
    'Sclerotic',
    'Punched-out',
    'Moth-eaten',
  ];
  static const internal = [
    'Radiolucent',
    'Radiopaque',
    'Mixed density',
    'Unilocular',
    'Multilocular',
    'Ground-glass',
    'Calcifications',
  ];
  static const effects = [
    'Expands the cortex',
    'Thins the cortex',
    'Perforates the cortex',
    'Displaces the canal',
    'Displaces teeth',
    'Resorbs roots',
    'Lifts the sinus floor',
    'Periosteal reaction',
  ];
}

/// One lesion in the report: location, size, shape, borders, internal
/// structure and effects on the neighbours, plus notes. With the AI
/// differential turned on, a violet panel says what it will add once an
/// AI key is connected.
class RadLesionCard extends StatefulWidget {
  const RadLesionCard({
    super.key,
    required this.index,
    required this.lesion,
    required this.onChanged,
    required this.onRemove,
    required this.readOnly,
    required this.phrases,
    required this.showAiDifferential,
  });

  final int index;
  final RadLesion lesion;
  final ValueChanged<RadLesion> onChanged;
  final VoidCallback onRemove;
  final bool readOnly;
  final List<RadPhrase> phrases;
  final bool showAiDifferential;

  @override
  State<RadLesionCard> createState() => _RadLesionCardState();
}

class _RadLesionCardState extends State<RadLesionCard> {
  late final _location = TextEditingController(text: widget.lesion.location);
  late final _size = TextEditingController(text: widget.lesion.sizeMm);
  late final _shape = TextEditingController(text: widget.lesion.shape);
  late final _borders = TextEditingController(text: widget.lesion.borders);
  late final _internal = TextEditingController(text: widget.lesion.internal);
  late final _effects = TextEditingController(text: widget.lesion.effects);
  late final _notes = TextEditingController(text: widget.lesion.notes);

  @override
  void dispose() {
    for (final t in [_location, _size, _shape, _borders, _internal, _effects, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(widget.lesion.copyWith(
      location: _location.text.trim(),
      sizeMm: _size.text.trim(),
      shape: _shape.text.trim(),
      borders: _borders.text.trim(),
      internal: _internal.text.trim(),
      effects: _effects.text.trim(),
      notes: _notes.text.trim(),
    ));
  }

  void _toggle(TextEditingController t, String term) {
    setState(() => t.text = radToggleTerm(t.text, term));
    _emit();
  }

  Widget _field(
    String label,
    TextEditingController t, {
    List<String> chips = const [],
    String? hint,
  }) {
    final c = context.cru;
    if (widget.readOnly && t.text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: CruType.subhead.w500.tint(c.label2)),
          const SizedBox(height: CruSpace.s6),
          if (chips.isNotEmpty && !widget.readOnly) ...[
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final term in chips)
                  DentalChoiceChip(
                    label: term,
                    selected: radHasTerm(t.text, term),
                    onSurface: true,
                    onTap: () => _toggle(t, term),
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),
          ],
          RadTextArea(
            controller: t,
            phrases: widget.phrases,
            readOnly: widget.readOnly,
            minLines: 1,
            hint: hint,
            onChanged: () {
              setState(() {});
              _emit();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final location = _location.text.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(CruSpace.s16, CruSpace.s14, CruSpace.s16, CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIcon(RadReportIcons.lesion, size: 18, strokeWidth: 1.8, color: c.label2),
              const SizedBox(width: CruSpace.s8),
              Text('Lesion ${widget.index + 1}', style: CruType.callout.tint(c.label)),
              if (location.isNotEmpty) ...[
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.subhead.tint(c.label2),
                  ),
                ),
              ] else
                const Spacer(),
              if (!widget.readOnly)
                CruIconButton(
                  icon: CruIcons.close,
                  size: CruSize.rowCapsule,
                  iconSize: 15,
                  semanticLabel: 'Remove lesion ${widget.index + 1}',
                  tooltip: 'Remove lesion',
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          if (widget.readOnly)
            _field('Location', _location)
          else
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s2),
              child: CruFieldRow(
                flex: const [3, 2],
                children: [
                  _field('Location', _location, hint: 'Left mandibular body, periapical to 36'),
                  _field('Size (mm)', _size, hint: '12 × 9 × 8'),
                ],
              ),
            ),
          if (widget.readOnly) _field('Size (mm)', _size),
          _field('Shape', _shape, chips: RadLesionTerms.shape),
          _field('Borders', _borders, chips: RadLesionTerms.borders),
          _field('Internal structure', _internal, chips: RadLesionTerms.internal),
          _field('Effects on surrounding structures', _effects, chips: RadLesionTerms.effects),
          _field('Notes', _notes, hint: 'Anything else about this lesion'),
          if (widget.showAiDifferential) ...[
            const SizedBox(height: CruSpace.s16),
            Container(
              padding: const EdgeInsets.all(CruSpace.s12),
              decoration: ShapeDecoration(
                color: c.aiTint,
                shape: cruShape(CruRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CruIcon(CruIcons.sparkle, size: 15, strokeWidth: 1.8, color: c.ai),
                      const SizedBox(width: CruSpace.s6),
                      Text('AI differential', style: CruType.subhead.w600.tint(c.ai)),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    'Lists likely diagnoses from these descriptors once an AI key is '
                    "connected. Only the descriptors are sent, never the patient's details.",
                    style: CruType.caption.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s10),
                  const RadAiPending(
                    label: 'Suggest differential',
                    explain: 'Suggests a differential diagnosis for this lesion.',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
