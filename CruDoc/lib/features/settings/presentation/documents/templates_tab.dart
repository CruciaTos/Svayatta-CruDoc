import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_screen.dart';
import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/render/doc_renderer.dart';
import 'package:doctor_management_app/core/pdf/render/doc_samples.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/documents_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Templates: which one each kind of document uses by default, then every
/// template with a preview, Customize/Edit and a ⋯ menu.
class TemplatesTab extends ConsumerStatefulWidget {
  const TemplatesTab({super.key});

  @override
  ConsumerState<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<TemplatesTab> {
  /// Rendered first pages, by template id and version.
  static final Map<String, _Thumb> _thumbCache = {};

  /// Which defaults are showing when the doctor can set both.
  bool _clinicDefaults = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openNewTemplateDialog(bool canEditClinic) async {
    final presets = builtinTemplates
        .where((t) => t.id != 'builtin.receipt80')
        .toList();
    final created = await showDialog<DocTemplate>(
      context: context,
      builder: (_) =>
          _NewTemplateDialog(presets: presets, canEditClinic: canEditClinic),
    );

    if (created != null && mounted) {
      final saved = await TemplateEditorScreen.open(context, template: created);
      if (saved == true && mounted) {
        _toast('Template "${created.name}" saved');
      }
    }
  }

  Future<void> _renameTemplate(DocTemplate t) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: t.name),
    );

    if (newName != null && newName.isNotEmpty && newName != t.name) {
      try {
        await DocRepository.instance.saveTemplate(
          t.copyWith(name: newName),
          loadedUpdatedAt: t.updatedAt,
        );
        _toast('Template renamed to $newName');
      } catch (e) {
        _toast('Failed to rename: $e');
      }
    }
  }

  Future<void> _duplicateTemplate(DocTemplate t) async {
    try {
      final access = ClinicSession.instance.access;
      final canEditClinic =
          access == null || access.can(ClinicPermission.settings);
      final me = DocRepository.instance.tenantOrNull;

      final copy = t.copyWith(
        id: '',
        name: '${t.name} (copy)',
        scope: canEditClinic ? DocScope.clinic : DocScope.doctor,
        ownerUid: me,
      );

      await DocRepository.instance.saveTemplate(copy, loadedUpdatedAt: 0);
      _toast('Duplicated "${t.name}"');
    } catch (e) {
      _toast('Failed to duplicate: $e');
    }
  }

  Future<void> _deleteTemplate(DocTemplate t) async {
    final s = await DocRepository.instance.clinicSettingsOnce();
    final clearedClinicKinds = [
      for (final k in DocKind.values)
        if (s.defaults[k.name] == t.id) k.label,
    ];

    if (!mounted) return;
    final body = clearedClinicKinds.isEmpty
        ? 'This can\'t be undone.'
        : 'It is the clinic default for ${clearedClinicKinds.join(', ')}. '
              'Those go back to Classic. This can\'t be undone.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete "${t.name}"?',
        leading: const CruIconTile(
          icon: DocIcons.trash,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        width: CruSize.dialog + CruSpace.s32 * 2,
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(body, style: CruType.text.tint(ctx.cru.label2)),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await DocRepository.instance.deleteTemplate(t);
        _toast('Template deleted');
      } catch (e) {
        _toast('Failed to delete: $e');
      }
    }
  }

  Future<void> _edit(DocTemplate t) async {
    final saved = await TemplateEditorScreen.open(context, template: t);
    if (saved == true && mounted) _toast('Template saved');
  }

  void _preview(DocTemplate t) {
    MedicalPdfPreviewScreen.open(
      context,
      documentData: docSampleData(
        t.kinds.firstOrNull ?? DocKind.invoice,
        templateId: t.id,
      ),
    );
  }

  List<DocMenuItem> _menuFor(DocTemplate t) => [
    if (!t.isBuiltin) DocMenuItem('Rename', () => _renameTemplate(t)),
    DocMenuItem('Duplicate', () => _duplicateTemplate(t)),
    if (!t.isBuiltin) DocMenuItem('Delete', () => _deleteTemplate(t)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = cruIsPhone(context);
    final access = ref.watch(clinicAccessProvider).value;
    final canEditClinic =
        access == null || access.can(ClinicPermission.settings);
    final isDoctor = access == null || access.kind == MemberKind.doctor;

    final templates = ref.watch(docTemplatesProvider).value ?? builtinTemplates;
    final settings =
        ref.watch(clinicDocSettingsProvider).value ?? const ClinicDocSettings();
    final doctorProfile = ref.watch(myDocProfileProvider).value;

    _TemplateItem item(DocTemplate t) => _TemplateItem(
      template: t,
      clinic: settings,
      doctor: doctorProfile,
      cache: _thumbCache,
      menu: _menuFor(t),
      onPreview: () => _preview(t),
      onEdit: () => _edit(t),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDoctor || canEditClinic) ...[
          _defaultsCard(
            templates: templates,
            settings: settings,
            doctorProfile: doctorProfile,
            isDoctor: isDoctor,
            canEditClinic: canEditClinic,
          ),
          const SizedBox(height: CruSpace.cardGap + CruSpace.s8),
        ],

        // Every template
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'All templates',
                      style: CruType.headline.tint(c.label),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    templates.length == 1
                        ? '1 template'
                        : '${templates.length} templates',
                    style: CruType.subhead.tabular.tint(c.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: 'New template',
              icon: CruIcons.plus,
              onPressed: () => _openNewTemplateDialog(canEditClinic),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s16),

        if (phone)
          CruCard(
            semanticLabel: 'All templates',
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < templates.length; i++) ...[
                  if (i > 0)
                    const CruSeparator(
                      indent: _TemplateRow.thumbWidth + CruSpace.s12,
                    ),
                  _TemplateRow(item: item(templates[i])),
                ],
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth >= 860 ? 3 : 2,
                mainAxisSpacing: CruSpace.cardGap,
                crossAxisSpacing: CruSpace.cardGap,
                mainAxisExtent: _TemplateCard.height,
              ),
              itemCount: templates.length,
              itemBuilder: (context, i) =>
                  _TemplateCard(item: item(templates[i])),
            ),
          ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }

  Widget _defaultsCard({
    required List<DocTemplate> templates,
    required ClinicDocSettings settings,
    required DoctorDocProfile? doctorProfile,
    required bool isDoctor,
    required bool canEditClinic,
  }) {
    final both = isDoctor && canEditClinic;
    final forClinic = both ? _clinicDefaults : !isDoctor;

    return CruCard(
      semanticLabel: 'Default templates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DocCardHeader(
            title: 'Default templates',
            description: forClinic
                ? 'Picked for everyone in the clinic who hasn\'t chosen '
                      'their own.'
                : 'Picked automatically when you create a document.',
            trailing: both
                ? CruSegmentedControl<bool>(
                    semanticLabel: 'Whose defaults',
                    segments: const [
                      CruSegment(false, 'Mine'),
                      CruSegment(true, 'Clinic'),
                    ],
                    selected: _clinicDefaults,
                    onChanged: (v) => setState(() => _clinicDefaults = v),
                  )
                : null,
          ),
          const SizedBox(height: CruSpace.s20),
          DocFieldGrid(
            children: [
              for (final kind in DocKind.values)
                _defaultField(
                  kind: kind,
                  templates: templates,
                  settings: settings,
                  doctorProfile: doctorProfile,
                  forClinic: forClinic,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultField({
    required DocKind kind,
    required List<DocTemplate> templates,
    required ClinicDocSettings settings,
    required DoctorDocProfile? doctorProfile,
    required bool forClinic,
  }) {
    final visible = DocRepository.instance.visibleTemplates(
      templates,
      settings,
      kind: kind,
    );
    final names = {for (final t in visible) t.id: t.name};
    final ids = names.keys.toList();
    final clinicDefault = settings.defaults[kind.name] ?? 'builtin.classic';
    final current = forClinic
        ? clinicDefault
        : doctorProfile?.defaults[kind.name] ?? clinicDefault;

    return CruDropdownField<String>(
      label: kind.label,
      value: ids.contains(current) ? current : ids.firstOrNull,
      items: ids,
      itemLabel: (id) => names[id] ?? id,
      onChanged: ids.isEmpty
          ? null
          : (id) async {
              await DocRepository.instance.setDefault(
                kind,
                id,
                forClinic: forClinic,
              );
              _toast('${kind.label} now uses ${names[id]}');
            },
    );
  }
}

/// A rendered first page and its shape.
class _Thumb {
  const _Thumb(this.bytes, this.aspectRatio);
  final Uint8List bytes;
  final double aspectRatio;
}

/// What a gallery card or row needs to show one template.
class _TemplateItem {
  const _TemplateItem({
    required this.template,
    required this.clinic,
    required this.doctor,
    required this.cache,
    required this.menu,
    required this.onPreview,
    required this.onEdit,
  });

  final DocTemplate template;
  final ClinicDocSettings clinic;
  final DoctorDocProfile? doctor;
  final Map<String, _Thumb> cache;
  final List<DocMenuItem> menu;
  final VoidCallback onPreview;
  final VoidCallback onEdit;

  String get editLabel => template.isBuiltin ? 'Customize' : 'Edit';

  /// "Ready-made · A4", "Clinic · 80 mm roll · Invoice only".
  String get subtitle {
    final t = template;
    final scope = switch (t.scope) {
      DocScope.builtin => 'Ready-made',
      DocScope.clinic => 'Clinic',
      DocScope.doctor => 'Mine',
    };
    final paper = switch (t.paper.format) {
      DocPaperFormat.roll80 => '80 mm roll',
      DocPaperFormat.custom => 'Custom size',
      final f => f.label,
    };
    return [
      scope,
      paper,
      if (t.kinds.length == 1) '${t.kinds.first.label} only',
    ].join(' · ');
  }
}

/// The template's first page on its tray, rendered once and cached.
class _TemplateThumb extends StatefulWidget {
  const _TemplateThumb({
    required this.item,
    required this.radius,
    required this.padding,
    this.hovered = false,
  });

  final _TemplateItem item;
  final double radius;
  final double padding;
  final bool hovered;

  @override
  State<_TemplateThumb> createState() => _TemplateThumbState();
}

class _TemplateThumbState extends State<_TemplateThumb> {
  _Thumb? _thumb;

  DocTemplate get _t => widget.item.template;
  String get _key => '${_t.id}:${_t.updatedAt}';

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_TemplateThumb old) {
    super.didUpdateWidget(old);
    if (old.item.template.id != _t.id ||
        old.item.template.updatedAt != _t.updatedAt) {
      _render();
    }
  }

  Future<void> _render() async {
    final key = _key;
    final cached = widget.item.cache[key];
    if (cached != null) {
      setState(() => _thumb = cached);
      return;
    }
    _thumb = null;

    try {
      final t = _t;
      final clinic = widget.item.clinic;
      final doctor = widget.item.doctor;
      final kind = t.kinds.firstOrNull ?? DocKind.invoice;
      final ctx = docSampleContext(
        docSampleData(kind),
        clinic: DocClinicInfo(
          name: clinic.name.isNotEmpty ? clinic.name : 'Sample Clinic',
          tagline: clinic.tagline,
          address: clinic.address,
          phone: clinic.phone,
          email: clinic.email,
          gstEnabled: clinic.gstEnabled,
          roundOff: clinic.roundOff,
        ),
        doctor: doctor == null
            ? null
            : DocDoctorInfo(
                uid: doctor.uid,
                name: doctor.nameOnDocs.isNotEmpty
                    ? doctor.nameOnDocs
                    : 'Dr. Sample',
                qualification: doctor.qualification,
                specialty: doctor.specialty,
                regNo: doctor.regNo,
              ),
      );
      final pdfBytes = await DocRenderer.render(t, ctx);
      await for (final page in Printing.raster(
        pdfBytes,
        pages: [0],
        dpi: 40,
      )) {
        final thumb = _Thumb(
          await page.toPng(),
          page.height == 0 ? _fallbackAspect : page.width / page.height,
        );
        widget.item.cache[key] = thumb;
        if (mounted && key == _key) setState(() => _thumb = thumb);
        return;
      }
    } catch (_) {
      // Leave the empty tray: the name and actions still work.
    }
  }

  /// The paper's shape before the page has rendered.
  double get _fallbackAspect {
    final p = _t.paper;
    return p.heightMm > 0 ? p.widthMm / p.heightMm : 0.5;
  }

  @override
  Widget build(BuildContext context) {
    return DocPaperThumb(
      bytes: _thumb?.bytes,
      aspectRatio: _thumb?.aspectRatio ?? _fallbackAspect,
      radius: widget.radius,
      padding: widget.padding,
      hovered: widget.hovered,
    );
  }
}

/// ⋯ for a template's other actions.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.item});

  final _TemplateItem item;

  @override
  Widget build(BuildContext context) {
    return DocMenu(
      items: item.menu,
      builder: (context, open) => CruIconButton(
        icon: CruIcons.more,
        size: CruSize.capsule + CruSpace.s6,
        iconSize: 18,
        semanticLabel: 'More for ${item.template.name}',
        tooltip: 'More',
        onPressed: open,
      ),
    );
  }
}

/// Desktop and tablet: a card with the page on a tray, the name and the
/// actions. Tapping the page previews it.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.item});

  final _TemplateItem item;

  /// Fixed so the grid rows line up; the tray takes what's left.
  static const double height = 352;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = item.template;
    return CruCard(
      semanticLabel: t.name,
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CruPressable(
              onTap: item.onPreview,
              scaleOnPress: false,
              semanticLabel: 'Preview ${t.name}',
              tooltip: 'Preview',
              builder: (context, hovered) => _TemplateThumb(
                item: item,
                radius: CruRadius.control,
                padding: CruSpace.s16,
                hovered: hovered,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: CruType.callout.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  item.subtitle,
                  style: CruType.subhead.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          Row(
            children: [
              CruCapsuleButton(
                label: item.editLabel,
                icon: CruIcons.pen,
                onPressed: item.onEdit,
              ),
              const SizedBox(width: CruSpace.s8),
              CruCapsuleButton(label: 'Preview', onPressed: item.onPreview),
              const Spacer(),
              _MoreButton(item: item),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phone: one row per template. Tapping the row previews it.
class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.item});

  final _TemplateItem item;

  static const double thumbWidth = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = item.template;
    return CruPressable(
      onTap: item.onPreview,
      scaleOnPress: false,
      semanticLabel: 'Preview ${t.name}',
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: Row(
          children: [
            SizedBox(
              width: thumbWidth,
              height: thumbWidth * 1.3,
              child: _TemplateThumb(
                item: item,
                radius: CruRadius.iconTile,
                padding: CruSpace.s6,
                hovered: hovered,
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: CruType.row.tint(c.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    item.subtitle,
                    style: CruType.subhead.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            CruCapsuleButton(label: item.editLabel, onPressed: item.onEdit),
            const SizedBox(width: CruSpace.s2),
            _MoreButton(item: item),
          ],
        ),
      ),
    );
  }
}

/// Start a template from a ready-made one. Returns the unsaved copy.
class _NewTemplateDialog extends StatefulWidget {
  const _NewTemplateDialog({
    required this.presets,
    required this.canEditClinic,
  });

  final List<DocTemplate> presets;
  final bool canEditClinic;

  @override
  State<_NewTemplateDialog> createState() => _NewTemplateDialogState();
}

class _NewTemplateDialogState extends State<_NewTemplateDialog> {
  late DocTemplate _preset = widget.presets.first;
  late final TextEditingController _name = TextEditingController(
    text: _copyName(_preset),
  );
  late DocScope _scope = widget.canEditClinic
      ? DocScope.clinic
      : DocScope.doctor;
  bool _nameEdited = false;
  String? _notice;

  static String _copyName(DocTemplate t) => '${t.name} (my copy)';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = 'Type a name for the template.');
      return;
    }
    final myUid = DocRepository.instance.tenantOrNull;
    Navigator.of(context).pop(
      _preset.copyWith(
        id: '',
        name: name,
        scope: _scope,
        ownerUid: _scope == DocScope.doctor ? myUid : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: 'New template',
      subtitle: 'Start from a ready-made layout, then make it yours.',
      leading: const CruIconTile(
        icon: CruIcons.fileText,
        tone: CruTileTone.neutral,
      ),
      submitLabel: 'Create and edit',
      onSubmit: _create,
      notice: _notice,
      width: CruSize.dialog + CruSpace.s32 * 2,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruDropdownField<DocTemplate>(
              label: 'Start from',
              value: _preset,
              items: widget.presets,
              itemLabel: (t) => t.name,
              onChanged: (p) => setState(() {
                _preset = p;
                if (!_nameEdited) _name.text = _copyName(p);
              }),
            ),
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Name',
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                _nameEdited = true;
                if (_notice != null) setState(() => _notice = null);
              },
              onSubmitted: (_) => _create(),
            ),
            if (widget.canEditClinic) ...[
              const SizedBox(height: CruSpace.s16),
              CruDropdownField<DocScope>(
                label: 'Who can use it',
                value: _scope,
                items: const [DocScope.clinic, DocScope.doctor],
                itemLabel: (s) =>
                    s == DocScope.clinic ? 'Everyone in the clinic' : 'Only me',
                onChanged: (s) => setState(() => _scope = s),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A new name for a template. Returns it, or null when cancelled.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = 'Type a name for the template.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return CruFormDialog(
      title: 'Rename template',
      leading: const CruIconTile(icon: CruIcons.pen, tone: CruTileTone.neutral),
      submitLabel: 'Save',
      onSubmit: _save,
      notice: _notice,
      dirty: _name.text.trim() != widget.initial,
      width: CruSize.dialog + CruSpace.s32 * 2,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: CruTextField(
          label: 'Name',
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _notice = null),
          onSubmitted: (_) => _save(),
        ),
      ),
    );
  }
}
