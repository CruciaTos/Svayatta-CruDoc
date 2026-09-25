import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/dictation.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/lesion_card.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_kit.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_share.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/report_workflow.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/study_context_panel.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/tooth_findings.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _SaveState { saved, pending, saving, failed }

enum _SectionAction { up, down, remove }

/// Viewer-preference keys the editor owns (panel width and visibility).
const _prefWidth = 'report.leftWidth';
const _prefOpen = 'report.leftOpen';
const _minPanel = 240.0;
const _maxPanel = 460.0;

/// One heading of the report being written.
class _Section {
  _Section(RadReportSection s)
      : title = TextEditingController(text: s.title),
        body = TextEditingController(text: s.body);

  final String key = radId('sec_');
  final TextEditingController title;
  final TextEditingController body;
  final FocusNode titleFocus = FocusNode();
  final FocusNode focus = FocusNode();

  void dispose() {
    title.dispose();
    body.dispose();
    titleFocus.dispose();
    focus.dispose();
  }
}

/// Writing the report for one study: the study beside it (key images,
/// measurements, exposure), the report in the middle (template, sections,
/// teeth, lesions, ceph values, impression), autosaved as a draft, then
/// marked preliminary, signed and sent.
class RadReportEditorScreen extends ConsumerStatefulWidget {
  const RadReportEditorScreen({super.key, required this.studyId});

  final String studyId;

  @override
  ConsumerState<RadReportEditorScreen> createState() => _RadReportEditorScreenState();
}

class _RadReportEditorScreenState extends ConsumerState<RadReportEditorScreen> {
  late final RadiologyController _rad = ref.read(radiologyProvider);

  /// The working copy; the text lives in the controllers until saved.
  RadReport? _report;

  /// Saved at least once (a new report isn't saved until it's touched).
  bool _persisted = false;

  /// updatedAt of the version held here, to spot changes made elsewhere
  /// (the viewer's "include in report").
  DateTime? _lastKnown;

  final _title = TextEditingController();
  final _technique = TextEditingController();
  final _impression = TextEditingController();
  final _recommendations = TextEditingController();
  final _impressionFocus = FocusNode();
  final _recommendationsFocus = FocusNode();
  final List<_Section> _sections = [];
  Map<String, String> _teeth = {};
  List<RadLesion> _lesions = [];
  List<String> _keyIds = [];
  List<String> _measureIds = [];
  Set<String> _knownKeys = {};

  Timer? _timer;
  Future<void>? _inFlight;
  bool _dirty = false;
  _SaveState _state = _SaveState.saved;
  DateTime? _savedAt;

  /// The field the mic is on.
  String? _dictating;
  double _panelWidth = 300;
  bool _panelOpen = true;
  bool _prefsRead = false;

  bool get _locked => _report?.isSigned ?? false;

  @override
  void dispose() {
    _timer?.cancel();
    if (_dirty && _report != null && !_locked) {
      // Leaving mid-edit: keep what was typed.
      unawaited(_rad.saveReport(_compose()));
    }
    for (final t in [_title, _technique, _impression, _recommendations]) {
      t.dispose();
    }
    _impressionFocus.dispose();
    _recommendationsFocus.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────── Loading ─────────────────────────────

  static String _defaultTitle(RadStudy s) {
    final q = s.clinicalQuestion.trim();
    return q.isEmpty ? '${s.modality.label} report' : '${s.modality.label} report — $q';
  }

  static int? _age(RadStudy s) {
    final dob = s.patientDob;
    if (dob == null) return null;
    final now = DateTime.now();
    var y = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) y--;
    return y;
  }

  /// Starts from the saved report, or a new one from the study type's
  /// first template (with every key image and measurement included).
  void _init(RadStudy s, RadReport? existing, List<RadTemplate> templates) {
    final RadReport r;
    if (existing != null) {
      r = existing;
      _persisted = true;
    } else {
      final now = DateTime.now();
      final t = templates.where((t) => t.modality == s.modality).firstOrNull;
      r = RadReport(
        id: radId('rep_'),
        studyId: s.id,
        patientId: s.patientId,
        templateId: t?.id ?? '',
        title: _defaultTitle(s),
        technique: t?.technique ?? '',
        sections: t == null || t.sections.isEmpty
            ? const [RadReportSection(title: 'Findings')]
            : t.sections,
        impression: t?.impression ?? '',
        keyImageIds: [for (final k in s.keyImages) k.id],
        measurementIds: [for (final m in radMeasurementRows(s)) m.id],
        createdAt: now,
        updatedAt: now,
      );
    }
    _report = r;
    _lastKnown = r.updatedAt;
    _title.text = r.title;
    _technique.text = r.technique;
    _impression.text = r.impression;
    _recommendations.text = r.recommendations;
    _sections.addAll(r.sections.map(_Section.new));
    _teeth = {...r.toothFindings};
    _lesions = [...r.lesions];
    _keyIds = [...r.keyImageIds];
    _measureIds = [...r.measurementIds];
    _knownKeys = {for (final k in s.keyImages) k.id};
    // Key images marked since the report was last saved are for it.
    if (existing != null && !existing.isSigned) {
      final fresh = [
        for (final k in s.keyImages)
          if (k.createdAt.isAfter(existing.updatedAt) && !_keyIds.contains(k.id)) k.id,
      ];
      if (fresh.isNotEmpty) {
        _keyIds.addAll(fresh);
        _markDirty();
      }
    }
  }

