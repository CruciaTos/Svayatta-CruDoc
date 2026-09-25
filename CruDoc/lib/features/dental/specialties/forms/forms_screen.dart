import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/form_builder.dart';
import 'package:doctor_management_app/features/dental/specialties/forms/form_fill.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Screen displayed for Tab 22 (Oral Medicine / Clinic Forms).
class FormsScreen extends ConsumerStatefulWidget {
  const FormsScreen({super.key});

  @override
  ConsumerState<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends ConsumerState<FormsScreen> {
  final _searchCtrl = TextEditingController();

  Future<void> _createStarterTemplate({
    required String name,
    required String description,
    required List<FormFieldSpec> fields,
  }) async {
    final now = DateTime.now();
    final rec = DentalRecord.create(
      '',
      RecKind.formTemplate,
      {
        'name': name,
        'description': description,
        'fields': fields.map((f) => f.toJson()).toList(),
      },
      at: now,
    );
    await saveDentalRecord(ref, rec);
    if (mounted) {
      recToast(context, 'Template "$name" created');
    }
  }

  void _loadStarterBurningMouth() {
    _createStarterTemplate(
      name: 'Burning Mouth Syndrome Intake',
      description: 'Standard clinical history for oral burning sensation, dysgeusia, and mucosal symptoms.',
      fields: [
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Primary anatomical site of burning sensation',
          type: FormFieldType.multiChoice,
          options: ['Anterior two-thirds of tongue', 'Hard palate', 'Lower lip', 'Buccal mucosa', 'Gingiva'],
          required: true,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Severity of discomfort (0 = none, 10 = worst imaginable)',
          type: FormFieldType.scale10,
          required: true,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Associated taste changes (dysgeusia, metallic, bitter)',
          type: FormFieldType.yesNo,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Associated subjective dry mouth (xerostomia)',
          type: FormFieldType.yesNo,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Diurnal pattern (increases through day, constant, wakes from sleep)',
          type: FormFieldType.choice,
          options: ['Worsens progressively during day', 'Constant from waking', 'Intermittent', 'Wakes from sleep'],
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Exacerbating or relieving factors (spicy foods, eating, gum)',
          type: FormFieldType.longText,
        ),
      ],
    );
  }

