import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/form_builder.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One patient response to a form template.
class FormResponse {
  final String id;
  final String patientId;
  final String templateId;
  final String templateName;
  final Map<String, dynamic> answers;
  final DateTime answeredAt;
  final DentalRecord record;

  const FormResponse({
    required this.id,
    required this.patientId,
    required this.templateId,
    required this.templateName,
    required this.answers,
    required this.answeredAt,
    required this.record,
  });

  factory FormResponse.fromRecord(DentalRecord r) {
    final d = r.data;
    return FormResponse(
      id: r.id,
      patientId: r.patientId,
      templateId: d['templateId'] as String? ?? '',
      templateName: d['templateName'] as String? ?? 'Form Response',
      answers: d['answers'] is Map
          ? Map<String, dynamic>.from(d['answers'] as Map)
          : <String, dynamic>{},
      answeredAt: r.recordedAt,
      record: r,
    );
  }
}

/// Dialog for filling or reviewing a custom clinical form for a patient.
class FormFillDialog extends ConsumerStatefulWidget {
  const FormFillDialog({
    super.key,
    required this.patient,
    required this.template,
    this.initialResponse,
    this.readOnly = false,
  });

  final Patient patient;
  final FormTemplate template;
  final FormResponse? initialResponse;
  final bool readOnly;

  @override
  ConsumerState<FormFillDialog> createState() => _FormFillDialogState();
}

class _FormFillDialogState extends ConsumerState<FormFillDialog> {
  late bool _editing;
  late Map<String, dynamic> _answers;
  final Map<String, TextEditingController> _controllers = {};
  String? _validationError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _editing = !widget.readOnly;
    _answers = widget.initialResponse != null
        ? Map<String, dynamic>.from(widget.initialResponse!.answers)
        : <String, dynamic>{};

    for (final field in widget.template.fields) {
      if (field.type == FormFieldType.text ||
          field.type == FormFieldType.longText ||
          field.type == FormFieldType.number) {
        final val = _answers[field.id]?.toString() ?? '';
        _controllers[field.id] = TextEditingController(text: val);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // Collect text controller values
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) {
        _answers[entry.key] = text;
      } else {
        _answers.remove(entry.key);
      }
    }

    // Validate required fields
    for (final field in widget.template.fields) {
      if (field.required) {
        final val = _answers[field.id];
        final empty = val == null ||
            (val is String && val.trim().isEmpty) ||
            (val is List && val.isEmpty);
        if (empty) {
          setState(() {
            _validationError = 'Please answer required question: "${field.label}"';
          });
          return;
        }
      }
    }

    setState(() {
      _validationError = null;
      _busy = true;
    });

