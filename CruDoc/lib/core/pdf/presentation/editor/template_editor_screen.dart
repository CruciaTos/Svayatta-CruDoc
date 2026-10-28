import 'dart:async';
import 'dart:convert';
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
import 'package:doctor_management_app/core/pdf/presentation/editor/editor_touch_ui.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/render/doc_renderer.dart';
import 'package:doctor_management_app/core/pdf/render/doc_samples.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_presets.dart';
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

  /// The page body rendered without header/footer blocks, shown under them.
  Uint8List? _bodyImage;
  String? _bodyKey;
  Timer? _bodyTimer;

  /// The "tap anything" tip goes once something has been selected.
  bool _hintSeen = false;
  final TransformationController _view = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller = TemplateEditorController(widget.initialTemplate);
    _controller.addListener(_onControllerChange);
    _loadImages();
  }

  @override
  void dispose() {
    _bodyTimer?.cancel();
    _view.dispose();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (_controller.selected != null) _hintSeen = true;
    if (mounted) setState(() {});
  }

  /// Re-renders the body when something that changes it changes (paper,
  /// zones, style, sections), not while blocks move.
  void _scheduleBodyRender(DocContext ctx) {
    final t = _controller.template;
    final key = [
      _controller.previewKind.name,
      jsonEncode(t.copyWith(blocks: const []).toMap()),
      ctx.clinic.name,
      ctx.clinic.gstEnabled,
      ctx.clinic.roundOff,
      ctx.clinic.upiId,
      ctx.images.background?.length ?? 0,
    ].join('|');
    if (key == _bodyKey) return;
    _bodyKey = key;
    _bodyTimer?.cancel();
    _bodyTimer = Timer(
      Duration(milliseconds: _bodyImage == null ? 0 : 350),
      () => _renderBody(key, ctx),
    );
  }

  Future<void> _renderBody(String key, DocContext ctx) async {
    try {
      final t = _controller.template.copyWith(blocks: const []);
      // No "SAMPLE" watermark over the editing page.
      final plain = DocContext(
        data: ctx.data,
        clinic: ctx.clinic,
        doctor: ctx.doctor,
        doctors: ctx.doctors,
        images: ctx.images,
        warnings: ctx.warnings,
        scriptImages: ctx.scriptImages,
      );
      final pdf = await DocRenderer.render(t, plain);
      await for (final page in Printing.raster(pdf, pages: [0], dpi: 110)) {
        final png = await page.toPng();
        if (!mounted || key != _bodyKey) return;
        setState(() => _bodyImage = png);
        return;
      }
    } catch (_) {
      // Keep the placeholder rows; blocks still edit as usual.
    }
  }

  /// The ready-made template this one started from, if any.
  DocTemplate? get _preset {
    final t = _controller.template;
    final id = t.presetId.isNotEmpty ? t.presetId : (t.isBuiltin ? t.id : '');
    return builtinTemplates.where((p) => p.id == id).firstOrNull;
  }

  Future<void> _resetLayout() async {
    final preset = _preset;
    if (preset == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Reset the layout?',
        leading: const CruIconTile(
          icon: EditorIcons.reset,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Reset',
        width: CruSize.dialog + CruSpace.s32 * 2,
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            'Every element goes back to where it is in the ready-made '
            '"${preset.name}" template. You can undo this.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (ok == true) _controller.resetLayout(preset);
  }

  void _hideSelected() {
    final b = _controller.selected;
    if (b == null) return;
    _controller.updateBlock(b.id, (o) => o.copyWith(hidden: true));
    _controller.select(null);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${editorBlockTitle(b)} hidden. Show it again from Elements.',
        ),
        action: SnackBarAction(label: 'Undo', onPressed: _controller.undo),
        // Goes by itself so it doesn't sit over the tools.
        persist: false,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// A bottom sheet in the app's style holding one of the editor panels.
  Future<void> _sheet(Widget child, {double heightFactor = 0.62}) {
    final c = context.cru;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.sizeOf(sheetCtx).height * heightFactor,
        child: Column(
          children: [
            const SizedBox(height: CruSpace.s8),
            Container(
              width: 36,
              height: 5,
              decoration: ShapeDecoration(
                color: c.track,
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: CruSpace.s4),
            Expanded(
              // Rebuild with the editor so edits show in the sheet too.
              child: ListenableBuilder(
                listenable: _controller,
                builder: (_, _) => child,
              ),
            ),
          ],
        ),
      ),
    );
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
      builder: (ctx) => CruFormDialog(
        title: 'Discard your changes?',
        leading: const CruIconTile(
          icon: EditorIcons.trash,
          tone: CruTileTone.neutral,
        ),
        cancelLabel: 'Keep editing',
        submitLabel: 'Discard',
        width: CruSize.dialog + CruSpace.s32 * 2,
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            "This template has changes that aren't saved.",
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
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

    final pxPerMm = 3.2 * _zoom;
    _scheduleBodyRender(previewCtx);

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
              ? _buildMobileLayout(previewCtx)
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
                            bodyImage: _bodyImage,
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

  Widget _buildMobileLayout(DocContext previewCtx) {
    final c = context.cru;
    final t = _controller.template;
    final selected = _controller.selected;

    Widget dim(bool on, Widget child) => AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: on ? 1 : 0.35,
      child: child,
    );

    return Column(
      children: [
        // Top bar: back, name, undo/redo, the one filled action
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: CruSize.searchBar + CruSpace.s12,
              child: Row(
                children: [
                  const SizedBox(width: CruSpace.s4),
                  CruIconButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
                    onPressed: () async {
                      if (await _onWillPop() && mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: CruType.callout.tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _controller.dirty || t.id.isEmpty
                              ? 'Not saved yet'
                              : 'Saved',
                          style: CruType.caption.tint(c.label3),
                        ),
                      ],
                    ),
                  ),
                  dim(
                    _controller.canUndo,
                    CruIconButton(
                      icon: EditorIcons.undo,
                      semanticLabel: 'Undo',
                      onPressed: _controller.canUndo ? _controller.undo : null,
                    ),
                  ),
                  dim(
                    _controller.canRedo,
                    CruIconButton(
                      icon: EditorIcons.redo,
                      semanticLabel: 'Redo',
                      onPressed: _controller.canRedo ? _controller.redo : null,
                    ),
                  ),
                  const SizedBox(width: CruSpace.s4),
                  CruButton(
                    label: _saving ? 'Saving…' : 'Save',
                    onPressed: _saving ? null : _saveTemplate,
                  ),
                  const SizedBox(width: CruSpace.s12),
                ],
              ),
            ),
          ),
        ),

        // The page, fitted to the screen's width. Pinch to zoom; one finger
        // on an element moves it, on the paper scrolls.
        Expanded(
          child: ColoredBox(
            color: c.canvas,
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    const pad = CruSpace.s16;
                    final s = (box.maxWidth - pad * 2) / t.paper.widthMm;
                    return InteractiveViewer(
                      transformationController: _view,
                      constrained: false,
                      minScale: 1,
                      maxScale: 4,
                      panEnabled: !_dragLocked,
                      boundaryMargin: const EdgeInsets.only(bottom: pad),
                      child: Padding(
                        padding: const EdgeInsets.all(pad),
                        child: EditorCanvas(
                          controller: _controller,
                          pxPerMm: s,
                          previewCtx: previewCtx,
                          bodyImage: _bodyImage,
                          touch: true,
                          onDragLock: (locked) =>
                              setState(() => _dragLocked = locked),
                        ),
                      ),
                    );
                  },
                ),
                if (selected == null && !_hintSeen)
                  const Positioned(
                    left: CruSpace.s16,
                    right: CruSpace.s16,
                    bottom: CruSpace.s16,
                    child: Center(
                      child: IgnorePointer(
                        child: EditorHint(
                          'Tap anything on the page to move, resize or fade it',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Selected: the size / transparency panel. Otherwise: the tools.
        AnimatedSize(
          duration: CruMotion.of(context, CruMotion.standard),
          curve: CruMotion.curve,
          alignment: Alignment.bottomCenter,
          child: selected != null
              ? EditorTunePanel(
                  controller: _controller,
                  onHide: _hideSelected,
                  onMore: () => _sheet(
                    EditorPropertiesPanel(controller: _controller),
                    heightFactor: 0.7,
                  ),
                )
              : EditorToolBar(
                  tools: [
                    EditorTool(
                      'Elements',
                      EditorIcons.layers,
                      () =>
                          _sheet(EditorElementsPanel(controller: _controller)),
                    ),
                    EditorTool(
                      'Page',
                      CruIcons.settings,
                      () => _sheet(
                        EditorPagePanel(controller: _controller),
                        heightFactor: 0.7,
                      ),
                    ),
                    EditorTool(
                      'Reset',
                      EditorIcons.reset,
                      _preset == null ? null : _resetLayout,
                    ),
                    EditorTool('Preview', EditorIcons.eye, _previewPdf),
                  ],
                ),
        ),
      ],
    );
  }
}