  // ───────────────────────────── Saving ─────────────────────────────

  RadReport _compose() => _report!.copyWith(
        title: _title.text.trim(),
        technique: _technique.text.trim(),
        sections: [
          for (final s in _sections)
            RadReportSection(title: s.title.text.trim(), body: s.body.text.trim()),
        ],
        impression: _impression.text.trim(),
        recommendations: _recommendations.text.trim(),
        toothFindings: {..._teeth},
        lesions: [..._lesions],
        keyImageIds: [..._keyIds],
        measurementIds: [..._measureIds],
      );

  /// Marks unsaved edits and restarts the autosave timer. Doesn't rebuild
  /// (safe to call while building).
  void _markDirty() {
    if (_locked) return;
    _dirty = true;
    _state = _SaveState.pending;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1200), _save);
  }

  /// A keystroke: rebuilds only when the save status line changes.
  void _changed() {
    final was = _state;
    _markDirty();
    if (was != _SaveState.pending && mounted) setState(() {});
  }

  /// Saves now, after any save still running (so an audited status change
  /// never races an autosave).
  Future<void> _save({String? audit}) {
    _timer?.cancel();
    final prev = _inFlight;
    Future<void> run() async {
      if (prev != null) await prev;
      await _write(audit);
    }

    final next = run();
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
  }

  Future<void> _write(String? audit) async {
    if (_report == null || !mounted) return;
    final r = _compose();
    _report = r;
    _lastKnown = r.updatedAt;
    _dirty = false;
    setState(() => _state = _SaveState.saving);
    try {
      await _rad.saveReport(r, auditAction: audit ?? (_persisted ? null : 'Started report'));
      _persisted = true;
      _savedAt = DateTime.now();
      if (mounted) setState(() => _state = _dirty ? _SaveState.pending : _SaveState.saved);
    } catch (_) {
      _dirty = true;
      if (mounted) setState(() => _state = _SaveState.failed);
    }
  }

  Future<void> _leave() async {
    if (_dirty) await _save();
    if (mounted) Navigator.of(context).pop();
  }

  /// Controllers still attached to fields on screen are let go after the
  /// frame that removes them.
  void _disposeLater(Iterable<_Section> gone) {
    final list = gone.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final s in list) {
        s.dispose();
      }
    });
  }

  // ───────────────────────────── Workflow ─────────────────────────────

  String _me() {
    final s = ref.read(radSettingsProvider).value;
    if (s != null && s.signatureName.trim().isNotEmpty) return s.signatureName.trim();
    return ref.read(doctorIdentityProvider).fullName ?? '';
  }

  /// Moves the report on and keeps a copy of it in the history.
  Future<void> _setStatus(
    RadReportStatus status, {
    required String audit,
    required String by,
    DateTime? signedAt,
    String? signedBy,
  }) async {
    final now = DateTime.now();
    final base = _compose();
    setState(() {
      _report = base.copyWith(
        status: status,
        signedAt: signedAt,
        signedBy: signedBy,
        versions: [
          ...base.versions,
          RadReportVersion(at: now, status: status, snapshot: base.toPlainText(), by: by),
        ],
      );
      _dictating = null;
    });
    await _save(audit: audit);
  }

  Future<void> _markPreliminary() =>
      _setStatus(RadReportStatus.preliminary, audit: 'Marked preliminary', by: _me());

  Future<void> _sign() async {
    if (_impression.text.trim().isEmpty) {
      radToast(context, 'Write the impression before signing.');
      _impressionFocus.requestFocus();
      return;
    }
    final sig = await showRadSignDialog(context);
    if (sig == null || !mounted) return;
    final now = DateTime.now();
    await _setStatus(
      RadReportStatus.finalised,
      audit: 'Signed report',
      by: sig.signatureName,
      signedAt: now,
      signedBy: sig.signatureName,
    );
  }

  Future<void> _addendum() async {
    final text = await showRadAddendumDialog(context);
    if (text == null || !mounted) return;
    final by = _me();
    final now = DateTime.now();
    final r = _report!;
    final withText = r.copyWith(addenda: [...r.addenda, RadAddendum(at: now, text: text, by: by)]);
    setState(() {
      _report = withText.copyWith(versions: [
        ...withText.versions,
        RadReportVersion(
          at: now,
          status: withText.status,
          snapshot: withText.toPlainText(),
          by: by,
        ),
      ]);
    });
    await _save(audit: 'Added addendum');
    if (mounted && _report!.sharedAt != null) {
      radToast(context, 'Addendum added. Send the report again so the referrer has it.');
    }
  }

  Future<void> _share(RadStudy s, RadReferrer? referrer) async {
    if (_dirty) await _save();
    if (!mounted) return;
    await showRadShareDialog(
      context,
      study: s,
      report: _compose(),
      referrer: referrer,
      onShared: (via) async {
        if (!mounted) return;
        setState(() => _report = _report!.copyWith(sharedAt: DateTime.now(), sharedVia: via));
        await _save(audit: 'Sent by $via');
      },
    );
  }

  Future<void> _applyTemplate(RadTemplate t) async {
    final hasText = _technique.text.trim().isNotEmpty ||
        _impression.text.trim().isNotEmpty ||
        _sections.any((s) => s.body.text.trim().isNotEmpty);
    if (hasText) {
      final ok = await confirmDental(
        context,
        title: 'Switch to ${t.name}?',
        body: "Technique, sections and impression take the template's wording. The title, "
            'teeth, lesions and recommendations stay.',
        action: 'Switch',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _report = _report!.copyWith(templateId: t.id);
      _technique.text = t.technique;
      _impression.text = t.impression;
      _disposeLater(_sections);
      _sections
        ..clear()
        ..addAll((t.sections.isEmpty ? const [RadReportSection(title: 'Findings')] : t.sections)
            .map(_Section.new));
      _dictating = null;
      _markDirty();
    });
  }

  void _addSection() {
    final s = _Section(const RadReportSection(title: ''));
    setState(() {
      _sections.add(s);
      _markDirty();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => s.titleFocus.requestFocus());
  }

  Future<void> _sectionAction(int i, _SectionAction a) async {
    switch (a) {
      case _SectionAction.up:
      case _SectionAction.down:
        final to = a == _SectionAction.up ? i - 1 : i + 1;
        if (to < 0 || to >= _sections.length) return;
        setState(() {
          _sections.insert(to, _sections.removeAt(i));
          _markDirty();
        });
      case _SectionAction.remove:
        final s = _sections[i];
        if (s.body.text.trim().isNotEmpty) {
          final ok = await confirmDental(
            context,
            title: 'Remove ${s.title.text.trim().isEmpty ? 'this section' : s.title.text.trim()}?',
            body: 'The section and what you wrote in it are taken out of the report.',
            action: 'Remove',
          );
          if (!ok || !mounted) return;
        }
        setState(() {
          _sections.remove(s);
          if (_dictating == s.key) _dictating = null;
          _markDirty();
        });
        _disposeLater([s]);
    }
  }

  void _toggleDictation(String id, FocusNode focus) {
    setState(() => _dictating = _dictating == id ? null : id);
    if (_dictating == id) focus.requestFocus();
  }

  bool _hasAcceptedAiFindings(RadStudy study) {
    for (final read in study.aiReads) {
      final list = (read['findings'] as List?) ?? const [];
      for (final f in list) {
        if (f is Map && f['status'] == 'accepted') return true;
      }
    }
    return false;
  }

  void _addAcceptedAiFindings(RadStudy study) {
    final toothPattern = RegExp(r'\b(1[1-8]|2[1-8]|3[1-8]|4[1-8]|5[1-5]|6[1-5]|7[1-5]|8[1-5])\b');
    final updatedTeeth = Map<String, String>.from(_teeth);
    final generalFindings = <String>[];

    for (final read in study.aiReads) {
      final list = (read['findings'] as List?) ?? const [];
      for (final f in list) {
        if (f is Map && f['status'] == 'accepted') {
          final label = (f['label'] as String? ?? '').trim();
          if (label.isEmpty) continue;
          final match = toothPattern.firstMatch(label);
          if (match != null) {
            final tooth = match.group(1)!;
            final existing = updatedTeeth[tooth];
            final text = '$label (AI-assisted, confirmed)';
            if (existing != null && existing.isNotEmpty) {
              if (!existing.contains(label)) {
                updatedTeeth[tooth] = '$existing; $text';
              }
            } else {
              updatedTeeth[tooth] = text;
            }
          } else {
            generalFindings.add('$label (AI-assisted, confirmed)');
          }
        }
      }
    }

    setState(() {
      _teeth = updatedTeeth;
      if (generalFindings.isNotEmpty) {
        _Section? findingsSec;
        for (final s in _sections) {
          if (s.title.text.trim().toLowerCase() == 'findings') {
            findingsSec = s;
            break;
          }
        }
        if (findingsSec == null) {
          findingsSec = _Section(RadReportSection(title: 'Findings', body: ''));
          _sections.add(findingsSec);
        }
        final existingBody = findingsSec.body.text.trim();
        final addition = generalFindings.join('\n');
        findingsSec.body.text = existingBody.isEmpty ? addition : '$existingBody\n$addition';
      }
      _markDirty();
    });
    if (mounted) {
      radToast(context, 'Accepted AI findings added to report');
    }
  }

  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    unawaited(_rad.saveViewerPrefs({_prefOpen: _panelOpen}));
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final studyAsync = ref.watch(radStudyProvider(widget.studyId));
    final reportsAsync = ref.watch(radReportsProvider);
    final templatesAsync = ref.watch(radTemplatesProvider);
    final settingsAsync = ref.watch(radSettingsProvider);
    final phrases = ref.watch(radPhrasesProvider).value ?? const <RadPhrase>[];
    final referrers = ref.watch(radReferrerByIdProvider);

    // A change made elsewhere (the viewer ticking "include in report")
    // updates the two lists it can touch.
    ref.listen<RadReport?>(radReportForStudyProvider(widget.studyId), (_, next) {
      final known = _lastKnown;
      if (next == null || _report == null || known == null) return;
      if (!next.updatedAt.isAfter(known)) return;
      setState(() {
        _lastKnown = next.updatedAt;
        _keyIds = [...next.keyImageIds];
        _measureIds = [...next.measurementIds];
      });
    });

    final study = studyAsync.value;
    if (_report == null) {
      final ready = studyAsync.hasValue &&
          reportsAsync.hasValue &&
          (templatesAsync.hasValue || templatesAsync.hasError);
      if (!ready) return _shell(c, Text('Opening the report…', style: CruType.subhead.tint(c.label3)));
      if (study == null) {
        return _shell(
          c,
          DentalEmptyState(
            icon: RadIcons.report,
            title: "This study isn't here any more",
            body: 'It may have been deleted from the worklist.',
            actions: [
              CruButton(label: 'Back', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        );
      }
      _init(
        study,
        ref.read(radReportForStudyProvider(widget.studyId)),
        templatesAsync.value ?? const <RadTemplate>[],
      );
    }
    if (study == null) {
      return _shell(c, Text('Opening the report…', style: CruType.subhead.tint(c.label3)));
    }

    final settings = settingsAsync.value ?? const RadSettings();
    if (!_prefsRead && settingsAsync.hasValue) {
      _prefsRead = true;
      final w = settings.viewer[_prefWidth];
      if (w is num) _panelWidth = w.toDouble().clamp(_minPanel, _maxPanel);
      _panelOpen = settings.viewer[_prefOpen] != false;
    }

    // Key images marked while the report is open go into it.
    final newKeys = [
      for (final k in study.keyImages)
        if (!_knownKeys.contains(k.id)) k.id,
    ];
    if (newKeys.isNotEmpty) {
      _knownKeys.addAll(newKeys);
      if (!_locked) {
        _keyIds = [..._keyIds, ...newKeys.where((id) => !_keyIds.contains(id))];
        _markDirty();
      }
    }

    final referrer = referrers[study.referrerId];
    final rows = radMeasurementRows(study);
    final templates = templatesAsync.value ?? const <RadTemplate>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!_locked) _save();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: c.canvas,
            body: Column(
              children: [
                _topBar(c, study, referrer),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_panelOpen) ...[
                        SizedBox(
                          width: _panelWidth,
                          child: ColoredBox(
                            color: c.surface,
                            child: RadStudyContextPanel(
                              study: study,
                              referrer: referrer,
                              rows: rows,
                              keyImageIds: _keyIds,
                              measurementIds: _measureIds,
                              readOnly: _locked,
                              onToggleKeyImage: (id) => setState(() {
                                _keyIds = _keyIds.contains(id)
                                    ? _keyIds.where((e) => e != id).toList()
                                    : [..._keyIds, id];
                                _markDirty();
                              }),
                              onToggleMeasurement: (id) => setState(() {
                                _measureIds = _measureIds.contains(id)
                                    ? _measureIds.where((e) => e != id).toList()
                                    : [..._measureIds, id];
                                _markDirty();
                              }),
                              onIncludeAllMeasurements: () => setState(() {
                                _measureIds = {..._measureIds, ...rows.map((r) => r.id)}.toList();
                                _markDirty();
                              }),
                              onOpenViewer: (imageId) =>
                                  openRadStudy(context, ref, study, imageId: imageId),
                            ),
                          ),
                        ),
                        _Resizer(
                          onDrag: (dx) => setState(
                            () => _panelWidth = (_panelWidth + dx).clamp(_minPanel, _maxPanel),
                          ),
                          onEnd: () => _rad.saveViewerPrefs({_prefWidth: _panelWidth}),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  CruSpace.s32,
                                  CruSpace.s24,
                                  CruSpace.s32,
                                  CruSpace.s32,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 880),
                                    child: _document(c, study, referrer, settings, templates,
                                        phrases, rows),
                                  ),
                                ),
                              ),
                            ),
                            _footer(c),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Loading and missing-study frame: a back button and a message.
  Widget _shell(CruColors c, Widget child) => Scaffold(
        backgroundColor: c.canvas,
        body: Stack(
          children: [
            Center(child: child),
            Positioned(
              left: CruSpace.s16,
              top: CruSpace.s12,
              child: CruIconButton(
                icon: CruIcons.chevronLeft,
                size: CruSize.control,
                semanticLabel: 'Back',
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      );

  Widget _topBar(CruColors c, RadStudy s, RadReferrer? referrer) {
    final line = [
      RadFormat.patientLine(s, DateTime.now()),
      RadFormat.date(s.studyDate),
      if (referrer != null) 'from ${referrer.name}',
    ].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          CruIconButton(
            icon: CruIcons.chevronLeft,
            size: CruSize.control,
            semanticLabel: 'Back',
            tooltip: 'Back',
            onPressed: _leave,
          ),
          const SizedBox(width: CruSpace.s4),
          CruIconButton(
            icon: CruIcons.sidebar,
            size: CruSize.control,
            iconSize: 18,
            semanticLabel: _panelOpen ? 'Hide study panel' : 'Show study panel',
            tooltip: _panelOpen ? 'Hide study panel' : 'Show study panel',
            onPressed: _togglePanel,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.patientName.isEmpty ? 'Unnamed patient' : s.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.headline.tint(c.label),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    RadModalityBadge(s.modality),
                  ],
                ),
                if (line.isNotEmpty)
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          _saveStatus(c),
          const SizedBox(width: CruSpace.s16),
          _CriticalButton(
            critical: s.critical,
            onPressed: () => showRadCriticalDialog(context, studyId: s.id, referrer: referrer),
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(
            label: 'History',
            icon: RadIcons.history,
            kind: CruButtonKind.secondary,
            onPressed: () => showRadVersionHistory(context, _report!),
          ),
          const SizedBox(width: CruSpace.s8),
          // Same place in every state; the one filled action once signed.
          CruButton(
            label: 'Share',
            icon: RadIcons.share,
            kind: _locked ? CruButtonKind.primary : CruButtonKind.secondary,
            onPressed: () => _share(s, referrer),
          ),
        ],
      ),
    );
  }

  Widget _saveStatus(CruColors c) {
    if (_locked) return const SizedBox.shrink();
    return switch (_state) {
      _SaveState.failed => CruLink(
          label: "Couldn't save · Retry",
          color: c.amberText,
          onPressed: _save,
        ),
      _SaveState.saving => Text('Saving…', style: CruType.caption.tint(c.label3)),
      _SaveState.pending => Text('Unsaved changes', style: CruType.caption.tint(c.label3)),
      _SaveState.saved => Text(
          _persisted
              ? 'Saved ${RadFormat.time(_savedAt ?? _report!.updatedAt)}'
              : 'Saves as you type',
          style: CruType.caption.tabular.tint(c.label3),
        ),
    };
  }

  Widget _footer(CruColors c) {
    final r = _report!;
    final text = switch (r.status) {
      RadReportStatus.draft => 'Saves as you type. Ctrl + S saves now.',
      RadReportStatus.preliminary => 'Preliminary: still editable. Sign it when final.',
      RadReportStatus.finalised => '${[
          'Signed',
          if (r.signedBy.isNotEmpty) 'by ${r.signedBy}',
          if (r.signedAt != null) RadFormat.dateTime(r.signedAt!),
        ].join(' ')}. Locked; an addendum adds to it.',
    };
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s24),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          radReportStatusPill(c, r.status),
          const SizedBox(width: CruSpace.s10),
          if (_locked) ...[
            CruIcon(RadReportIcons.lock, size: 15, strokeWidth: 1.9, color: c.label3),
            const SizedBox(width: CruSpace.s6),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          if (r.status == RadReportStatus.draft) ...[
            CruButton(
              label: 'Mark preliminary',
              kind: CruButtonKind.inset,
              onPressed: _markPreliminary,
            ),
            const SizedBox(width: CruSpace.s10),
          ],
          if (!_locked)
            CruButton(
              label: 'Sign & finalise',
              icon: RadIcons.signature,
              onPressed: _sign,
            )
          else
            CruButton(
              label: 'Add addendum',
              icon: RadReportIcons.addendum,
              kind: CruButtonKind.inset,
              onPressed: _addendum,
            ),
        ],
      ),
    );
  }

  Widget _document(
    CruColors c,
    RadStudy study,
    RadReferrer? referrer,
    RadSettings settings,
    List<RadTemplate> templates,
    List<RadPhrase> phrases,
    List<({String id, String label, String value})> rows,
  ) {
    final r = _report!;
    final locked = _locked;
    final age = _age(study);
    final included = [
      for (final m in rows)
        if (_measureIds.contains(m.id)) m,
    ];
    final ceph = radCephTables(study);

    Widget mic(String id, FocusNode focus) => RadDictationButton(
          active: _dictating == id,
          onPressed: () => _toggleDictation(id, focus),
        );

    final blocks = <Widget>[
      if (!locked || r.technique.trim().isNotEmpty)
        RadBlock(
          title: const Text('Technique'),
          child: RadTextArea(
            controller: _technique,
            phrases: phrases,
            readOnly: locked,
            minLines: 1,
            hint: 'Field of view, voxel size, exposure, reconstructions reviewed',
            onChanged: _changed,
          ),
        ),
      for (var i = 0; i < _sections.length; i++)
        if (!locked || _sections[i].body.text.trim().isNotEmpty)
          _sectionBlock(c, i, phrases, mic),
      if (!locked)
        Padding(
          padding: const EdgeInsets.only(bottom: CruSpace.s8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CruCapsuleButton(label: 'Add section', icon: CruIcons.plus, onPressed: _addSection),
          ),
        ),
      if (!locked || _teeth.isNotEmpty)
        RadBlock(
          title: const Text('Teeth'),
          trailing: [
            if (!locked && _hasAcceptedAiFindings(study))
              CruCapsuleButton(
                label: 'Add accepted AI findings',
                icon: CruIcons.sparkle,
                onPressed: () => _addAcceptedAiFindings(study),
              ),
          ],
          child: RadToothFindings(
            findings: _teeth,
            readOnly: locked,
            childDefault: age != null && age < 12,
            phrases: phrases,
            onChanged: (m) => setState(() {
              _teeth = m;
              _markDirty();
            }),
          ),
        ),
      if (!locked || _lesions.isNotEmpty)
        RadBlock(
          title: const Text('Lesions'),
          caption: _lesions.isEmpty && !locked
              ? 'Describe each lesion with the standard checklist: location, size, shape, '
                  'borders, internal structure and effects.'
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _lesions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s12),
                  child: RadLesionCard(
                    key: ValueKey(_lesions[i].id),
                    index: i,
                    lesion: _lesions[i],
                    readOnly: locked,
                    phrases: phrases,
                    showAiDifferential: !locked && settings.ai('differential'),
                    onChanged: (l) {
                      final at = _lesions.indexWhere((e) => e.id == l.id);
                      if (at >= 0) _lesions[at] = l;
                      _changed();
                    },
                    onRemove: () => _removeLesion(_lesions[i]),
                  ),
                ),
              if (!locked)
                Align(
                  alignment: Alignment.centerLeft,
                  child: CruCapsuleButton(
                    label: 'Add lesion',
                    icon: CruIcons.plus,
                    onPressed: () => setState(() {
                      _lesions = [..._lesions, RadLesion(id: radId('les_'))];
                      _markDirty();
                    }),
                  ),
                ),
            ],
          ),
        ),
      if (included.isNotEmpty)
        RadBlock(
          title: const Text('Measurements'),
          caption: locked ? null : 'Choose which go in the report in the study panel.',
          child: Column(
            children: [
              for (var i = 0; i < included.length; i++) ...[
                if (i > 0) const CruSeparator(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
                  child: Row(
                    children: [
                      Expanded(child: Text(included[i].label, style: CruType.note.tint(c.label))),
                      const SizedBox(width: CruSpace.s12),
                      Text(included[i].value, style: CruType.callout.tabular.tint(c.label)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      for (final t in ceph)
        RadBlock(
          title: Text(t.analysis.isEmpty
              ? 'Cephalometric analysis'
              : 'Cephalometric analysis · ${t.analysis}'),
          caption: 'From the ceph tracing. Amber: more than one standard deviation from the norm.',
          child: _CephTableView(t),
        ),
      RadBlock(
        title: const Text('Impression'),
        trailing: locked ? const [] : [mic('impression', _impressionFocus)],
        child: RadTextArea(
          controller: _impression,
          focusNode: _impressionFocus,
          phrases: phrases,
          readOnly: locked,
          style: CruType.note.w500,
          hint: 'The answer to the clinical question, in a sentence or two',
          onChanged: _changed,
          below: _dictating == 'impression' ? const RadDictationNote() : null,
        ),
      ),
      if (!locked || r.recommendations.trim().isNotEmpty)
        RadBlock(
          title: const Text('Recommendations'),
          trailing: locked ? const [] : [mic('recommendations', _recommendationsFocus)],
          child: RadTextArea(
            controller: _recommendations,
            focusNode: _recommendationsFocus,
            phrases: phrases,
            readOnly: locked,
            minLines: 1,
            hint: 'Further imaging, referral or follow-up',
            onChanged: _changed,
            below: _dictating == 'recommendations' ? const RadDictationNote() : null,
          ),
        ),
      if (r.addenda.isNotEmpty)
        RadBlock(
          title: const Text('Addenda'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in r.addenda)
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [RadFormat.dateTime(a.at), if (a.by.isNotEmpty) a.by].join(' · '),
                        style: CruType.caption.tabular.tint(c.label3),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      SelectableText(a.text, style: CruType.note.tint(c.label)),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];

    return CruCard(
      semanticLabel: 'Report',
      padding: const EdgeInsets.fromLTRB(CruSpace.s32, CruSpace.s24, CruSpace.s32, CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (study.critical) ...[
            _criticalStrip(c, study, referrer),
            const SizedBox(height: CruSpace.s16),
          ],
          if (!locked) ...[
            Row(
              children: [
                _templatePicker(c, study, templates),
                const Spacer(),
                if (settings.ai('draft'))
                  const RadAiPending(
                    label: 'Draft with AI',
                    explain: 'Writes a first draft from the images and your measurements '
                        'for you to edit.',
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
          ],
          if (locked)
            SelectableText(
              r.title.isEmpty ? '${study.modality.label} report' : r.title,
              style: CruType.title.tint(c.label),
            )
          else
            TextField(
              controller: _title,
              style: CruType.title.tint(c.label),
              cursorColor: c.accent,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _changed(),
              decoration: InputDecoration.collapsed(
                hintText: 'Report title',
                hintStyle: CruType.title.tint(c.label3),
              ),
            ),
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0 && blocks[i] is RadBlock && blocks[i - 1] is RadBlock) const CruSeparator(),
            blocks[i],
          ],
        ],
      ),
    );
  }

  Future<void> _removeLesion(RadLesion l) async {
    final written = [l.location, l.sizeMm, l.shape, l.borders, l.internal, l.effects, l.notes]
        .any((e) => e.trim().isNotEmpty);
    if (written) {
      final ok = await confirmDental(
        context,
        title: 'Remove this lesion?',
        body: 'Its description is taken out of the report.',
        action: 'Remove',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _lesions = _lesions.where((e) => e.id != l.id).toList();
      _markDirty();
    });
  }

  Widget _sectionBlock(
    CruColors c,
    int i,
    List<RadPhrase> phrases,
    Widget Function(String id, FocusNode focus) mic,
  ) {
    final s = _sections[i];
    final locked = _locked;
    return RadBlock(
      key: ValueKey(s.key),
      title: locked
          ? Text(s.title.text.trim().isEmpty ? 'Findings' : s.title.text.trim())
          : TextField(
              controller: s.title,
              focusNode: s.titleFocus,
              style: CruType.headline.tint(c.label),
              cursorColor: c.accent,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _changed(),
              decoration: InputDecoration.collapsed(
                hintText: 'Heading',
                hintStyle: CruType.headline.tint(c.label3),
              ),
            ),
      trailing: locked
          ? const []
          : [
              mic(s.key, s.focus),
              PopupMenuButton<_SectionAction>(
                tooltip: 'Section',
                onSelected: (a) => _sectionAction(i, a),
                color: c.surface,
                shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
                itemBuilder: (_) => [
                  radMenuItem(c, _SectionAction.up, 'Move up', enabled: i > 0),
                  radMenuItem(c, _SectionAction.down, 'Move down',
                      enabled: i < _sections.length - 1),
                  radMenuItem(c, _SectionAction.remove, 'Remove section'),
                ],
                child: SizedBox(
                  width: CruSize.rowCapsule,
                  height: CruSize.rowCapsule,
                  child: Center(child: CruIcon(CruIcons.more, size: 16, color: c.label3)),
                ),
              ),
            ],
      child: RadTextArea(
        controller: s.body,
        focusNode: s.focus,
        phrases: phrases,
        readOnly: locked,
        hint: 'What the scan shows. Type a shortcut like .sinus and a space.',
        onChanged: _changed,
        below: _dictating == s.key ? const RadDictationNote() : null,
      ),
    );
  }

  Widget _templatePicker(CruColors c, RadStudy study, List<RadTemplate> templates) {
    final current = templates.where((t) => t.id == _report!.templateId).firstOrNull;
    final ordered = [
      ...templates.where((t) => t.modality == study.modality),
      ...templates.where((t) => t.modality != study.modality),
    ];
    return PopupMenuButton<RadTemplate>(
      tooltip: 'Template',
      enabled: ordered.isNotEmpty,
      onSelected: _applyTemplate,
      color: c.surface,
      shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
      itemBuilder: (_) => [
        for (final t in ordered)
          radMenuItem(
            c,
            t,
            t.modality == study.modality ? t.name : '${t.name} · ${t.modality.short}',
          ),
      ],
      child: Container(
        height: CruSize.control,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(color: c.inset, shape: cruShape(CruRadius.control)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(RadIcons.template, size: 16, strokeWidth: 1.9, color: c.label3),
            const SizedBox(width: CruSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                current?.name ?? 'No template',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.subhead.w500.tint(c.label),
              ),
            ),
            const SizedBox(width: CruSpace.s6),
            CruIcon(CruIcons.chevronDown, size: 14, color: c.label3),
          ],
        ),
      ),
    );
  }

  Widget _criticalStrip(CruColors c, RadStudy s, RadReferrer? referrer) {
    final told = s.criticalLog.isEmpty ? null : s.criticalLog.last;
    return Container(
      padding: const EdgeInsets.fromLTRB(CruSpace.s14, CruSpace.s10, CruSpace.s10, CruSpace.s10),
      decoration: ShapeDecoration(color: c.redTint, shape: cruShape(CruRadius.control)),
      child: Row(
        children: [
          CruIcon(RadIcons.flag, size: 16, strokeWidth: 2, color: c.redText),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Text(
              told == null
                  ? 'Critical finding · the referrer has not been told yet'
                  : 'Critical finding · told ${RadFormat.dateTime(told.at)}'
                      '${told.contacted.isEmpty ? '' : ' (${told.contacted})'}',
              style: CruType.subhead.w600.tabular.tint(c.redText),
            ),
          ),
          CruCapsuleButton(
            label: told == null ? 'Tell the referrer' : 'Open',
            kind: CruCapsuleKind.surface,
            onPressed: () => showRadCriticalDialog(context, studyId: s.id, referrer: referrer),
          ),
        ],
      ),
    );
  }
}

/// Flag critical (quiet) or Critical (red: patient safety) in the top bar.
class _CriticalButton extends StatelessWidget {
  const _CriticalButton({required this.critical, required this.onPressed});

  final bool critical;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = critical ? c.redText : c.label;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: critical ? 'Critical finding' : 'Flag a critical finding',
      tooltip: critical ? 'Critical finding: tell the referrer' : 'Flag a critical finding',
      builder: (context, hovered) {
        final fill = critical ? c.redTint : c.surface;
        return AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.control,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(fill, c) : fill,
            shape: cruShape(
              CruRadius.control,
              side: critical ? BorderSide.none : BorderSide(color: c.hairline),
            ),
            shadows: critical ? null : c.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(RadIcons.flag, size: 16, strokeWidth: 1.9, color: critical ? c.redText : c.label2),
              const SizedBox(width: CruSpace.s6),
              Text(
                critical ? 'Critical' : 'Flag critical',
                style: (critical ? CruType.text.w600 : CruType.text.w500).tint(fg),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The drag handle between the study panel and the report.
class _Resizer extends StatelessWidget {
  const _Resizer({required this.onDrag, required this.onEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: SizedBox(
          width: CruSpace.s6,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 1, child: ColoredBox(color: c.hairline)),
          ),
        ),
      ),
    );
  }
}

/// Ceph values with their norms; values more than one SD out are amber.
class _CephTableView extends StatelessWidget {
  const _CephTableView(this.table);

  final RadCephTable table;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const col = 110.0;
    Widget right(String text, TextStyle style) =>
        SizedBox(width: col, child: Text(text, textAlign: TextAlign.right, style: style));
    final head = CruType.caption.w500.tint(c.label3);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('Measure', style: head)),
            right('Value', head),
            right('Norm', head),
          ],
        ),
        const SizedBox(height: CruSpace.s6),
        for (final row in table.rows) ...[
          const CruSeparator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
            child: Row(
              children: [
                Expanded(child: Text(row.name, style: CruType.subhead.tint(c.label))),
                right(
                  row.value,
                  CruType.subhead.w600.tabular.tint(row.deviates ? c.amberText : c.label),
                ),
                right(row.norm.isEmpty ? '—' : row.norm, CruType.subhead.tabular.tint(c.label2)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
