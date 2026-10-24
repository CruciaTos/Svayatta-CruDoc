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
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class TemplatesTab extends ConsumerStatefulWidget {
  const TemplatesTab({super.key});

  @override
  ConsumerState<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<TemplatesTab> {
  static final Map<String, Uint8List> _thumbCache = {};

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openNewTemplateDialog(bool canEditClinic) async {
    final presets = builtinTemplates
        .where((t) => t.id != 'builtin.receipt80')
        .toList();
    var selectedPreset = presets.first;
    final nameCtrl = TextEditingController(
      text: '${selectedPreset.name} (my copy)',
    );
    var selectedScope = canEditClinic ? DocScope.clinic : DocScope.doctor;
    var userModifiedName = false;

    final created = await showDialog<DocTemplate>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ctx.cru.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CruRadius.card),
          ),
          title: Text('New template', style: CruType.headline),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<DocTemplate>(
                  initialValue: selectedPreset,
                  decoration: InputDecoration(
                    labelText: 'Base preset',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s12,
                      vertical: CruSpace.s8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CruRadius.control),
                    ),
                  ),
                  items: [
                    for (final p in presets)
                      DropdownMenuItem(value: p, child: Text(p.name)),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      setDialogState(() {
                        selectedPreset = p;
                        if (!userModifiedName) {
                          nameCtrl.text = '${p.name} (my copy)';
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: CruSpace.s16),
                CruTextField(
                  label: 'Template name',
                  controller: nameCtrl,
                  onChanged: (_) => userModifiedName = true,
                ),
                const SizedBox(height: CruSpace.s16),
                DropdownButtonFormField<DocScope>(
                  initialValue: selectedScope,
                  decoration: InputDecoration(
                    labelText: 'Template scope',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s12,
                      vertical: CruSpace.s8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CruRadius.control),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: DocScope.doctor,
                      child: Text('Only for me'),
                    ),
                    DropdownMenuItem(
                      value: DocScope.clinic,
                      enabled: canEditClinic,
                      child: Text(
                        'For the whole clinic${canEditClinic ? "" : " (Admin only)"}',
                      ),
                    ),
                  ],
                  onChanged: (s) {
                    if (s != null && (s == DocScope.doctor || canEditClinic)) {
                      setDialogState(() => selectedScope = s);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final myUid = DocRepository.instance.tenantOrNull;
                final copy = selectedPreset.copyWith(
                  id: '',
                  name: name,
                  scope: selectedScope,
                  ownerUid: selectedScope == DocScope.doctor ? myUid : null,
                );
                Navigator.pop(ctx, copy);
              },
              child: const Text('Create & Edit'),
            ),
          ],
        ),
      ),
    );

    if (created != null && mounted) {
      final saved = await TemplateEditorScreen.open(context, template: created);
      if (saved == true && mounted) {
        _toast('Template "${created.name}" saved');
      }
    }
  }

  Future<void> _renameTemplate(DocTemplate t) async {
    final ctrl = TextEditingController(text: t.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cru.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Text('Rename template', style: CruType.headline),
        content: CruTextField(
          label: 'Template name',
          controller: ctrl,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
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
    final clearedClinicKinds = s.defaults.entries
        .where((e) => e.value == t.id)
        .map((e) => e.key)
        .toList();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cru.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Text('Delete template', style: CruType.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${t.name}"?'),
            if (clearedClinicKinds.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s12),
              Text(
                'Notice: This template is the clinic default for ${clearedClinicKinds.join(", ")} and will revert to Classic.',
                style: CruType.subhead.tint(ctx.cru.redText),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.cru.redText,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final access = ref.watch(clinicAccessProvider).value;
    final canEditClinic =
        access == null || access.can(ClinicPermission.settings);
    final isDoctor = access == null || access.kind == MemberKind.doctor;

    final templates = ref.watch(docTemplatesProvider).value ?? builtinTemplates;
    final settings =
        ref.watch(clinicDocSettingsProvider).value ?? const ClinicDocSettings();
    final doctorProfile = ref.watch(myDocProfileProvider).value;

    final isCompact = MediaQuery.sizeOf(context).width < CruBreakpoint.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Defaults section
        CruCard(
          semanticLabel: 'Default templates',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Default templates', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'The template picked automatically when creating new documents.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              for (final kind in DocKind.values) ...[
                _DefaultKindRow(
                  kind: kind,
                  templates: templates,
                  settings: settings,
                  doctorProfile: doctorProfile,
                  isDoctor: isDoctor,
                  canEditClinic: canEditClinic,
                  onChanged: (templateId, forClinic) async {
                    await DocRepository.instance.setDefault(
                      kind,
                      templateId,
                      forClinic: forClinic,
                    );
                    _toast('Default updated');
                  },
                ),
                const SizedBox(height: CruSpace.s12),
              ],
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Gallery header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Templates gallery',
                  style: CruType.headline.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  '${templates.length} templates available',
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
            CruButton(
              label: '+ New template',
              kind: CruButtonKind.primary,
              onPressed: () => _openNewTemplateDialog(canEditClinic),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s16),

        // Gallery Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isCompact ? 2 : 3,
            mainAxisSpacing: CruSpace.s16,
            crossAxisSpacing: CruSpace.s16,
            childAspectRatio: isCompact ? 0.65 : 0.68,
          ),
          itemCount: templates.length,
          itemBuilder: (context, i) {
            final t = templates[i];
            return _TemplateGalleryCard(
              template: t,
              clinic: settings,
              doctor: doctorProfile,
              onPreview: () => MedicalPdfPreviewScreen.open(
                context,
                documentData: docSampleData(
                  t.kinds.firstOrNull ?? DocKind.invoice,
                ),
              ),
              onEdit: () async {
                final saved = await TemplateEditorScreen.open(
                  context,
                  template: t,
                );
                if (saved == true && mounted) {
                  _toast('Template saved');
                }
              },
              onRename: () => _renameTemplate(t),
              onDuplicate: () => _duplicateTemplate(t),
              onDelete: () => _deleteTemplate(t),
            );
          },
        ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }
}

class _DefaultKindRow extends StatelessWidget {
  const _DefaultKindRow({
    required this.kind,
    required this.templates,
    required this.settings,
    required this.doctorProfile,
    required this.isDoctor,
    required this.canEditClinic,
    required this.onChanged,
  });

  final DocKind kind;
  final List<DocTemplate> templates;
  final ClinicDocSettings settings;
  final DoctorDocProfile? doctorProfile;
  final bool isDoctor;
  final bool canEditClinic;
  final void Function(String id, bool forClinic) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final visible = DocRepository.instance.visibleTemplates(
      templates,
      settings,
      kind: kind,
    );

    final clinicDefault = settings.defaults[kind.name] ?? 'builtin.classic';
    final myDefault = doctorProfile?.defaults[kind.name] ?? clinicDefault;

    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(kind.label, style: CruType.body.w500.tint(c.label)),
        ),
        if (isDoctor) ...[
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: visible.any((t) => t.id == myDefault)
                  ? myDefault
                  : visible.firstOrNull?.id,
              decoration: InputDecoration(
                labelText: canEditClinic ? 'My default' : 'Default',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s12,
                  vertical: CruSpace.s8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
              items: [
                for (final t in visible)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v, false);
              },
            ),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
        if (canEditClinic) ...[
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: visible.any((t) => t.id == clinicDefault)
                  ? clinicDefault
                  : visible.firstOrNull?.id,
              decoration: InputDecoration(
                labelText: 'Clinic default',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s12,
                  vertical: CruSpace.s8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                ),
              ),
              items: [
                for (final t in visible)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v, true);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _TemplateGalleryCard extends StatefulWidget {
  const _TemplateGalleryCard({
    required this.template,
    required this.clinic,
    required this.doctor,
    required this.onPreview,
    required this.onEdit,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final DocTemplate template;
  final ClinicDocSettings clinic;
  final DoctorDocProfile? doctor;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  State<_TemplateGalleryCard> createState() => _TemplateGalleryCardState();
}

class _TemplateGalleryCardState extends State<_TemplateGalleryCard> {
  Uint8List? _thumbBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _renderThumb();
  }

  @override
  void didUpdateWidget(_TemplateGalleryCard old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id ||
        old.template.updatedAt != widget.template.updatedAt) {
      _renderThumb();
    }
  }

  Future<void> _renderThumb() async {
    final t = widget.template;
    final cacheKey = '${t.id}:${t.updatedAt}';
    if (_TemplatesTabState._thumbCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _thumbBytes = _TemplatesTabState._thumbCache[cacheKey];
          _loading = false;
        });
      }
      return;
    }

    try {
      final kind = t.kinds.firstOrNull ?? DocKind.invoice;
      final sampleData = docSampleData(kind);
      final ctx = docSampleContext(
        sampleData,
        clinic: DocClinicInfo(
          name: widget.clinic.name.isNotEmpty
              ? widget.clinic.name
              : 'Sample Clinic',
          tagline: widget.clinic.tagline,
          address: widget.clinic.address,
          phone: widget.clinic.phone,
          email: widget.clinic.email,
          gstEnabled: widget.clinic.gstEnabled,
          roundOff: widget.clinic.roundOff,
        ),
        doctor: widget.doctor == null
            ? null
            : DocDoctorInfo(
                uid: widget.doctor!.uid,
                name: widget.doctor!.nameOnDocs.isNotEmpty
                    ? widget.doctor!.nameOnDocs
                    : 'Dr. Sample',
                qualification: widget.doctor!.qualification,
                specialty: widget.doctor!.specialty,
                regNo: widget.doctor!.regNo,
              ),
      );
      final pdfBytes = await DocRenderer.render(t, ctx);
      final pages = Printing.raster(pdfBytes, pages: [0], dpi: 40);
      await for (final page in pages) {
        final png = await page.toPng();
        _TemplatesTabState._thumbCache[cacheKey] = png;
        if (mounted) {
          setState(() {
            _thumbBytes = png;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = widget.template;

    final badgeLabel = t.isBuiltin
        ? 'Ready-made'
        : t.scope == DocScope.clinic
        ? 'Clinic'
        : 'Mine';

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail Box
          Expanded(
            child: Container(
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: cruShape(
                  CruRadius.control,
                  side: BorderSide(color: c.hairline),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CruRadius.control),
                child: _loading
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accentText,
                          ),
                        ),
                      )
                    : _thumbBytes != null
                    ? Image.memory(_thumbBytes!, fit: BoxFit.contain)
                    : Icon(
                        Icons.description_outlined,
                        color: c.label2,
                        size: 36,
                      ),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s8),

          // Title & Badge Row
          Row(
            children: [
              Expanded(
                child: Text(
                  t.name,
                  style: CruType.subhead.w600.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: CruSpace.s4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: ShapeDecoration(
                  color: t.isBuiltin ? c.track : c.accentTint,
                  shape: cruShape(CruRadius.control),
                ),
                child: Text(
                  badgeLabel,
                  style: CruType.caption.tint(
                    t.isBuiltin ? c.label2 : c.accentText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),

          // Actions Row
          Row(
            children: [
              Expanded(
                child: CruButton(
                  label: 'Preview',
                  kind: CruButtonKind.secondary,
                  onPressed: widget.onPreview,
                ),
              ),
              const SizedBox(width: CruSpace.s6),
              Expanded(
                child: CruButton(
                  label: t.isBuiltin ? 'Customize' : 'Edit',
                  kind: CruButtonKind.primary,
                  onPressed: widget.onEdit,
                ),
              ),
              if (!t.isBuiltin) ...[
                const SizedBox(width: CruSpace.s6),
                PopupMenuButton<String>(
                  icon: CruIcon(CruIcons.more, size: 16, color: c.label),
                  onSelected: (val) {
                    if (val == 'rename') widget.onRename();
                    if (val == 'duplicate') widget.onDuplicate();
                    if (val == 'delete') widget.onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: ctx.cru.redText),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(width: CruSpace.s6),
                PopupMenuButton<String>(
                  icon: CruIcon(CruIcons.more, size: 16, color: c.label),
                  onSelected: (val) {
                    if (val == 'duplicate') widget.onDuplicate();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
