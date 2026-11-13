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

/// Interactive 3D dental view (the web app in `assets/dental3d/`).
/// Embedded directly in cards or used inside [Dental3dScreen].
class Dental3dView extends ConsumerStatefulWidget {
  const Dental3dView({
    super.key,
    required this.patientId,
    this.patientName,
    this.showPlan = true,
    this.onToothSelected,
    this.onToothTapped,
    this.compact = false,
    this.selectedFdi,
  });

  final String patientId;
  final String? patientName;
  final bool showPlan;
  final ValueChanged<int?>? onToothSelected;

  /// A tap (not a drag) on a tooth in 3D: the host opens that tooth's form.
  final ValueChanged<int>? onToothTapped;
  final bool compact;
  final int? selectedFdi;

  @override
  ConsumerState<Dental3dView> createState() => _Dental3dViewState();
}

class _Dental3dViewState extends ConsumerState<Dental3dView> {
  Uri? _url;
  String? _token;
  String? _error;
  bool _started = false;
  bool _ready = false;
  InAppWebViewController? _web;
  Map<String, dynamic>? _snapshot;
  Timer? _saveTimer;
  Timer? _refreshTimer;
  Object? _pendingPersist;
  // The saved view state as last read or written, so a refresh does not wait
  // for the debounced write to reach disk.
  String? _savedJson;
  // The tooth the page currently has selected (what it told us last, or what
  // we told it), so our own selection is not echoed back and flown to again.
  int? _webFdi;

  String _key(String patientId) => 'dental3d.saved.$patientId';

  @override
  void dispose() {
    _saveTimer?.cancel();
    _refreshTimer?.cancel();
    if (_pendingPersist != null) unawaited(_flush(widget.patientId));
    final token = _token;
    if (token != null) Dental3dServer.instance.revoke(token);
    _web = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(Dental3dView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.patientId != oldWidget.patientId) {
      _restart(oldWidget.patientId);
      return;
    }
    if (widget.showPlan != oldWidget.showPlan) {
      unawaited(_updateSnapshot());
    }
    if (widget.selectedFdi != oldWidget.selectedFdi) {
      _selectToothInWeb(widget.selectedFdi);
    }
  }

  /// Another patient: save the old one's view, drop the page and start over.
  void _restart(String oldPatientId) {
    _saveTimer?.cancel();
    _refreshTimer?.cancel();
    if (_pendingPersist != null) unawaited(_flush(oldPatientId));
    final token = _token;
    if (token != null) Dental3dServer.instance.revoke(token);
    setState(() {
      _token = null;
      _url = null;
      _error = null;
      _web = null;
      _ready = false;
      _snapshot = null;
      _savedJson = null;
      _webFdi = null;
      _started = false;
    });
  }

  void _selectToothInWeb(int? fdi) {
    if (!_ready || fdi == _webFdi) return;
    _webFdi = fdi;
    final id = fdi == null ? null : 'tooth_$fdi';
    unawaited(_callWeb('window.App3DBridge.selectPart(id);', {'id': id}));
  }

  Future<void> _callWeb(String body, Map<String, dynamic> args) async {
    try {
      await _web?.callAsyncJavaScript(functionBody: body, arguments: args);
    } on Object catch (e) {
      // The view may have been closed while the call was in flight.
      debugPrint('[dental3d] web call failed: $e');
    }
  }

  /// The chart (and plan, when shown) as the page's snapshot, plus the saved view.
  Future<Map<String, dynamic>> _buildSnapshot() async {
    final entries = await ref.read(
      patientToothChartProvider(widget.patientId).future,
    );
    var plan = const <TreatmentPlanLineItemModel>[];
    if (widget.showPlan) {
      try {
        plan = await ref.read(
          patientTreatmentPlanProvider(widget.patientId).future,
        );
      } on Object {
        // The chart alone is still worth showing.
      }
    }
    var saved = _pendingPersist != null
        ? jsonEncode(_pendingPersist)
        : _savedJson;
    if (saved == null) {
      try {
        saved = (await SharedPreferences.getInstance()).getString(
          _key(widget.patientId),
        );
      } on Object {
        saved = null;
      }
    }
    _savedJson = saved;
    return buildDental3dSnapshot(entries, plan: plan, savedJson: saved);
  }

