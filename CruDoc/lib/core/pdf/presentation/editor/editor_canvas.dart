import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/pdf/presentation/editor/editor_block_view.dart';
import 'package:doctor_management_app/core/pdf/presentation/editor/template_editor_controller.dart';
import 'package:doctor_management_app/core/pdf/render/doc_context.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_body_sections.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _DragTargetKind { block, handle, headerEdge, footerEdge }

class _DragState {
  _DragState({
    required this.kind,
    required this.startPos,
    this.origBlock,
    this.handle,
    this.startZoneHeight = 0,
  });

  final _DragTargetKind kind;
  final Offset startPos;
  final DocBlock? origBlock;
  final DocHandle? handle;
  final double startZoneHeight;
  bool checkpointDone = false;
}

class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.controller,
    required this.pxPerMm,
    required this.previewCtx,
    required this.onDragLock,
    this.bodyImage,
    this.touch = false,
  });

  final TemplateEditorController controller;
  final double pxPerMm;
  final DocContext previewCtx;
  final ValueChanged<bool> onDragLock;

  /// The page rendered without its header and footer blocks: the real
  /// body under the blocks. Placeholder rows until it arrives.
  final Uint8List? bodyImage;

  /// Fingers: bigger handles and a faint outline on everything movable.
  final bool touch;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  _DragState? _drag;
  final Set<int> _pointers = {};

  TemplateEditorController get ctrl => widget.controller;
  DocTemplate get t => ctrl.template;
  double get s => widget.pxPerMm;

  double get _paperWidthPx => t.paper.widthMm * s;
  double get _paperHeightPx => t.paper.heightMm * s;

  double get _headerTopPx => t.paper.margins.top * s;
  double get _headerHeightPx => t.headerMm * s;
  double get _footerTopPx =>
      (t.paper.heightMm - t.paper.margins.bottom - t.footerMm) * s;

  bool get _hasLogo => widget.previewCtx.images.logo != null;

  /// Drawn on the page. On a phone a picture that isn't uploaded yet is
  /// left out, as in the PDF, so its empty box doesn't sit over text that
  /// slid into its place.
  bool _shows(DocBlock b) {
    if (b.hidden || (b.onlyWithLogo && !_hasLogo)) return false;
    if (widget.touch &&
        b.type == DocBlockType.image &&
        widget.previewCtx.images.forBlock(b) == null) {
      return false;
    }
    return true;
  }

  /// Where [b] is drawn: without a logo, slid by its no-logo offset, the
  /// same as in the PDF. Drags still change the stored x/y.
  Rect _blockRect(DocBlock b) {
    final zoneTop = b.zone == DocZone.header
        ? t.paper.margins.top
        : (t.paper.heightMm - t.paper.margins.bottom - t.footerMm);
    final dx = _hasLogo ? 0.0 : b.noLogoDx;
    final dy = _hasLogo ? 0.0 : b.noLogoDy;
    return Rect.fromLTWH(
      (t.paper.margins.left + b.x + dx) * s,
      (zoneTop + b.y + dy) * s,
      b.w * s,
      b.h * s,
    );
  }

  Rect _handleRect(Rect blockRect, DocHandle h) {
    final handleHitSize = widget.touch ? 40.0 : 24.0;
    final center = switch (h) {
      DocHandle.tl => blockRect.topLeft,
      DocHandle.tr => blockRect.topRight,
      DocHandle.bl => blockRect.bottomLeft,
      DocHandle.br => blockRect.bottomRight,
    };
    return Rect.fromCenter(
      center: center,
      width: handleHitSize,
      height: handleHitSize,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    // A second finger means pinch-to-zoom: let go of the block.
    if (_pointers.length > 1) {
      if (_drag != null) {
        _drag = null;
        ctrl.endDrag();
        widget.onDragLock(false);
      }
      return;
    }
    final pos = e.localPosition;

    // 1. Check corner handles of selected block
    final sel = ctrl.selected;
    if (sel != null && !sel.locked && !sel.hidden) {
      final rect = _blockRect(sel);
      for (final h in DocHandle.values) {
        if (_handleRect(rect, h).contains(pos)) {
          _drag = _DragState(
            kind: _DragTargetKind.handle,
            startPos: pos,
            origBlock: sel,
            handle: h,
          );
          widget.onDragLock(true);
          return;
        }
      }
    }

    // 2. Check zone edge handles
    const edgeHitHeight = 16.0;
    final headerEdgeY = _headerTopPx + _headerHeightPx;
    if ((pos.dy - headerEdgeY).abs() <= edgeHitHeight / 2) {
      _drag = _DragState(
        kind: _DragTargetKind.headerEdge,
        startPos: pos,
        startZoneHeight: t.headerMm,
      );
      widget.onDragLock(true);
      return;
    }

    final footerEdgeY = _footerTopPx;
    if ((pos.dy - footerEdgeY).abs() <= edgeHitHeight / 2) {
      _drag = _DragState(
        kind: _DragTargetKind.footerEdge,
        startPos: pos,
        startZoneHeight: t.footerMm,
      );
      widget.onDragLock(true);
      return;
    }

    // 3. Check blocks top-most to bottom-most
    final blocks = t.blocks;
    for (var i = blocks.length - 1; i >= 0; i--) {
      final b = blocks[i];
      if (!_shows(b)) continue;
      if (_blockRect(b).contains(pos)) {
        ctrl.select(b.id);
        if (!b.locked) {
          _drag = _DragState(
            kind: _DragTargetKind.block,
            startPos: pos,
            origBlock: b,
          );
          widget.onDragLock(true);
        }
        return;
      }
    }

    // 4. Hit nothing
    ctrl.select(null);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final drag = _drag;
    if (drag == null || _pointers.length > 1) return;

    final diff = e.localPosition - drag.startPos;
    final dxMm = diff.dx / s;
    final dyMm = diff.dy / s;

    // Call checkpoint only on the first actual move
    if (!drag.checkpointDone && (diff.dx.abs() > 1 || diff.dy.abs() > 1)) {
      ctrl.checkpoint();
      drag.checkpointDone = true;
    }

    if (!drag.checkpointDone) return;

    switch (drag.kind) {
      case _DragTargetKind.block:
        if (drag.origBlock != null) {
          ctrl.moveTo(drag.origBlock!, dxMm, dyMm);
        }
        break;
      case _DragTargetKind.handle:
        if (drag.origBlock != null && drag.handle != null) {
          ctrl.resize(drag.origBlock!, drag.handle!, dxMm, dyMm);
        }
        break;
      case _DragTargetKind.headerEdge:
        ctrl.setZoneHeight(DocZone.header, drag.startZoneHeight + dyMm);
        break;
      case _DragTargetKind.footerEdge:
        ctrl.setZoneHeight(DocZone.footer, drag.startZoneHeight - dyMm);
        break;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (_drag != null) {
      _drag = null;
      ctrl.endDrag();
      widget.onDragLock(false);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_drag != null) {
      _drag = null;
      ctrl.endDrag();
      widget.onDragLock(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bgBytes = widget.previewCtx.images.background;
    final hasLogo = widget.previewCtx.images.logo != null;

    final headerZoneTop = t.paper.margins.top * s;
    final headerZoneHeight = t.headerMm * s;
    final footerZoneHeight = t.footerMm * s;
    final footerZoneTop =
        (t.paper.heightMm - t.paper.margins.bottom - t.footerMm) * s;

    final contentLeft = t.paper.margins.left * s;
    final contentWidth = t.paper.contentWidthMm * s;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Container(
        width: _paperWidthPx,
        height: _paperHeightPx,
        decoration: BoxDecoration(
          // Paper is white in both appearances.
          color: CruBrand.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The real page, rendered without its blocks (it includes the
            // letterhead background). Placeholder rows until it arrives.
            if (widget.bodyImage != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.memory(
                    widget.bodyImage!,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),

            // Letterhead background image
            if (widget.bodyImage == null &&
                bgBytes != null &&
                t.background != null)
              Positioned.fill(
                child: Opacity(
                  opacity: t.background!.opacity.clamp(0.0, 1.0),
                  child: Image.memory(bgBytes, fit: BoxFit.fill),
                ),
              ),

            // Margins outline (faint dashed border)
            Positioned(
              left: contentLeft,
              top: headerZoneTop,
              width: contentWidth,
              height: (t.paper.contentHeightMm) * s,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),

            // Header Zone Tint
            if (t.headerMm > 0)
              Positioned(
                left: contentLeft,
                top: headerZoneTop,
                width: contentWidth,
                height: headerZoneHeight,
                child: IgnorePointer(
                  child: Container(
                    color: c.accentTint.withValues(alpha: 0.12),
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(4),
                    child: widget.touch
                        ? null
                        : Text(
                            'HEADER',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 9,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                              color: c.accentText.withValues(alpha: 0.5),
                            ),
                          ),
                  ),
                ),
              ),

            // Footer Zone Tint
            if (t.footerMm > 0)
              Positioned(
                left: contentLeft,
                top: footerZoneTop,
                width: contentWidth,
                height: footerZoneHeight,
                child: IgnorePointer(
                  child: Container(
                    color: c.accentTint.withValues(alpha: 0.12),
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(4),
                    child: widget.touch
                        ? null
                        : Text(
                            'FOOTER',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 9,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                              color: c.accentText.withValues(alpha: 0.5),
                            ),
                          ),
                  ),
                ),
              ),

            // Body placeholder rows until the rendered page arrives
            if (widget.bodyImage == null)
              Positioned(
                left: contentLeft,
                top: headerZoneTop + headerZoneHeight,
                width: contentWidth,
                height: math.max(
                  0,
                  footerZoneTop - (headerZoneTop + headerZoneHeight),
                ),
                child: IgnorePointer(child: _buildBodyPlaceholders()),
              ),

            // Blocks
            for (final b in t.blocks)
              if (_shows(b)) _buildBlockWidget(b, hasLogo: hasLogo),

            // The selection sits above every block so its handles show.
            if (ctrl.selected case final sel? when _shows(sel))
              _buildSelection(sel),

            // Guides while dragging
            if (ctrl.guideZone != null) ...[
              for (final gx in ctrl.guideX)
                Positioned(
                  left: contentLeft + gx * s,
                  top: ctrl.guideZone == DocZone.header
                      ? headerZoneTop
                      : footerZoneTop,
                  width: 1,
                  height: ctrl.guideZone == DocZone.header
                      ? headerZoneHeight
                      : footerZoneHeight,
                  child: IgnorePointer(child: Container(color: c.accent)),
                ),
              for (final gy in ctrl.guideY)
                Positioned(
                  left: contentLeft,
                  top:
                      (ctrl.guideZone == DocZone.header
                          ? headerZoneTop
                          : footerZoneTop) +
                      gy * s,
                  width: contentWidth,
                  height: 1,
                  child: IgnorePointer(child: Container(color: c.accent)),
                ),
            ],

            // Zone Edge Handle: Header
            Positioned(
              left: contentLeft,
              top: headerZoneTop + headerZoneHeight - 6,
              width: contentWidth,
              height: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // Zone Edge Handle: Footer
            Positioned(
              left: contentLeft,
              top: footerZoneTop - 6,
              width: contentWidth,
              height: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyPlaceholders() {
    final sections = t.bodyFor(ctrl.previewKind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final sec in sections) ...[
            if (sec.visible)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notes, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text(
                      DocSection.labels[sec.id] ?? sec.id,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockWidget(DocBlock b, {required bool hasLogo}) {
    final c = context.cru;
    final isSelected = ctrl.selectedId == b.id;

    var bx = b.x;
    var by = b.y;
    if (!hasLogo) {
      bx += b.noLogoDx;
      by += b.noLogoDy;
    }

    final zoneTop = b.zone == DocZone.header
        ? t.paper.margins.top
        : (t.paper.heightMm - t.paper.margins.bottom - t.footerMm);

    final leftPx = (t.paper.margins.left + bx) * s;
    final topPx = (zoneTop + by) * s;
    final widthPx = b.w * s;
    final heightPx = b.h * s;

    return Positioned(
      left: leftPx,
      top: topPx,
      width: widthPx,
      height: heightPx,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: EditorBlockView(
              block: b,
              template: t,
              previewCtx: widget.previewCtx,
              pxPerMm: s,
            ),
          ),
          // Everything movable shows a faint outline on a touch screen.
          if (widget.touch && !isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: c.accent.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Outline and corner handles (or a lock badge) for the selection.
  Widget _buildSelection(DocBlock b) {
    final c = context.cru;
    return Positioned.fromRect(
      rect: _blockRect(b),
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.06),
                  border: Border.all(color: c.accent, width: 1.5),
                ),
              ),
            ),
            if (b.locked)
              Positioned(
                top: -10,
                right: -10,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accent, width: 1.5),
                  ),
                  child: Icon(Icons.lock, size: 11, color: c.accentText),
                ),
              )
            else ...[
              _buildCornerSquare(Alignment.topLeft),
              _buildCornerSquare(Alignment.topRight),
              _buildCornerSquare(Alignment.bottomLeft),
              _buildCornerSquare(Alignment.bottomRight),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCornerSquare(Alignment align) {
    final c = context.cru;
    final size = widget.touch ? 14.0 : 8.0;
    return Align(
      alignment: align,
      child: FractionalTranslation(
        translation: Offset(
          align.x == -1.0 ? -0.5 : 0.5,
          align.y == -1.0 ? -0.5 : 0.5,
        ),
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.surface,
              shape: widget.touch ? BoxShape.circle : BoxShape.rectangle,
              border: Border.all(color: c.accent, width: 1.5),
              boxShadow: widget.touch && !c.isEvening ? c.cardShadow : null,
            ),
          ),
        ),
      ),
    );
  }
}
