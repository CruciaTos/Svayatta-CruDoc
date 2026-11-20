import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:doctor_management_app/features/therapy/muscle_chart/muscle_asset_server.dart';

/// One recorded problem on one muscle (one side).
@immutable
class MuscleFinding {
  const MuscleFinding({
    required this.id,
    this.status = 'affected',
    this.condition = '',
    this.pain = 0,
  });

  factory MuscleFinding.fromJson(Map<String, dynamic> j) => MuscleFinding(
    id: j['id'] as String,
    status: (j['status'] as String?) ?? 'affected',
    condition: (j['condition'] as String?) ?? '',
    pain: (j['pain'] as num?)?.toInt() ?? 0,
  );

  /// Model id, e.g. `m_supraspinatus_muscle_r` (side is part of the id).
  final String id;

  /// affected | improving | resolved
  final String status;
  final String condition;

  /// 0–10.
  final int pain;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'condition': condition,
    'pain': pain,
  };
}

/// Interactive 3D muscle chart (three.js in a WebView2 / WKWebView).
///
/// Drag to turn, scroll to zoom, click a muscle to select it and record a
/// finding. Anatomy, Focus (x-ray) and Isolate modes live in the viewer.
class MuscleChartView extends StatefulWidget {
  const MuscleChartView({
    super.key,
    required this.findings,
    this.highlight = const [],
    this.onFindingsChanged,
    this.onSelect,
    this.embed = false,
  });

  final List<MuscleFinding> findings;

  /// Muscles to light up, as side-neutral catalogue ids (no `_l`/`_r`), so
  /// one id lights both sides. Typically the muscles an exercise works, from
  /// `ExerciseDef.muscles`.
  ///
  /// While this is not empty the rest of the body is drawn see-through, so
  /// the highlight needs no colour of its own and cannot be mistaken for a
  /// clinical finding. A finding on a highlighted muscle still shows.
  final List<String> highlight;

  /// Every change the physio makes in the viewer, with the full list.
  final ValueChanged<List<MuscleFinding>>? onFindingsChanged;

  /// Selected muscle id, or null when cleared.
  final ValueChanged<String?>? onSelect;

  /// Hide the viewer's own side panel (when the host draws its own).
  final bool embed;

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  @override
  State<MuscleChartView> createState() => _MuscleChartViewState();
}

class _MuscleChartViewState extends State<MuscleChartView> {
  late final Future<Uri> _url = MuscleAssetServer.ensureStarted();
  InAppWebViewController? _web;
  bool _ready = false;
  String? _error;
  int _attempt = 0;
  String _lastSynced = '';
  String _lastHighlight = '';

  String _encode(List<MuscleFinding> f) =>
      jsonEncode([for (final x in f) x.toJson()]);

  Future<void> _push() async {
    final web = _web;
    if (web == null || !_ready) return;
    final json = _encode(widget.findings);
    if (json != _lastSynced) {
      _lastSynced = json;
      await web.evaluateJavascript(source: 'MuscleChart.setFindings($json)');
    }
    final lit = jsonEncode(widget.highlight);
    if (lit != _lastHighlight) {
      _lastHighlight = lit;
      await web.evaluateJavascript(source: 'MuscleChart.setHighlight($lit)');
    }
  }

  @override
  void didUpdateWidget(MuscleChartView old) {
    super.didUpdateWidget(old);
    _push();
  }

  void _onMessage(List<dynamic> args) {
    if (args.isEmpty || args.first is! Map) return;
    final msg = Map<String, dynamic>.from(args.first as Map);
    switch (msg['type']) {
      case 'ready':
        _ready = true;
        _push();
      case 'select':
        widget.onSelect?.call(msg['id'] as String?);
      case 'finding':
        final all = [
          for (final f in (msg['all'] as List? ?? const []))
            MuscleFinding.fromJson(Map<String, dynamic>.from(f as Map)),
        ];
        _lastSynced = _encode(all);
        widget.onFindingsChanged?.call(all);
      case 'error':
        debugPrint('Muscle chart: ${msg['message']}');
        _fail('${msg['message']}');
    }
  }

  /// Show a visible message instead of a blank box when the model can't load.
  void _fail(String why) {
    if (!mounted || _ready) return;
    setState(() => _error = why);
  }

  void _retry() => setState(() {
    _error = null;
    _ready = false;
    _web = null;
    _attempt++;
  });

  @override
  Widget build(BuildContext context) {
    if (!MuscleChartView.supported) {
      return const Center(child: Text('The 3D muscle chart is not available on this device.'));
    }
    return FutureBuilder<Uri>(
      future: _url,
      builder: (context, snap) {
        final base = snap.data;
        if (base == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final url = base.replace(
          path: '/index.html',
          query: widget.embed ? 'embed=1' : null,
        );
        if (_error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('The 3D muscle chart could not load.'),
                TextButton(onPressed: _retry, child: const Text('Try again')),
              ],
            ),
          );
        }
        return InAppWebView(
          key: ValueKey(_attempt),
          initialUrlRequest: URLRequest(url: WebUri.uri(url)),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            disableContextMenu: true,
            isInspectable: kDebugMode,
            supportZoom: false,
          ),
          // Keep drags and wheel inside the chart instead of scrolling the page.
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          onWebViewCreated: (c) {
            _web = c;
            c.addJavaScriptHandler(handlerName: 'muscleChart', callback: _onMessage);
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame ?? false) _fail(error.description);
          },
          onConsoleMessage: kDebugMode
              ? (_, m) => debugPrint('[muscle viewer] ${m.message}')
              : null,
        );
      },
    );
  }
}
