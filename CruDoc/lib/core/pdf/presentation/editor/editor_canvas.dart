import 'dart:math' as math;

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
  });

  final TemplateEditorController controller;
  final double pxPerMm;
  final DocContext previewCtx;
  final ValueChanged<bool> onDragLock;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  _DragState? _drag;

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
    const handleHitSize = 24.0;
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
      if (b.hidden || (b.onlyWithLogo && !_hasLogo)) continue;
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
    if (drag == null) return;

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
    if (_drag != null) {
      _drag = null;
      ctrl.endDrag();
      widget.onDragLock(false);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
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
          color: Colors.white,
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
            // Letterhead background image
            if (bgBytes != null && t.background != null)
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
                    child: Text(
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
                    child: Text(
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

            // Body Area Placeholder Rows
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
              if (!b.hidden)
                if (hasLogo || !b.onlyWithLogo)
                  _buildBlockWidget(b, hasLogo: hasLogo),

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
          if (isSelected) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: c.accent, width: 1.5),
                  ),
                ),
              ),
            ),
            if (b.locked)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock, size: 12, color: c.accent),
                ),
              )
            else ...[
              // 4 corner handles
              _buildCornerSquare(Alignment.topLeft),
              _buildCornerSquare(Alignment.topRight),
              _buildCornerSquare(Alignment.bottomLeft),
              _buildCornerSquare(Alignment.bottomRight),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCornerSquare(Alignment align) {
    return Align(
      alignment: align,
      child: FractionalTranslation(
        translation: Offset(
          align.x == -1.0 ? -0.5 : 0.5,
          align.y == -1.0 ? -0.5 : 0.5,
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: context.cru.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}
