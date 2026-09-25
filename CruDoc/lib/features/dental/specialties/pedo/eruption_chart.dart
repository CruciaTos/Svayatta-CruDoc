import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Where a tooth is in coming in (or, for milk teeth, falling out).
enum EruptionStatus {
  notErupted('Not erupted'),
  erupting('Erupting'),
  erupted('Erupted'),
  exfoliated('Exfoliated'),
  missing('Missing');

  const EruptionStatus(this.label);
  final String label;

  static EruptionStatus? fromName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Normal eruption ranges: milk teeth in months, permanent teeth in years,
/// by tooth position (1 central incisor … 8 third molar). From the
/// handoff's table; a pediatric dentist must verify it before clinical use.
const _milkMonths = {
  true: {1: (8, 12), 2: (9, 13), 3: (16, 22), 4: (13, 19), 5: (25, 33)},
  false: {1: (6, 10), 2: (10, 16), 3: (17, 23), 4: (14, 18), 5: (23, 31)},
};
const _permanentYears = {
  true: {1: (7, 8), 2: (8, 9), 3: (11, 12), 4: (10, 11), 5: (10, 12), 6: (6, 7), 7: (12, 13), 8: (17, 21)},
  false: {1: (6, 7), 2: (7, 8), 3: (9, 10), 4: (10, 12), 5: (11, 12), 6: (6, 7), 7: (11, 13), 8: (17, 21)},
};

bool _upper(String t) {
  final q = int.parse(t[0]);
  return q == 1 || q == 2 || q == 5 || q == 6;
}

/// The usual eruption window of [tooth] in months of age.
(int, int)? eruptionWindowMonths(String tooth) {
  final pos = int.parse(tooth[1]);
  if (DentalChart.isPrimary(tooth)) return _milkMonths[_upper(tooth)]![pos];
  final y = _permanentYears[_upper(tooth)]![pos];
  return y == null ? null : (y.$1 * 12, y.$2 * 12);
}

/// "8–12 months", "7–8 years".
String eruptionWindowText(String tooth) {
  final pos = int.parse(tooth[1]);
  if (DentalChart.isPrimary(tooth)) {
    final m = _milkMonths[_upper(tooth)]![pos]!;
    return '${m.$1}–${m.$2} months';
  }
  final y = _permanentYears[_upper(tooth)]![pos]!;
  return '${y.$1}–${y.$2} years';
}

/// The permanent tooth that replaces milk tooth [t] (51 → 11, 85 → 45).
String successorOf(String t) => '${int.parse(t[0]) - 4}${t[1]}';

/// Age in whole months on [on].
int ageInMonths(DateTime dob, DateTime on) {
  var m = (on.year - dob.year) * 12 + on.month - dob.month;
  if (on.day < dob.day) m--;
  return m < 0 ? 0 : m;
}

/// "9 years 4 months", "18 months".
String ageText(int months) => months < 24
    ? '$months months'
    : '${months ~/ 12} years${months % 12 == 0 ? '' : ' ${months % 12} months'}';

/// Status and date per tooth from an eruption record.
Map<String, (EruptionStatus, DateTime?)> eruptionTeethOf(DentalRecord? r) {
  final raw = r?.data['teeth'];
  final out = <String, (EruptionStatus, DateTime?)>{};
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final s = EruptionStatus.fromName(v['status']);
    if (s == null) continue;
    final at = v['date'] is int ? DateTime.fromMillisecondsSinceEpoch(v['date'] as int) : null;
    out['${e.key}'] = (s, at);
  }
  return out;
}

/// Teeth later than usual (not in yet, past the end of their window) and
/// milk teeth still in after their successor came through.
({List<String> late, List<String> retained}) eruptionFlags(
  Map<String, (EruptionStatus, DateTime?)> teeth,
  int ageMonths,
) {
  final late = <String>[];
  final retained = <String>[];
  for (final e in teeth.entries) {
    final t = e.key;
    final s = e.value.$1;
    final w = eruptionWindowMonths(t);
    if (w != null &&
        ageMonths > w.$2 &&
        (s == EruptionStatus.notErupted || s == EruptionStatus.erupting)) {
      late.add(t);
    }
    if (DentalChart.isPrimary(t) && s == EruptionStatus.erupted) {
      final next = teeth[successorOf(t)]?.$1;
      if (next == EruptionStatus.erupted || next == EruptionStatus.erupting) {
        retained.add(t);
      }
    }
  }
  return (late: late, retained: retained);
}