  /// Chart or plan changed (layer switch, a finding added): feed the page the
  /// new snapshot without reloading it.
  Future<void> _updateSnapshot() async {
    final patientId = widget.patientId;
    try {
      final snapshot = await _buildSnapshot();
      if (!mounted || patientId != widget.patientId) return;
      _snapshot = snapshot;
      if (_ready) {
        await _callWeb('window.App3DBridge.applyStateSnapshot(snapshot);', {
          'snapshot': snapshot,
        });
      }
    } on Object catch (e) {
      debugPrint('[dental3d] update snapshot failed: $e');
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_updateSnapshot()),
    );
  }

  Future<void> _load() async {
    final patientId = widget.patientId;
    try {
      // The page is bundled by the build; without it there is nothing to show.
      await rootBundle.load('assets/dental3d/index.html');
      final snapshot = await _buildSnapshot();
      final opened = await Dental3dServer.instance.open();
      if (!mounted || patientId != widget.patientId) {
        Dental3dServer.instance.revoke(opened.token);
        return;
      }
      _snapshot = snapshot;
      // app=1: the page hides its demo-patient picker (it would overwrite this
      // patient's chart); compact=1: no side panel (the card has its own).
      final uri = opened.page.replace(
        queryParameters: {
          'app': '1',
          if (widget.compact) 'compact': '1',
          if (Theme.of(context).brightness == Brightness.dark) 'theme': 'dark',
        },
      );
      setState(() {
        _token = opened.token;
        _url = uri;
      });
    } on Object catch (e) {
      debugPrint('[dental3d] open failed: $e');
      if (mounted && patientId == widget.patientId) {
        setState(() => _error = 'The 3D view could not be opened.');
      }
    }
  }

  Future<void> _flush(String patientId) async {
    final persist = _pendingPersist;
    _pendingPersist = null;
    if (persist == null) return;
    final json = jsonEncode(persist);
    _savedJson = json;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(patientId), json);
    } on Object catch (e) {
      debugPrint('[dental3d] save failed: $e');
    }
  }

  void _onMessage(List<dynamic> args) {
    if (!mounted) return;
    final msg = args.isNotEmpty && args.first is Map
        ? args.first as Map
        : const {};
    switch (msg['type']) {
      case 'READY':
        _ready = true;
        final snapshot = _snapshot;
        if (snapshot != null) {
          unawaited(
            _callWeb('window.App3DBridge.applyStateSnapshot(snapshot);', {
              'snapshot': snapshot,
            }),
          );
        }
        if (widget.selectedFdi != null) {
          _selectToothInWeb(widget.selectedFdi);
        }
      case 'PART_SELECTED':
        final payload = msg['payload'];
        final nodeId = payload is Map ? payload['nodeId']?.toString() : null;
        final fdi = payload is Map ? (payload['fdi'] as num?)?.toInt() : null;
        final tooth = nodeId != null && nodeId.startsWith('tooth_')
            ? fdi
            : null;
        _webFdi = tooth;
        widget.onToothSelected?.call(tooth);
      case 'TOOTH_TAPPED':
        final payload = msg['payload'];
        final fdi = payload is Map ? (payload['fdi'] as num?)?.toInt() : null;
        if (fdi != null) widget.onToothTapped?.call(fdi);
      case 'STATE_UPDATED':
        final payload = msg['payload'];
        if (payload is Map && payload['persist'] != null) {
          _pendingPersist = payload['persist'];
          _saveTimer?.cancel();
          final patientId = widget.patientId;
          _saveTimer = Timer(
            const Duration(milliseconds: 800),
            () => unawaited(_flush(patientId)),
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
    // A finding added or a plan item changed elsewhere: update the page in place.
    ref.listen(
      patientToothChartProvider(widget.patientId),
      (previous, next) => _scheduleRefresh(),
    );
    if (widget.showPlan) {
      ref.listen(
        patientTreatmentPlanProvider(widget.patientId),
        (previous, next) => _scheduleRefresh(),
      );
    }
    final error = _error;
    final url = _url;
    if (error != null) {
      return Center(
        child: Text(error, style: CruType.callout.tint(c.label2)),
      );
    }
    if (url == null) {
      return Center(
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
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(url)),
      initialSettings: InAppWebViewSettings(
        disableContextMenu: true,
        isInspectable: kDebugMode,
        supportZoom: false,
        // The page owns every drag: no rubber-banding or scrolling around it.
        disallowOverScroll: true,
        overScrollMode: OverScrollMode.NEVER,
      ),
      // A phone can drop the page's process under memory pressure (216k
      // triangles): reload, and the READY packet feeds it the snapshot again.
      onWebContentProcessDidTerminate: (controller) {
        _ready = false;
        controller.reload();
      },
      onRenderProcessGone: (controller, detail) {
        _ready = false;
        controller.reload();
      },
      // Keep drags and the wheel inside the viewer instead of scrolling.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
      onWebViewCreated: (controller) {
        _web = controller;
        _ready = false;
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
}

/// "Show the patient": the patient's teeth as an interactive 3D model (the
/// web page in `assets/dental3d/`) in a full-screen WebView, served over
/// loopback. [peekBuilder], when given, shows the picked tooth and the way
/// into it under the model (the card's picked-tooth panel).
class Dental3dScreen extends StatefulWidget {
  const Dental3dScreen({
    super.key,
    required this.patientId,
    this.patientName,
    this.showPlan = true,
    this.peekBuilder,
    this.onToothTapped,
  });

  final String patientId;
  final String? patientName;
  final bool showPlan;

  /// A tap (not a drag) on a tooth: the host opens that tooth's form.
  final ValueChanged<int>? onToothTapped;
  final Widget Function(int fdi)? peekBuilder;

  @override
  State<Dental3dScreen> createState() => _Dental3dScreenState();
}

class _Dental3dScreenState extends State<Dental3dScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final name = widget.patientName?.trim() ?? '';
    final peek = _selected;
    final peekBuilder = widget.peekBuilder;
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
            Expanded(
              child: Dental3dView(
                patientId: widget.patientId,
                patientName: widget.patientName,
                showPlan: widget.showPlan,
                compact: false,
                selectedFdi: _selected,
                onToothTapped: widget.onToothTapped,
                onToothSelected: peekBuilder == null
                    ? null
                    : (fdi) => setState(() => _selected = fdi),
              ),
            ),
            if (peekBuilder != null && peek != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s8,
                  CruSpace.s16,
                  CruSpace.s8,
                ),
                child: peekBuilder(peek),
              ),
          ],
        ),
      ),
    );
  }
}
