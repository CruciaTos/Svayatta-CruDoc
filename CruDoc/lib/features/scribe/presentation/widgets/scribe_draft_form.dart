import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';

/// Editable AI-draft form shared by the mobile review screen and the
/// desktop review phase. Not scrollable itself — the host provides the
/// scroll view. On wide layouts the secondary sections move to a side
/// column.
class ScribeDraftForm extends StatelessWidget {
  const ScribeDraftForm({
    super.key,
    required this.controller,
    required this.palette,
    this.existingDiagnoses = const [],
  });

  final ScribeDraftFormController controller;
  final ScribePalette palette;

  /// Diagnoses already on the patient record, shown for context.
  final List<String> existingDiagnoses;

  static const _splitBreakpoint = 880.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final main = <Widget>[
            ..._notices(),
            for (final section in SoapSection.values)
              ..._soapSection(section, _fieldsFor(section)),
          ];
          final side = <Widget>[
            _followUpSection(context),
            if (controller.original.transcript.trim().isNotEmpty)
              _TranscriptSection(
                transcript: controller.original.transcript,
                palette: palette,
              ),
          ];

          if (constraints.maxWidth >= _splitBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _column(main)),
                const SizedBox(width: _gap + 4),
                SizedBox(width: 340, child: _column(side)),
              ],
            );
          }
          return _column([...main, ...side]);
        },
      ),
    );
  }

  Widget _column(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          children[i],
        ],
      ],
    );
  }

  // ---- Notices ----

  List<Widget> _notices() {
    final note = controller.original;
    final fromAi =
        note.transcript.trim().isNotEmpty ||
        note.confidenceNote.trim().isNotEmpty;
    return [
      if (!fromAi)
        ScribeNotice(
          icon: Icons.edit_note_rounded,
          color: palette.accent,
          background: palette.accentSoft,
          message:
              'Write the consultation note below. Nothing is added to '
              'the patient record until you confirm it.',
        )
      else if (controller.originalWasEmpty)
        ScribeNotice(
          icon: Icons.hearing_disabled_rounded,
          color: palette.warning,
          background: palette.warningSoft,
          message:
              "The AI couldn't find clinical details in this recording. "
              'Check the transcript, or fill in the note yourself.',
        )
      else
        ScribeNotice(
          icon: Icons.auto_awesome_rounded,
          color: palette.accent,
          background: palette.accentSoft,
          message:
              'AI-generated draft. Check every field against the '
              'transcript — only what you confirm is saved to the record.',
        ),
      if (note.confidenceNote.trim().isNotEmpty)
        ScribeNotice(
          icon: Icons.info_outline_rounded,
          color: palette.warning,
          background: palette.warningSoft,
          title: 'AI note on this recording',
          message: note.confidenceNote.trim(),
        ),
      if (controller.physioLists['redFlags']!.isNotEmpty)
        ScribeNotice(
          icon: Icons.warning_amber_rounded,
          color: palette.danger,
          background: palette.dangerSoft,
          title: 'Red flags reported',
          message:
              '${controller.physioLists['redFlags']!.join(' · ')}\n'
              'Consider medical screening or referral before treatment.',
        ),
    ];
  }

  // ---- SOAP layout ----

  /// Fields in [section], in display order. `filled` fields always show;
  /// empty ones only when the section is expanded.
  List<_Field> _fieldsFor(SoapSection section) {
    final p = controller.original.physio;
    bool hasText(String key) =>
        p.textOf(key).isNotEmpty ||
        controller.physioText[key]!.text.trim().isNotEmpty;
    bool hasList(String key) =>
        p.listOf(key).isNotEmpty || controller.physioLists[key]!.isNotEmpty;
    bool hasTable(String key) =>
        p.tableOf(key).isNotEmpty || controller.physioTables[key]!.isNotEmpty;

    final physioFields = <_Field>[
      for (final spec in PhysioFindings.textSpecs)
        if (spec.section == section &&
            !spec.compact &&
            spec.key != 'painNature')
          _Field(hasText(spec.key), () => _physioTextSection(spec)),
      for (final spec in PhysioFindings.listSpecs)
        if (spec.section == section && spec.key != 'painLocation')
          _Field(hasList(spec.key), () => _physioListSection(spec)),
      for (final spec in PhysioFindings.tableSpecs)
        if (spec.section == section)
          _Field(hasTable(spec.key), () => _physioTableSection(spec)),
    ];

    final original = controller.original;
    switch (section) {
      case SoapSection.subjective:
        final painFilled =
            const [
              'painNow',
              'painWorst',
              'painBest',
              'painNature',
            ].any(hasText) ||
            hasList('painLocation');
        return [
          _Field(true, _complaintSection),
          _Field(painFilled, _painSection),
          ...physioFields,
          _Field(
            original.symptoms.isNotEmpty || controller.symptoms.isNotEmpty,
            _symptomsSection,
          ),
          _Field(
            original.medicines.isNotEmpty || controller.medicines.isNotEmpty,
            _medicinesSection,
          ),
        ];
      case SoapSection.objective:
        final vitalsFilled =
            original.vitals.values.any((v) => (v ?? '').trim().isNotEmpty) ||
            [
              controller.bp,
              controller.temp,
              controller.pulse,
            ].any((c) => c.text.trim().isNotEmpty);
        return [...physioFields, _Field(vitalsFilled, _vitalsSection)];
      case SoapSection.assessment:
        return [_Field(true, _diagnosisSection), ...physioFields];
      case SoapSection.plan:
        return [...physioFields, _Field(true, _adviceSection)];
    }
  }

  List<Widget> _soapSection(SoapSection section, List<_Field> fields) {
    final expanded = controller.isSectionExpanded(section);
    final visible = [
      for (final f in fields)
        if (f.filled || expanded) f.build(),
    ];
    final hidden = fields.length - visible.length;
    final canToggle = !controller.originalWasEmpty && (hidden > 0 || expanded);
    if (visible.isEmpty && !canToggle) return const [];

    return [
      _SoapHeader(
        section: section,
        palette: palette,
        trailing: canToggle
            ? TextButton.icon(
                onPressed: () => controller.toggleSection(section),
                icon: Icon(
                  expanded ? Icons.unfold_less_rounded : Icons.add_rounded,
                  size: 16,
                ),
                label: Text(expanded ? 'Hide empty' : 'Add fields ($hidden)'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      ),
      ...visible,
    ];
  }

  // ---- Sections ----

  Widget _complaintSection() {
    return _Section(
      label: 'CHIEF COMPLAINT',
      palette: palette,
      child: _textField(
        controller.chiefComplaint,
        hint: 'e.g. Right knee pain for 3 weeks',
        capitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _symptomsSection() {
    return _Section(
      label: 'ASSOCIATED SYMPTOMS',
      palette: palette,
      child: _ChipEditor(
        items: controller.symptoms,
        input: controller.symptomInput,
        hint: 'Add a symptom',
        color: palette.symptom,
        palette: palette,
        onAdd: controller.addSymptom,
        onRemove: controller.removeSymptom,
      ),
    );
  }

  Widget _diagnosisSection() {
    final merge = ConsultationNoteRepository.mergeDiagnoses(
      existingDiagnoses,
      controller.diagnoses,
    );
    final added =
        merge.diagnoses.length -
        existingDiagnoses.length +
        merge.overflow.length;

    return _Section(
      label: 'CLINICAL IMPRESSION / DIAGNOSIS',
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (existingDiagnoses.isNotEmpty) ...[
            Text(
              'On record (${existingDiagnoses.length} of ${Patient.maxDiagnoses})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in existingDiagnoses)
                  _Pill(label: d, color: palette.existing),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'From this consultation',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _ChipEditor(
            items: controller.diagnoses,
            input: controller.diagnosisInput,
            hint: 'Add a diagnosis',
            color: palette.diagnosis,
            palette: palette,
            onAdd: controller.addDiagnosis,
            onRemove: controller.removeDiagnosis,
          ),
          if (added > 0 && existingDiagnoses.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              merge.overflow.isEmpty
                  ? '$added new ${added == 1 ? 'diagnosis' : 'diagnoses'} '
                        'will be added to the patient record.'
                  : 'The record holds ${Patient.maxDiagnoses} diagnoses — '
                        '${merge.overflow.join(', ')} will be saved to the '
                        "patient's notes instead.",
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: merge.overflow.isEmpty
                    ? palette.textSecondary
                    : palette.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _medicinesSection() {
    return _Section(
      label: 'MEDICATIONS',
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.medicines.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'No medicines mentioned.',
                style: TextStyle(fontSize: 13, color: palette.hint),
              ),
            ),
          for (final row in controller.medicines)
            _MedicineRowEditor(
              key: ValueKey(row.id),
              row: row,
              palette: palette,
              onRemove: () => controller.removeMedicine(row),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.addMedicine,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add medicine'),
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adviceSection() {
    return _Section(
      label: 'EDUCATION & ADVICE',
      palette: palette,
      child: _textField(
        controller.advice,
        hint: 'e.g. Avoid forward bending, ice 15 min twice daily',
        maxLines: 5,
        capitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _vitalsSection() {
    return _Section(
      label: 'VITALS',
      palette: palette,
      trailing: Text(
        'Only if stated',
        style: TextStyle(fontSize: 11, color: palette.hint),
      ),
      child: Column(
        children: [
          _labelledField('Blood pressure', controller.bp, 'e.g. 120/80 mmHg'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _labelledField(
                  'Temperature',
                  controller.temp,
                  'e.g. 99.1 °F',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _labelledField('Pulse', controller.pulse, 'e.g. 78 bpm'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _followUpSection(BuildContext context) {
    final date = controller.followUpDate;
    return _Section(
      label: 'FOLLOW-UP',
      palette: palette,
      child: Material(
        color: palette.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.fieldRadius),
          side: palette.fieldBorder == null
              ? BorderSide.none
              : BorderSide(color: palette.fieldBorder!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pickFollowUp(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: date == null ? palette.hint : palette.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    date == null
                        ? 'No follow-up — tap to set'
                        : DateFormat('EEE, d MMM yyyy').format(date),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: date == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: date == null ? palette.hint : palette.textPrimary,
                    ),
                  ),
                ),
                if (date != null)
                  IconButton(
                    tooltip: 'Clear follow-up',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: palette.hint,
                    ),
                    onPressed: () => controller.setFollowUpDate(null),
                  )
                else
                  const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFollowUp(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = controller.followUpDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(today)
          ? current
          : today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Follow-up date',
    );
    if (picked != null) controller.setFollowUpDate(picked);
  }

  Widget _painSection() {
    final compact = PhysioFindings.textSpecs.where((s) => s.compact).toList();
    final nature = PhysioFindings.textSpecs.firstWhere(
      (s) => s.key == 'painNature',
    );
    final location = PhysioFindings.listSpecs.firstWhere(
      (s) => s.key == 'painLocation',
    );
    return _Section(
      label: 'PAIN',
      palette: palette,
      trailing: Text(
        'NPRS 0–10',
        style: TextStyle(fontSize: 11, color: palette.hint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < compact.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _labelledField(
                    compact[i].label,
                    controller.physioText[compact[i].key]!,
                    compact[i].hint,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _subLabel(location.label),
          const SizedBox(height: 6),
          _physioChips(location, palette.symptom),
          const SizedBox(height: 12),
          _subLabel(nature.label),
          const SizedBox(height: 6),
          _textField(
            controller.physioText[nature.key]!,
            hint: nature.hint,
            maxLines: nature.maxLines,
            capitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }

  Widget _physioTextSection(PhysioTextSpec spec) {
    return _Section(
      label: spec.label.toUpperCase(),
      palette: palette,
      child: _textField(
        controller.physioText[spec.key]!,
        hint: spec.hint,
        maxLines: spec.maxLines + 2,
        capitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _physioListSection(PhysioListSpec spec) {
    final color = switch (spec.key) {
      'redFlags' => palette.danger,
      'redFlagsCleared' => palette.success,
      _ => spec.section == SoapSection.plan ? palette.accent : palette.symptom,
    };
    return _Section(
      label: spec.label.toUpperCase(),
      palette: palette,
      child: _physioChips(spec, color),
    );
  }

  Widget _physioChips(PhysioListSpec spec, Color color) {
    return _ChipEditor(
      items: controller.physioLists[spec.key]!,
      input: controller.physioListInputs[spec.key]!,
      hint: spec.hint,
      color: color,
      palette: palette,
      onAdd: ([v]) => controller.addPhysioListItem(spec.key, v),
      onRemove: (i) => controller.removePhysioListItem(spec.key, i),
    );
  }

  Widget _physioTableSection(PhysioTableSpec spec) {
    final rows = controller.physioTables[spec.key]!;
    return _Section(
      label: spec.label.toUpperCase(),
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            _TableRowEditor(
              key: ValueKey(row.id),
              spec: spec,
              row: row,
              palette: palette,
              onRemove: () => controller.removeTableRow(spec.key, row),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.addTableRow(spec),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(spec.addLabel),
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                textStyle: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
      ),
    );
  }

  // ---- Field helpers ----

  Widget _textField(
    TextEditingController c, {
    required String hint,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: c,
      minLines: 1,
      maxLines: maxLines,
      textCapitalization: capitalization,
      style: TextStyle(fontSize: 14, color: palette.textPrimary, height: 1.4),
      decoration: palette.fieldDecoration(hint),
    );
  }

  Widget _labelledField(String label, TextEditingController c, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: c,
          style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
          decoration: palette.fieldDecoration(hint, dense: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

class _Field {
  const _Field(this.filled, this.build);
  final bool filled;
  final Widget Function() build;
}

/// "S — Subjective" divider between SOAP groups.
class _SoapHeader extends StatelessWidget {
  const _SoapHeader({
    required this.section,
    required this.palette,
    this.trailing,
  });

  final SoapSection section;
  final ScribePalette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              section.letter,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              section.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One row of a physio table: the identity column on top with a remove
/// button, the remaining columns side by side below it.
class _TableRowEditor extends StatelessWidget {
  const _TableRowEditor({
    super.key,
    required this.spec,
    required this.row,
    required this.palette,
    required this.onRemove,
  });

  final PhysioTableSpec spec;
  final ScribeTableRow row;
  final ScribePalette palette;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13.5, color: palette.textPrimary);
    final first = spec.columns.first;
    final rest = spec.columns.skip(1).toList();

    InputDecoration deco(String hint) => palette
        .fieldDecoration(hint, dense: true)
        .copyWith(
          fillColor: palette.card,
          labelText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: BoxDecoration(
        color: palette.field.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(palette.fieldRadius + 2),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.cells[first.key],
                  textCapitalization: TextCapitalization.sentences,
                  style: style.copyWith(fontWeight: FontWeight.w600),
                  decoration: deco(first.label),
                ),
              ),
              IconButton(
                tooltip: 'Remove row',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: palette.danger,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rest.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: rest[i].flex,
                    child: TextField(
                      controller: row.cells[rest[i].key],
                      minLines: 1,
                      maxLines: 3,
                      style: style,
                      decoration: deco(rest[i].label),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tinted inline notice used across the scribe screens.
class ScribeNotice extends StatelessWidget {
  const ScribeNotice({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.message,
    this.title,
    this.action,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color.lerp(color, Colors.black, 0.35),
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.palette,
    required this.child,
    this.trailing,
  });

  final String label;
  final ScribePalette palette;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(child: Text(label, style: palette.sectionLabel)),
        ?trailing,
      ],
    );
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(palette.cardRadius),
        border: Border.all(color: palette.cardBorder),
      ),
      child: palette.labelsOutsideCards
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, const SizedBox(height: 12), child],
            ),
    );
    if (!palette.labelsOutsideCards) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(left: 2), child: header),
        const SizedBox(height: 10),
        card,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.onRemove});

  final String label;
  final Color color;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, onRemove == null ? 12 : 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color.lerp(color, Colors.black, 0.2),
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            InkResponse(
              onTap: onRemove,
              radius: 14,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipEditor extends StatelessWidget {
  const _ChipEditor({
    required this.items,
    required this.input,
    required this.hint,
    required this.color,
    required this.palette,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> items;
  final TextEditingController input;
  final String hint;
  final Color color;
  final ScribePalette palette;
  final void Function([String?]) onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < items.length; i++)
                _Pill(
                  label: items[i],
                  color: color,
                  onRemove: () => onRemove(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: input,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 13.5, color: palette.textPrimary),
          onSubmitted: (v) => onAdd(v),
          inputFormatters: [LengthLimitingTextInputFormatter(120)],
          decoration: palette
              .fieldDecoration(hint, dense: true)
              .copyWith(
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: input,
                  builder: (context, value, _) => IconButton(
                    tooltip: 'Add',
                    icon: Icon(
                      Icons.add_circle_rounded,
                      color: value.text.trim().isEmpty ? palette.hint : color,
                    ),
                    onPressed: value.text.trim().isEmpty ? null : () => onAdd(),
                  ),
                ),
              ),
        ),
      ],
    );
  }
}

class _MedicineRowEditor extends StatelessWidget {
  const _MedicineRowEditor({
    super.key,
    required this.row,
    required this.palette,
    required this.onRemove,
  });

  final ScribeMedicineRow row;
  final ScribePalette palette;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13.5, color: palette.textPrimary);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: BoxDecoration(
        color: palette.field.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(palette.fieldRadius + 2),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.medication_rounded,
                size: 18,
                color: palette.diagnosis,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.name,
                  textCapitalization: TextCapitalization.words,
                  style: style.copyWith(fontWeight: FontWeight.w600),
                  decoration: palette
                      .fieldDecoration('Medicine name', dense: true)
                      .copyWith(fillColor: palette.card),
                ),
              ),
              IconButton(
                tooltip: 'Remove medicine',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: palette.danger,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 26, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.dosage,
                    minLines: 1,
                    maxLines: 3,
                    style: style,
                    decoration: palette
                        .fieldDecoration('Dose & frequency', dense: true)
                        .copyWith(fillColor: palette.card),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.instructions,
                    minLines: 1,
                    maxLines: 3,
                    style: style,
                    decoration: palette
                        .fieldDecoration('Instructions', dense: true)
                        .copyWith(fillColor: palette.card),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptSection extends StatefulWidget {
  const _TranscriptSection({required this.transcript, required this.palette});

  final String transcript;
  final ScribePalette palette;

  @override
  State<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends State<_TranscriptSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return _Section(
      label: 'TRANSCRIPT',
      palette: p,
      trailing: TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(_expanded ? 'Show less' : 'Show all'),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _expanded ? double.infinity : 96,
          ),
          child: ClipRect(
            child: SelectableText(
              widget.transcript,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
