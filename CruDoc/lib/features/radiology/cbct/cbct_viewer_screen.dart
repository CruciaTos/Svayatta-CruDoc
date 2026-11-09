import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_server.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
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

  static bool get _platformSupported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  @override
  void dispose() {
    final token = _token;
    if (token != null) CbctServer.instance.revoke(token);
    super.dispose();
  }

  bool _tooSmall(BuildContext context) =>
      !_platformSupported || MediaQuery.sizeOf(context).shortestSide < 600;

  Future<void> _load() async {
    try {
      final study = await ref.read(radStudyProvider(widget.studyId).future);
      if (study == null) throw CbctPackException('This study could not be found.');
      final repo = ref.read(radiologyRepositoryProvider);
      final dir = await repo.studyDir(ref.read(radDoctorIdProvider), study.id);
      final pack = await ensureCbctPack(study: study, studyDir: dir);
      debugPrint('[cbct] tap->pack ${_clock.elapsedMilliseconds} ms');
      final opened = await CbctServer.instance.open(pack.dir);
      if (!mounted) {
        CbctServer.instance.revoke(opened.token);
        return;
      }
      setState(() {
        _token = opened.token;
        _url = opened.page.replace(
          queryParameters: {
            'base': opened.base,
            'title': study.patientName.isNotEmpty ? study.patientName : study.description,
            'chip': _chip(study, pack.meta),
          },
        );
      });
    } on CbctPackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      debugPrint('[cbct] open failed: $e');
      if (mounted) setState(() => _error = 'The 3D viewer could not read this scan.');
    }
  }

  /// "CBCT · Maker Model · 22 Jul 2026 · 40 × 40 × 40 mm"
  String _chip(RadStudy study, Map<String, dynamic> meta) {
    final device = meta['device'] as Map<String, dynamic>? ?? const {};
    final maker = '${device['manufacturer'] ?? ''} ${device['model'] ?? ''}'.trim();
    final g = meta['geometry'] as Map<String, dynamic>;
    final dims = (g['dims'] as List).cast<num>();
    final sp = (g['spacing'] as List).cast<num>();
    final fov = [for (var i = 0; i < 3; i++) (dims[i] * sp[i]).round()].join(' × ');
    return [
      'CBCT',
      if (maker.isNotEmpty) maker,
      RadFormat.date(study.studyDate),
      '$fov mm',
    ].join(' · ');
  }

  void _onMessage(List<dynamic> args) {
    final msg = args.isNotEmpty && args.first is Map ? args.first as Map : const {};
    switch (msg['type']) {
      case 'close':
        if (mounted) unawaited(Navigator.of(context).maybePop());
      case 'full':
        debugPrint('[cbct] tap->viewer ${_clock.elapsedMilliseconds} ms');
      case 'error':
        debugPrint('[cbct] viewer error: ${msg['message']}');
        if (mounted) setState(() => _error = '${msg['message'] ?? 'The 3D viewer hit a problem.'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (_tooSmall(context)) {
      return _shell(
        context,
        const RadNotConnected(
          icon: RadIcons.cube,
          title: '3D needs a tablet or computer',
          body: 'This screen is too small for the 3D viewer. Page through the slices '
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
        RadNotConnected(icon: RadIcons.cube, title: "Can't open the 3D viewer", body: error),
      );
    }
    final url = _url;
    if (url == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: Center(
          child: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Preparing 3D · once per scan',
                  textAlign: TextAlign.center,
                  style: CruType.callout.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s12),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(url)),
          initialSettings: InAppWebViewSettings(
            disableContextMenu: true,
            isInspectable: kDebugMode,
            supportZoom: false,
          ),
          // Keep drags and the wheel inside the viewer instead of scrolling.
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(handlerName: 'cbct', callback: _onMessage);
          },
          onConsoleMessage: kDebugMode ? (_, m) => debugPrint('[cbct web] ${m.message}') : null,
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

/// A CBCT volume: several slices, or one multi-frame file.
bool radIsVolume(RadStudy s) {
  if (!s.modality.isVolume) return false;
  final readable = s.images.where((i) => !i.compressed).toList();
  return readable.length > 1 ||
      (readable.length == 1 && readable.first.frames > 1);
}