    try {
      final now = DateTime.now();
      final data = {
        'templateId': widget.template.id,
        'templateName': widget.template.name,
        'answers': _answers,
      };

      final resp = widget.initialResponse;
      if (resp == null) {
        final rec = DentalRecord.create(
          widget.patient.id,
          RecKind.formResponse,
          data,
          at: now,
        );
        await saveDentalRecord(ref, rec);
        if (mounted) recToast(context, 'Form submitted');
      } else {
        final updated = resp.record.copyWith(
          data: data,
          recordedAt: now,
        );
        await saveDentalRecord(ref, updated);
        if (mounted) recToast(context, 'Form response updated');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving response: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = widget.template;
    final p = widget.patient;

    return CruFormDialog(
      title: t.name,
      subtitle: '${p.fullName} (${p.age}y) · ${widget.initialResponse != null ? 'Recorded ${DentalFormat.date(widget.initialResponse!.answeredAt)}' : 'New entry'}',
      width: 660,
      busy: _busy,
      submitLabel: _editing ? 'Submit response' : 'Edit response',
      onSubmit: () {
        if (!_editing) {
          setState(() => _editing = true);
        } else {
          _submit();
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t.description.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(CruSpace.s12),
              decoration: BoxDecoration(
                color: c.inset,
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
              child: Text(
                t.description,
                style: CruType.caption.tint(c.label2),
              ),
            ),
            const SizedBox(height: CruSpace.s16),
          ],

          if (_validationError != null) ...[
            Container(
              padding: const EdgeInsets.all(CruSpace.s10),
              decoration: BoxDecoration(
                color: c.amberTint,
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(color: c.amberText),
              ),
              child: Row(
                children: [
                  CruIcon(CruIcons.warning, size: 16, color: c.amberText),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Text(_validationError!, style: CruType.caption.tint(c.amberText)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          for (var i = 0; i < t.fields.length; i++) ...[
            _buildFieldWidget(t.fields[i], i, c),
            const SizedBox(height: CruSpace.s16),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldWidget(FormFieldSpec spec, int index, CruColors c) {
    final ans = _answers[spec.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${index + 1}. ${spec.label}',
              style: CruType.callout.w600.tint(c.label),
            ),
            if (spec.required) ...[
              const SizedBox(width: CruSpace.s4),
              Text('*', style: CruType.callout.w600.tint(c.redText)),
            ],
          ],
        ),
        const SizedBox(height: CruSpace.s8),

        // Value widget depending on field type
        switch (spec.type) {
          FormFieldType.text => !_editing
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Text(
                    ans?.toString().isNotEmpty == true ? ans.toString() : '—',
                    style: CruType.body.tint(c.label),
                  ),
                )
              : CruTextField(
                  label: spec.label,
                  controller: _controllers.putIfAbsent(spec.id, () => TextEditingController()),
                  hint: 'Type your answer...',
                ),
          FormFieldType.longText => !_editing
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(CruSpace.s12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Text(
                    ans?.toString().isNotEmpty == true ? ans.toString() : '—',
                    style: CruType.body.tint(c.label),
                  ),
                )
              : CruTextField(
                  label: spec.label,
                  controller: _controllers.putIfAbsent(spec.id, () => TextEditingController()),
                  maxLines: 4,
                  hint: 'Detailed notes...',
                ),
          FormFieldType.number => !_editing
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Text(
                    ans != null ? '$ans ${spec.unit}'.trim() : '—',
                    style: CruType.body.tabular.tint(c.label),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: CruTextField(
                        label: spec.label,
                        controller: _controllers.putIfAbsent(spec.id, () => TextEditingController()),
                        keyboardType: TextInputType.number,
                        hint: '0.0',
                      ),
                    ),
                    if (spec.unit.isNotEmpty) ...[
                      const SizedBox(width: CruSpace.s8),
                      Text(spec.unit, style: CruType.caption.w600.tint(c.label2)),
                    ],
                  ],
                ),
          FormFieldType.choice => Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s6,
              children: [
                for (final opt in spec.options)
                  DentalChoiceChip(
                    label: opt,
                    selected: ans == opt,
                    onTap: _editing
                        ? () => setState(() => _answers[spec.id] = opt)
                        : () {},
                  ),
              ],
            ),
          FormFieldType.multiChoice => Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s6,
              children: [
                for (final opt in spec.options)
                  DentalChoiceChip(
                    label: opt,
                    selected: (ans is List) && ans.contains(opt),
                    onTap: _editing
                        ? () {
                            setState(() {
                              final list = (ans is List) ? List<String>.from(ans) : <String>[];
                              if (list.contains(opt)) {
                                list.remove(opt);
                              } else {
                                list.add(opt);
                              }
                              _answers[spec.id] = list;
                            });
                          }
                        : () {},
                  ),
              ],
            ),
          FormFieldType.yesNo => Row(
              children: [
                DentalChoiceChip(
                  label: 'Yes',
                  selected: ans == true || ans == 'Yes',
                  onTap: _editing
                      ? () => setState(() => _answers[spec.id] = 'Yes')
                      : () {},
                ),
                const SizedBox(width: CruSpace.s8),
                DentalChoiceChip(
                  label: 'No',
                  selected: ans == false || ans == 'No',
                  onTap: _editing
                      ? () => setState(() => _answers[spec.id] = 'No')
                      : () {},
                ),
              ],
            ),
          FormFieldType.date => Container(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(color: c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CruIcon(CruIcons.calendar, size: 16, color: c.accent),
                  const SizedBox(width: CruSpace.s8),
                  Text(
                    ans != null ? DentalFormat.date(DateTime.tryParse(ans.toString()) ?? DateTime.now()) : 'Pick date',
                    style: CruType.caption.tint(c.label),
                  ),
                  if (_editing) ...[
                    const SizedBox(width: CruSpace.s12),
                    CruCapsuleButton(
                      label: 'Change',
                      icon: CruIcons.calendar,
                      onPressed: () async {
                        final picked = await pickDentalDate(context, initial: DateTime.now());
                        if (picked != null) {
                          setState(() => _answers[spec.id] = picked.toIso8601String());
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          FormFieldType.scale10 => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Rating: ${ans ?? 'Not rated'}', style: CruType.caption.w600.tabular.tint(c.label)),
                    Text('0 = None, 10 = Severe', style: CruType.micro.tint(c.label3)),
                  ],
                ),
                const SizedBox(height: CruSpace.s4),
                Slider(
                  value: (ans is num) ? ans.toDouble() : 0.0,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  activeColor: c.accent,
                  label: '${ans ?? 0}',
                  onChanged: _editing
                      ? (v) => setState(() => _answers[spec.id] = v.toInt())
                      : null,
                ),
              ],
            ),
        },
      ],
    );
  }
}

/// Dialog showing all completed questionnaires/forms for a patient, plus action to fill a new form.
class PatientFormsDialog extends ConsumerWidget {
  const PatientFormsDialog({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final responsesAsync = ref.watch(
      patientRecordsProvider((patientId: patient.id, kind: RecKind.formResponse)),
    );
    final templatesAsync = ref.watch(clinicRecordsProvider(RecKind.formTemplate));

    return DentalPanelDialog(
      title: 'Clinical Questionnaires & Forms',
      subtitle: patient.fullName,
      width: 720,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Patient Responses', style: CruType.callout.w600.tint(c.label)),
              CruButton(
                label: 'Fill a form',
                icon: CruIcons.plus,
                kind: CruButtonKind.primary,
                onPressed: () {
                  final templates = templatesAsync.value
                          ?.map(FormTemplate.fromRecord)
                          .toList() ??
                      [];
                  if (templates.isEmpty) {
                    recToast(context, 'No templates created yet. Create a form template first.');
                    return;
                  }

                  showDialog<void>(
                    context: context,
                    builder: (ctx) => CruFormDialog(
                      title: 'Select form template',
                      subtitle: patient.fullName,
                      width: 480,
                      submitLabel: 'Cancel',
                      onSubmit: () => Navigator.of(ctx).pop(),
                      body: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final t in templates)
                            DentalListRow(
                              semanticLabel: t.name,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => FormFillDialog(
                                    patient: patient,
                                    template: t,
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  const CruIconTile(icon: CruIcons.box, tone: CruTileTone.neutral),
                                  const SizedBox(width: CruSpace.s12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.name, style: CruType.callout.w600.tint(c.label)),
                                        Text('${t.fields.length} questions', style: CruType.caption.tint(c.label2)),
                                      ],
                                    ),
                                  ),
                                  CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),

          responsesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(CruSpace.s24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Error loading forms: $e'),
            data: (records) {
              if (records.isEmpty) {
                return DentalEmptyState(
                  icon: CruIcons.box,
                  title: 'No forms filled for this patient',
                  body: 'Complete custom clinical intake, symptoms, or screening forms.',
                  actions: [
                    CruButton(
                      label: 'Fill a form',
                      icon: CruIcons.plus,
                      onPressed: () {
                        final templates = templatesAsync.value
                                ?.map(FormTemplate.fromRecord)
                                .toList() ??
                            [];
                        if (templates.isEmpty) {
                          recToast(context, 'No templates created yet. Create a form template first.');
                          return;
                        }
                        showDialog<void>(
                          context: context,
                          builder: (_) => FormFillDialog(
                            patient: patient,
                            template: templates.first,
                          ),
                        );
                      },
                    ),
                  ],
                );
              }

              final responses = records.map(FormResponse.fromRecord).toList()
                ..sort((a, b) => b.answeredAt.compareTo(a.answeredAt));
              final templates = templatesAsync.value?.map(FormTemplate.fromRecord).toList() ?? [];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in responses) ...[
                    DentalListRow(
                      semanticLabel: r.templateName,
                      onTap: () {
                        final tmpl = templates.where((t) => t.id == r.templateId).firstOrNull ??
                            FormTemplate(
                              id: r.templateId,
                              name: r.templateName,
                              fields: [
                                for (final k in r.answers.keys)
                                  FormFieldSpec(
                                    id: k,
                                    label: k,
                                    type: FormFieldType.text,
                                  ),
                              ],
                            );
                        showDialog<void>(
                          context: context,
                          builder: (_) => FormFillDialog(
                            patient: patient,
                            template: tmpl,
                            initialResponse: r,
                            readOnly: true,
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          const CruIconTile(icon: CruIcons.box, tone: CruTileTone.accent),
                          const SizedBox(width: CruSpace.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.templateName, style: CruType.callout.w600.tint(c.label)),
                                Text(
                                  'Submitted ${DentalFormat.date(r.answeredAt)} · ${r.answers.length} answers recorded',
                                  style: CruType.caption.tint(c.label2),
                                ),
                              ],
                            ),
                          ),
                          CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
                        ],
                      ),
                    ),
                    const SizedBox(height: CruSpace.s4),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

