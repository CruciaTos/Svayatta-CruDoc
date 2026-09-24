import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// Sites per tooth are stored in this order: MB, B, DB, ML, L, DL.

const _molars = {
  '16',
  '17',
  '18',
  '26',
  '27',
  '28',
  '36',
  '37',
  '38',
  '46',
  '47',
  '48',
};

/// One tooth's perio findings, six sites each (MB, B, DB, ML, L, DL).
class PerioTooth {
  PerioTooth()
    : pd = List<int?>.filled(6, null),
      rec = List<int?>.filled(6, null),
      bop = List<bool>.filled(6, false),
      sup = List<bool>.filled(6, false);

  final List<int?> pd;

  /// Recession in mm (gingival margin below the CEJ; negative when above).
  final List<int?> rec;
  final List<bool> bop;
  final List<bool> sup;

  /// Miller class 0–3.
  int? mobility;

  /// Glickman class 1–4.
  int? furcation;
  bool missing = false;

  /// Clinical attachment level = probing depth + recession.
  int? cal(int site) => pd[site] == null ? null : pd[site]! + (rec[site] ?? 0);

  Map<String, dynamic> toJson() => {
    'pd': pd,
    'rec': rec,
    'bop': bop,
    'sup': sup,
    'mob': mobility,
    'furc': furcation,
    'missing': missing,
  };

  static PerioTooth fromJson(Object? j) {
    final t = PerioTooth();
    if (j is! Map) return t;
    List<Object?> l(String k) => j[k] is List ? j[k] as List : const [];
    for (var i = 0; i < 6; i++) {
      final pd = l('pd'), rec = l('rec'), bop = l('bop'), sup = l('sup');
      if (i < pd.length) t.pd[i] = (pd[i] as num?)?.toInt();
      if (i < rec.length) t.rec[i] = (rec[i] as num?)?.toInt();
      if (i < bop.length) t.bop[i] = bop[i] == true;
      if (i < sup.length) t.sup[i] = sup[i] == true;
    }
    t.mobility = (j['mob'] as num?)?.toInt();
    t.furcation = (j['furc'] as num?)?.toInt();
    t.missing = j['missing'] == true;
    return t;
  }
}

/// The numbers a perio exam is judged by.
class PerioSummary {
  PerioSummary(Map<String, PerioTooth> teeth) {
    for (final t in teeth.values) {
      if (t.missing) continue;
      var any = false;
      for (var s = 0; s < 6; s++) {
        final pd = t.pd[s];
        if (pd == null) continue;
        any = true;
        sites++;
        pdSum += pd;
        calSum += t.cal(s)!;
        if (t.bop[s]) bleeding++;
        if (pd >= 4) deep4++;
        if (pd >= 6) deep6++;
      }
      if (any) teethCharted++;
    }
  }

  int teethCharted = 0;
  int sites = 0;
  int pdSum = 0;
  int calSum = 0;
  int bleeding = 0;
  int deep4 = 0;
  int deep6 = 0;

  double? get meanPd => sites == 0 ? null : pdSum / sites;
  double? get meanCal => sites == 0 ? null : calSum / sites;
  double? get bopPct => sites == 0 ? null : bleeding * 100 / sites;
}

Map<String, PerioTooth> _teethOf(DentalRecord r) {
  final raw = r.data['teeth'];
  final out = <String, PerioTooth>{};
  for (final t in [...DentalChart.adultUpper, ...DentalChart.adultLower]) {
    out[t] = PerioTooth.fromJson(raw is Map ? raw[t] : null);
  }
  return out;
}

/// Summary of a saved perio exam (for cards and lists).
PerioSummary perioSummaryOf(DentalRecord r) => PerioSummary(_teethOf(r));

