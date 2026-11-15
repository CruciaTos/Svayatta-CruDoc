import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/radiology/cbct/cbct_device.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_poster_layer.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_server.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens one surface mesh in 3D: an intraoral scan, a lab design or a model
/// to print (`.stl`, `.ply`, `.obj`). The page is `assets/cbct_viewer/
/// mesh.html` (built from `cbct_viewer/src/mesh/`), served over the same
/// loopback server as the CBCT viewer, and the file never leaves the device.
///
/// Drag to rotate, scroll to zoom, middle-drag to move. A file a phone screen
/// or an unsupported platform cannot show falls back to a card with the file's
/// details and a way to open it in the clinic's own CAD software.
class ScanViewerScreen extends StatefulWidget {
  const ScanViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.title,
  });

  final String filePath;
  final String fileName;

  /// Shown in the page's top bar; the file name when nothing is given.
  final String? title;

  @override
  State<ScanViewerScreen> createState() => _ScanViewerScreenState();
}

class _ScanViewerScreenState extends State<ScanViewerScreen> {
  /// Beyond this a scan is not something the viewer should try to hold in
  /// memory; the clinic's own software is the honest answer.
  static const _maxBytes = 512 * 1024 * 1024;

  Uri? _url;
  String? _token;
  String? _error;
  bool _started = false;
  bool _shown = false;
  Color? _background;

  @override
  void dispose() {
    final token = _token;
    if (token != null) CbctServer.instance.revoke(token);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() => _error = 'This file is no longer on this computer.');
        return;
      }
      final size = await file.length();
      if (size > _maxBytes) {
        setState(
          () => _error =
              'This scan is ${_formatBytes(size)} — too large to open here. '
              'Open it in your CAD or lab software.',
        );
        return;
      }
      unawaited(cbctPageBackground().then((c) {
        if (mounted) setState(() => _background = c);
      }));
      final opened = await CbctServer.instance.openMesh(file);
      if (!mounted) {
        CbctServer.instance.revoke(opened.token);
        return;
      }
      final reduced = MediaQuery.disableAnimationsOf(context);
      setState(() {
        _token = opened.token;
        _url = opened.page.replace(
          queryParameters: {
            'file': opened.base,
            'name': widget.fileName,
            'title': widget.title?.isNotEmpty == true
                ? widget.title!
                : widget.fileName,
            'badge': 'On this device',
            'reduced': reduced ? '1' : '0',
          },
        );
      });
    } on Object catch (e) {
      debugPrint('[scan] open failed: $e');
      if (mounted) {
        setState(() => _error = 'CruDoc could not open this 3D file.');
      }
    }
  }

  void _onMessage(List<dynamic> args) {
    final msg = args.isNotEmpty && args.first is Map
        ? args.first as Map
        : const {};
    switch (msg['type']) {
      case 'close':
        if (mounted) Navigator.of(context).pop();
      case 'shown':
        if (mounted && !_shown) setState(() => _shown = true);
      case 'error':
        debugPrint('[scan] viewer error: ${msg['message']}');
        if (mounted) {
          setState(() => _shown = true);
        }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (!CbctDevice.canOpen3d(context)) {
      return _fallback(
        context,
        'This screen is too small for the 3D view. Open the file in your CAD '
        'or lab software.',
      );
    }
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
    final error = _error;
    if (error != null) return _fallback(context, error);

    final url = _url;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: _background ?? c.canvas,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri.uri(url)),
                  initialSettings: InAppWebViewSettings(
                    disableContextMenu: true,
                    isInspectable: kDebugMode,
                    supportZoom: false,
                  ),
                  // Keep drags and the wheel inside the viewer instead of scrolling.
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                  onWebViewCreated: (controller) =>
                      controller.addJavaScriptHandler(
                        handlerName: 'cbct',
                        callback: _onMessage,
                      ),
                  onConsoleMessage: kDebugMode
                      ? (_, m) => debugPrint('[scan web] ${m.message}')
                      : null,
                ),
              // The page paints its own background and progress; this covers
              // the white flash before its first frame.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _shown ? 0 : 1,
                  duration: CruMotion.fast,
                  curve: CruMotion.curve,
                  child: ColoredBox(color: _background ?? c.canvas),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What the doctor sees when the 3D view cannot run: the file's details and
  /// the way out through their own software.
  Widget _fallback(BuildContext context, String reason) {
    final c = context.cru;
    final file = File(widget.filePath);
    final exists = file.existsSync();
    final ext = p.extension(widget.filePath).replaceFirst('.', '').toUpperCase();

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Padding(
          padding: CruSpace.mainPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CruIconButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.cardGap),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: CruCard(
                    padding: const EdgeInsets.all(CruSpace.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CruIconTile(
                          icon: CruIcons.box,
                          tone: CruTileTone.accent,
                        ),
                        const SizedBox(height: CruSpace.s16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                widget.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CruType.title2.tint(c.label),
                              ),
                            ),
                            if (ext.isNotEmpty) ...[
                              const SizedBox(width: CruSpace.s8),
                              CruPill(
                                text: ext,
                                background: c.accentTint,
                                foreground: c.accent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: CruSpace.s16),
                        Text(
                          reason,
                          textAlign: TextAlign.center,
                          style: CruType.callout.tint(c.label2),
                        ),
                        if (exists) ...[
                          const SizedBox(height: CruSpace.s20),
                          CruButton(
                            label: 'Open with default app',
                            icon: CruIcons.arrowUpRight,
                            kind: CruButtonKind.primary,
                            onPressed: () => launchUrl(Uri.file(widget.filePath)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
