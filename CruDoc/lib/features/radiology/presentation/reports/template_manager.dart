import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_seed.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Report templates: the headings and normal wording a report starts from,
/// by study type. Built-in ones can be edited (and restored), duplicated,
/// not deleted; the doctor's own can be deleted.
Future<void> showRadTemplateManager(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TemplateManager());

/// The shipped version of a built-in template, to tell whether it was
/// edited.
RadTemplate? _original(String id) {
  for (final t in RadSeed.templates()) {
    if (t.id == id) return t;
  }
  return null;
}

bool _edited(RadTemplate t) {
  if (!t.builtIn) return false;
  final o = _original(t.id);
  return o != null && jsonEncode(o.toJson()) != jsonEncode(t.toJson());
}

enum _TplAction { edit, duplicate, restore, delete }

class _TemplateManager extends ConsumerWidget {
  const _TemplateManager();

  Future<void> _act(BuildContext context, WidgetRef ref, RadTemplate t, _TplAction a) async {
    final rad = ref.read(radiologyProvider);
    switch (a) {
      case _TplAction.edit:
        await _showTemplateEditor(context, existing: t);
      case _TplAction.duplicate:
        await _showTemplateEditor(
          context,
          existing: RadTemplate(
            id: radId('tpl_'),
            name: '${t.name} (copy)',
            modality: t.modality,
            technique: t.technique,
            sections: t.sections,
            impression: t.impression,
          ),
          isNew: true,
        );
      case _TplAction.restore:
        final ok = await confirmDental(
          context,
          title: 'Restore the original wording?',
          body: 'Your changes to "${t.name}" are replaced with the wording CruDoc ships.',
          action: 'Restore',
        );
        if (ok) await rad.deleteTemplate(t);
      case _TplAction.delete:
        final ok = await confirmDental(
          context,
          title: 'Delete this template?',
          body: '"${t.name}" is removed. Reports already written with it stay as they are.',
          action: 'Delete',
        );
        if (ok) await rad.deleteTemplate(t);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final templates = ref.watch(radTemplatesProvider).value ?? const <RadTemplate>[];
    final byType = <RadModality, List<RadTemplate>>{};
    for (final t in templates) {
      (byType[t.modality] ??= []).add(t);
    }
    return DentalPanelDialog(
      title: 'Report templates',
      subtitle: 'The headings and normal wording each report starts from',
      leading: const CruIconTile(icon: RadIcons.template, tone: CruTileTone.accent),
      body: templates.isEmpty
          ? const DentalEmptyState(
              icon: RadIcons.template,
              title: 'No templates',
              body: 'Make one for each kind of study you read.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in RadModality.values)
                  if (byType[m] != null) ...[
                    DentalGroupLabel(m.label, trailing: '${byType[m]!.length}'),
                    for (var i = 0; i < byType[m]!.length; i++) ...[
                      if (i > 0) const CruSeparator(indent: CruSpace.s12),
                      _TemplateRow(
                        template: byType[m]![i],
                        onTap: () => _act(context, ref, byType[m]![i], _TplAction.edit),
                        onAction: (a) => _act(context, ref, byType[m]![i], a),
                      ),
                    ],
                  ],
                const SizedBox(height: CruSpace.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                  child: Text(
                    'A new report uses the first template of its study type. Pick another '
                    'from the report itself.',
                    style: CruType.caption.tint(c.label3),
                  ),
                ),
              ],
            ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CruButton(
            label: 'New template',
            icon: CruIcons.plus,
            onPressed: () => _showTemplateEditor(
              context,
              existing: RadTemplate(
                id: radId('tpl_'),
                name: '',
                modality: RadModality.cbct,
                sections: const [RadReportSection(title: 'Findings')],
              ),
              isNew: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onTap, required this.onAction});

  final RadTemplate template;
  final VoidCallback onTap;
  final ValueChanged<_TplAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = template;
    final edited = _edited(t);
    final headings = t.sections.map((s) => s.title).where((s) => s.isNotEmpty).join(', ');
    return DentalListRow(
      semanticLabel: t.name,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name.isEmpty ? 'Untitled template' : t.name,
                  style: CruType.callout.tint(c.label),
                ),
                Text(
                  headings.isEmpty ? 'No sections' : headings,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          if (t.builtIn)
            CruPill(
              text: edited ? 'Built-in, edited' : 'Built-in',
              background: c.inset,
              foreground: c.label2,
            ),
          const SizedBox(width: CruSpace.s4),
          PopupMenuButton<_TplAction>(
            tooltip: 'More',
            onSelected: onAction,
            color: c.surface,
            shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
            itemBuilder: (_) => [
              radMenuItem(c, _TplAction.edit, 'Edit'),
              radMenuItem(c, _TplAction.duplicate, 'Duplicate'),
              if (edited) radMenuItem(c, _TplAction.restore, 'Restore original wording'),
              if (!t.builtIn) radMenuItem(c, _TplAction.delete, 'Delete'),
            ],
            child: SizedBox(
              width: CruSize.squareButton,
              height: CruSize.squareButton,
              child: Center(child: CruIcon(CruIcons.more, size: 18, color: c.label2)),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Editor ─────────────────────────────

Future<void> _showTemplateEditor(
  BuildContext context, {
  required RadTemplate existing,
  bool isNew = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _TemplateEditor(template: existing, isNew: isNew),
    );

/// One heading of the template being edited.
class _SectionDraft {
  _SectionDraft(RadReportSection s)
      : title = TextEditingController(text: s.title),
        body = TextEditingController(text: s.body);

  final Key key = UniqueKey();
  final TextEditingController title;
  final TextEditingController body;

  void dispose() {
    title.dispose();
    body.dispose();
  }
}

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({required this.template, required this.isNew});

  final RadTemplate template;
  final bool isNew;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.template.name);
  late final _technique = TextEditingController(text: widget.template.technique);
  late final _impression = TextEditingController(text: widget.template.impression);
  late RadModality _modality = widget.template.modality;
  late final List<_SectionDraft> _sections = [
    for (final s in widget.template.sections) _SectionDraft(s),
  ];
  bool _dirty = false;
  bool _busy = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _dirty = widget.isNew && widget.template.name.isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _technique.dispose();
    _impression.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _move(int from, int to) {
    setState(() {
      final s = _sections.removeAt(from);
      _sections.insert(to, s);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final t = widget.template.copyWith(
        name: _name.text.trim(),
        modality: _modality,
        technique: _technique.text.trim(),
        impression: _impression.text.trim(),
        sections: [
          for (final s in _sections)
            if (s.title.text.trim().isNotEmpty)
              RadReportSection(title: s.title.text.trim(), body: s.body.text.trim()),
        ],
      );
      await ref.read(radiologyProvider).saveTemplate(t);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() {
        _busy = false;
        _notice = "Couldn't save the template. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruFormDialog(
      title: widget.isNew ? 'New template' : 'Edit template',
      subtitle: widget.template.builtIn
          ? 'Built-in: your changes are kept, and the original can be restored'
          : null,
      leading: const CruIconTile(icon: RadIcons.template, tone: CruTileTone.accent),
      submitLabel: widget.isNew ? 'Add template' : 'Save template',
      onSubmit: _save,
      busy: _busy,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Template',
              description: 'A new report of this study type starts from it.',
              children: [
                CruTextField(
                  label: 'Name',
                  controller: _name,
                  hint: 'CBCT — implant site assessment',
                  autofocus: widget.isNew,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Name the template.' : null,
                  onChanged: (_) => _edited(),
                ),
                CruFieldFrame(
                  label: 'Study type',
                  child: DentalChipWrap<RadModality>(
                    options: RadModality.values,
                    label: (m) => m.short,
                    isSelected: (m) => m == _modality,
                    onTap: (m) {
                      setState(() => _modality = m);
                      _edited();
                    },
                  ),
                ),
                CruTextField(
                  label: 'Technique',
                  controller: _technique,
                  optional: true,
                  maxLines: 3,
                  hint: 'How the scan was taken: field of view, voxel size, reconstructions',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
              ],
            ),
            CruFormSection(
              title: 'Sections',
              description: 'One heading each, with the wording for a normal finding. '
                  'The doctor edits it in the report.',
              children: [
                for (var i = 0; i < _sections.length; i++)
                  Container(
                    key: _sections[i].key,
                    padding: const EdgeInsets.all(CruSpace.s12),
                    decoration: ShapeDecoration(
                      shape: cruShape(CruRadius.control, side: BorderSide(color: c.separator)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CruTextField(
                          label: 'Heading ${i + 1}',
                          controller: _sections[i].title,
                          hint: 'Maxillary sinuses',
                          textCapitalization: TextCapitalization.sentences,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CruIconButton(
                                icon: CruIcons.arrowUp,
                                size: CruSize.rowCapsule,
                                iconSize: 15,
                                semanticLabel: 'Move up',
                                tooltip: 'Move up',
                                onPressed: i == 0 ? null : () => _move(i, i - 1),
                              ),
                              CruIconButton(
                                icon: CruIcons.arrowDown,
                                size: CruSize.rowCapsule,
                                iconSize: 15,
                                semanticLabel: 'Move down',
                                tooltip: 'Move down',
                                onPressed:
                                    i == _sections.length - 1 ? null : () => _move(i, i + 1),
                              ),
                              CruIconButton(
                                icon: CruIcons.close,
                                size: CruSize.rowCapsule,
                                iconSize: 15,
                                semanticLabel: 'Remove section',
                                tooltip: 'Remove section',
                                onPressed: () => setState(() {
                                  _sections.removeAt(i).dispose();
                                  _dirty = true;
                                }),
                              ),
                            ],
                          ),
                          onChanged: (_) => _edited(),
                        ),
                        const SizedBox(height: CruSpace.s10),
                        CruTextField(
                          label: 'Normal wording',
                          controller: _sections[i].body,
                          optional: true,
                          maxLines: 3,
                          hint: 'Both maxillary sinuses are clear.',
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => _edited(),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruCapsuleButton(
                    label: 'Add section',
                    icon: CruIcons.plus,
                    onPressed: () => setState(() {
                      _sections.add(_SectionDraft(const RadReportSection(title: '')));
                      _dirty = true;
                    }),
                  ),
                ),
              ],
            ),
            CruFormSection(
              title: 'Impression',
              description: 'The summary a normal study gets.',
              children: [
                CruTextField(
                  label: 'Impression',
                  controller: _impression,
                  optional: true,
                  maxLines: 3,
                  hint: 'No significant abnormality detected.',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _edited(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
