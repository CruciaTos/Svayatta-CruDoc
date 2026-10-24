import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_canvas.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_panels.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/render/doc_renderer.dart';
import 'package:doctor_management_app/core/pdf/render/doc_samples.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key, required this.initialTemplate});

  final DocTemplate initialTemplate;

  static Future<bool?> open(
    BuildContext context, {
    required DocTemplate template,
  }) async {
    DocTemplate target = template;

    // Ready-made clone handling
    if (template.isBuiltin) {
      final access = ClinicSession.instance.access;
      final canEditClinic =
          access != null && access.can(ClinicPermission.settings);
      var chosenScope = DocScope.doctor;

      if (canEditClinic) {
        final makeForClinic = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.cru.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CruRadius.card),
            ),
            title: Text('Customize template', style: CruType.headline),
            content: Text(
              'Do you want this custom template for yourself, or available to the whole clinic?',
              style: CruType.body,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('For me only'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('For whole clinic'),
              ),
            ],
          ),
        );
        if (makeForClinic == null) return false;
        if (makeForClinic) chosenScope = DocScope.clinic;
      }

      final me = DocRepository.instance.tenantOrNull;
      target = template.copyWith(
        id: '',
        name: '${template.name} (my copy)',
        scope: chosenScope,
        ownerUid: me,
        presetId: template.presetId.isNotEmpty
            ? template.presetId
            : template.id,
      );
    }

    if (!context.mounted) return false;
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TemplateEditorScreen(initialTemplate: target),
      ),
    );
  }

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  late final TemplateEditorController _controller;
  bool _dragLocked = false;
  double _zoom = 1.0; // 1.0 = 100%
  int _activeSideTab = 0; // 0 = Properties/Page, 1 = Elements
  bool _saving = false;
  DocImages _images = const DocImages();

  @override
  void initState() {
    super.initState();
    _controller = TemplateEditorController(widget.initialTemplate);
    _controller.addListener(_onControllerChange);
    _loadImages();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadImages() async {
    final s = await DocRepository.instance.clinicSettingsOnce();
    Uint8List? logo;
    Uint8List? stamp;
    Uint8List? bg;

    if (s.logoSha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(s.logoPath, s.logoSha);
      logo = res.bytes;
    }
    if (s.clinicStampSha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(
        s.clinicStampPath,
        s.clinicStampSha,
      );
      stamp = res.bytes;
    }
    final bgConfig = _controller.template.background;
    if (bgConfig != null && bgConfig.sha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(
        bgConfig.path,
        bgConfig.sha,
      );
      bg = res.bytes;
    }

    if (mounted) {
      setState(() {
        _images = DocImages(logo: logo, clinicStamp: stamp, background: bg);
      });
    }
  }

  DocContext _buildPreviewContext() {
    final s =
        ref.watch(clinicDocSettingsProvider).value ?? const ClinicDocSettings();
    final prof = ref.watch(myDocProfileProvider).value;

    final sampleData = docSampleData(_controller.previewKind);
    return docSampleContext(
      sampleData,
      clinic: DocClinicInfo(
        name: s.name.isNotEmpty ? s.name : 'Sanjeevani Clinic',
        tagline: s.tagline,
        address: s.address,
        phone: s.phone,
        email: s.email,
        website: s.website,
        timings: s.timings,
        regNo: s.regNo,
        gstin: s.gstin,
        footerText: s.footerText,
        upiId: s.upiId,
        upiName: s.upiName,
        gstEnabled: s.gstEnabled,
        roundOff: s.roundOff,
      ),
      doctor: prof == null
          ? null
          : DocDoctorInfo(
              uid: prof.uid,
              name: prof.nameOnDocs.isNotEmpty ? prof.nameOnDocs : 'Dr. Sample',
              qualification: prof.qualification,
              specialty: prof.specialty,
              regNo: prof.regNo,
              phone: prof.phone,
              email: prof.email,
            ),
      images: _images,
    );
  }

  Future<void> _saveTemplate({bool force = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final t = _controller.template;
      final saved = await DocRepository.instance.saveTemplate(
        t,
        loadedUpdatedAt: force ? 0 : _controller.loadedUpdatedAt,
      );
      _controller.markSaved(saved);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Template saved.')));
      }
    } on DocTemplateConflict {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.cru.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CruRadius.card),
          ),
          title: Text('Template modified', style: CruType.headline),
          content: Text(
            'Someone changed this template since you opened it. Do you want to overwrite their changes, or reload the latest template?',
            style: CruType.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reload'),
              child: const Text('Reload latest'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );

      if (choice == 'overwrite') {
        await _saveTemplate(force: true);
      } else if (choice == 'reload') {
        final list = await DocRepository.instance.templatesOnce();
        final reloaded = list
            .where((t) => t.id == _controller.template.id)
            .firstOrNull;
        if (reloaded != null) {
          _controller.markSaved(reloaded);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewPdf() async {
    try {
      final ctx = _buildPreviewContext();
      final pdfBytes = await DocRenderer.render(_controller.template, ctx);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dialogCtx) => Dialog(
          backgroundColor: dialogCtx.cru.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CruRadius.card),
          ),
          child: SizedBox(
            width: 800,
            height: 700,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s16,
                    vertical: CruSpace.s12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('PDF Preview (Sample)', style: CruType.headline),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => pdfBytes,
                    useActions: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not render preview: $e')));
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isControl) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          _controller.redo();
        } else {
          _controller.undo();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        _controller.redo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _controller.duplicateSelected();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveTemplate();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.select(null);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _controller.deleteSelected();
      return KeyEventResult.handled;
    }

    // Arrow keys nudge
    final dist = isShift ? 5.0 : 0.5;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _controller.nudge(0, -dist);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _controller.nudge(0, dist);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _controller.nudge(-dist, 0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _controller.nudge(dist, 0);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<bool> _onWillPop() async {
    if (!_controller.dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cru.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Text('Discard changes?', style: CruType.headline),
        content: Text(
          'You have unsaved changes to this template. Do you want to discard them?',
          style: CruType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.cru.redText),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isCompact = MediaQuery.sizeOf(context).width < CruBreakpoint.compact;
    final previewCtx = _buildPreviewContext();

    if (_controller.template.tooNew) {
      return Scaffold(
        appBar: AppBar(title: Text(_controller.template.name)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update_alt, size: 48, color: c.amberText),
              const SizedBox(height: 16),
              Text(
                'Update CruDoc to edit this template',
                style: CruType.headline.tint(c.label),
              ),
            ],
          ),
        ),
      );
    }

    final pxPerMm = (isCompact ? 2.8 : 3.2) * _zoom;

    return PopScope(
      canPop: !_controller.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: c.canvas,
          body: isCompact
              ? _buildMobileLayout(previewCtx, pxPerMm)
              : _buildDesktopLayout(previewCtx, pxPerMm),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(DocContext previewCtx, double pxPerMm) {
    final c = context.cru;

    return Column(
      children: [
        // Top Bar
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () async {
                  if (await _onWillPop() && mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Text(
                  _controller.template.name,
                  style: CruType.headline.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Undo & Redo
              IconButton(
                icon: const Icon(Icons.undo, size: 18),
                tooltip: 'Undo (Ctrl+Z)',
                onPressed: _controller.canUndo ? _controller.undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo, size: 18),
                tooltip: 'Redo (Ctrl+Y)',
                onPressed: _controller.canRedo ? _controller.redo : null,
              ),
              const SizedBox(width: CruSpace.s8),

              // Zoom controls
              IconButton(
                icon: const Icon(Icons.zoom_out, size: 18),
                onPressed: _zoom > 0.6
                    ? () => setState(() => _zoom = math.max(0.5, _zoom - 0.2))
                    : null,
              ),
              Text('${(_zoom * 100).toInt()}%', style: CruType.caption),
              IconButton(
                icon: const Icon(Icons.zoom_in, size: 18),
                onPressed: _zoom < 2.5
                    ? () => setState(() => _zoom = math.min(3.0, _zoom + 0.2))
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.fit_screen, size: 18),
                tooltip: 'Reset Zoom',
                onPressed: () => setState(() => _zoom = 1.0),
              ),
              const SizedBox(width: CruSpace.s12),

              // Preview PDF
              CruButton(
                label: 'Preview PDF',
                kind: CruButtonKind.secondary,
                onPressed: _previewPdf,
              ),
              const SizedBox(width: CruSpace.s8),

              // Save button
              CruButton(
                label: _saving ? 'Saving…' : 'Save',
                onPressed: _saving ? null : _saveTemplate,
              ),
            ],
          ),
        ),

        // Main Editor Area: Elements (260) | Canvas | Properties / Page (320)
        Expanded(
          child: Row(
            children: [
              // Left: Elements Panel
              Container(
                width: 260,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(right: BorderSide(color: c.hairline)),
                ),
                child: EditorElementsPanel(controller: _controller),
              ),

              // Center: Canvas View
              Expanded(
                child: Container(
                  color: c.inset,
                  child: InteractiveViewer(
                    panEnabled: !_dragLocked,
                    scaleEnabled: false,
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        physics: _dragLocked
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: _dragLocked
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(40),
                          child: EditorCanvas(
                            controller: _controller,
                            pxPerMm: pxPerMm,
                            previewCtx: previewCtx,
                            onDragLock: (locked) =>
                                setState(() => _dragLocked = locked),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Right: Properties / Page Panel
              Container(
                width: 320,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(left: BorderSide(color: c.hairline)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.hairline)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeSideTab = 0),
                              child: Center(
                                child: Text(
                                  _controller.selected != null
                                      ? 'Properties'
                                      : 'Page',
                                  style: CruType.subhead.w600.tint(
                                    _activeSideTab == 0
                                        ? c.accentText
                                        : c.label2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeSideTab = 1),
                              child: Center(
                                child: Text(
                                  'Page Setup',
                                  style: CruType.subhead.w600.tint(
                                    _activeSideTab == 1
                                        ? c.accentText
                                        : c.label2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _activeSideTab == 0 && _controller.selected != null
                          ? EditorPropertiesPanel(controller: _controller)
                          : EditorPagePanel(controller: _controller),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(DocContext previewCtx, double pxPerMm) {
    final c = context.cru;

    return SafeArea(
      child: Column(
        children: [
          // Mobile Top Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s8,
              vertical: CruSpace.s6,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await _onWillPop() && mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    _controller.template.name,
                    style: CruType.headline.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _controller.canUndo ? _controller.undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  onPressed: _controller.canRedo ? _controller.redo : null,
                ),
                CruButton(
                  label: _saving ? 'Saving…' : 'Save',
                  onPressed: _saving ? null : _saveTemplate,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Canvas in 2-axis scroll view
          Expanded(
            child: Container(
              color: c.inset,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: _dragLocked
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: _dragLocked
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: EditorCanvas(
                    controller: _controller,
                    pxPerMm: pxPerMm,
                    previewCtx: previewCtx,
                    onDragLock: (locked) =>
                        setState(() => _dragLocked = locked),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Sheet or Bottom Toolbar
          if (_controller.selected != null)
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: EditorPropertiesPanel(controller: _controller),
            )
          else
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text('Elements'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => SizedBox(
                          height: 400,
                          child: EditorElementsPanel(controller: _controller),
                        ),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('Page'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => SizedBox(
                          height: 450,
                          child: EditorPagePanel(controller: _controller),
                        ),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Preview'),
                    onPressed: _previewPdf,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
