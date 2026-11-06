import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
          builder: (_) => const _CopyForDialog(),
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

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TemplateEditorController _controller;
  bool _dragLocked = false;
  double _zoom = 1.0; // 1.0 = 100%
  int _activeSideTab = 1; // 0 = the selected element, 1 = the page
  bool _saving = false;
  DocImages _images = const DocImages();

  /// The page body rendered without header/footer blocks, shown under them.
  Uint8List? _bodyImage;

  /// Width ÷ height of the rendered page (a receipt's length varies).
  double? _bodyAspect;
  String? _bodyKey;
  String? _lastSelectedId;
  Timer? _bodyTimer;

  /// The "tap anything" tip shows on the first visit only (remembered).
  bool _hintSeen = true;
  static const _hintKey = 'templateEditor.hintSeen';
  final TransformationController _view = TransformationController();

  /// Double-tap zoom on the phone.
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: CruMotion.standard,
  );
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = TemplateEditorController(widget.initialTemplate);
    _controller.addListener(_onControllerChange);
    _loadImages();
    _loadHint();
    _zoomAnim.addListener(() {
      final z = _zoomTween;
      if (z != null) _view.value = z.value;
    });
  }

  Future<void> _loadHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_hintKey) ?? false;
      if (mounted && !seen) setState(() => _hintSeen = false);
    } catch (_) {}
  }

  void _markHintSeen() {
    if (_hintSeen) return;
    _hintSeen = true;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_hintKey, true))
        .catchError((_) => false);
  }

  /// Double-tap: zoom in where it was tapped; again to zoom back out.
  void _toggleZoom() {
    final zoomed = _view.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end;
    if (zoomed) {
      end = Matrix4.identity();
    } else {
      const k = 2.5;
      final p = _doubleTapAt;
      end = Matrix4.diagonal3Values(k, k, 1)
        ..setTranslationRaw(-p.dx * (k - 1), -p.dy * (k - 1), 0);
    }
    _zoomTween = Matrix4Tween(
      begin: _view.value,
      end: end,
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: CruMotion.curve));
    _zoomAnim.forward(from: 0);
  }

  @override
  void dispose() {
    _bodyTimer?.cancel();
    _zoomAnim.dispose();
    _view.dispose();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    final id = _controller.selectedId;
    if (id != _lastSelectedId) {
      // The side panel follows the selection on wide screens.
      _activeSideTab = id != null ? 0 : 1;
      _lastSelectedId = id;
    }
    if (_controller.selected != null) _markHintSeen();
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
      // About 1100 px across whatever the paper (a narrow receipt needs
      // more dots per inch than A4 to look as sharp).
      final dpi = (1100 / (t.paper.widthMm / 25.4)).clamp(100.0, 300.0);
      await for (final page in Printing.raster(pdf, pages: [0], dpi: dpi)) {
        final png = await page.toPng();
        if (!mounted || key != _bodyKey) return;
        setState(() {
          _bodyImage = png;
          _bodyAspect = page.height == 0 ? null : page.width / page.height;
        });
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

  /// Hide, lock, duplicate, delete and the detailed settings for [b].
  void _openActions(DocBlock b) {
    _controller.select(b.id);
    final custom =
        !b.id.startsWith('builtin.') && !_controller.template.isBuiltin;
    showEditorActions(
      context,
      title: editorBlockTitle(b),
      actions: [
        EditorAction(
          'Text, colour and more',
          CruIcons.settings,
          () => _sheet(
            (_) =>
                EditorPropertiesPanel(controller: _controller, showTune: false),
            heightFactor: 0.7,
          ),
        ),
        EditorAction(
          b.locked ? 'Unlock' : 'Lock in place',
          b.locked ? EditorIcons.unlock : EditorIcons.lock,
          () => _controller.updateBlock(
            b.id,
            (o) => o.copyWith(locked: !o.locked),
          ),
        ),
        EditorAction('Duplicate', EditorIcons.copy, () {
          _controller.select(b.id);
          _controller.duplicateSelected();
        }),
        EditorAction('Hide', EditorIcons.eyeOff, _hideSelected),
        if (custom)
          EditorAction('Delete', EditorIcons.trash, () {
            _controller.select(b.id);
            _controller.deleteSelected();
          }),
      ],
    );
  }

  /// One Save for both layouts: the filled action only when there is
  /// something to save; otherwise quiet.
  Widget _saveButton() {
    final t = _controller.template;
    final canSave = !_saving && (_controller.dirty || t.id.isEmpty);
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: canSave || _saving ? 1 : 0.45,
      child: CruButton(
        label: _saving ? 'Saving…' : 'Save',
        kind: canSave || _saving ? CruButtonKind.primary : CruButtonKind.inset,
        onPressed: canSave ? _saveTemplate : null,
      ),
    );
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
  Future<void> _sheet(
    Widget Function(VoidCallback close) build, {
    double heightFactor = 0.62,
  }) {
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
                builder: (_, _) => build(() => Navigator.of(sheetCtx).pop()),
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
              : _buildDesktopLayout(previewCtx),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(DocContext previewCtx) {
    final c = context.cru;
    final t = _controller.template;
    final roll = t.paper.isRoll;
    final showElement = _activeSideTab == 0;

    Widget dim(bool on, Widget child) => AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: on ? 1 : 0.35,
      child: child,
    );

    return Column(
      children: [
        // Top bar: back, name, undo/redo, zoom, reset, preview, save
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          // Clear of the status bar on a tablet.
          child: SafeArea(
            bottom: false,
            child: Container(
              height: CruSize.searchBar + CruSpace.s16,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              child: Row(
                children: [
                  CruIconButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
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
                      t.name,
                      style: CruType.headline.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  dim(
                    _controller.canUndo,
                    CruIconButton(
                      icon: EditorIcons.undo,
                      semanticLabel: 'Undo',
                      tooltip: 'Undo (Ctrl+Z)',
                      onPressed: _controller.canUndo ? _controller.undo : null,
                    ),
                  ),
                  dim(
                    _controller.canRedo,
                    CruIconButton(
                      icon: EditorIcons.redo,
                      semanticLabel: 'Redo',
                      tooltip: 'Redo (Ctrl+Y)',
                      onPressed: _controller.canRedo ? _controller.redo : null,
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Container(width: 1, height: CruSpace.s24, color: c.separator),
                  const SizedBox(width: CruSpace.s8),
                  dim(
                    _zoom > 0.6,
                    CruIconButton(
                      icon: EditorIcons.zoomOut,
                      semanticLabel: 'Zoom out',
                      tooltip: 'Zoom out',
                      onPressed: _zoom > 0.6
                          ? () => setState(
                              () => _zoom = math.max(0.5, _zoom - 0.2),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(_zoom * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: CruType.subhead.w600.tabular.tint(c.label2),
                    ),
                  ),
                  dim(
                    _zoom < 2.5,
                    CruIconButton(
                      icon: EditorIcons.zoomIn,
                      semanticLabel: 'Zoom in',
                      tooltip: 'Zoom in',
                      onPressed: _zoom < 2.5
                          ? () => setState(
                              () => _zoom = math.min(3.0, _zoom + 0.2),
                            )
                          : null,
                    ),
                  ),
                  CruIconButton(
                    icon: EditorIcons.fit,
                    semanticLabel: 'Fit to screen',
                    tooltip: 'Fit to screen',
                    onPressed: () => setState(() => _zoom = 1.0),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruButton(
                    label: 'Preview',
                    icon: EditorIcons.eye,
                    kind: CruButtonKind.inset,
                    onPressed: _previewPdf,
                  ),
                  const SizedBox(width: CruSpace.s8),
                  _saveButton(),
                ],
              ),
            ),
          ),
        ),

        // Elements | page | element or page settings
        Expanded(
          child: Row(
            children: [
              Container(
                width: 272,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(right: BorderSide(color: c.hairline)),
                ),
                child: EditorElementsPanel(controller: _controller),
              ),
              Expanded(
                child: ColoredBox(
                  color: c.canvas,
                  // 100 % fits the page to the space (never above 3.2 px/mm).
                  child: LayoutBuilder(
                    builder: (context, box) {
                      const pad = CruSpace.s32 + 8;
                      final fit = math.min(
                        3.2,
                        (box.maxWidth - pad * 2) / t.paper.widthMm,
                      );
                      return InteractiveViewer(
                        panEnabled: !_dragLocked,
                        scaleEnabled: false,
                        child: Center(
                          child: SingleChildScrollView(
                            physics: _dragLocked
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: _dragLocked
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                              padding: const EdgeInsets.all(pad),
                              child: EditorCanvas(
                                controller: _controller,
                                pxPerMm: fit * _zoom,
                                previewCtx: previewCtx,
                                bodyImage: _bodyImage,
                                bodyAspect: _bodyAspect,
                                // Fingers on a tablet get the bigger handles.
                                touch: cruIsTouchPlatform,
                                onLongPress: _openActions,
                                onDragLock: (locked) =>
                                    setState(() => _dragLocked = locked),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(left: BorderSide(color: c.hairline)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CruSpace.s16,
                        CruSpace.s12,
                        CruSpace.s16,
                        CruSpace.s12,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: CruSegmentedControl<int>(
                          semanticLabel: 'Settings for',
                          segments: const [
                            CruSegment(0, 'Element'),
                            CruSegment(1, 'Page'),
                          ],
                          selected: showElement ? 0 : 1,
                          onChanged: (v) => setState(() => _activeSideTab = v),
                        ),
                      ),
                    ),
                    const CruSeparator(),
                    Expanded(
                      child: showElement
                          ? EditorPropertiesPanel(controller: _controller)
                          : EditorPagePanel(
                              controller: _controller,
                              onResetLayout: _preset == null || roll
                                  ? null
                                  : _resetLayout,
                            ),
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
                    child: Text(
                      t.name,
                      style: CruType.callout.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  _saveButton(),
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
                    return GestureDetector(
                      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                      onDoubleTap: _toggleZoom,
                      child: InteractiveViewer(
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
                            bodyAspect: _bodyAspect,
                            touch: true,
                            onLongPress: _openActions,
                            onDragLock: (locked) =>
                                setState(() => _dragLocked = locked),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (t.paper.isRoll || (selected == null && !_hintSeen))
                  Positioned(
                    left: CruSpace.s16,
                    right: CruSpace.s16,
                    bottom: CruSpace.s16,
                    child: Center(
                      child: IgnorePointer(
                        child: EditorHint(
                          t.paper.isRoll
                              ? 'Receipts have a fixed layout. Change the '
                                    'name and colour from Page.'
                              : 'Tap anything on the page to move, resize '
                                    'or fade it',
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
                  onMore: () => _openActions(selected),
                )
              : EditorToolBar(
                  tools: [
                    EditorTool(
                      'Elements',
                      EditorIcons.layers,
                      () => _sheet(
                        (close) => EditorElementsPanel(
                          controller: _controller,
                          onPicked: close,
                        ),
                      ),
                    ),
                    EditorTool(
                      'Page',
                      CruIcons.settings,
                      () => _sheet(
                        (close) => EditorPagePanel(
                          controller: _controller,
                          onResetLayout: _preset == null || t.paper.isRoll
                              ? null
                              : () {
                                  close();
                                  _resetLayout();
                                },
                        ),
                        heightFactor: 0.7,
                      ),
                    ),
                    EditorTool('Preview', EditorIcons.eye, _previewPdf),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Before customizing a ready-made template: who the copy is for.
/// Returns true for the whole clinic, false for only me, null to cancel.
class _CopyForDialog extends StatefulWidget {
  const _CopyForDialog();

  @override
  State<_CopyForDialog> createState() => _CopyForDialogState();
}

class _CopyForDialogState extends State<_CopyForDialog> {
  bool _clinic = true;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruFormDialog(
      title: 'Customize a copy',
      leading: const CruIconTile(icon: CruIcons.pen, tone: CruTileTone.neutral),
      submitLabel: 'Customize',
      width: CruSize.dialog + CruSpace.s32 * 2,
      onSubmit: () => Navigator.of(context).pop(_clinic),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The ready-made design stays as it is. Who can use your copy?',
              style: CruType.text.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            CruSegmentedControl<bool>(
              semanticLabel: 'Who can use it',
              segments: const [
                CruSegment(true, 'Whole clinic'),
                CruSegment(false, 'Only me'),
              ],
              selected: _clinic,
              onChanged: (v) => setState(() => _clinic = v),
            ),
          ],
        ),
      ),
    );
  }
}