/// The card row: "2 later than usual · 1 retained", or what's charted.
({String text, bool warn}) eruptionCardLine(DentalRecord? r, Patient p) {
  final teeth = eruptionTeethOf(r);
  if (teeth.isEmpty) return (text: 'Not charted yet', warn: false);
  final f = eruptionFlags(teeth, ageInMonths(p.dateOfBirth, DateTime.now()));
  if (f.late.isNotEmpty || f.retained.isNotEmpty) {
    return (
      text: [
        if (f.late.isNotEmpty) '${f.late.length} later than usual',
        if (f.retained.isNotEmpty) '${f.retained.length} retained',
      ].join(' · '),
      warn: true,
    );
  }
  final erupted = teeth.values.where((v) => v.$1 == EruptionStatus.erupted).length;
  return (
    text: '$erupted erupted · updated ${DentalFormat.date(r!.updatedAt)}',
    warn: false,
  );
}

/// The eruption chart for a child: milk and permanent teeth per arch,
/// each marked as it comes in or falls out, with late and retained teeth
/// called out. Changes save as you go.
Future<void> showEruptionDialog(
  BuildContext context,
  Patient patient, {
  DentalRecord? existing,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _EruptionDialog(patient: patient, existing: existing),
    );

class _EruptionDialog extends ConsumerStatefulWidget {
  const _EruptionDialog({required this.patient, this.existing});

  final Patient patient;
  final DentalRecord? existing;

  @override
  ConsumerState<_EruptionDialog> createState() => _EruptionDialogState();
}

class _EruptionDialogState extends ConsumerState<_EruptionDialog> {
  late DentalRecord? _record = widget.existing;
  late final Map<String, (EruptionStatus, DateTime?)> _teeth =
      eruptionTeethOf(widget.existing);

  static const _milkUpper = ['55', '54', '53', '52', '51', '61', '62', '63', '64', '65'];
  static const _milkLower = ['85', '84', '83', '82', '81', '71', '72', '73', '74', '75'];
  static const _permUpper = ['17', '16', '15', '14', '13', '12', '11', '21', '22', '23', '24', '25', '26', '27'];
  static const _permLower = ['47', '46', '45', '44', '43', '42', '41', '31', '32', '33', '34', '35', '36', '37'];

  Future<void> _set(String tooth, EruptionStatus? s, {DateTime? on}) async {
    setState(() {
      if (s == null) {
        _teeth.remove(tooth);
      } else {
        _teeth[tooth] = (s, on ?? DateTime.now());
      }
    });
    final data = {
      'teeth': {
        for (final e in _teeth.entries)
          e.key: {
            'status': e.value.$1.name,
            if (e.value.$2 != null) 'date': e.value.$2!.millisecondsSinceEpoch,
          },
      },
    };
    final r = _record == null
        ? DentalRecord.create(widget.patient.id, RecKind.eruption, data)
        : _record!.copyWith(data: data, recordedAt: DateTime.now());
    _record = r;
    await saveDentalRecord(ref, r);
  }

  /// Click: the next status in the order a dentist usually meets them.
  void _cycle(String tooth) {
    final order = DentalChart.isPrimary(tooth)
        ? const [
            EruptionStatus.erupted,
            EruptionStatus.exfoliated,
            EruptionStatus.erupting,
            EruptionStatus.notErupted,
            EruptionStatus.missing,
          ]
        : const [
            EruptionStatus.erupted,
            EruptionStatus.erupting,
            EruptionStatus.notErupted,
            EruptionStatus.missing,
          ];
    final now = _teeth[tooth]?.$1;
    final i = now == null ? -1 : order.indexOf(now);
    _set(tooth, i + 1 < order.length ? order[i + 1] : null);
  }

  Future<void> _menu(String tooth, Offset at) async {
    final primary = DentalChart.isPrimary(tooth);
    final choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final s in EruptionStatus.values)
          if (primary || s != EruptionStatus.exfoliated)
            PopupMenuItem(value: s, child: Text(s.label)),
        const PopupMenuItem(value: 'clear', child: Text('Not charted')),
        if (_teeth[tooth] != null)
          const PopupMenuItem(value: 'date', child: Text('Change date…')),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'clear') return _set(tooth, null);
    if (choice == 'date') {
      final current = _teeth[tooth]!;
      final d = await pickDentalDate(
        context,
        initial: current.$2 ?? DateTime.now(),
        last: DateTime.now(),
      );
      if (d != null) await _set(tooth, current.$1, on: d);
      return;
    }
    await _set(tooth, choice as EruptionStatus);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final months = ageInMonths(widget.patient.dateOfBirth, DateTime.now());
    final flags = eruptionFlags(_teeth, months);

    Widget chips(String label, List<String> teeth) => Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Text(label, style: CruType.subhead.tint(c.label2)),
              ),
              Expanded(
                child: Wrap(
                  spacing: CruSpace.s4,
                  runSpacing: CruSpace.s4,
                  children: [
                    for (var i = 0; i < teeth.length; i++) ...[
                      if (i == teeth.length ~/ 2) const SizedBox(width: CruSpace.s10),
                      _ToothChip(
                        label: toothLabel(teeth[i], numbering),
                        status: _teeth[teeth[i]]?.$1,
                        late: flags.late.contains(teeth[i]),
                        tooltip: '${DentalChart.name(teeth[i])} · usually '
                            '${eruptionWindowText(teeth[i])}'
                            '${_teeth[teeth[i]] == null ? '' : '\n${_teeth[teeth[i]]!.$1.label}'
                                '${_teeth[teeth[i]]!.$2 == null ? '' : ' · ${DentalFormat.date(_teeth[teeth[i]]!.$2!)}'}'}',
                        onTap: () => _cycle(teeth[i]),
                        onMenu: (at) => _menu(teeth[i], at),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

    String line(String t, String why) =>
        '${toothLabel(t, numbering)} · ${DentalChart.name(t)} · $why';

    return DentalPanelDialog(
      title: 'Eruption chart',
      subtitle: '${widget.patient.fullName} · ${ageText(months)}',
      leading: const CruIconTile(icon: DentalIcons.tooth, tone: CruTileTone.accent),
      width: CruSize.formDialog,
      body: Padding(
        padding: const EdgeInsets.all(CruSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: CruSpace.s12,
              runSpacing: CruSpace.s6,
              children: [
                for (final s in EruptionStatus.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToothChip(label: '', status: s, late: false, small: true),
                      const SizedBox(width: CruSpace.s6),
                      Text(s.label, style: CruType.caption.tint(c.label2)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s6),
            Text(
              'Click a tooth to move it to the next state; right-click to '
              'pick one or change its date.',
              style: CruType.caption.tint(c.label3),
            ),
            DentalGroupLabel('Upper'),
            chips('Milk', _milkUpper),
            chips('Permanent', _permUpper),
            DentalGroupLabel('Lower'),
            chips('Milk', _milkLower),
            chips('Permanent', _permLower),
            const SizedBox(height: CruSpace.s12),
            const CruSeparator(),
            DentalGroupLabel('Later than usual'),
            if (flags.late.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
                child: Text(
                  _teeth.isEmpty ? 'Nothing charted yet.' : 'Nothing later than usual.',
                  style: CruType.subhead.tint(c.label3),
                ),
              ),
            for (final t in flags.late)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s12,
                  vertical: CruSpace.s2,
                ),
                child: Text(
                  line(t, 'usually ${eruptionWindowText(t)}'),
                  style: CruType.subhead.tint(c.amberText),
                ),
              ),
            if (flags.retained.isNotEmpty) ...[
              DentalGroupLabel('Retained milk teeth'),
              for (final t in flags.retained)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s2,
                  ),
                  child: Text(
                    line(t, '${toothLabel(successorOf(t), numbering)} has come through'),
                    style: CruType.subhead.tint(c.amberText),
                  ),
                ),
            ],
            const SizedBox(height: CruSpace.s12),
            Text(
              'Normal ages are a guide; check them against your own reference. '
              'Changes save as you go.',
              style: CruType.caption.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToothChip extends StatelessWidget {
  const _ToothChip({
    required this.label,
    required this.status,
    required this.late,
    this.tooltip,
    this.onTap,
    this.onMenu,
    this.small = false,
  });

  final String label;
  final EruptionStatus? status;
  final bool late;
  final String? tooltip;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onMenu;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (Color fill, Color fg, BorderSide side) = switch (status) {
      null => (c.surface, c.label3, BorderSide(color: c.separator)),
      EruptionStatus.notErupted => (c.inset, c.label2, BorderSide.none),
      EruptionStatus.erupting => (c.amberTint, c.amberText, BorderSide.none),
      EruptionStatus.erupted => (c.greenTint, c.greenText, BorderSide.none),
      EruptionStatus.exfoliated => (c.inset, c.label3, BorderSide.none),
      EruptionStatus.missing => (c.surface, c.label3, BorderSide(color: c.label3)),
    };
    final chip = Container(
      width: small ? 16 : 40,
      height: small ? 16 : 30,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: fill,
        shape: cruShape(
          small ? 4 : CruRadius.iconTile,
          side: late ? BorderSide(color: c.amber, width: 2) : side,
        ),
      ),
      child: small
          ? null
          : Text(
              label,
              style: CruType.caption.w600.tabular.tint(fg).copyWith(
                    decoration: status == EruptionStatus.exfoliated
                        ? TextDecoration.lineThrough
                        : null,
                  ),
            ),
    );
    if (onTap == null) return chip;
    return Tooltip(
      message: tooltip ?? '',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onSecondaryTapDown: (d) => onMenu?.call(d.globalPosition),
        child: CruPressable(
          onTap: onTap,
          semanticLabel: '$label ${status?.label ?? 'not charted'}${late ? ', later than usual' : ''}',
          builder: (context, hovered) => chip,
        ),
      ),
    );
  }
}
