import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crudoc_j2k/crudoc_j2k.dart' show j2kSupported;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/radiology/cbct/cbct_device.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_poster_layer.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_server.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_snapshot.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_store.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The CBCT 3D viewer: Axial, 3D, Coronal and Sagittal panels with linked
/// crosshairs (the web page in `assets/cbct_viewer/`, built from
/// `cbct_viewer/`), shown full screen in a WebView on Windows, macOS, iPad
/// and Android tablets. The scan is packed once into a volume file next to
/// the study (a rebuildable cache) and served to the page over loopback.
class CbctViewerScreen extends ConsumerStatefulWidget {
  const CbctViewerScreen({super.key, required this.studyId});

  final String studyId;

  @override
  ConsumerState<CbctViewerScreen> createState() => _CbctViewerScreenState();
}

class _CbctViewerScreenState extends ConsumerState<CbctViewerScreen> {
  final Stopwatch _clock = Stopwatch()..start();
  Uri? _url;
  String? _token;
  String? _error;
  bool _started = false;
  bool _opening = false;
  bool _shown = false;
  CbctStatus _status = const CbctStatus.missing();
  StreamSubscription<CbctStatus>? _sub;
  Directory? _packDir;
  Map<String, dynamic>? _meta;
  Color? _background;
  InAppWebViewController? _web;
  bool _saved = false;

