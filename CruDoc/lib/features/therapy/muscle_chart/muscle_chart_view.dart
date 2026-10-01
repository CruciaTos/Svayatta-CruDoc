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
    this.onFindingsChanged,
    this.onSelect,
    this.embed = false,
  });

  final List<MuscleFinding> findings;

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
  String _lastSynced = '';

  String _encode(List<MuscleFinding> f) =>
      jsonEncode([for (final x in f) x.toJson()]);

  Future<void> _push() async {
    final web = _web;
    if (web == null || !_ready) return;
    final json = _encode(widget.findings);
    if (json == _lastSynced) return;
    _lastSynced = json;
    await web.evaluateJavascript(source: 'MuscleChart.setFindings($json)');
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
    }
  }

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
        return InAppWebView(
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
          onConsoleMessage: kDebugMode
              ? (_, m) => debugPrint('[muscle viewer] ${m.message}')
              : null,
        );
      },
    );
  }
}
