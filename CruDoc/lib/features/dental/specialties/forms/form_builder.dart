import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Supported custom form field types.
enum FormFieldType {
  text('Short Text', 'Single line response'),
  longText('Long Text', 'Multi-line notes or history'),
  number('Number', 'Numeric value with optional unit'),
  choice('Single Choice', 'Pick one option'),
  multiChoice('Multi Choice', 'Select multiple options'),
  yesNo('Yes / No', 'Binary confirmation'),
  date('Date', 'Calendar date entry'),
  scale10('Scale 0–10', 'Severity / pain rating');

  final String label;
  final String desc;
  const FormFieldType(this.label, this.desc);

  static FormFieldType fromString(String val) {
    return FormFieldType.values.firstWhere(
      (t) => t.name == val,
      orElse: () => FormFieldType.text,
    );
  }
}

/// Specification of a single field inside a form template.
class FormFieldSpec {
  final String id;
  String label;
  FormFieldType type;
  List<String> options;
  bool required;
  String unit;

  FormFieldSpec({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.required = false,
    this.unit = '',
  });

  factory FormFieldSpec.fromJson(Map<String, dynamic> json) {
    return FormFieldSpec(
      id: json['id'] as String? ?? const Uuid().v4(),
      label: json['label'] as String? ?? 'Untitled question',
      type: FormFieldType.fromString(json['type'] as String? ?? 'text'),
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      required: json['required'] as bool? ?? false,
      unit: json['unit'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'options': options,
        'required': required,
        'unit': unit,
      };

  FormFieldSpec copyWith({
    String? label,
    FormFieldType? type,
    List<String>? options,
    bool? required,
    String? unit,
  }) {
    return FormFieldSpec(
      id: id,
      label: label ?? this.label,
      type: type ?? this.type,
      options: options ?? List.from(this.options),
      required: required ?? this.required,
      unit: unit ?? this.unit,
    );
  }
}

/// Clinic form template model.
class FormTemplate {
  final String id;
  final String name;
  final String description;
  final List<FormFieldSpec> fields;
  final DentalRecord? record;

  const FormTemplate({
    required this.id,
    required this.name,
    this.description = '',
    required this.fields,
    this.record,
  });

  factory FormTemplate.fromRecord(DentalRecord r) {
    final d = r.data;
    final rawFields = (d['fields'] as List?) ?? [];
    return FormTemplate(
      id: r.id,
      name: d['name'] as String? ?? 'Custom form',
      description: d['description'] as String? ?? '',
      fields: rawFields
          .whereType<Map>()
          .map((f) => FormFieldSpec.fromJson(Map<String, dynamic>.from(f)))
          .toList(),
      record: r,
    );
  }
}

/// Dialog for designing custom questionnaires and clinical form templates.
class FormBuilderDialog extends ConsumerStatefulWidget {
  const FormBuilderDialog({
    super.key,
    this.initialTemplate,
  });

  final FormTemplate? initialTemplate;

  @override
  ConsumerState<FormBuilderDialog> createState() => _FormBuilderDialogState();
}

class _FormBuilderDialogState extends ConsumerState<FormBuilderDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late List<FormFieldSpec> _fields;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTemplate;
    if (t != null) {
      _nameCtrl.text = t.name;
      _descCtrl.text = t.description;
      _fields = t.fields.map((f) => f.copyWith()).toList();
    } else {
      _nameCtrl.text = 'New Clinical Form';
      _fields = [
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Primary Symptom / Complaint',
          type: FormFieldType.text,
          required: true,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _addField() {
    setState(() {
      _fields.add(
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Question ${_fields.length + 1}',
          type: FormFieldType.text,
        ),
      );
    });
  }

  void _removeField(int index) {
    setState(() => _fields.removeAt(index));
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final f = _fields.removeAt(index);
      _fields.insert(index - 1, f);
    });
  }

