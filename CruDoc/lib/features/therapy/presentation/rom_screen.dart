import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_assess_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Bottom sheet listing the regions; opens the chosen region's screen.
Future<void> pickRomRegion(BuildContext context, Patient patient) async {
  final region = await showModalBottomSheet<RomRegion>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final r in kRomRegions)
            ListTile(
              title: Text(r.label),
              onTap: () => Navigator.of(ctx).pop(r),
            ),
        ],
      ),
    ),
  );
  if (region == null || !context.mounted) return;
  openRomRegion(context, patient, region);
}

void openRomRegion(BuildContext context, Patient patient, RomRegion region) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => RomRegionScreen(patient: patient, region: region),
      ),
    );

/// New assessment for one region on top, earlier assessments below.
class RomRegionScreen extends ConsumerStatefulWidget {
  const RomRegionScreen({
    super.key,
    required this.patient,
    required this.region,
  });

  final Patient patient;
  final RomRegion region;

  @override
  ConsumerState<RomRegionScreen> createState() => _RomRegionScreenState();
}

class _RomRegionScreenState extends ConsumerState<RomRegionScreen> {
  // Keyed '<move>|<field>' where field is lDeg, rDeg, lMmt or rMmt.
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, FocusNode> _focus = {};
  final _note = TextEditingController();
  bool _busy = false;

  /// The saved assessment being edited, or null for a new one.
  DentalRecord? _editing;

  void _load(RomAssessment a) {
    for (final c in _ctl.values) {
      c.clear();
    }
    for (final r in a.rows) {
      _c(r.move, 'lDeg').text = r.lDeg?.toString() ?? '';
      _c(r.move, 'rDeg').text = r.rDeg?.toString() ?? '';
      _c(r.move, 'lMmt').text = r.lMmt?.toString() ?? '';
      _c(r.move, 'rMmt').text = r.rMmt?.toString() ?? '';
    }
    _note.text = a.note;
    setState(() => _editing = a.record);
  }

  void _stopEditing() {
    for (final c in _ctl.values) {
      c.clear();
    }
    _note.clear();
    setState(() => _editing = null);
  }

  TextEditingController _c(String move, String field) =>
      _ctl.putIfAbsent('$move|$field', () => TextEditingController());
  FocusNode _f(String move, String field) =>
      _focus.putIfAbsent('$move|$field', () => FocusNode());

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  int? _val(String move, String field) =>
      int.tryParse(_c(move, field).text.trim());