  /// Asks the page to save fresh posters and its view state (it answers within
  /// 300 ms), then leaves. System back, Esc and the page's back button all end here.
  Future<void> _leave() async {
    if (!_saved) {
      _saved = true;
      try {
        await _web
            ?.callAsyncJavaScript(
              functionBody:
                  'if (window.CbctViewer) await window.CbctViewer.prepareClose();',
            )
            .timeout(const Duration(milliseconds: 600));
      } on Object {
        // Leaving anyway: the next open just starts from the older posters.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// "Anonymized" when the DICOM says the identity was removed, else "On this device".
  Future<String> _badge(RadStudy study, Directory packDir) async {
    try {
      final studyDir = packDir.parent.parent.path;
      final first = study.images.firstWhere((i) => i.kind == RadFileKind.dicom);
      final d = await DicomFile.load(File(p.join(studyDir, first.path)));
      if ((d.string(DicomTag.identityRemoved) ?? '').toUpperCase() == 'YES') {
        return 'Anonymized';
      }
    } on Object {
      // No readable header: the safe wording.
    }
    return 'On this device';
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    final token = _token;
    if (token != null) CbctServer.instance.revoke(token);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final study = await ref.read(radStudyProvider(widget.studyId).future);
      if (study == null) {
        throw CbctPackException('This study could not be found.');
      }
      unawaited(cbctPageBackground().then((c) => _background = c));
      final store = ref.read(cbctStoreProvider);
      final first = await store.refresh(study);
      if (first.state != CbctPackState.ready &&
          first.state != CbctPackState.failed) {
        store.enqueue(study, priority: true);
      }
      if (!mounted) return;
      _sub = store.watch(study).listen((s) => _onStatus(study, s));
      _onStatus(study, store.statusOf(study));
    } on CbctPackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      debugPrint('[cbct] open failed: $e');
      if (mounted) {
        setState(() => _error = 'The 3D viewer could not read this scan.');
      }
    }
  }

  void _onStatus(RadStudy study, CbctStatus s) {
    if (!mounted) return;
    setState(() {
      _status = s;
      if (s.state == CbctPackState.failed) {
        _error = s.failure ?? 'The 3D viewer could not read this scan.';
      }
    });
    if (s.state == CbctPackState.ready && !_opening) {
      _opening = true;
      unawaited(_open(study, s));
    }
  }

  Future<void> _open(RadStudy study, CbctStatus s) async {
    try {
      final dir = s.packDir!;
      final meta = s.meta!;
      debugPrint('[cbct] tap->pack ${_clock.elapsedMilliseconds} ms');
      final hasState = await File(p.join(dir.path, 'state.json')).exists();
      final opened = await CbctServer.instance.open(dir);
      if (!mounted) {
        CbctServer.instance.revoke(opened.token);
        return;
      }
      final device = CbctDevice.deviceClass(context);
      final reduced = MediaQuery.disableAnimationsOf(context);
      final badge = await _badge(study, dir);
      if (!mounted) return;
      setState(() {
        _token = opened.token;
        _packDir = dir;
        _meta = meta;
        _url = opened.page.replace(
          queryParameters: {
            'base': opened.base,
            'title': study.patientName.isNotEmpty
                ? study.patientName
                : study.description,
            'chip': _chip(study, meta),
            'badge': badge,
            'device': device.name,
            'first': hasState ? '0' : '1',
            'reduced': reduced ? '1' : '0',
          },
        );
      });
    } on Object catch (e) {
      debugPrint('[cbct] open failed: $e');
      if (mounted) {
        setState(() => _error = 'The 3D viewer could not read this scan.');
      }
    }
  }

  /// "CBCT · Maker Model · 22 Jul 2026 · 40 × 40 × 40 mm"
  String _chip(RadStudy study, Map<String, dynamic> meta) {
    final device = meta['device'] as Map<String, dynamic>? ?? const {};
    final maker = '${device['manufacturer'] ?? ''} ${device['model'] ?? ''}'
        .trim();
    final g = meta['geometry'] as Map<String, dynamic>;
    final dims = (g['dims'] as List).cast<num>();
    final sp = (g['spacing'] as List).cast<num>();
    final fov = [
      for (var i = 0; i < 3; i++) (dims[i] * sp[i]).round(),
    ].join(' × ');
    final kind = meta['kind'] as String? ?? 'dental';
    return [
      if (kind == 'dental') 'CBCT' else '3D viewer',
      if (maker.isNotEmpty) maker,
      RadFormat.date(study.studyDate),
      '$fov mm',
    ].join(' · ');
  }

  void _hidePosters() {
    if (mounted && !_shown) setState(() => _shown = true);
  }

  void _onMessage(List<dynamic> args) {
    final msg = args.isNotEmpty && args.first is Map
        ? args.first as Map
        : const {};
    switch (msg['type']) {
      case 'close':
        // The page already saved its state before posting this.
        _saved = true;
        unawaited(_leave());
      case 'shown':
        debugPrint('[cbct] tap->shown ${_clock.elapsedMilliseconds} ms');
        _hidePosters();
      case 'preview':
        debugPrint('[cbct] tap->preview ${_clock.elapsedMilliseconds} ms');
      case 'full':
        debugPrint('[cbct] tap->full ${_clock.elapsedMilliseconds} ms');
        _hidePosters();
      case 'snapshot':
        final dir = _packDir;
        if (dir != null && mounted) {
          unawaited(
            saveCbctSnapshot(
              context: context,
              ref: ref,
              studyId: widget.studyId,
              packDir: dir,
              file: '${msg['file'] ?? ''}',
              view: '${msg['view'] ?? ''}',
            ),
          );
        }
      case 'error':
        debugPrint('[cbct] viewer error: ${msg['message']}');
        _hidePosters();
        if (mounted) {
          setState(
            () =>
                _error = '${msg['message'] ?? 'The 3D viewer hit a problem.'}',
          );
        }
    }
  }

  /// Posters from an earlier pack of this scan, shown behind the label
  /// while it is rebuilt; null when there are none.
  Widget? _stalePosters() {
    final dir = _status.packDir;
    if (dir == null) return null;
    try {
      final f = File(p.join(dir.path, 'meta.json'));
      if (!f.existsSync()) return null;
      final meta = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      if (meta['posters'] is! Map || meta['geometry'] is! Map) return null;
      return CbctPosterLayer(
        packDir: dir,
        meta: meta,
        visible: true,
        background: _background,
      );
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (!CbctDevice.canOpen3d(context)) {
      return _shell(
        context,
        const RadNotConnected(
          icon: RadIcons.cube,
          title: '3D needs a tablet or computer',
          body:
              'This screen is too small for the 3D viewer. Page through the slices '
              'in the 2D viewer instead.',
        ),
      );
    }
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
    final error = _error;
    if (error != null) {
      return _shell(
        context,
        RadNotConnected(
          icon: RadIcons.cube,
          title: "Can't open the 3D viewer",
          body: error,
        ),
      );
    }
    final url = _url;
    if (url == null) {
      final packing =
          _status.state == CbctPackState.packing && _status.progress > 0;
      final pct = (_status.progress * 100).round();
      final stale = _stalePosters();
      return Scaffold(
        backgroundColor: c.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ?stale,
            Center(
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      packing
                          ? 'Preparing 3D · once per scan · $pct%'
                          : 'Preparing 3D · once per scan',
                      textAlign: TextAlign.center,
                      style: CruType.callout.tint(c.label2),
                    ),
                    const SizedBox(height: CruSpace.s12),
                    LinearProgressIndicator(
                      minHeight: 2,
                      value: packing ? _status.progress : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
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
                onWebViewCreated: (controller) {
                  _web = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'cbct',
                    callback: _onMessage,
                  );
                },
                onConsoleMessage: kDebugMode
                    ? (_, m) => debugPrint('[cbct web] ${m.message}')
                    : null,
              ),
              if (_packDir != null && _meta != null)
                CbctPosterLayer(
                  packDir: _packDir!,
                  meta: _meta!,
                  visible: !_shown,
                  background: _background,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A back button plus a message card, with a way into the 2D viewer.
  Widget _shell(BuildContext context, Widget card) {
    final c = context.cru;
    final study = ref.watch(radStudyProvider(widget.studyId)).value;
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
                  const Spacer(),
                  CruButton(
                    label: 'Read slices in 2D',
                    icon: RadIcons.xray,
                    onPressed: study == null
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => Theme(
                                data: Theme.of(context),
                                child: RadViewerScreen(
                                  studyId: widget.studyId,
                                  initialStudy: study,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.cardGap),
              card,
            ],
          ),
        ),
      ),
    );
  }
}

/// A CBCT volume: several slices, or one multi-frame file. Compressed files
/// count when they are JPEG 2000 / HTJ2K and this build can decode those.
///
/// Also accepts any CT or MR DICOM series with at least 30 slices (frames)
/// of equal pixel dimensions.
bool radIsVolume(RadStudy s) {
  // --- existing CBCT path ---
  if (s.modality.isVolume) {
    final readable = s.images
        .where((i) => !i.compressed || _decodableCompressed(i))
        .toList();
    return readable.length > 1 ||
        (readable.length == 1 && readable.first.frames > 1);
  }

  // --- CT / MR path: any DICOM series whose per-image modality tag is CT or MR ---
  final dicom = s.images.where((i) => i.kind == RadFileKind.dicom).toList();
  final ctOrMr = dicom.where((i) => i.dicomModality == 'CT' || i.dicomModality == 'MR');
  if (ctOrMr.isEmpty) return false;

  // Count total frames.
  final totalFrames = dicom.fold<int>(0, (n, i) => n + (i.frames < 1 ? 1 : i.frames));
  if (totalFrames < 30) return false;

  // All images with a known size must share the same dimensions.
  final sized = dicom.where((i) => i.width > 0 && i.height > 0).toList();
  if (sized.length > 1) {
    final w0 = sized.first.width, h0 = sized.first.height;
    if (sized.any((i) => i.width != w0 || i.height != h0)) return false;
  }

  return true;
}

bool _decodableCompressed(RadImageRef i) {
  if (!j2kSupported || i.kind != RadFileKind.dicom) return false;
  final ts = i.transferSyntax;
  return ts.startsWith('1.2.840.10008.1.2.4.9') ||
      ts.startsWith('1.2.840.10008.1.2.4.20');
}
