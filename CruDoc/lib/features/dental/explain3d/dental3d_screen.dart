import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/explain3d/dental3d_server.dart';
import 'package:doctor_management_app/features/dental/explain3d/dental3d_snapshot.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Show the patient": the patient's teeth as an interactive 3D model (the
/// web page in `assets/dental3d/`) in a full-screen WebView, served over
/// loopback. The page starts from the chart and hands back its view state,
/// which is kept on this device per patient.
class Dental3dScreen extends ConsumerStatefulWidget {
  const Dental3dScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<Dental3dScreen> createState() => _Dental3dScreenState();
}

class _Dental3dScreenState extends ConsumerState<Dental3dScreen> {
  Uri? _url;
  String? _token;
  String? _error;
  bool _started = false;
  InAppWebViewController? _web;
  Map<String, dynamic>? _snapshot;
  Timer? _saveTimer;
  Object? _pendingPersist;

  String get _key => 'dental3d.saved.${widget.patientId}';

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_pendingPersist != null) unawaited(_flush());
    final token = _token;
    if (token != null) Dental3dServer.instance.revoke(token);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // The page is bundled by the build; without it there is nothing to show.
      await rootBundle.load('assets/dental3d/index.html');
      final entries = await ref.read(
        patientToothChartProvider(widget.patientId).future,
      );
      var plan = const <TreatmentPlanLineItemModel>[];
      try {
        plan = await ref.read(
          patientTreatmentPlanProvider(widget.patientId).future,
        );
      } on Object {
        // The chart alone is still worth showing.
      }
      String? saved;
      try {
        saved = (await SharedPreferences.getInstance()).getString(_key);
      } on Object {
        saved = null;
      }
      _snapshot = buildDental3dSnapshot(entries, plan: plan, savedJson: saved);
      final opened = await Dental3dServer.instance.open();
      if (!mounted) {
        Dental3dServer.instance.revoke(opened.token);
        return;
      }
      setState(() {
        _token = opened.token;
        _url = opened.page;
      });
    } on Object catch (e) {
      debugPrint('[dental3d] open failed: $e');
      if (mounted) {
        setState(() => _error = 'The 3D view could not be opened.');
      }
    }
  }

  Future<void> _flush() async {
    final persist = _pendingPersist;
    _pendingPersist = null;
    if (persist == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(persist));
    } on Object catch (e) {
      debugPrint('[dental3d] save failed: $e');
    }
  }

  void _onMessage(List<dynamic> args) {
    final msg = args.isNotEmpty && args.first is Map
        ? args.first as Map
        : const {};
    switch (msg['type']) {
      case 'READY':
        final snapshot = _snapshot;
        if (snapshot != null) {
          unawaited(
            _web?.callAsyncJavaScript(
              functionBody:
                  'window.App3DBridge.applyStateSnapshot(snapshot);',
              arguments: {'snapshot': snapshot},
            ),
          );
        }
      case 'STATE_UPDATED':
        final payload = msg['payload'];
        if (payload is Map && payload['persist'] != null) {
          _pendingPersist = payload['persist'];
          _saveTimer?.cancel();
          _saveTimer = Timer(
            const Duration(milliseconds: 800),
            () => unawaited(_flush()),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
    final name = widget.patientName?.trim() ?? '';
    final error = _error;
    final url = _url;
    final Widget body;
    if (error != null) {
      body = Center(
        child: Text(error, style: CruType.callout.tint(c.label2)),
      );
    } else if (url == null) {
      body = Center(
        child: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Preparing 3D view',
                textAlign: TextAlign.center,
                style: CruType.callout.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
      );
    } else {
      body = InAppWebView(
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
          _web = controller;
          controller.addJavaScriptHandler(
            handlerName: 'dental3d',
            callback: _onMessage,
          );
        },
        onConsoleMessage: kDebugMode
            ? (_, m) => debugPrint('[dental3d web] ${m.message}')
            : null,
      );
    }
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s8,
                CruSpace.s4,
                CruSpace.s16,
                CruSpace.s4,
              ),
              child: Row(
                children: [
                  CruIconButton(
                    icon: CruIcons.chevronLeft,
                    semanticLabel: 'Back',
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Text(
                      name.isEmpty ? '3D view' : '3D view · $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.headline.tint(c.label),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