  void _loadStarterXerostomia() {
    _createStarterTemplate(
      name: 'Xerostomia (Dry Mouth) Inventory',
      description: 'Assessment of salivary hypofunction and impact on swallowing and speech.',
      fields: [
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Does your mouth feel dry when eating a meal?',
          type: FormFieldType.choice,
          options: ['Never', 'Occasionally', 'Frequently', 'Always'],
          required: true,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Do you need to sip liquids to aid swallowing dry food?',
          type: FormFieldType.yesNo,
          required: true,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Do you get up at night to drink water?',
          type: FormFieldType.yesNo,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Dryness severity rating (0 = normal, 10 = completely dry)',
          type: FormFieldType.scale10,
          required: true,
        ),
        FormFieldSpec(
          id: const Uuid().v4(),
          label: 'Current medications (antihistamines, antihypertensives, psychotropics)',
          type: FormFieldType.longText,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recordsAsync = ref.watch(clinicRecordsProvider(RecKind.formTemplate));

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          DentalPageHeader(
            title: 'Clinical Forms & Questionnaires',
            subtitle: 'Design custom intake questionnaires, symptom logs, and patient forms',
            actions: [
              CruButton(
                label: 'New form template',
                icon: CruIcons.plus,
                kind: CruButtonKind.primary,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FormBuilderDialog(),
                ),
              ),
            ],
          ),

          Expanded(
            child: recordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (records) {
                final templates = records.map(FormTemplate.fromRecord).toList()
                  ..sort((a, b) => a.name.compareTo(b.name));

                final query = _searchCtrl.text.trim().toLowerCase();
                final filtered = templates.where((t) {
                  return t.name.toLowerCase().contains(query) ||
                      t.description.toLowerCase().contains(query);
                }).toList();

                if (templates.isEmpty) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Padding(
                        padding: const EdgeInsets.all(CruSpace.s24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DentalEmptyState(
                              icon: CruIcons.box,
                              title: 'No custom forms designed yet',
                              body: 'Design specialized symptom questionnaires, medical intake, or oral medicine screening forms for your clinic.',
                              actions: [
                                CruButton(
                                  label: 'Create first form',
                                  icon: CruIcons.plus,
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => const FormBuilderDialog(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: CruSpace.s24),

                            // Starter presets
                            Container(
                              padding: const EdgeInsets.all(CruSpace.s16),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(CruRadius.control),
                                border: Border.all(color: c.hairline),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CruIcon(CruIcons.sparkle, size: 16, color: c.accent),
                                      const SizedBox(width: CruSpace.s8),
                                      Text('OR START WITH A CLINICAL TEMPLATE',
                                          style: CruType.micro.w600.tint(c.accent)),
                                    ],
                                  ),
                                  const SizedBox(height: CruSpace.s12),
                                  _presetRow(
                                    title: 'Burning Mouth Syndrome Intake',
                                    desc: '6 questions on site, severity, dysgeusia, xerostomia and diurnal pattern.',
                                    onUse: _loadStarterBurningMouth,
                                    c: c,
                                  ),
                                  const CruSeparator(),
                                  _presetRow(
                                    title: 'Xerostomia (Dry Mouth) Inventory',
                                    desc: '5 questions assessing salivary hypofunction, swallowing, and nocturnal dryness.',
                                    onUse: _loadStarterXerostomia,
                                    c: c,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(CruSpace.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search & count bar
                      Row(
                        children: [
                          Text(
                            '${filtered.length} ${filtered.length == 1 ? 'Template' : 'Templates'}',
                            style: CruType.callout.w600.tint(c.label),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 280,
                            child: DentalSearchField(
                              hint: 'Search form templates...',
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: CruSpace.s16),

                      // Templates list
                      CruCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < filtered.length; i++) ...[
                              if (i > 0) const CruSeparator(),
                              _TemplateRow(
                                template: filtered[i],
                                onEdit: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => FormBuilderDialog(
                                    initialTemplate: filtered[i],
                                  ),
                                ),
                                onDelete: () async {
                                  final ok = await confirmDental(
                                    context,
                                    title: 'Delete template?',
                                    body: 'Delete "${filtered[i].name}"? Existing patient responses will remain saved in their charts.',
                                    action: 'Delete',
                                  );
                                  if (ok && filtered[i].record != null) {
                                    await deleteDentalRecord(ref, filtered[i].record!);
                                    if (context.mounted) {
                                      recToast(context, 'Template deleted');
                                    }
                                  }
                                },
                                onFill: () async {
                                  final patient = await pickRadPatient(context);
                                  if (patient != null && context.mounted) {
                                    showDialog<void>(
                                      context: context,
                                      builder: (_) => FormFillDialog(
                                        patient: patient,
                                        template: filtered[i],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetRow({
    required String title,
    required String desc,
    required VoidCallback onUse,
    required CruColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.callout.w600.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(desc, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          CruCapsuleButton(
            label: 'Use template',
            icon: CruIcons.plus,
            onPressed: onUse,
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.onEdit,
    required this.onDelete,
    required this.onFill,
  });

  final FormTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = template;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16, vertical: CruSpace.s12),
      child: Row(
        children: [
          const CruIconTile(icon: CruIcons.box, tone: CruTileTone.accent),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(t.name, style: CruType.callout.w600.tint(c.label)),
                    const SizedBox(width: CruSpace.s8),
                    CruPill(
                      text: '${t.fields.length} questions',
                      background: c.inset,
                      foreground: c.label2,
                    ),
                  ],
                ),
                if (t.description.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    t.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tint(c.label2),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: 'Fill for patient',
            icon: CruIcons.pen,
            onPressed: onFill,
          ),
          const SizedBox(width: CruSpace.s8),
          CruIconButton(
            icon: CruIcons.pen,
            size: CruSize.squareButton,
            semanticLabel: 'Edit template',
            tooltip: 'Edit template',
            onPressed: onEdit,
          ),
          CruIconButton(
            icon: CruIcons.close,
            size: CruSize.squareButton,
            semanticLabel: 'Delete template',
            tooltip: 'Delete template',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