  Future<void> _save() async {
    final rows = [
      for (final m in widget.region.moves)
        RomRow(
          move: m.name,
          lDeg: _val(m.name, 'lDeg'),
          rDeg: _val(m.name, 'rDeg'),
          lMmt: _val(m.name, 'lMmt'),
          rMmt: _val(m.name, 'rMmt'),
        ),
    ].where((r) => !r.isEmpty).toList();
    if (rows.isEmpty) {
      recToast(context, 'Enter at least one value');
      return;
    }
    setState(() => _busy = true);
    final data = {
      'region': widget.region.id,
      'rows': [for (final r in rows) r.toJson()],
      'note': _note.text.trim(),
    };
    final editing = _editing;
    await saveDentalRecord(
      ref,
      editing != null
          ? editing.copyWith(data: data)
          : DentalRecord.create(widget.patient.id, RecKind.physioRom, data),
    );
    if (!mounted) return;
    recToast(
      context,
      '${widget.region.label} ${editing != null ? 'updated' : 'saved'}',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: widget.patient.id,
        kind: RecKind.physioRom,
      )),
    );
    final history = romAssessments(
      recs.value ?? const <DentalRecord>[],
    ).where((a) => a.regionId == widget.region.id).toList();
    // The assessment before the one being edited (or the latest, for a new one).
    final editDate = history
        .where((a) => a.record.id == _editing?.id)
        .firstOrNull
        ?.date;
    final prev = history
        .where((a) => editDate == null || a.date.isBefore(editDate))
        .firstOrNull;
    final since = prev == null ? '' : DentalFormat.shortDate(prev.date);
    final moves = widget.region.moves;

    String? delta(String move, String field, String unit) {
      final old = prev?.row(move);
      final oldV = old == null
          ? null
          : switch (field) {
              'lDeg' => old.lDeg,
              'rDeg' => old.rDeg,
              'lMmt' => old.lMmt,
              _ => old.rMmt,
            };
      final now = _val(move, field);
      if (oldV == null || now == null) return null;
      final d = now - oldV;
      return '${d > 0 ? '+' : ''}$d$unit since $since';
    }

    Widget field(
      String move,
      String field,
      String label, {
      required bool deg,
      required bool last,
    }) {
      final d = delta(move, field, deg ? '°' : '');
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: CruType.micro.tint(c.label2)),
              const SizedBox(height: CruSpace.s2),
              TextField(
                controller: _c(move, field),
                focusNode: _f(move, field),
                keyboardType: TextInputType.number,
                textInputAction: last
                    ? TextInputAction.done
                    : TextInputAction.next,
                inputFormatters: deg
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ]
                    : [
                        FilteringTextInputFormatter.allow(RegExp('[0-5]')),
                        LengthLimitingTextInputFormatter(1),
                      ],
                onChanged: (_) => setState(() {}),
                style: CruType.body.tint(c.label),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.inset,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s8,
                    vertical: CruSpace.s12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CruRadius.control),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                child: d == null
                    ? null
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(d, style: CruType.micro.tint(c.label2)),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text('${widget.region.label} · ${widget.patient.fullName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s16),
              children: [
                Text(
                  'ACTIVE ROM (degrees) AND STRENGTH (MMT 0-5)',
                  style: CruType.micro.w600.tint(c.label2),
                ),
                if (_editing != null) ...[
                  const SizedBox(height: CruSpace.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Editing the assessment from ${DentalFormat.date(_editing!.recordedAt)}',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ),
                      CruCapsuleButton(
                        label: 'New instead',
                        onPressed: _stopEditing,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: CruSpace.s8),
                for (final m in moves)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CruSpace.s8),
                    child: CruCard(
                      padding: const EdgeInsets.all(CruSpace.s12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.name,
                                  style: CruType.body.w600.tint(c.label),
                                ),
                              ),
                              Text(
                                'normal ${m.normal}°',
                                style: CruType.micro.tint(c.label3),
                              ),
                            ],
                          ),
                          const SizedBox(height: CruSpace.s8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              field(
                                m.name,
                                'lDeg',
                                'L °',
                                deg: true,
                                last: false,
                              ),
                              field(
                                m.name,
                                'rDeg',
                                'R °',
                                deg: true,
                                last: false,
                              ),
                              field(
                                m.name,
                                'lMmt',
                                'L /5',
                                deg: false,
                                last: false,
                              ),
                              field(
                                m.name,
                                'rMmt',
                                'R /5',
                                deg: false,
                                last: m == moves.last,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: CruSpace.s4),
                CruMoreFields(
                  label: 'Note',
                  open: _note.text.isNotEmpty,
                  children: [
                    CruTextField(
                      label: 'Note',
                      controller: _note,
                      optional: true,
                    ),
                  ],
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s24),
                  Text(
                    'EARLIER ASSESSMENTS (TAP TO EDIT)',
                    style: CruType.micro.w600.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s8),
                  for (final a in history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CruSpace.s8),
                      child: CruCard(
                        padding: const EdgeInsets.fromLTRB(
                          CruSpace.s16,
                          CruSpace.s12,
                          CruSpace.s4,
                          CruSpace.s12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  CruRadius.control,
                                ),
                                onTap: () => _load(a),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DentalFormat.date(a.date),
                                      style: CruType.body.w600.tint(c.label),
                                    ),
                                    const SizedBox(height: CruSpace.s4),
                                    for (final r in a.rows)
                                      Text(
                                        _rowText(r),
                                        style: CruType.caption.tint(c.label2),
                                      ),
                                    if (a.note.isNotEmpty)
                                      Text(
                                        a.note,
                                        style: CruType.caption.tint(c.label2),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: c.label2,
                              ),
                              onPressed: () async {
                                final ok = await confirmDental(
                                  context,
                                  title: 'Delete this assessment?',
                                  body:
                                      'The ${widget.region.label.toLowerCase()} assessment from ${DentalFormat.date(a.date)} will be removed.',
                                  action: 'Delete',
                                );
                                if (!ok) return;
                                if (_editing?.id == a.record.id) {
                                  _stopEditing();
                                }
                                await deleteDentalRecord(ref, a.record);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: CruButton(
                label: _editing != null
                    ? 'Update assessment'
                    : 'Save assessment',
                expand: true,
                onPressed: _busy ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _rowText(RomRow r) {
  String pair(String unit, int? l, int? rt) =>
      (l == null && rt == null) ? '' : '${l ?? '-'}/${rt ?? '-'}$unit';
  final deg = pair('°', r.lDeg, r.rDeg);
  final mmt = pair('', r.lMmt, r.rMmt);
  return [
    r.move,
    if (deg.isNotEmpty) 'ROM L/R $deg',
    if (mmt.isNotEmpty) 'MMT L/R $mmt',
  ].join(' · ');
}