/// Full-screen periodontal chart: six sites per tooth, keyboard entry,
/// automatic attachment levels, exam history with a trend, and print.
class PerioChartScreen extends ConsumerStatefulWidget {
  const PerioChartScreen({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<PerioChartScreen> createState() => _PerioChartScreenState();
}

enum _Field { pd, rec }

class _Cursor {
  const _Cursor(this.tooth, this.lingual, this.pos, this.field);
  final String tooth;
  final bool lingual;

  /// 0–2, left to right on screen.
  final int pos;
  final _Field field;
}

class _PerioChartScreenState extends ConsumerState<PerioChartScreen> {
  DentalRecord? _record;
  Map<String, PerioTooth> _teeth = {};
  final _notes = TextEditingController();
  _Cursor? _cursor;
  Timer? _debounce;
  bool _saved = true;
  final _focus = FocusNode();

  RecKey get _key => (patientId: widget.patient.id, kind: RecKind.perio);

  @override
  void dispose() {
    _debounce?.cancel();
    _notes.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _load(DentalRecord? r) {
    setState(() {
      _record = r;
      _teeth = r == null ? {} : _teethOf(r);
      _notes.text = r?.str('notes') ?? '';
      _cursor = null;
      _saved = true;
    });
  }

  /// A new exam carries over missing teeth from the last one.
  void _newExam(List<DentalRecord> exams) {
    final teeth = <String, PerioTooth>{
      for (final t in [...DentalChart.adultUpper, ...DentalChart.adultLower])
        t: PerioTooth(),
    };
    if (exams.isNotEmpty) {
      final last = _teethOf(exams.first);
      for (final e in last.entries) {
        teeth[e.key]!.missing = e.value.missing;
      }
    }
    final r = DentalRecord.create(widget.patient.id, RecKind.perio, {
      'teeth': {},
    });
    setState(() {
      _record = r;
      _teeth = teeth;
      _notes.clear();
      _cursor = _Cursor(
        DentalChart.adultUpper.firstWhere((t) => !teeth[t]!.missing),
        false,
        0,
        _Field.pd,
      );
      _saved = false;
    });
    _schedule();
    _focus.requestFocus();
  }

  void _schedule() {
    _saved = false;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    final r = _record;
    if (r == null) return;
    final updated = r.copyWith(
      data: {
        'teeth': {for (final e in _teeth.entries) e.key: e.value.toJson()},
        'notes': _notes.text.trim(),
      },
    );
    _record = updated;
    await saveDentalRecord(ref, updated);
    if (mounted) setState(() => _saved = true);
  }

  // ---------------------------------------------------------------- entry

  /// Site index for a screen position: patient's right (quadrants 1, 4)
  /// shows distal first.
  static int _site(String tooth, bool lingual, int pos) {
    final right = tooth.startsWith('1') || tooth.startsWith('4');
    final p = right ? 2 - pos : pos;
    return lingual ? 3 + p : p;
  }

  List<_Cursor> _order() {
    final out = <_Cursor>[];
    for (final arch in [DentalChart.adultUpper, DentalChart.adultLower]) {
      for (final lingual in [false, true]) {
        for (final field in _Field.values) {
          for (final t in arch) {
            if (_teeth[t]?.missing ?? true) continue;
            for (var p = 0; p < 3; p++) {
              out.add(_Cursor(t, lingual, p, field));
            }
          }
        }
      }
    }
    return out;
  }

  int _indexOf(List<_Cursor> order, _Cursor c) => order.indexWhere(
    (o) =>
        o.tooth == c.tooth &&
        o.lingual == c.lingual &&
        o.pos == c.pos &&
        o.field == c.field,
  );

  void _move(int delta) {
    final order = _order();
    if (order.isEmpty) return;
    final c = _cursor;
    final i = c == null ? -1 : _indexOf(order, c);
    setState(() => _cursor = order[(i + delta).clamp(0, order.length - 1)]);
  }

  void _set(int? v) {
    final c = _cursor;
    if (c == null) return;
    final t = _teeth[c.tooth]!;
    final s = _site(c.tooth, c.lingual, c.pos);
    setState(() => (c.field == _Field.pd ? t.pd : t.rec)[s] = v);
    _schedule();
  }

  void _toggle(String tooth, bool lingual, int pos, {required bool bleeding}) {
    final t = _teeth[tooth]!;
    final s = _site(tooth, lingual, pos);
    setState(() => bleeding ? t.bop[s] = !t.bop[s] : t.sup[s] = !t.sup[s]);
    _schedule();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final c = _cursor;
    if (c == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final digit = e.character != null ? int.tryParse(e.character!) : null;
    if (digit != null) {
      _set(digit);
      _move(1);
      return KeyEventResult.handled;
    }
    if (e.character == '-') {
      // Gingival margin above the CEJ.
      if (c.field == _Field.rec) {
        final t = _teeth[c.tooth]!;
        final s = _site(c.tooth, c.lingual, c.pos);
        final v = t.rec[s] ?? 0;
        setState(() => t.rec[s] = -v.abs());
        _schedule();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
      _set(null);
      if (k == LogicalKeyboardKey.backspace) _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyB) {
      _toggle(c.tooth, c.lingual, c.pos, bleeding: true);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyS) {
      _toggle(c.tooth, c.lingual, c.pos, bleeding: false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.tab) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------- print

  Future<void> _print() async {
    final r = _record;
    if (r == null) return;
    await _saveNow();
    final identity = ref.read(doctorIdentityProvider);
    final sum = PerioSummary(_teeth);
    String cell(PerioTooth t, List<int?> v, bool lingual, String tooth) {
      if (t.missing) return '—';
      return [
        for (var p = 0; p < 3; p++)
          v[_site(tooth, lingual, p)]?.toString() ?? '·',
      ].join(' ');
    }

    String calCell(PerioTooth t, bool lingual, String tooth) {
      if (t.missing) return '—';
      return [
        for (var p = 0; p < 3; p++)
          t.cal(_site(tooth, lingual, p))?.toString() ?? '·',
      ].join(' ');
    }

    String marks(PerioTooth t, bool lingual, String tooth) {
      if (t.missing) return '';
      return [
        for (var p = 0; p < 3; p++)
          '${t.bop[_site(tooth, lingual, p)] ? 'B' : ''}${t.sup[_site(tooth, lingual, p)] ? 'S' : ''}'
              .padRight(1, '·'),
      ].join(' ');
    }

    pw.Widget arch(List<String> teeth, String title) {
      final rows = <List<String>>[
        [
          'Buccal PD',
          for (final t in teeth) cell(_teeth[t]!, _teeth[t]!.pd, false, t),
        ],
        [
          'Buccal rec',
          for (final t in teeth) cell(_teeth[t]!, _teeth[t]!.rec, false, t),
        ],
        ['Buccal CAL', for (final t in teeth) calCell(_teeth[t]!, false, t)],
        ['Bleed / pus', for (final t in teeth) marks(_teeth[t]!, false, t)],
        [
          'Lingual PD',
          for (final t in teeth) cell(_teeth[t]!, _teeth[t]!.pd, true, t),
        ],
        [
          'Lingual rec',
          for (final t in teeth) cell(_teeth[t]!, _teeth[t]!.rec, true, t),
        ],
        ['Lingual CAL', for (final t in teeth) calCell(_teeth[t]!, true, t)],
        ['Bleed / pus', for (final t in teeth) marks(_teeth[t]!, true, t)],
        ['Mobility', for (final t in teeth) _roman(_teeth[t]!.mobility)],
        ['Furcation', for (final t in teeth) _roman(_teeth[t]!.furcation)],
      ];
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['', ...teeth],
            data: rows,
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.all(2),
          ),
        ],
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              identity.clinicName ?? identity.fullName ?? 'Periodontal chart',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Periodontal chart · ${widget.patient.fullName} · ${DentalFormat.date(r.recordedAt)}',
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Mean PD ${sum.meanPd?.toStringAsFixed(1) ?? '-'} mm · mean CAL '
              '${sum.meanCal?.toStringAsFixed(1) ?? '-'} mm · bleeding '
              '${sum.bopPct?.toStringAsFixed(0) ?? '-'}% · sites ≥4 mm: ${sum.deep4} · ≥6 mm: ${sum.deep6}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
            arch(DentalChart.adultUpper, 'Upper'),
            pw.SizedBox(height: 10),
            arch(DentalChart.adultLower, 'Lower'),
            if (_notes.text.trim().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'Notes: ${_notes.text.trim()}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      name: 'Perio chart ${widget.patient.fullName}',
      onLayout: (_) => doc.save(),
    );
  }

  static String _roman(int? v) => switch (v) {
    null => '',
    0 => '0',
    1 => 'I',
    2 => 'II',
    3 => 'III',
    4 => 'IV',
    _ => '$v',
  };

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final exams = ref.watch(patientRecordsProvider(_key)).value;
    if (_record == null &&
        exams != null &&
        exams.isNotEmpty &&
        _teeth.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _record == null) _load(exams.first);
      });
    }
    final sum = PerioSummary(_teeth);

    // Unsaved entries are saved on the way out (the screen still has its
    // providers then).
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!_saved) {
          _debounce?.cancel();
          _saveNow();
        }
      },
      child: Scaffold(
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
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      child: DentalPageHeader(
                        title: 'Perio chart',
                        subtitle: _record == null
                            ? widget.patient.fullName
                            : '${widget.patient.fullName} · ${DentalFormat.date(_record!.recordedAt)}'
                                  '${_saved ? ' · saved' : ' · saving…'}',
                        actions: [
                          if (_record != null)
                            CruButton(
                              label: 'Print',
                              icon: CruIcons.download,
                              kind: CruButtonKind.secondary,
                              onPressed: _print,
                            ),
                          CruButton(
                            label: 'New exam',
                            icon: CruIcons.plus,
                            onPressed: exams == null
                                ? null
                                : () => _newExam(exams),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.cardGap),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CruCard(
                          semanticLabel: 'Chart',
                          padding: const EdgeInsets.all(CruSpace.s16),
                          child: _record == null
                              ? Center(
                                  child: DentalEmptyState(
                                    icon: RecIcons.perio,
                                    title: 'No perio exam yet',
                                    body:
                                        'Start an exam and type depths: each number moves to the '
                                        'next site. B marks bleeding, S suppuration, minus makes '
                                        'recession negative. Attachment levels work themselves out.',
                                    actions: [
                                      CruButton(
                                        label: 'New exam',
                                        icon: CruIcons.plus,
                                        onPressed: exams == null
                                            ? null
                                            : () => _newExam(exams),
                                      ),
                                    ],
                                  ),
                                )
                              : Focus(
                                  focusNode: _focus,
                                  autofocus: true,
                                  onKeyEvent: _onKey,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _SummaryLine(sum: sum),
                                        const SizedBox(height: CruSpace.s12),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _arch(
                                                context,
                                                DentalChart.adultUpper,
                                                'Upper',
                                                'Buccal',
                                                'Palatal',
                                              ),
                                              const SizedBox(
                                                height: CruSpace.s20,
                                              ),
                                              _arch(
                                                context,
                                                DentalChart.adultLower,
                                                'Lower',
                                                'Buccal',
                                                'Lingual',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: CruSpace.s16),
                                        Text(
                                          'Type a number to fill the site and move on · B bleeding · '
                                          'S suppuration · − recession above the CEJ · ⌫ clear · '
                                          'tap a tooth number to mark it missing',
                                          style: CruType.caption.tint(c.label3),
                                        ),
                                        const SizedBox(height: CruSpace.s12),
                                        CruTextField(
                                          label: 'Notes',
                                          optional: true,
                                          controller: _notes,
                                          maxLines: 2,
                                          onChanged: (_) => _schedule(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: CruSpace.cardGap),
                      SizedBox(
                        width: 300,
                        child: _History(
                          exams: exams ?? const [],
                          selectedId: _record?.id,
                          onSelect: (r) async {
                            if (!_saved) await _saveNow();
                            _load(r);
                          },
                          onDelete: (r) async {
                            final ok = await confirmDental(
                              context,
                              title: 'Delete this exam?',
                              body:
                                  'The ${DentalFormat.date(r.recordedAt)} perio chart will be removed.',
                              action: 'Delete',
                            );
                            if (!ok) return;
                            await deleteDentalRecord(ref, r);
                            if (_record?.id == r.id) _load(null);
                          },
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

  static const _cellW = 22.0;
  static const _labelW = 92.0;

  Widget _arch(
    BuildContext context,
    List<String> teeth,
    String title,
    String outer,
    String inner,
  ) {
    final c = context.cru;
    Widget label(String t) => SizedBox(
      width: _labelW,
      child: Text(t, style: CruType.caption.w600.tint(c.label2)),
    );

    Widget valueRow(bool lingual, _Field field) => Row(
      children: [
        label(
          '${lingual ? inner : outer} ${field == _Field.pd ? 'PD' : 'rec'}',
        ),
        for (final t in teeth) ...[
          for (var p = 0; p < 3; p++) _valueCell(context, t, lingual, p, field),
          const SizedBox(width: CruSpace.s4),
        ],
      ],
    );

    Widget calRow(bool lingual) => Row(
      children: [
        label('${lingual ? inner : outer} CAL'),
        for (final t in teeth) ...[
          for (var p = 0; p < 3; p++)
            SizedBox(
              width: _cellW,
              height: 20,
              child: Center(
                child: Text(
                  _teeth[t]!.missing
                      ? ''
                      : '${_teeth[t]!.cal(_site(t, lingual, p)) ?? ''}',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
              ),
            ),
          const SizedBox(width: CruSpace.s4),
        ],
      ],
    );

    Widget dotsRow(bool lingual) => Row(
      children: [
        label('Bleed · pus'),
        for (final t in teeth) ...[
          for (var p = 0; p < 3; p++) _dotCell(context, t, lingual, p),
          const SizedBox(width: CruSpace.s4),
        ],
      ],
    );

    Widget toothRow() => Row(
      children: [
        label(title),
        for (final t in teeth) ...[
          _toothHeader(context, t),
          const SizedBox(width: CruSpace.s4),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        valueRow(false, _Field.pd),
        valueRow(false, _Field.rec),
        calRow(false),
        dotsRow(false),
        const SizedBox(height: CruSpace.s6),
        toothRow(),
        const SizedBox(height: CruSpace.s6),
        dotsRow(true),
        valueRow(true, _Field.pd),
        valueRow(true, _Field.rec),
        calRow(true),
      ],
    );
  }

  Widget _valueCell(
    BuildContext context,
    String t,
    bool lingual,
    int p,
    _Field field,
  ) {
    final c = context.cru;
    final tooth = _teeth[t]!;
    final s = _site(t, lingual, p);
    final v = (field == _Field.pd ? tooth.pd : tooth.rec)[s];
    final cur = _cursor;
    final selected =
        cur != null &&
        cur.tooth == t &&
        cur.lingual == lingual &&
        cur.pos == p &&
        cur.field == field;
    final deep = field == _Field.pd && v != null && v >= 4;
    return GestureDetector(
      onTap: tooth.missing
          ? null
          : () {
              setState(() => _cursor = _Cursor(t, lingual, p, field));
              _focus.requestFocus();
            },
      child: Container(
        width: _cellW - 2,
        height: 24,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: tooth.missing
              ? c.inset.withValues(alpha: 0.4)
              : selected
              ? c.accentTint
              : c.inset,
          shape: cruShape(
            4,
            side: selected ? BorderSide(color: c.accent) : BorderSide.none,
          ),
        ),
        child: Text(
          tooth.missing ? '' : (v?.toString() ?? ''),
          style: (deep && v >= 6 ? CruType.caption.w600 : CruType.caption)
              .tabular
              .tint(deep ? c.amberText : c.label),
        ),
      ),
    );
  }

  Widget _dotCell(BuildContext context, String t, bool lingual, int p) {
    final c = context.cru;
    final tooth = _teeth[t]!;
    final s = _site(t, lingual, p);
    Widget dot(bool on, Color color, VoidCallback onTap, String tip) => Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: tooth.missing ? null : onTap,
        child: Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: ShapeDecoration(
            color: on ? color : c.inset,
            shape: const CircleBorder(),
          ),
        ),
      ),
    );
    return SizedBox(
      width: _cellW,
      height: 16,
      child: tooth.missing
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                dot(
                  tooth.bop[s],
                  c.amber,
                  () => _toggle(t, lingual, p, bleeding: true),
                  'Bleeding',
                ),
                dot(
                  tooth.sup[s],
                  c.label,
                  () => _toggle(t, lingual, p, bleeding: false),
                  'Suppuration',
                ),
              ],
            ),
    );
  }

  Widget _toothHeader(BuildContext context, String t) {
    final c = context.cru;
    final tooth = _teeth[t]!;
    Widget chip(String text, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: ShapeDecoration(
            color: c.inset,
            shape: const StadiumBorder(),
          ),
          alignment: Alignment.center,
          child: Text(text, style: CruType.micro.tabular.tint(c.label2)),
        ),
      ),
    );
    return SizedBox(
      width: _cellW * 3,
      child: Column(
        children: [
          Tooltip(
            message: tooth.missing
                ? 'Missing · tap to restore'
                : 'Tap to mark missing',
            child: GestureDetector(
              onTap: () {
                setState(() {
                  tooth.missing = !tooth.missing;
                  if (_cursor?.tooth == t) _cursor = null;
                });
                _schedule();
              },
              child: Text(
                t,
                style: CruType.subhead.w600.tabular
                    .tint(tooth.missing ? c.label3 : c.label)
                    .copyWith(
                      decoration: tooth.missing
                          ? TextDecoration.lineThrough
                          : null,
                    ),
              ),
            ),
          ),
          if (!tooth.missing)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                chip(
                  'M${_roman(tooth.mobility).isEmpty ? '–' : _roman(tooth.mobility)}',
                  'Mobility (Miller) · tap to change',
                  () {
                    setState(
                      () => tooth.mobility = tooth.mobility == null
                          ? 0
                          : tooth.mobility! >= 3
                          ? null
                          : tooth.mobility! + 1,
                    );
                    _schedule();
                  },
                ),
                if (_molars.contains(t)) ...[
                  const SizedBox(width: 2),
                  chip(
                    'F${_roman(tooth.furcation).isEmpty ? '–' : _roman(tooth.furcation)}',
                    'Furcation (Glickman) · tap to change',
                    () {
                      setState(
                        () => tooth.furcation = tooth.furcation == null
                            ? 1
                            : tooth.furcation! >= 4
                            ? null
                            : tooth.furcation! + 1,
                      );
                      _schedule();
                    },
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.sum});

  final PerioSummary sum;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget cell(String label, String value, {bool warn = false}) => Padding(
      padding: const EdgeInsets.only(right: CruSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: CruType.caption.tint(c.label2)),
          Text(
            value,
            style: CruType.headline.tabular.tint(warn ? c.amberText : c.label),
          ),
        ],
      ),
    );
    return Wrap(
      children: [
        cell('Teeth charted', '${sum.teethCharted}'),
        cell(
          'Mean PD',
          sum.meanPd == null ? '—' : '${sum.meanPd!.toStringAsFixed(1)} mm',
        ),
        cell(
          'Mean CAL',
          sum.meanCal == null ? '—' : '${sum.meanCal!.toStringAsFixed(1)} mm',
        ),
        cell(
          'Bleeding',
          sum.bopPct == null ? '—' : '${sum.bopPct!.toStringAsFixed(0)}%',
          warn: (sum.bopPct ?? 0) >= 10,
        ),
        cell('Sites ≥ 4 mm', '${sum.deep4}', warn: sum.deep4 > 0),
        cell('Sites ≥ 6 mm', '${sum.deep6}', warn: sum.deep6 > 0),
      ],
    );
  }
}

/// Past exams with a trend of mean depth, attachment and bleeding.
class _History extends StatelessWidget {
  const _History({
    required this.exams,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
  });

  final List<DentalRecord> exams;
  final String? selectedId;
  final ValueChanged<DentalRecord> onSelect;
  final ValueChanged<DentalRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final chrono = [...exams]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final sums = [for (final e in chrono) perioSummaryOf(e)];
    return CruCard(
      semanticLabel: 'Exams',
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Trend', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s8),
          SizedBox(
            height: 120,
            child: chrono.length < 2
                ? Center(
                    child: Text(
                      'Two exams make a trend.',
                      style: CruType.caption.tint(c.label3),
                    ),
                  )
                : CustomPaint(painter: _TrendPainter(sums, c)),
          ),
          const SizedBox(height: CruSpace.s6),
          Wrap(
            spacing: CruSpace.s12,
            children: [
              _Legend(color: c.label, text: 'Mean PD'),
              _Legend(color: c.label3, text: 'Mean CAL'),
              _Legend(color: c.amber, text: 'Bleeding %'),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          Text('Exams', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Expanded(
            child: ListView(
              children: [
                if (exams.isEmpty)
                  Text('None yet.', style: CruType.subhead.tint(c.label2)),
                for (final e in exams)
                  DentalListRow(
                    semanticLabel: DentalFormat.date(e.recordedAt),
                    onTap: () => onSelect(e),
                    minHeight: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DentalFormat.date(e.recordedAt),
                                style:
                                    (e.id == selectedId
                                            ? CruType.subhead.w600
                                            : CruType.subhead)
                                        .tabular
                                        .tint(c.label),
                              ),
                              Builder(
                                builder: (context) {
                                  final s = perioSummaryOf(e);
                                  return Text(
                                    s.sites == 0
                                        ? 'Empty'
                                        : 'PD ${s.meanPd!.toStringAsFixed(1)} · BOP ${s.bopPct!.toStringAsFixed(0)}% · ≥4 mm ${s.deep4}',
                                    style: CruType.caption.tabular.tint(
                                      c.label2,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        CruIconButton(
                          icon: CruIcons.close,
                          size: CruSize.rowCapsule,
                          iconSize: 12,
                          semanticLabel: 'Delete exam',
                          tooltip: 'Delete exam',
                          onPressed: () => onDelete(e),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 3, color: color),
      const SizedBox(width: CruSpace.s4),
      Text(text, style: CruType.caption.tint(context.cru.label2)),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.sums, this.c);

  final List<PerioSummary> sums;
  final CruColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final n = sums.length;
    double x(int i) => n == 1 ? size.width / 2 : i * size.width / (n - 1);
    // Bleeding % as bars (0–100).
    final bar = Paint()..color = c.amber.withValues(alpha: 0.35);
    for (var i = 0; i < n; i++) {
      final v = (sums[i].bopPct ?? 0) / 100;
      canvas.drawRect(
        Rect.fromLTWH(x(i) - 4, size.height * (1 - v), 8, size.height * v),
        bar,
      );
    }
    // Depth and attachment lines (0–max mm).
    final maxMm = math.max(
      6.0,
      sums.fold<double>(
            0,
            (m, s) => math.max(m, math.max(s.meanPd ?? 0, s.meanCal ?? 0)),
          ) +
          1,
    );
    void line(double? Function(PerioSummary) f, Color color) {
      final p = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = f(sums[i]);
        if (v == null) continue;
        final pt = Offset(x(i), size.height * (1 - v / maxMm));
        started ? path.lineTo(pt.dx, pt.dy) : path.moveTo(pt.dx, pt.dy);
        started = true;
        canvas.drawCircle(pt, 2.5, Paint()..color = color);
      }
      canvas.drawPath(path, p);
    }

    line((s) => s.meanCal, c.label3);
    line((s) => s.meanPd, c.label);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.sums != sums;
}