  void _moveDown(int index) {
    if (index >= _fields.length - 1) return;
    setState(() {
      final f = _fields.removeAt(index);
      _fields.insert(index + 1, f);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      recToast(context, 'Please enter a form name');
      return;
    }
    if (_fields.isEmpty) {
      recToast(context, 'Add at least one question to the form');
      return;
    }

    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final data = {
        'name': name,
        'description': _descCtrl.text.trim(),
        'fields': _fields.map((f) => f.toJson()).toList(),
      };

      final t = widget.initialTemplate;
      if (t == null || t.record == null) {
        final rec = DentalRecord.create(
          '',
          RecKind.formTemplate,
          data,
          at: now,
        );
        await saveDentalRecord(ref, rec);
        if (mounted) recToast(context, 'Form template created');
      } else {
        final updated = t.record!.copyWith(data: data);
        await saveDentalRecord(ref, updated);
        if (mounted) recToast(context, 'Form template updated');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) recToast(context, 'Error saving form: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    return CruFormDialog(
      title: widget.initialTemplate == null ? 'Create Form Template' : 'Edit Form Template',
      subtitle: 'Design custom clinical questionnaire with live preview',
      width: 980,
      busy: _busy,
      submitLabel: widget.initialTemplate == null ? 'Save template' : 'Save changes',
      onSubmit: _save,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Builder Editor
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CruTextField(
                  label: 'Form name',
                  controller: _nameCtrl,
                  hint: 'e.g. Burning Mouth Symptom Questionnaire',
                ),
                const SizedBox(height: CruSpace.s12),

                CruTextField(
                  label: 'Description / Instructions (optional)',
                  controller: _descCtrl,
                  hint: 'Patient-facing or clinician instructions',
                ),
                const SizedBox(height: CruSpace.s16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Questions (${_fields.length})', style: CruType.callout.w600.tint(c.label)),
                    CruCapsuleButton(
                      label: 'Add question',
                      icon: CruIcons.plus,
                      onPressed: _addField,
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s10),

                for (var i = 0; i < _fields.length; i++)
                  _FieldEditorCard(
                    index: i,
                    spec: _fields[i],
                    total: _fields.length,
                    onMoveUp: () => _moveUp(i),
                    onMoveDown: () => _moveDown(i),
                    onDelete: () => _removeField(i),
                    onChanged: () => setState(() {}),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s20),

          // Right: Live Preview
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(CruSpace.s16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CruRadius.control),
                border: Border.all(color: c.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CruIcon(CruIcons.box, size: 16, color: c.accent),
                      const SizedBox(width: CruSpace.s8),
                      Text('LIVE PREVIEW', style: CruType.micro.w600.tint(c.accent)),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s8),
                  Text(
                    _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Form Title',
                    style: CruType.title2.tint(c.label),
                  ),
                  if (_descCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s4),
                    Text(_descCtrl.text, style: CruType.caption.tint(c.label2)),
                  ],
                  const SizedBox(height: CruSpace.s12),
                  const CruSeparator(),
                  const SizedBox(height: CruSpace.s12),

                  if (_fields.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CruSpace.s24),
                        child: Text(
                          'Add questions on the left to preview form layout.',
                          style: CruType.caption.tint(c.label3),
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < _fields.length; i++)
                      _FieldPreviewItem(index: i, spec: _fields[i]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldEditorCard extends StatelessWidget {
  const _FieldEditorCard({
    required this.index,
    required this.spec,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onChanged,
  });

  final int index;
  final FormFieldSpec spec;
  final int total;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s10),
      child: Container(
        padding: const EdgeInsets.all(CruSpace.s12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Question header & reorder
            Row(
              children: [
                Text('Q${index + 1}', style: CruType.caption.w600.tint(c.accent)),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: TextFormField(
                    initialValue: spec.label,
                    style: CruType.callout.w600.tint(c.label),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Enter question label...',
                    ),
                    onChanged: (val) {
                      spec.label = val;
                      onChanged();
                    },
                  ),
                ),
                CruIconButton(
                  icon: CruIcons.arrowUp,
                  size: CruSize.squareButton,
                  semanticLabel: 'Move up',
                  onPressed: index > 0 ? onMoveUp : null,
                ),
                CruIconButton(
                  icon: CruIcons.arrowDown,
                  size: CruSize.squareButton,
                  semanticLabel: 'Move down',
                  onPressed: index < total - 1 ? onMoveDown : null,
                ),
                CruIconButton(
                  icon: CruIcons.close,
                  size: CruSize.squareButton,
                  semanticLabel: 'Delete question',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),

            // Type selector chips
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                for (final t in FormFieldType.values)
                  DentalChoiceChip(
                    label: t.label,
                    selected: spec.type == t,
                    onTap: () {
                      spec.type = t;
                      if ((t == FormFieldType.choice || t == FormFieldType.multiChoice) &&
                          spec.options.isEmpty) {
                        spec.options = ['Option 1', 'Option 2'];
                      }
                      onChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),

            // Options editor if choice or multiChoice
            if (spec.type == FormFieldType.choice || spec.type == FormFieldType.multiChoice) ...[
              TextFormField(
                initialValue: spec.options.join(', '),
                style: CruType.caption.tint(c.label),
                decoration: const InputDecoration(
                  labelText: 'Options (comma-separated)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  spec.options = val
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  onChanged();
                },
              ),
              const SizedBox(height: CruSpace.s8),
            ],

            // Unit input if number
            if (spec.type == FormFieldType.number) ...[
              TextFormField(
                initialValue: spec.unit,
                style: CruType.caption.tint(c.label),
                decoration: const InputDecoration(
                  labelText: 'Unit suffix (e.g. mm, days, kg)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  spec.unit = val.trim();
                  onChanged();
                },
              ),
              const SizedBox(height: CruSpace.s8),
            ],

            // Required toggle
            Row(
              children: [
                Switch(
                  value: spec.required,
                  activeThumbColor: c.accent,
                  onChanged: (val) {
                    spec.required = val;
                    onChanged();
                  },
                ),
                const SizedBox(width: CruSpace.s4),
                Text('Required answer', style: CruType.caption.tint(c.label2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldPreviewItem extends StatelessWidget {
  const _FieldPreviewItem({
    required this.index,
    required this.spec,
  });

  final int index;
  final FormFieldSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s12),
      child: Column(
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
          const SizedBox(height: CruSpace.s4),

          // Render sample widget
          switch (spec.type) {
            FormFieldType.text => Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                alignment: Alignment.centerLeft,
                child: Text('Short answer text...', style: CruType.caption.tint(c.label3)),
              ),
            FormFieldType.longText => Container(
                height: 64,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Text('Detailed notes...', style: CruType.caption.tint(c.label3)),
              ),
            FormFieldType.number => Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  spec.unit.isNotEmpty ? '0.0 ${spec.unit}' : '0.0',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ),
            FormFieldType.choice || FormFieldType.multiChoice => Wrap(
                spacing: CruSpace.s6,
                runSpacing: CruSpace.s6,
                children: [
                  for (final opt in (spec.options.isNotEmpty ? spec.options : ['Option 1', 'Option 2']))
                    CruPill(text: opt, background: c.inset, foreground: c.label2),
                ],
              ),
            FormFieldType.yesNo => Row(
                children: [
                  CruPill(text: 'Yes', background: c.inset, foreground: c.label2),
                  const SizedBox(width: CruSpace.s8),
                  CruPill(text: 'No', background: c.inset, foreground: c.label2),
                ],
              ),
            FormFieldType.date => Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(CruIcons.calendar, size: 16, color: c.label3),
                    const SizedBox(width: CruSpace.s6),
                    Text('Select date', style: CruType.caption.tint(c.label3)),
                  ],
                ),
              ),
            FormFieldType.scale10 => Row(
                children: [
                  for (var s = 0; s <= 10; s++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c.inset,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text('$s', style: CruType.micro.tabular.tint(c.label2)),
                      ),
                    ),
                ],
              ),
          },
        ],
      ),
    );
  }
}
